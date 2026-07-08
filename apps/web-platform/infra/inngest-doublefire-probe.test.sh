#!/usr/bin/env bash
# Tests for inngest-doublefire-probe.sh — the 2.6 exactly-once cron-run
# enumeration probe for the Inngest dedicated-host cutover verify (#6178, P1-12,
# ADR-100). Verifies it returns a single pure-JSON OBJECT {runs:[{functionID,
# startedAt}...]} on stdout, paginates on pageInfo.hasNextPage, and FAILS LOUD
# (non-zero + stderr) on a non-array `.data.runs.edges` — never a false-clean
# "no double-fire". `scheduled_tick` must appear nowhere (does not exist in
# v1.19.4).
#
# Test seam: INNGEST_DOUBLEFIRE_RUNS_FIXTURE (a dir with page-N.json runs
# responses) short-circuits the curl. No network, no inngest, no root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-doublefire-probe.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

# Build a v1.19.4-shaped runs page. Args: <hasNextPage> <endCursor> <edges-json>
make_page() {
  local has_next="$1" end_cursor="$2" edges="$3"
  jq -nc --argjson hn "$has_next" --arg ec "$end_cursor" --argjson edges "$edges" \
    '{data:{runs:{totalCount:($edges|length),pageInfo:{hasNextPage:$hn,endCursor:$ec},edges:$edges}}}'
}

# Build one run edge. Args: <run_id> <function_id> <started_at>
make_edge() {
  local rid="$1" fid="$2" started="$3"
  jq -nc --arg rid "$rid" --arg fid "$fid" --arg s "$started" \
    '{cursor:$rid,node:{id:$rid,functionID:$fid,status:"COMPLETED",queuedAt:$s,startedAt:$s,endedAt:$s}}'
}

# --- Test 1: valid single-page runs → pure JSON {runs:[{functionID,startedAt}]} ---
test_valid_runs_single_page() {
  echo "TEST: doublefire-probe — valid single page yields pure-JSON {runs:[...]}"
  local dir; dir=$(mktemp -d)
  local e1 e2 edges
  e1=$(make_edge "run-1" "fn-a" "2026-07-08T10:00:00Z")
  e2=$(make_edge "run-2" "fn-a" "2026-07-08T10:01:00Z")
  edges=$(jq -nc --argjson a "$e1" --argjson b "$e2" '[$a,$b]')
  make_page false "" "$edges" > "$dir/page-1.json"

  local out; out=$(INNGEST_DOUBLEFIRE_RUNS_FIXTURE="$dir" bash "$TARGET")
  assert_eq "stdout is a single JSON object" "object" "$(echo "$out" | jq -r 'type')"
  assert_eq "runs is an array of 2" "2" "$(echo "$out" | jq -r '.runs | length')"
  assert_eq "run 0 functionID projected" "fn-a" "$(echo "$out" | jq -r '.runs[0].functionID')"
  assert_eq "run 0 startedAt projected" "2026-07-08T10:00:00Z" "$(echo "$out" | jq -r '.runs[0].startedAt')"
  # No reminder body / status leakage — only functionID + startedAt keys.
  assert_eq "run object has exactly functionID+startedAt keys" "functionID,startedAt" \
    "$(echo "$out" | jq -r '.runs[0] | keys_unsorted | join(",")')"
  rm -rf "$dir"
}

# --- Test 2: pagination across pages via pageInfo.hasNextPage ---
test_pagination() {
  echo "TEST: doublefire-probe — paginates on pageInfo.hasNextPage"
  local dir; dir=$(mktemp -d)
  make_page true "cursor-1" "[$(make_edge run-1 fn-a 2026-07-08T10:00:00Z)]" > "$dir/page-1.json"
  make_page false "" "[$(make_edge run-2 fn-b 2026-07-08T10:05:00Z)]" > "$dir/page-2.json"

  local out; out=$(INNGEST_DOUBLEFIRE_RUNS_FIXTURE="$dir" bash "$TARGET")
  assert_eq "both pages accumulated (2 runs)" "2" "$(echo "$out" | jq -r '.runs | length')"
  assert_eq "page-2 run present" "fn-b" "$(echo "$out" | jq -r '.runs[1].functionID')"
  rm -rf "$dir"
}

# --- Test 3: malformed / non-array .data.runs.edges → fail LOUD (non-zero) ---
test_malformed_fails_loud() {
  echo "TEST: doublefire-probe — non-array .data.runs.edges fails LOUD (non-zero)"
  local dir; dir=$(mktemp -d)
  echo '{"errors":[{"message":"bad RunsFilterV2 bound"}],"data":null}' > "$dir/page-1.json"

  local rc=0 out
  out=$(INNGEST_DOUBLEFIRE_RUNS_FIXTURE="$dir" bash "$TARGET" 2>/dev/null) || rc=$?
  if [[ "$rc" -ne 0 ]]; then echo "  PASS: exits non-zero on malformed runs response"; PASS=$((PASS + 1));
  else echo "  FAIL: expected non-zero exit on malformed runs response (got rc=0, out=$out)"; FAIL=$((FAIL + 1)); fi
  if echo "$out" | jq -e '.runs' >/dev/null 2>&1; then
    echo "  FAIL: emitted a false-clean {runs:[]} on a malformed response"; FAIL=$((FAIL + 1));
  else echo "  PASS: no false-clean runs object emitted"; PASS=$((PASS + 1)); fi
  rm -rf "$dir"
}

# --- Test 3b: hasNextPage=true but endCursor empty → fail LOUD (P3-b, no silent truncation) ---
test_pagination_truncation_fails_loud() {
  echo "TEST: doublefire-probe — hasNextPage=true + empty endCursor fails LOUD (P3-b)"
  local dir; dir=$(mktemp -d)
  # A first page that claims more pages exist but supplies NO cursor to reach them. Breaking
  # clean here would silently drop the later runs (a missed double-fire reads clean).
  make_page true "" "[$(make_edge run-1 fn-a 2026-07-08T10:00:00Z)]" > "$dir/page-1.json"
  local rc=0 out
  out=$(INNGEST_DOUBLEFIRE_RUNS_FIXTURE="$dir" bash "$TARGET" 2>/dev/null) || rc=$?
  if [[ "$rc" -ne 0 ]]; then echo "  PASS: exits non-zero on hasNextPage-but-empty-cursor"; PASS=$((PASS + 1));
  else echo "  FAIL: expected non-zero exit on truncated pagination (got rc=0, out=$out)"; FAIL=$((FAIL + 1)); fi
  if echo "$out" | jq -e '.runs' >/dev/null 2>&1; then
    echo "  FAIL: emitted a possibly-truncated {runs:...} on hasNextPage-but-empty-cursor"; FAIL=$((FAIL + 1));
  else echo "  PASS: no truncated runs object emitted"; PASS=$((PASS + 1)); fi
  rm -rf "$dir"
}

# --- Test 3b: hasNextPage=true but endCursor empty → fail LOUD, no truncation (P3-b) ---
test_truncated_pagination_fails_loud() {
  echo "TEST: doublefire-probe — hasNextPage=true + empty endCursor fails LOUD (P3-b)"
  local dir; dir=$(mktemp -d)
  # Page 1 claims a next page but supplies NO cursor → cannot page → must NOT break-clean.
  make_page true "" "[$(make_edge run-1 fn-a 2026-07-08T10:00:00Z)]" > "$dir/page-1.json"
  local rc=0 out
  out=$(INNGEST_DOUBLEFIRE_RUNS_FIXTURE="$dir" bash "$TARGET" 2>/dev/null) || rc=$?
  if [[ "$rc" -ne 0 ]]; then echo "  PASS: exits non-zero on truncated pagination"; PASS=$((PASS + 1));
  else echo "  FAIL: expected non-zero exit on hasNextPage=true+empty cursor (got rc=0, out=$out)"; FAIL=$((FAIL + 1)); fi
  if echo "$out" | jq -e '.runs' >/dev/null 2>&1; then
    echo "  FAIL: emitted a (possibly-truncated) false-clean {runs:[]} on truncated pagination"; FAIL=$((FAIL + 1));
  else echo "  PASS: no false-clean runs object emitted on truncation"; PASS=$((PASS + 1)); fi
  rm -rf "$dir"
}

# --- Test 4: empty runs page (no double-fire data) → {runs:[]} exit 0 ---
test_empty_runs() {
  echo "TEST: doublefire-probe — legitimately-empty runs → {runs:[]} exit 0"
  local dir; dir=$(mktemp -d)
  make_page false "" '[]' > "$dir/page-1.json"
  local rc=0 out
  out=$(INNGEST_DOUBLEFIRE_RUNS_FIXTURE="$dir" bash "$TARGET") || rc=$?
  assert_eq "exit 0 on empty runs" "0" "$rc"
  assert_eq "runs is empty array" "0" "$(echo "$out" | jq -r '.runs | length')"
  rm -rf "$dir"
}

# --- Test 5: script carries curl --max-time ---
test_curl_max_time() {
  echo "TEST: doublefire-probe — curl carries --max-time"
  if grep -qE 'curl[^|]*--max-time' "$TARGET"; then
    echo "  PASS: curl --max-time present"; PASS=$((PASS + 1));
  else echo "  FAIL: no curl --max-time in $TARGET"; FAIL=$((FAIL + 1)); fi
}

# --- Test 6: uses RunsFilterV2 + STARTED_AT, and NO scheduled_tick ---
test_query_shape() {
  echo "TEST: doublefire-probe — RunsFilterV2 + STARTED_AT, no scheduled_tick"
  if grep -q 'RunsFilterV2' "$TARGET"; then echo "  PASS: uses RunsFilterV2"; PASS=$((PASS + 1));
  else echo "  FAIL: RunsFilterV2 not referenced"; FAIL=$((FAIL + 1)); fi
  if grep -q 'STARTED_AT' "$TARGET"; then echo "  PASS: timeField STARTED_AT present"; PASS=$((PASS + 1));
  else echo "  FAIL: STARTED_AT not referenced"; FAIL=$((FAIL + 1)); fi
  if grep -q 'scheduled_tick' "$TARGET"; then
    echo "  FAIL: scheduled_tick must appear nowhere (does not exist in v1.19.4)"; FAIL=$((FAIL + 1));
  else echo "  PASS: no scheduled_tick reference"; PASS=$((PASS + 1)); fi
}

# --- Test 7: targets the dedicated host GQL by default ---
test_default_gql_url() {
  echo "TEST: doublefire-probe — defaults to the dedicated host 10.0.1.40:8288/v0/gql"
  if grep -q '10.0.1.40:8288/v0/gql' "$TARGET"; then
    echo "  PASS: default INNGEST_REMOTE_GQL_URL targets 10.0.1.40:8288"; PASS=$((PASS + 1));
  else echo "  FAIL: default GQL URL does not target the dedicated host"; FAIL=$((FAIL + 1)); fi
}

echo "=== inngest-doublefire-probe.sh test suite ==="
test_valid_runs_single_page
test_pagination
test_pagination_truncation_fails_loud
test_malformed_fails_loud
test_empty_runs
test_curl_max_time
test_query_shape
test_default_gql_url
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi

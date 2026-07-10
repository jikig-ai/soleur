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

# ===========================================================================
# #6258 (ADR-106) — bounding + markers + window-superset invariant
# ===========================================================================

RC=0; STDOUT_CAP=""; MARKERS_CAP=""
# Run with a logger stub capturing marker lines. Sets RC/STDOUT_CAP/MARKERS_CAP globals
# (called DIRECTLY — a $(...) subshell would discard them). $1=runs-fixture-dir, extra
# args = KEY=VAL env seams (passed via `env`, since an expanded "$@" is not an assignment prefix).
run_probe_logcap() {
  local dir="$1"; shift
  local bindir logout; bindir=$(mktemp -d); logout=$(mktemp)
  cat > "$bindir/logger" <<STUB
#!/usr/bin/env bash
shift 2 2>/dev/null || true
echo "\$*" >> "$logout"
STUB
  chmod +x "$bindir/logger"
  RC=0
  STDOUT_CAP=$(PATH="$bindir:$PATH" INNGEST_DOUBLEFIRE_RUNS_FIXTURE="$dir" env "$@" bash "$TARGET" 2>/dev/null) || RC=$?
  MARKERS_CAP=$(cat "$logout")
  rm -rf "$bindir" "$logout"
}

# --- #6258 T1: deadline hit → exit 1 (NOT break) + TIMEOUT reason=deadline + non-JSON stdout ---
test_df_deadline_abort() {
  echo "TEST: doublefire-probe — deadline hit exits 1 + TIMEOUT marker (not break)"
  local dir; dir=$(mktemp -d)
  make_page true "CUR1" "[$(make_edge run-1 fn-a 2026-07-08T10:00:00Z)]" > "$dir/page-1.json"
  run_probe_logcap "$dir" PREFLIGHT_DEADLINE_S=0
  if [[ "$RC" -eq 1 ]]; then echo "  PASS: deadline abort exits 1"; PASS=$((PASS+1)); else echo "  FAIL: deadline abort rc=$RC (want 1)"; FAIL=$((FAIL+1)); fi
  if echo "$STDOUT_CAP" | jq -e '.runs' >/dev/null 2>&1; then
    echo "  FAIL: stdout is a jq-parseable {runs} object on a deadline abort (false-clean)"; FAIL=$((FAIL+1));
  else echo "  PASS: stdout NOT a jq-parseable runs object on abort"; PASS=$((PASS+1)); fi
  if echo "$MARKERS_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_TIMEOUT .*op=verify-doublefire.*reason=deadline'; then
    echo "  PASS: TIMEOUT reason=deadline marker (op=verify-doublefire)"; PASS=$((PASS+1));
  else echo "  FAIL: no TIMEOUT reason=deadline marker (markers=$MARKERS_CAP)"; FAIL=$((FAIL+1)); fi
  rm -rf "$dir"
}

# --- #6258 T2: page ceiling hit → exit 1 + reason=page_ceiling; exact-fit breaks clean ---
test_df_page_ceiling_abort() {
  echo "TEST: doublefire-probe — page ceiling exits 1 + reason=page_ceiling; exact-fit clean"
  local dir; dir=$(mktemp -d)
  make_page true "CUR1" "[$(make_edge run-1 fn-a 2026-07-08T10:00:00Z)]" > "$dir/page-1.json"
  make_page true "CUR2" "[$(make_edge run-2 fn-a 2026-07-08T10:01:00Z)]" > "$dir/page-2.json"
  make_page false "" "[$(make_edge run-3 fn-a 2026-07-08T10:02:00Z)]" > "$dir/page-3.json"
  run_probe_logcap "$dir" INNGEST_MAX_PAGES=2
  if [[ "$RC" -eq 1 ]]; then echo "  PASS: ceiling abort exits 1"; PASS=$((PASS+1)); else echo "  FAIL: ceiling abort rc=$RC"; FAIL=$((FAIL+1)); fi
  if echo "$MARKERS_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_TIMEOUT .*reason=page_ceiling'; then
    echo "  PASS: TIMEOUT reason=page_ceiling marker"; PASS=$((PASS+1));
  else echo "  FAIL: no TIMEOUT reason=page_ceiling marker (markers=$MARKERS_CAP)"; FAIL=$((FAIL+1)); fi
  # A page-ceiling abort must also refuse to emit a truncated (false-clean) parseable body.
  if echo "$STDOUT_CAP" | jq -e '.runs' >/dev/null 2>&1; then
    echo "  FAIL: stdout is a jq-parseable .runs object on a page-ceiling abort (false-clean)"; FAIL=$((FAIL+1));
  else echo "  PASS: stdout NOT a jq-parseable .runs object on page-ceiling abort"; PASS=$((PASS+1)); fi
  # exact-fit: 2-page corpus with MAX_PAGES=2 breaks clean
  local dir2; dir2=$(mktemp -d)
  make_page true "CURx" "[$(make_edge r1 fn-a 2026-07-08T10:00:00Z)]" > "$dir2/page-1.json"
  make_page false "" "[$(make_edge r2 fn-a 2026-07-08T10:01:00Z)]" > "$dir2/page-2.json"
  local rc2=0 out2
  out2=$(INNGEST_DOUBLEFIRE_RUNS_FIXTURE="$dir2" INNGEST_MAX_PAGES=2 bash "$TARGET" 2>/dev/null) || rc2=$?
  if [[ "$rc2" -eq 0 ]] && echo "$out2" | jq -e '.runs | length == 2' >/dev/null 2>&1; then
    echo "  PASS: exact-fit corpus (pages == MAX_PAGES) breaks clean (2 runs)"; PASS=$((PASS+1));
  else echo "  FAIL: exact-fit corpus did not break clean (rc=$rc2 out=$out2)"; FAIL=$((FAIL+1)); fi
  rm -rf "$dir" "$dir2"
}

# --- #6258 T3: happy path → START+DONE in journald, stdout stays pure JSON ---
test_df_markers_journald_only() {
  echo "TEST: doublefire-probe — START+DONE journald-only, stdout stays pure JSON"
  local dir; dir=$(mktemp -d)
  make_page false "" "[$(make_edge run-1 fn-a 2026-07-08T10:00:00Z)]" > "$dir/page-1.json"
  run_probe_logcap "$dir"
  if [[ "$RC" -eq 0 ]]; then echo "  PASS: happy path exits 0"; PASS=$((PASS+1)); else echo "  FAIL: happy path rc=$RC"; FAIL=$((FAIL+1)); fi
  if echo "$STDOUT_CAP" | jq -e '.runs | type == "array"' >/dev/null 2>&1 && ! echo "$STDOUT_CAP" | grep -q SOLEUR; then
    echo "  PASS: stdout is a pure {runs} object, no marker leaked"; PASS=$((PASS+1));
  else echo "  FAIL: stdout polluted or missing runs (out=$STDOUT_CAP)"; FAIL=$((FAIL+1)); fi
  echo "$MARKERS_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_START op=verify-doublefire' \
    && { echo "  PASS: START in journald"; PASS=$((PASS+1)); } || { echo "  FAIL: no START (markers=$MARKERS_CAP)"; FAIL=$((FAIL+1)); }
  echo "$MARKERS_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_DONE op=verify-doublefire pages=' \
    && { echo "  PASS: DONE in journald"; PASS=$((PASS+1)); } || { echo "  FAIL: no DONE (markers=$MARKERS_CAP)"; FAIL=$((FAIL+1)); }
  rm -rf "$dir"
}

# --- #6258 T4: connect-timeout + remaining-budget clamp (sum-bound by construction) ---
test_df_connect_timeout_and_clamp() {
  echo "TEST: doublefire-probe — --connect-timeout + remaining-budget curl clamp"
  if grep -qE 'curl[^|]*--connect-timeout' "$TARGET"; then echo "  PASS: --connect-timeout present"; PASS=$((PASS+1));
  else echo "  FAIL: no --connect-timeout"; FAIL=$((FAIL+1)); fi
  if grep -qE 'max-time "\$max_time"' "$TARGET" && grep -qE 'remaining=\$\(\( PREFLIGHT_DEADLINE_S - elapsed \)\)' "$TARGET"; then
    echo "  PASS: per-page curl clamped to remaining budget"; PASS=$((PASS+1));
  else echo "  FAIL: per-page curl not clamped to remaining budget"; FAIL=$((FAIL+1)); fi
}

# --- #6258 T5: window ⊇ cutover window — the time window is NEVER narrowed (Finding 5) ---
# Narrowing INNGEST_DOUBLEFIRE_FROM/UNTIL below the operator window feeds false "missed
# ticks" → operator re-fire → DOUBLE-FIRE. The default FROM is the 365-day clamp (⊇ any
# realistic cutover window); cost is cut via functionIDs + page ceiling, not a narrow window.
test_df_window_not_narrowed() {
  echo "TEST: doublefire-probe — default window is the 365-day clamp (⊇ cutover window)"
  if grep -q '365 days ago' "$TARGET"; then echo "  PASS: 365-day FROM clamp present (window ⊇ cutover)"; PASS=$((PASS+1));
  else echo "  FAIL: 365-day FROM clamp missing (window may be narrowed → false missed-ticks)"; FAIL=$((FAIL+1)); fi
  # a run inside a wide window but nominally 'old' is still observed (no client-side window narrowing).
  local dir; dir=$(mktemp -d)
  make_page false "" "[$(make_edge old-run fn-a 2025-09-01T00:00:00Z)]" > "$dir/page-1.json"
  local out; out=$(INNGEST_DOUBLEFIRE_RUNS_FIXTURE="$dir" bash "$TARGET" 2>/dev/null)
  assert_eq "an 'old' run inside the window is still observed (no false missed-tick)" "1" "$(echo "$out" | jq -r '.runs | length')"
  # cost lever is functionIDs, not a window narrow: build_request_body carries functionIDs.
  if grep -q 'functionIDs:\$fnids' "$TARGET"; then echo "  PASS: cost cut via functionIDs filter"; PASS=$((PASS+1));
  else echo "  FAIL: no functionIDs filter (cost lever missing)"; FAIL=$((FAIL+1)); fi
  rm -rf "$dir"
}

# --- #6258 T6: marker purity — no URI / actor@host:port / raw GraphQL message ---
test_df_marker_purity() {
  echo "TEST: doublefire-probe — marker purity (enum/count only)"
  local dir; dir=$(mktemp -d)
  printf '%s' '{"errors":[{"message":"FATAL password for postgres://u:p@10.0.1.40:5432/db"}],"data":null}' > "$dir/page-1.json"
  run_probe_logcap "$dir"
  local soleur; soleur=$(echo "$MARKERS_CAP" | grep SOLEUR_INNGEST_PREFLIGHT || true)
  assert_eq "no '://' in any SOLEUR marker" "0" "$(echo "$soleur" | grep -c '://' || true)"
  assert_eq "no user:pass@host:port in any SOLEUR marker" "0" "$(echo "$soleur" | grep -cE '@[^ ]+:[0-9]+' || true)"
  assert_eq "raw GraphQL message never verbatim (reason=enum)" "0" "$(echo "$soleur" | grep -c 'password' || true)"
  # #6258 review P1: scrub the DSN from the sibling FATAL/ERROR diagnostics too —
  # journald (→ Better Stack) AND stdout (→ the Actions run log), not just SOLEUR markers.
  assert_eq "no '://' URI in ANY journald line (incl. error diagnostics)" "0" "$(echo "$MARKERS_CAP" | grep -c '://' || true)"
  assert_eq "no user:pass@host:port DSN in ANY journald line" "0" "$(echo "$MARKERS_CAP" | grep -cE '@[^ ]+:[0-9]+' || true)"
  assert_eq "no '://' URI on stdout (run log)" "0" "$(echo "$STDOUT_CAP" | grep -c '://' || true)"
  assert_eq "no user:pass@host:port DSN on stdout" "0" "$(echo "$STDOUT_CAP" | grep -cE '@[^ ]+:[0-9]+' || true)"
  rm -rf "$dir"
}

# --- #6258 T7: marker tag present in vector.toml allowlist (drift guard) ---
test_df_marker_tag_in_vector() {
  echo "TEST: doublefire-probe — inngest-doublefire-probe tag in vector.toml allowlist"
  local vector="$SCRIPT_DIR/vector.toml"
  if grep -qE '^[[:space:]]*"inngest-doublefire-probe",' "$vector"; then echo "  PASS: tag in vector.toml"; PASS=$((PASS+1));
  else echo "  FAIL: tag NOT in vector.toml (marker would not ship)"; FAIL=$((FAIL+1)); fi
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
test_df_deadline_abort
test_df_page_ceiling_abort
test_df_markers_journald_only
test_df_connect_timeout_and_clamp
test_df_window_not_narrowed
test_df_marker_purity
test_df_marker_tag_in_vector
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi

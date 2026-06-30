#!/usr/bin/env bash
# Tests for inngest-enumerate-reminders.sh — the no-SSH cutover step-2 enumeration
# (#5450). Verifies the script reconstructs FULL re-armable records from the
# inngest v1.19.4 eventsV2 `raw` envelope, drops already-fired events (terminal
# `runs` status), drops past-dated events (client-side `occurredAt`/`ts` filter —
# the server `from`/`until` bounds receivedAt, NOT fire-time), and paginates the
# cursor to exhaustion.
#
# Schema pinned in knowledge-base/project/specs/feat-one-shot-inngest-cutover-no-ssh-5450/inngest-graphql-schema.md
#
# Test seam: the script reads page N from "${INNGEST_GQL_FIXTURE_DIR}/page-N.json"
# instead of curling when INNGEST_GQL_FIXTURE_DIR is set, and uses ENUMERATE_NOW_MS
# for a deterministic "now". No network, no inngest, no root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-enumerate-reminders.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc — '$needle' not found"; FAIL=$((FAIL + 1)); fi
}

# NOW = 2026-06-17T12:00:00Z = 1781784000000 ms. Future fire = 2026-06-18 (the
# #5432-class armed reminder). Past fire = 2026-06-01.
readonly NOW_MS=1781784000000
readonly FUTURE_MS=1781870400000   # 2026-06-18T12:00:00Z
readonly PAST_MS=1780358400000     # 2026-06-01T12:00:00Z

# Build a v1.19.4-shaped eventsV2 page. Args: <hasNextPage> <endCursor> <edges-json>
make_page() {
  local has_next="$1" end_cursor="$2" edges="$3"
  jq -nc --argjson hn "$has_next" --arg ec "$end_cursor" --argjson edges "$edges" \
    '{data:{eventsV2:{totalCount:($edges|length),pageInfo:{hasNextPage:$hn,endCursor:$ec},edges:$edges}}}'
}

# Build one edge. Args: <ulid> <reminder_id> <fire_ms> <runs-json>
make_edge() {
  local ulid="$1" rid="$2" fire_ms="$3" runs="$4"
  local occurred; occurred=$(date -u -d "@$((fire_ms/1000))" +%Y-%m-%dT%H:%M:%SZ)
  # raw is the JSON-STRING envelope the producer sent (per schema pin).
  local raw; raw=$(jq -nc --arg rid "$rid" --arg fa "$occurred" --argjson ts "$fire_ms" \
    '{data:{reminder_id:$rid,fire_at:$fa,actor:"platform",action:{type:"issue-comment",issue:7,body:"SECRET-BODY"}},id:$rid,name:"reminder.scheduled",ts:$ts,v:null}')
  jq -nc --arg ulid "$ulid" --arg occ "$occurred" --arg raw "$raw" --argjson runs "$runs" \
    '{cursor:$ulid,node:{id:$ulid,name:"reminder.scheduled",occurredAt:$occ,receivedAt:"2026-06-10T00:00:00Z",idempotencyKey:null,raw:$raw,runs:$runs}}'
}

run_enum() {
  local dir="$1"
  INNGEST_GQL_FIXTURE_DIR="$dir" ENUMERATE_NOW_MS="$NOW_MS" bash "$TARGET" 2>/dev/null
}

# Build a page with $3 synthesized bulk reminder.scheduled edges (one jq call, fast) so
# the eventsV2 accumulator can be driven past MAX_ARG_STRLEN without thousands of
# make_edge spawns (#5523). $1=hasNextPage $2=endCursor $3=count $4=fire_ms (bulk edges
# share one fire time — past-dated → dropped by the future filter, keeping records small)
# $5=extra-edges-json (default []).
make_bulk_page() {
  local hn="$1" ec="$2" n="$3" fire_ms="$4" extra="${5:-[]}"
  jq -nc --argjson hn "$hn" --arg ec "$ec" --argjson n "$n" --argjson ts "$fire_ms" --argjson extra "$extra" '
    {data:{eventsV2:{
      totalCount:($n + ($extra|length)),
      pageInfo:{hasNextPage:$hn,endCursor:$ec},
      edges:( [ range($n) as $i | {
        cursor:("bulk-\($i)"),
        node:{id:("bulk-\($i)"),name:"reminder.scheduled",occurredAt:"2026-06-01T12:00:00Z",
              receivedAt:"2026-06-10T00:00:00Z",idempotencyKey:null,
              raw:({data:{reminder_id:("bulk-\($i)"),fire_at:"2026-06-01T12:00:00Z",actor:"platform",action:{type:"issue-comment",issue:7,body:"SECRET-BODY"}},id:("bulk-\($i)"),name:"reminder.scheduled",ts:$ts,v:null}|tojson),
              runs:[]} } ] + $extra )
    }}}'
}

echo "=== inngest-enumerate-reminders.sh tests ==="

assert_eq "script exists and is executable" "1" "$([[ -x "$TARGET" ]] && echo 1 || echo 0)"

# --- Test 1: future-dated, no runs → INCLUDED with full re-armable payload ---
test_future_unfired_included() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  make_page false "" "[$(make_edge "01ULIDFUTURE" "rem-future" "$FUTURE_MS" "[]")]" > "$d/page-1.json"
  local out; out=$(run_enum "$d")
  assert_eq "one record emitted" "1" "$(echo "$out" | jq 'length')"
  assert_eq "reminder_id reconstructed from raw.data" "rem-future" "$(echo "$out" | jq -r '.[0].reminder_id')"
  assert_eq "actor preserved (route 400s without it)" "platform" "$(echo "$out" | jq -r '.[0].actor')"
  local expect_fire; expect_fire=$(date -u -d "@$((FUTURE_MS/1000))" +%Y-%m-%dT%H:%M:%SZ)
  assert_eq "fire_at preserved" "$expect_fire" "$(echo "$out" | jq -r '.[0].fire_at')"
  assert_eq "action object preserved" "issue-comment" "$(echo "$out" | jq -r '.[0].action.type')"
}

# --- Test 2: already-fired (COMPLETED run) → DROPPED ---
test_completed_dropped() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  local edges; edges=$(jq -nc --argjson a "$(make_edge "01ULIDDONE" "rem-done" "$FUTURE_MS" '[{"id":"r1","status":"COMPLETED","startedAt":null,"endedAt":null}]')" '[$a]')
  make_page false "" "$edges" > "$d/page-1.json"
  assert_eq "completed event dropped" "0" "$(run_enum "$d" | jq 'length')"
}

# --- Test 3: past-dated (client-side occurredAt filter) → DROPPED even with no runs ---
test_past_dropped() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  make_page false "" "[$(make_edge "01ULIDPAST" "rem-past" "$PAST_MS" "[]")]" > "$d/page-1.json"
  assert_eq "past-dated event dropped (server from= bounds receivedAt not fire-time)" "0" "$(run_enum "$d" | jq 'length')"
}

# --- Test 4: CANCELLED/FAILED/SKIPPED terminal runs → DROPPED; RUNNING/QUEUED → KEPT ---
test_terminal_status_matrix() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  local e_cancel e_fail e_skip e_running e_queued edges
  e_cancel=$(make_edge "01C" "rem-c" "$FUTURE_MS" '[{"id":"r","status":"CANCELLED","startedAt":null,"endedAt":null}]')
  e_fail=$(make_edge "01F" "rem-f" "$FUTURE_MS" '[{"id":"r","status":"FAILED","startedAt":null,"endedAt":null}]')
  e_skip=$(make_edge "01S" "rem-s" "$FUTURE_MS" '[{"id":"r","status":"SKIPPED","startedAt":null,"endedAt":null}]')
  e_running=$(make_edge "01R" "rem-r" "$FUTURE_MS" '[{"id":"r","status":"RUNNING","startedAt":null,"endedAt":null}]')
  e_queued=$(make_edge "01Q" "rem-q" "$FUTURE_MS" '[{"id":"r","status":"QUEUED","startedAt":null,"endedAt":null}]')
  edges=$(jq -nc --argjson a "$e_cancel" --argjson b "$e_fail" --argjson c "$e_skip" --argjson dd "$e_running" --argjson e "$e_queued" '[$a,$b,$c,$dd,$e]')
  make_page false "" "$edges" > "$d/page-1.json"
  local out; out=$(run_enum "$d")
  assert_eq "terminal CANCELLED/FAILED/SKIPPED dropped; RUNNING/QUEUED kept" "2" "$(echo "$out" | jq 'length')"
  assert_eq "kept set is exactly the non-terminal ids" "rem-q,rem-r" "$(echo "$out" | jq -r '[.[].reminder_id]|sort|join(",")')"
}

# --- Test 5: pagination — a future reminder on PAGE 2 is still captured ---
test_pagination_page2_captured() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  make_page true "CURSOR1" "[$(make_edge "01P1" "rem-p1" "$PAST_MS" "[]")]" > "$d/page-1.json"
  make_page false "" "[$(make_edge "01P2" "rem-p2" "$FUTURE_MS" "[]")]" > "$d/page-2.json"
  local out; out=$(run_enum "$d")
  assert_eq "page-2 future reminder captured" "1" "$(echo "$out" | jq 'length')"
  assert_eq "page-2 reminder_id correct" "rem-p2" "$(echo "$out" | jq -r '.[0].reminder_id')"
}

# --- Test 6 (#5503): SUCCESS-path output must be PURE JSON on the webhook stream ---
# adnanh/webhook v2.8.2 returns cmd.CombinedOutput() (stdout AND stderr) even on a 200,
# and the cutover workflow parses that body as a JSON array (`jq -e 'type == "array"'`).
# So the success path must write NOTHING non-JSON to EITHER stream; the observability
# summary goes to journald via `logger` ONLY. RED before #5503 (the stderr summary was
# merged ahead of the JSON → array parse failed → cutover blocked); GREEN after.
# (Replaces the former stderr-summary assertion — that summary no longer exists on stderr.)
test_success_combined_output_pure_json() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  make_page false "" "[$(make_edge "01L" "rem-log" "$FUTURE_MS" "[]")]" > "$d/page-1.json"
  # Combined stdout+stderr, mimicking the webhook CombinedOutput the workflow parses.
  local combined; combined=$(INNGEST_GQL_FIXTURE_DIR="$d" ENUMERATE_NOW_MS="$NOW_MS" bash "$TARGET" 2>&1)
  if echo "$combined" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "  PASS: combined stdout+stderr parses as a JSON array"; PASS=$((PASS + 1));
  else
    echo "  FAIL: combined stdout+stderr is NOT a pure JSON array (success-path stream pollution)"; FAIL=$((FAIL + 1)); fi
  assert_eq "combined output is the 1-record array" "1" "$(echo "$combined" | jq 'length' 2>/dev/null || echo BAD)"
  # The summary is journald-only now: success-path stderr must be empty, so no prose
  # (and so no reminder_id / comment body) can leak into the webhook response stream.
  local err; err=$(INNGEST_GQL_FIXTURE_DIR="$d" ENUMERATE_NOW_MS="$NOW_MS" bash "$TARGET" 2>&1 1>/dev/null)
  assert_eq "success-path stderr is empty (summary is journald-only)" "" "$err"
}

# --- Test 7: empty event set → emits [] (not an error) ---
test_empty_set() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  make_page false "" "[]" > "$d/page-1.json"
  assert_eq "empty set emits []" "0" "$(run_enum "$d" | jq 'length')"
}

# --- Test 8: jq -n --arg body construction (injection-safe), shellcheck-clean source ---
test_no_shell_string_interpolation_in_gql() {
  # The GraphQL request body must be built with jq -n (no bare shell var splice
  # into the JSON request). Assert the source uses `jq -n` for the request body.
  assert_contains "GraphQL request body built with jq -n" "$(cat "$TARGET")" "jq -n"
}

# --- Test 9 (#5492 AC6): the DEFAULT filter.from is a recent instant, NOT epoch ---
# Sources the script with NO ENUMERATE_FROM override and invokes build_request_body
# directly (sourcing does not run the network loop — BASH_SOURCE guard). RED before
# the AC5 clamp (epoch default), GREEN after. The epoch 1970 default is what inngest
# rejected as an out-of-range Time! bound → the opaque 500 (#5492 root cause).
test_default_from_is_recent_not_epoch() {
  local from
  # Fresh `bash -c` (NOT in-process `source` — this test file marks NOW_MS readonly,
  # which a same-process subshell would inherit and the script's NOW_MS= would then
  # fail to assign). `bash -c 'source X'` has BASH_SOURCE!=$0 so the network loop
  # stays guarded; a fresh exec does not inherit the readonly.
  from=$(unset ENUMERATE_FROM; bash -c 'source "$1"; build_request_body ""' _ "$TARGET" | jq -r '.variables.filter.from')
  assert_eq "default filter.from is not the 1970 epoch" "0" "$([[ "$from" == 1970-* ]] && echo 1 || echo 0)"
  # Within the last ~2 years (clamped recent lookback), and a real ISO instant.
  local from_year now_year
  from_year=${from:0:4}; now_year=$(date -u +%Y)
  assert_eq "default filter.from year is within 2 years of now" "1" \
    "$([[ "$from_year" =~ ^[0-9]{4}$ && $((now_year - from_year)) -le 2 && $((now_year - from_year)) -ge 0 ]] && echo 1 || echo 0)"
  # ENUMERATE_FROM still wins (it IS the override — no second env var).
  local overridden
  overridden=$(ENUMERATE_FROM="2099-01-01T00:00:00Z" bash -c 'source "$1"; build_request_body ""' _ "$TARGET" | jq -r '.variables.filter.from')
  assert_eq "ENUMERATE_FROM override wins" "2099-01-01T00:00:00Z" "$overridden"
}

# --- Test 10 (#5492 AC7): malformed-response cause carries NO payload on EITHER stream ---
# webhook CombinedOutput() captures stdout+stderr and the workflow cats the body
# into the run log, so the assertion is against the COMBINED stream (2>&1), NOT
# stdout-only. Two leak vectors: a secret in .errors[].extensions, and a secret in
# a .data value. Only error MESSAGES + .data key NAMES may surface.
test_malformed_cause_no_payload_leak() {
  local d out rc
  # Vector 1: secret in an error's extensions (the whole .errors must NOT be dumped).
  d=$(mktemp -d)
  printf '%s' '{"errors":[{"message":"invalid Time bound","extensions":{"secret":"SECRET-EXT-XYZ"}}]}' > "$d/page-1.json"
  rc=0; out=$(INNGEST_GQL_FIXTURE_DIR="$d" ENUMERATE_NOW_MS="$NOW_MS" bash "$TARGET" 2>&1) || rc=$?
  rm -rf "$d"
  assert_eq "malformed response exits non-zero" "1" "$rc"
  assert_contains "combined output carries the upstream GraphQL message" "$out" "invalid Time bound"
  if [[ "$out" == *"SECRET-EXT-XYZ"* ]]; then
    echo "  FAIL: error.extensions secret leaked into combined output"; FAIL=$((FAIL + 1));
  else echo "  PASS: error.extensions secret NOT leaked (combined stdout+stderr)"; PASS=$((PASS + 1)); fi
  # Vector 2: secret in a .data value (well-formed-but-unexpected — no .data.eventsV2).
  d=$(mktemp -d)
  printf '%s' '{"data":{"eventsV2OTHER":{"raw":"SECRET-DATA-XYZ"}}}' > "$d/page-1.json"
  rc=0; out=$(INNGEST_GQL_FIXTURE_DIR="$d" ENUMERATE_NOW_MS="$NOW_MS" bash "$TARGET" 2>&1) || rc=$?
  rm -rf "$d"
  assert_eq "data-bearing malformed response exits non-zero" "1" "$rc"
  if [[ "$out" == *"SECRET-DATA-XYZ"* ]]; then
    echo "  FAIL: .data value leaked into combined output"; FAIL=$((FAIL + 1));
  else echo "  PASS: .data value NOT leaked (combined stdout+stderr; only key names surface)"; PASS=$((PASS + 1)); fi
}

# --- Test 11 (#5523 AC3-overflow): large accumulated edge set does NOT overflow MAX_ARG_STRLEN ---
# RED against the pre-fix per-page argv accumulation (jq -nc --argjson a <accumulator>):
# once the RUNNING accumulator crosses the ~128 KB per-arg ceiling it trips
# `jq: Argument list too long` (the live HTTP 500). GREEN after the mktemp +
# `jq -s 'add // []'` file-spool fix. Calibrated at authoring time: 5 pages × 400
# past-dated reminder edges builds a running accumulator past the ceiling by ~page 3;
# each page stays under the per-arg limit, so this exercises the accumulator overflow
# specifically. A future reminder on the LAST page proves the fix accumulates ALL pages.
test_large_accumulator_no_argv_overflow() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  local i
  for i in 1 2 3 4; do
    make_bulk_page true "CUR$i" 400 "$PAST_MS" "[]" > "$d/page-$i.json"
  done
  make_bulk_page false "" 400 "$PAST_MS" \
    "[$(make_edge "01CANARY" "rem-overflow-canary" "$FUTURE_MS" "[]")]" > "$d/page-5.json"
  local out rc=0
  out=$(run_enum "$d") || rc=$?
  assert_eq "large accumulated edge set exits 0 (no MAX_ARG_STRLEN overflow)" "0" "$rc"
  assert_eq "only the last-page future reminder survives (all pages collapsed)" "rem-overflow-canary" "$(echo "$out" | jq -r '[.[].reminder_id] | join(",")')"
}

# --- Test 12 (#5523 AC3-structural): accumulation never passes the running accumulator via argv ---
# Anchored on the EXACT accumulator string — NOT a bare --argjson — so the legitimate
# `--argjson first/after` in build_request_body does not false-trip it.
test_no_argv_accumulation() {
  if grep -qE 'argjson a "\$all_edges"' "$TARGET"; then
    echo "  FAIL: argv accumulation (jq --argjson a accumulator) reintroduced — overflows MAX_ARG_STRLEN"; FAIL=$((FAIL+1));
  else echo "  PASS: no argv accumulation of the running edge set"; PASS=$((PASS+1)); fi
  if grep -qE 'jq -s|--slurpfile' "$TARGET"; then
    echo "  PASS: accumulation collapses a spool file (jq -s / --slurpfile)"; PASS=$((PASS+1));
  else echo "  FAIL: no file-based accumulation (jq -s / --slurpfile) found"; FAIL=$((FAIL+1)); fi
}

# --- Test 13 (#5523 cleanup): the spool temp file is cleaned on a FATAL exit path ---
# The mktemp spool is created before the loop; a malformed page exits 1 from inside it.
# The in-function `trap 'rm -f ...' EXIT` (NOT RETURN — RETURN does not fire on `exit`)
# must still clean the spool. Isolate mktemp via a private TMPDIR and assert nothing survives.
test_fatal_cleans_spool_tempfile() {
  local d; d=$(mktemp -d); local tmpd; tmpd=$(mktemp -d)
  trap 'rm -rf "$d" "$tmpd"' RETURN
  printf '%s' '{"data":{"eventsV2OTHER":{}}}' > "$d/page-1.json"
  local rc=0
  TMPDIR="$tmpd" INNGEST_GQL_FIXTURE_DIR="$d" ENUMERATE_NOW_MS="$NOW_MS" bash "$TARGET" >/dev/null 2>&1 || rc=$?
  assert_eq "malformed page exits non-zero (FATAL)" "1" "$rc"
  local leftover; leftover=$(find "$tmpd" -type f 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "no spool temp file leaked on FATAL exit (EXIT trap fired)" "0" "$leftover"
}

test_future_unfired_included
test_completed_dropped
test_past_dropped
test_terminal_status_matrix
test_pagination_page2_captured
test_success_combined_output_pure_json
test_empty_set
test_no_shell_string_interpolation_in_gql
test_default_from_is_recent_not_epoch
test_malformed_cause_no_payload_leak
test_large_accumulator_no_argv_overflow
test_no_argv_accumulation
test_fatal_cleans_spool_tempfile

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0

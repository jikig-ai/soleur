#!/usr/bin/env bash
# Tests for inngest-inventory.sh — the no-SSH full-state cutover inventory (#5509).
# Verifies it returns a single pure-JSON OBJECT {functions, event_names,
# armed_reminders} on stdout (the #5503 combined-stream-purity invariant: the
# webhook returns CombinedOutput and the workflow jq-parses the body as an object),
# derives event_names as the DISTINCT set across ALL events (not just
# reminder.scheduled), and reuses enumerate's armed-reminder projection.
#
# Test seam: INNGEST_GQL_FIXTURE_DIR (page-N.json eventsV2 pages),
# INVENTORY_FUNCTIONS_FIXTURE (a /v1/functions JSON file), INVENTORY_NOW_MS.
# No network, no inngest, no root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-inventory.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

readonly NOW_MS=1781784000000        # 2026-06-17T12:00:00Z
readonly FUTURE_MS=1781870400000     # 2026-06-18T12:00:00Z
readonly PAST_MS=1780358400000       # 2026-06-01T12:00:00Z

# Build a v1.19.4-shaped eventsV2 page. Args: <hasNextPage> <endCursor> <edges-json>
make_page() {
  local has_next="$1" end_cursor="$2" edges="$3"
  jq -nc --argjson hn "$has_next" --arg ec "$end_cursor" --argjson edges "$edges" \
    '{data:{eventsV2:{totalCount:($edges|length),pageInfo:{hasNextPage:$hn,endCursor:$ec},edges:$edges}}}'
}

# Build one edge. Args: <ulid> <event_name> <reminder_id> <fire_ms> <runs-json>
# Non-reminder events (cron/*) carry a minimal raw envelope.
make_edge() {
  local ulid="$1" name="$2" rid="$3" fire_ms="$4" runs="$5"
  local occurred; occurred=$(date -u -d "@$((fire_ms/1000))" +%Y-%m-%dT%H:%M:%SZ)
  local raw
  if [[ "$name" == "reminder.scheduled" ]]; then
    raw=$(jq -nc --arg rid "$rid" --arg fa "$occurred" --argjson ts "$fire_ms" \
      '{data:{reminder_id:$rid,fire_at:$fa,actor:"platform",action:{type:"issue-comment",issue:7,body:"SECRET-BODY"}},id:$rid,name:"reminder.scheduled",ts:$ts,v:null}')
  else
    raw=$(jq -nc --arg n "$name" --argjson ts "$fire_ms" '{data:{},id:"x",name:$n,ts:$ts,v:null}')
  fi
  jq -nc --arg ulid "$ulid" --arg occ "$occurred" --arg nm "$name" --arg raw "$raw" --argjson runs "$runs" \
    '{cursor:$ulid,node:{id:$ulid,name:$nm,occurredAt:$occ,receivedAt:"2026-06-10T00:00:00Z",idempotencyKey:null,raw:$raw,runs:$runs}}'
}

make_functions() {  # $1 = JSON array of names
  jq -nc --argjson names "$1" '[ $names[] | {name:., slug:., triggers:[]} ]'
}

# Run the script with fixtures; $1=page-dir, $2=functions-fixture-file. Returns stdout only.
run_inv() {
  INNGEST_GQL_FIXTURE_DIR="$1" INVENTORY_FUNCTIONS_FIXTURE="$2" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" 2>/dev/null
}

echo "=== inngest-inventory.sh tests ==="

assert_eq "script exists and is executable" "1" "$([[ -x "$TARGET" ]] && echo 1 || echo 0)"

# --- Test 1 (#5503): SUCCESS-path COMBINED stream is a pure JSON object ---
test_combined_is_pure_json_object() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '["cron-daily-triage","cron-bug-fixer"]' > "$ff"
  make_page false "" "[$(make_edge 01A reminder.scheduled rem-fut "$FUTURE_MS" "[]")]" > "$d/page-1.json"
  local combined
  combined=$(INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" 2>&1)
  if echo "$combined" | jq -e 'type == "object" and has("functions") and has("event_names") and has("armed_reminders")' >/dev/null 2>&1; then
    echo "  PASS: combined stdout+stderr is a JSON object with all 3 keys"; PASS=$((PASS + 1));
  else
    echo "  FAIL: combined stdout+stderr is NOT a pure 3-key JSON object (success-path stream pollution)"; FAIL=$((FAIL + 1)); fi
  # success-path stderr empty (summary is journald-only)
  local err; err=$(INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" 2>&1 1>/dev/null)
  assert_eq "success-path stderr is empty (summary journald-only)" "" "$err"
}

# --- Test 2: functions = sorted names from /v1/functions ---
test_functions_names() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '["cron-zeta","cron-alpha"]' > "$ff"
  make_page false "" "[]" > "$d/page-1.json"
  local out; out=$(run_inv "$d" "$ff")
  assert_eq "functions sorted names" "cron-alpha,cron-zeta" "$(echo "$out" | jq -r '.functions | join(",")')"
}

# --- Test 3: event_names = DISTINCT sorted set across ALL events (not just reminders) ---
test_event_names_distinct_all() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '[]' > "$ff"
  local edges; edges="[$(make_edge 01A reminder.scheduled rem1 "$FUTURE_MS" "[]"),$(make_edge 01B "cron/daily-triage" "" "$PAST_MS" "[]"),$(make_edge 01C reminder.scheduled rem2 "$PAST_MS" "[]")]"
  make_page false "" "$edges" > "$d/page-1.json"
  local out; out=$(run_inv "$d" "$ff")
  assert_eq "event_names distinct+sorted, incl non-reminder" "cron/daily-triage,reminder.scheduled" "$(echo "$out" | jq -r '.event_names | join(",")')"
}

# --- Test 4: armed_reminders = enumerate projection (future-fire AND non-terminal) ---
test_armed_projection() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '[]' > "$ff"
  # future+empty-runs (keep), future+COMPLETED (drop), past+empty (drop), cron (ignored)
  local edges; edges="[$(make_edge 01A reminder.scheduled rem-keep "$FUTURE_MS" "[]"),$(make_edge 01B reminder.scheduled rem-fired "$FUTURE_MS" '[{"id":"r","status":"COMPLETED","startedAt":null,"endedAt":null}]'),$(make_edge 01C reminder.scheduled rem-past "$PAST_MS" "[]"),$(make_edge 01D "cron/x" "" "$FUTURE_MS" "[]")]"
  make_page false "" "$edges" > "$d/page-1.json"
  local out; out=$(run_inv "$d" "$ff")
  assert_eq "armed_reminders = only future+non-terminal reminder" "rem-keep" "$(echo "$out" | jq -r '[.armed_reminders[].reminder_id] | join(",")')"
  assert_eq "armed record preserves action (re-arm fidelity)" "issue-comment" "$(echo "$out" | jq -r '.armed_reminders[0].action.type')"
}

# --- Test 5: pagination to exhaustion ---
test_pagination() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '[]' > "$ff"
  make_page true "CUR1" "[$(make_edge 01P1 "cron/a" "" "$PAST_MS" "[]")]" > "$d/page-1.json"
  make_page false "" "[$(make_edge 01P2 reminder.scheduled rem-p2 "$FUTURE_MS" "[]")]" > "$d/page-2.json"
  local out; out=$(run_inv "$d" "$ff")
  assert_eq "page-2 event captured (event_names spans pages)" "cron/a,reminder.scheduled" "$(echo "$out" | jq -r '.event_names | join(",")')"
  assert_eq "page-2 armed reminder captured" "rem-p2" "$(echo "$out" | jq -r '[.armed_reminders[].reminder_id] | join(",")')"
}

# --- Test 6: no payload-body leak in the journald SUMMARY (logger stub on PATH) ---
test_summary_no_body_leak() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); local bindir; bindir=$(mktemp -d); local logout; logout=$(mktemp)
  trap 'rm -rf "$d" "$ff" "$bindir" "$logout"' RETURN
  # logger stub: capture every "logger" invocation's args to $logout
  cat > "$bindir/logger" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$logout"
STUB
  chmod +x "$bindir/logger"
  make_functions '[]' > "$ff"
  make_page false "" "[$(make_edge 01A reminder.scheduled rem-secret "$FUTURE_MS" "[]")]" > "$d/page-1.json"
  PATH="$bindir:$PATH" INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" >/dev/null 2>&1
  local summary; summary=$(cat "$logout" 2>/dev/null || echo "")
  # summary mentions the reminder_id (counts + ids) ...
  if [[ "$summary" == *"rem-secret"* ]]; then echo "  PASS: journald summary carries reminder_id"; PASS=$((PASS+1));
  else echo "  FAIL: journald summary missing reminder_id"; FAIL=$((FAIL+1)); fi
  # ... but NOT the comment body
  if [[ "$summary" == *"SECRET-BODY"* ]]; then echo "  FAIL: comment body leaked into journald summary"; FAIL=$((FAIL+1));
  else echo "  PASS: comment body NOT leaked into journald summary"; PASS=$((PASS+1)); fi
}

# --- Test 7: injection-safe GraphQL body via jq -n; shellcheck-clean source ---
test_jq_n_body() {
  if grep -q 'jq -nc' "$TARGET"; then echo "  PASS: GraphQL body built with jq -n"; PASS=$((PASS+1));
  else echo "  FAIL: GraphQL body not built with jq -n"; FAIL=$((FAIL+1)); fi
}

# --- Test 8: empty inngest state → empty arrays, not an error ---
test_empty_state() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '[]' > "$ff"
  make_page false "" "[]" > "$d/page-1.json"
  local out; out=$(run_inv "$d" "$ff")
  assert_eq "empty state → {functions:[],event_names:[],armed_reminders:[]}" '{"functions":[],"event_names":[],"armed_reminders":[]}' "$(echo "$out" | jq -c '.')"
}

# --- Test 9 (#5509 review P3): a degraded /v1/functions read fails LOUD, not false-clean ---
test_functions_fetch_failure_is_loud() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  # Non-array functions body (simulates curl-failure sentinel / error envelope).
  printf '%s' '{"error":"connection refused"}' > "$ff"
  make_page false "" "[]" > "$d/page-1.json"
  local out rc=0
  out=$(INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" 2>/dev/null) || rc=$?
  assert_eq "non-array functions read exits non-zero (no false-clean baseline)" "1" "$rc"
  if [[ "$out" == *"FATAL /v1/functions"* ]]; then echo "  PASS: emits a diagnosable FATAL cause"; PASS=$((PASS+1));
  else echo "  FAIL: no FATAL cause on degraded functions read"; FAIL=$((FAIL+1)); fi
  if [[ "$out" == *'"functions":[]'* ]]; then echo "  FAIL: emitted a false-clean empty functions object"; FAIL=$((FAIL+1));
  else echo "  PASS: did NOT emit a false-clean functions baseline"; PASS=$((PASS+1)); fi
}

test_combined_is_pure_json_object
test_functions_fetch_failure_is_loud
test_functions_names
test_event_names_distinct_all
test_armed_projection
test_pagination
test_summary_no_body_leak
test_jq_n_body
test_empty_state

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]

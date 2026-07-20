#!/usr/bin/env bash
# Tests for inngest-inventory.sh — the no-SSH full-state cutover inventory (#5509).
# Verifies it returns a single pure-JSON OBJECT {functions, event_names,
# armed_reminders} on stdout (the #5503 combined-stream-purity invariant: the
# webhook returns CombinedOutput and the workflow jq-parses the body as an object),
# derives event_names as the DISTINCT set across ALL events (not just
# reminder.scheduled), and reuses enumerate's armed-reminder projection.
#
# Test seam: INNGEST_GQL_FIXTURE_DIR (page-N.json eventsV2 pages),
# INVENTORY_FUNCTIONS_FIXTURE (a /v0/gql functions-query response file, #5517),
# INVENTORY_NOW_MS. No network, no inngest, no root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-inventory.sh"

# #6425: MANDATORY, not a convenience. Every test below runs `bash "$TARGET"`, and the target
# now resolves a host_id. Without this override each invocation issues resolve_host_id's
# `curl --max-time 3` at the link-local metadata address, which BLACKHOLES off-host (measured:
# a full 3.0s per call) — across this suite's invocations that alone exceeds the runner's
# timeout. It also pins determinism: runners have /etc/machine-id, so an unset override falls
# through to a nondeterministic `machine-<id>`. Tests that exercise resolution itself set their
# own value inline (a local assignment wins over this export).
export SOLEUR_HOST_ID_OVERRIDE="hetzner-test-1"

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

# Build a /v0/gql `functions` query response (#5517). The captured real shape is
# {"data":{"functions":[{id,name,slug,triggers}]}} — GET /v1/functions is a 404 in
# inngest v1.19.4, so the projection reads the GraphQL envelope, not a bare array.
make_functions() {  # $1 = JSON array of names
  jq -nc --argjson names "$1" '{data:{functions:[ $names[] | {id:., name:., slug:., triggers:[]} ]}}'
}

# Build a page with $3 synthesized bulk edges (one jq call, fast) so the eventsV2
# accumulator can be driven past MAX_ARG_STRLEN without thousands of make_edge spawns
# (#5523). $1=hasNextPage $2=endCursor $3=count $4=node.name $5=extra-edges-json (default []).
make_bulk_page() {
  local hn="$1" ec="$2" n="$3" name="$4" extra="${5:-[]}"
  jq -nc --argjson hn "$hn" --arg ec "$ec" --argjson n "$n" --arg name "$name" --argjson extra "$extra" '
    {data:{eventsV2:{
      totalCount:($n + ($extra|length)),
      pageInfo:{hasNextPage:$hn,endCursor:$ec},
      edges:( [ range($n) as $i | {
        cursor:("\($name)-\($i)"),
        node:{id:("\($name)-\($i)"),name:$name,occurredAt:"2026-06-10T00:00:00Z",
              receivedAt:"2026-06-10T00:00:00Z",idempotencyKey:null,
              raw:({data:{},id:("\($name)-\($i)"),name:$name,ts:1780358400000,v:null}|tojson),
              runs:[]} } ] + $extra )
    }}}'
}

# Run the script with fixtures; $1=page-dir, $2=functions-fixture-file. Returns stdout only.
run_inv() {
  INNGEST_GQL_FIXTURE_DIR="$1" INVENTORY_FUNCTIONS_FIXTURE="$2" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" 2>/dev/null
}

# Run with the durability seams overlaid on a minimal empty fixture set (so the
# functions/events path is satisfied while we vary ONLY the durability inputs).
# $1 = INVENTORY_EXECSTART value (may be ""), $2 = INVENTORY_REDIS_ACTIVE value.
# Returns stdout only. Mirrors run_inv (#5553).
run_inv_durability() {
  local execstart="$1" redis="$2"
  local d ff out; d=$(mktemp -d); ff=$(mktemp)
  make_functions '[]' > "$ff"
  make_page false "" "[]" > "$d/page-1.json"
  out=$(INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" \
    INVENTORY_EXECSTART="$execstart" INVENTORY_REDIS_ACTIVE="$redis" bash "$TARGET" 2>/dev/null)
  rm -rf "$d" "$ff"
  printf '%s' "$out"
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

# --- Test 2: functions = sorted names from /v0/gql functions ---
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
  # Project the three enumeration keys (durability_state is exercised by the #5553
  # tests and depends on the runner's systemd state, so it is excluded here).
  assert_eq "empty state → {functions:[],event_names:[],armed_reminders:[]}" '{"functions":[],"event_names":[],"armed_reminders":[]}' "$(echo "$out" | jq -c '{functions,event_names,armed_reminders}')"
}

# --- Test 9 (#5509 review P3): a degraded functions read fails LOUD, not false-clean ---
test_functions_fetch_failure_is_loud() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  # A GraphQL error envelope (no .data.functions) — simulates curl-failure sentinel /
  # server error. The corrected guard (.data.functions | type=="array") must trip.
  printf '%s' '{"errors":[{"message":"connection refused"}],"data":null}' > "$ff"
  make_page false "" "[]" > "$d/page-1.json"
  local out rc=0
  out=$(INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" 2>/dev/null) || rc=$?
  assert_eq "non-array functions read exits non-zero (no false-clean baseline)" "1" "$rc"
  if [[ "$out" == "inngest-inventory: FATAL "* && "$out" == *"/v0/gql functions"* ]]; then echo "  PASS: emits a diagnosable FATAL cause"; PASS=$((PASS+1));
  else echo "  FAIL: no FATAL cause on degraded functions read"; FAIL=$((FAIL+1)); fi
  if [[ "$out" == *'"functions":[]'* ]]; then echo "  FAIL: emitted a false-clean empty functions object"; FAIL=$((FAIL+1));
  else echo "  PASS: did NOT emit a false-clean functions baseline"; PASS=$((PASS+1)); fi
}

# --- Test 10 (#5517): functions projected from the captured /v0/gql functions shape ---
# The real shape is {"data":{"functions":[{id,name,slug,...}]}} (GET /v1/functions is a
# 404 in v1.19.4). The projection MUST read .data.functions, and a BARE array (the old
# wrong assumption) must trip the guard rather than be silently accepted.
test_functions_from_gql_shape() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  # Captured-shape fixture: a populated /v0/gql functions response (soleur crons).
  printf '%s' '{"data":{"functions":[{"id":"01J","name":"cron-bug-fixer","slug":"cron-bug-fixer","triggers":[{"type":"CRON","value":"*/30 * * * *"}]},{"id":"01K","name":"cron-daily-triage","slug":"cron-daily-triage","triggers":[{"type":"CRON","value":"0 9 * * *"}]}]}}' > "$ff"
  make_page false "" "[]" > "$d/page-1.json"
  local out; out=$(run_inv "$d" "$ff")
  assert_eq "functions = sorted names projected from .data.functions" "cron-bug-fixer,cron-daily-triage" "$(echo "$out" | jq -r '.functions | join(",")')"

  # A BARE array (the pre-#5517 wrong assumption) has no .data.functions → must FATAL.
  local bf; bf=$(mktemp); trap 'rm -rf "$d" "$ff" "$bf"' RETURN
  printf '%s' '[{"name":"cron-x","slug":"cron-x"}]' > "$bf"
  local brc=0
  INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$bf" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" >/dev/null 2>&1 || brc=$?
  assert_eq "a bare array (old shape) trips the guard (not silently accepted)" "1" "$brc"
}

# --- Test 11 (#5523 AC1): a large accumulated edge set does NOT overflow MAX_ARG_STRLEN ---
# RED against the pre-fix per-page argv accumulation (jq -nc --argjson a <accumulator>):
# once the RUNNING accumulator crosses the ~128 KB per-arg ceiling it
# trips `jq: Argument list too long` (the live HTTP 500). GREEN after the mktemp +
# `jq -s 'add // []'` file-spool fix (file I/O has no argv size limit). Calibrated at
# authoring time: 5 pages × 400 cron edges builds a running accumulator past the
# ceiling by ~page 3; each individual page stays under the limit, so this exercises the
# accumulator overflow specifically (not a single oversized page). A known future
# reminder on the LAST page proves the fix accumulates ALL pages, not just truncates.
test_large_accumulator_no_argv_overflow() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '[]' > "$ff"
  local i
  for i in 1 2 3 4; do
    make_bulk_page true "CUR$i" 400 "cron/bulk" "[]" > "$d/page-$i.json"
  done
  make_bulk_page false "" 400 "cron/bulk" \
    "[$(make_edge 01CANARY reminder.scheduled rem-overflow-canary "$FUTURE_MS" "[]")]" > "$d/page-5.json"
  local out rc=0
  out=$(run_inv "$d" "$ff") || rc=$?
  assert_eq "large accumulated edge set exits 0 (no MAX_ARG_STRLEN overflow)" "0" "$rc"
  assert_eq "event_names spans bulk + reminder across all pages" "cron/bulk,reminder.scheduled" "$(echo "$out" | jq -r '.event_names | join(",")')"
  assert_eq "last-page armed reminder accumulated (all pages collapsed)" "rem-overflow-canary" "$(echo "$out" | jq -r '[.armed_reminders[].reminder_id] | join(",")')"
}

# --- Test 12 (#5523 AC2): accumulation never passes the running accumulator via argv ---
# Structural regression guard: the test FAILs if the argv accumulation form is
# reintroduced, and asserts the accumulation reads from a spool file (jq -s / file arg).
# Anchored on the EXACT accumulator string — NOT a bare --argjson — so the legitimate
# `--argjson first/after` in build_request_body and `--argjson f/e/r` in the final
# object assembly do not false-trip it (Sharp Edges: structural-guard grep specificity).
test_no_argv_accumulation() {
  if grep -qE 'argjson a "\$all_edges"' "$TARGET"; then
    echo "  FAIL: argv accumulation (jq --argjson a \"\$all_edges\") reintroduced — overflows MAX_ARG_STRLEN"; FAIL=$((FAIL+1));
  else echo "  PASS: no argv accumulation of \$all_edges"; PASS=$((PASS+1)); fi
  if grep -qE 'jq -s|--slurpfile' "$TARGET"; then
    echo "  PASS: accumulation collapses a spool file (jq -s / --slurpfile)"; PASS=$((PASS+1));
  else echo "  FAIL: no file-based accumulation (jq -s / --slurpfile) found"; FAIL=$((FAIL+1)); fi
}

# --- Test 13 (#5523 AC5): the spool temp file is cleaned on a FATAL exit path ---
# The mktemp spool is created before the eventsV2 loop; a malformed page exits 1 from
# inside the loop. The in-function `trap 'rm -f ...' EXIT` (NOT RETURN — RETURN does not
# fire on `exit`) must still clean the spool file. Isolate mktemp via a private TMPDIR
# and assert nothing survives.
# --- Test: argv ceiling at the FINAL EMIT — armed_reminders > MAX_ARG_STRLEN (#6736) ---
#
# COVERAGE GAP THIS CLOSES. Test 11/12 prove the PER-PAGE accumulator is spooled, and Test
# 12's own comment explicitly blesses "the legitimate `--argjson f/e/r` in the final object
# assembly" as safe. It was not. Test 11's fixture produces exactly ONE armed reminder and
# two event names, so the final emit it exercises is a few hundred bytes — it never touched
# that binding. `--argjson r "$armed"` made the armed set ONE argv argument, and the kernel
# caps a SINGLE argv argument at MAX_ARG_STRLEN = 131,072 B (NOT `getconf ARG_MAX`, the
# 2,097,152 B argv+envp total); bisected on this host: 131,071 B passes, 131,072 B fails E2BIG.
#
# WHY $armed IS THE UNBOUNDED ONE. It is one object per ARMED REMINDER, produced by a
# dedicated full-window reminder.scheduled scan with no page-ceiling narrowing (#6258
# completeness-by-construction). $functions and $event_names are weakly bounded, but they
# shared the same per-argument budget, so bounding one of the three bounded nothing — all
# three are now `--rawfile … | fromjson`.
#
# ROW COUNT IS NOT THE LOAD-BEARING PARAMETER — BYTES PER REMINDER IS. The projection keeps
# {reminder_id, fire_at, actor, action}, and `action` is the caller-supplied payload. With a
# stub action these rows are ~110 B and even 1,000 of them stay under the ceiling, i.e. they
# PASS ON UNMODIFIED CODE (vacuous). These carry a production-shaped issue-comment action
# body, which is what actually crosses the ceiling.
test_argv_ceiling_final_emit_armed() {
  echo "TEST: inventory — >MAX_ARG_STRLEN armed set at the final emit (#6736)"
  # Named at every use, never bare.
  local MAX_ARG_STRLEN=131072
  local rows=600
  local d ff; d=$(mktemp -d); ff=$(mktemp)
  trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '["synthesized-fixture-reminder-dispatch"]' > "$ff"

  # One page of $rows future-dated reminder.scheduled edges with NO terminal runs, so
  # derive_armed keeps every one of them. Synthesized, never copied from a real event.
  jq -nc --argjson n "$rows" --argjson ts "$FUTURE_MS" '
    {data:{eventsV2:{
      totalCount:$n,
      pageInfo:{hasNextPage:false,endCursor:""},
      edges:[ range($n) as $i
        | { cursor:("rem-\($i)"),
            node:{ id:("rem-\($i)"), name:"reminder.scheduled",
                   occurredAt:"2026-06-10T00:00:00Z", receivedAt:"2026-06-10T00:00:00Z",
                   idempotencyKey:null,
                   raw:({ data:{ reminder_id:("synthesized-fixture-reminder-\($i)-with-a-production-shaped-identifier"),
                                 fire_at:"2026-12-01T00:00:00Z",
                                 actor:"synthesized-fixture-platform-scheduler",
                                 action:{ type:"issue-comment", issue:(1000 + $i),
                                          body:("Synthesized fixture reminder action body number \($i). This text stands in for a real issue-comment payload and is deliberately long enough that bytes-per-reminder, not reminder count, is what drives this fixture past the per-argument kernel ceiling.") } },
                          id:("rem-\($i)"), name:"reminder.scheduled", ts:$ts, v:null }|tojson),
                   runs:[] } } ]
    }}}' > "$d/page-1.json"

  # Generator cardinality: an under-filled generator makes every assert below vacuous.
  local gen
  gen=$(jq '.data.eventsV2.edges | length' "$d/page-1.json")
  assert_eq "argv-ceiling fixture generated $rows reminder edges" "$rows" "$gen"

  local out rc=0
  out=$(run_inv "$d" "$ff") || rc=$?
  assert_eq ">ceiling armed set exits 0 (pre-fix: 'Argument list too long')" "0" "$rc"

  # FIXTURE ADEQUACY, asserted IN-SUITE so this cannot silently degrade to vacuous as the
  # projection, the fixture, or jq's encoding changes. A PR-body demonstration is
  # unrunnable post-merge — there is no pre-fix code left to run it against.
  local armed_bytes over="no"
  armed_bytes=$(printf '%s' "$out" | jq -c '.armed_reminders' | wc -c)
  [[ "$armed_bytes" -gt "$MAX_ARG_STRLEN" ]] && over="yes"
  assert_eq "armed_reminders payload (${armed_bytes} B) exceeds MAX_ARG_STRLEN ($MAX_ARG_STRLEN)" "yes" "$over"

  # EXACT count asserted RELATIONALLY against the generated edge count, not a literal pin.
  # Discriminating against a truncating collapse and against the --slurpfile
  # array-of-arrays undercount (which would yield 1).
  assert_eq "armed_reminders|length == generated edge count (no truncation)" "$gen" \
    "$(printf '%s' "$out" | jq -r '.armed_reminders | length')"

  # The rows really carry their projected fields at >ceiling size, not empty shells.
  assert_eq "every armed row carries reminder_id + fire_at + action" "$gen" \
    "$(printf '%s' "$out" | jq -r '[.armed_reminders[] | select(.reminder_id != null and .fire_at != null and .action != null)] | length')"

  # The sibling fields must still be correct on the same >ceiling emit — this is what
  # catches converting only $r and leaving $f/$e on argv.
  assert_eq "functions still emitted alongside a >ceiling armed set" "1" \
    "$(printf '%s' "$out" | jq -r '.functions | length')"
  assert_eq "event_names still emitted alongside a >ceiling armed set" "reminder.scheduled" \
    "$(printf '%s' "$out" | jq -r '.event_names | join(",")')"
}

test_fatal_cleans_spool_tempfile() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); local tmpd; tmpd=$(mktemp -d)
  trap 'rm -rf "$d" "$ff" "$tmpd"' RETURN
  make_functions '[]' > "$ff"
  # well-formed-but-unexpected page (no .data.eventsV2) → FATAL exit 1 inside the loop,
  # AFTER the spool file is created.
  printf '%s' '{"data":{"eventsV2OTHER":{}}}' > "$d/page-1.json"
  local rc=0
  TMPDIR="$tmpd" INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" >/dev/null 2>&1 || rc=$?
  assert_eq "malformed page exits non-zero (FATAL)" "1" "$rc"
  local leftover; leftover=$(find "$tmpd" -type f 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "no spool temp file leaked on FATAL exit (EXIT trap fired)" "0" "$leftover"
}

# --- Test 14 (#5553): durability_state verdict mirrors ci-deploy.sh:277-287 ---
# Five canonical states from a seam-injected ExecStart + redis activeness. The
# verdict rule is byte-identical in intent to the deploy-time source of truth.
test_durability_states() {
  # #5560: durability keys on the NON-SECRET --postgres-max-open-conns sentinel
  # (the postgres/redis URIs are env-delivered now, never on argv).
  assert_eq "durable: sentinel present, redis active" "durable" \
    "$(run_inv_durability '/usr/bin/inngest start --sqlite-dir /var/lib/inngest --postgres-max-open-conns 10' active | jq -r '.durability_state')"
  assert_eq "degraded: sentinel present but redis inactive" "degraded" \
    "$(run_inv_durability '/usr/bin/inngest start --sqlite-dir /var/lib/inngest --postgres-max-open-conns 10' inactive | jq -r '.durability_state')"
  assert_eq "sqlite_only: no sentinel, redis inactive (SQLite-only fail-safe)" "sqlite_only" \
    "$(run_inv_durability '/usr/bin/inngest start --sqlite-dir /var/lib/inngest' inactive | jq -r '.durability_state')"
  assert_eq "sqlite_only: no sentinel EVEN with redis active (sentinel is the gate)" "sqlite_only" \
    "$(run_inv_durability '/usr/bin/inngest start --sqlite-dir /var/lib/inngest' active | jq -r '.durability_state')"
  assert_eq "unknown: ExecStart unreadable (empty seam)" "unknown" \
    "$(run_inv_durability '' inactive | jq -r '.durability_state')"
}

# --- Test 15 (#5553 AC3): the ExecStart connection ref never reaches any stream ---
# #5503 purity extended to durability: only the enum is emitted, never the
# $VAR/resolved ExecStart string. Seed a sentinel DSN and assert it is absent from
# the COMBINED (stdout+stderr) stream — mirrors the SECRET-BODY journald guard.
test_durability_no_secret_leak() {
  local d ff out; d=$(mktemp -d); ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '[]' > "$ff"
  make_page false "" "[]" > "$d/page-1.json"
  out=$(INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" \
    INVENTORY_EXECSTART='/usr/bin/inngest start --postgres-uri postgres://SECRET-DSN --postgres-max-open-conns 10' \
    INVENTORY_REDIS_ACTIVE=active bash "$TARGET" 2>&1)
  assert_eq "ExecStart connection ref absent from combined stream (AC3)" "0" \
    "$(printf '%s' "$out" | grep -c SECRET-DSN || true)"
  assert_eq "durable verdict still emitted (no-leak path correct)" "durable" \
    "$(printf '%s' "$out" | jq -r '.durability_state')"
}

# --- Test 16 (#5553 AC4): #5503 combined-stream purity preserved with the 4th key ---
test_durability_purity_preserved() {
  local d ff combined err; d=$(mktemp -d); ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '[]' > "$ff"
  make_page false "" "[]" > "$d/page-1.json"
  combined=$(INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" \
    INVENTORY_EXECSTART='--sqlite-dir /var/lib/inngest --postgres-max-open-conns 10' INVENTORY_REDIS_ACTIVE=active bash "$TARGET" 2>&1)
  if echo "$combined" | jq -e 'type == "object" and has("functions") and has("event_names") and has("armed_reminders") and has("durability_state")' >/dev/null 2>&1; then
    echo "  PASS: combined stream is a 4-key object incl durability_state"; PASS=$((PASS + 1));
  else
    echo "  FAIL: combined stream missing a key or polluted (durability field)"; FAIL=$((FAIL + 1)); fi
  err=$(INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" \
    INVENTORY_EXECSTART='--sqlite-dir /var/lib/inngest --postgres-max-open-conns 10' INVENTORY_REDIS_ACTIVE=active bash "$TARGET" 2>&1 1>/dev/null)
  assert_eq "success-path stderr empty with durability field" "" "$err"
}

# --- #6425 AC3: host_id on the SUCCESS x FAILURE axis (not the full-vs-liveness axis) ---
# The axis matters. hooks.json.tmpl sets include-command-output-in-response-on-error: true
# precisely so the watchdog can read the FAILURE body — and the incident that motivated this
# work returned HTTP 500 `FATAL __FETCH_FAILED__`, a plain-text exit-1 path. host_id on the
# JSON success emits alone would NOT have been present in that incident: the watchdog would
# still have filed an anonymous inngest_down P1 naming no host. So the failure paths, not the
# success paths, are the ones that carry the alert.
test_host_id_success_x_failure_axis() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_page false "" "[]" > "$d/page-1.json"

  # --- SUCCESS arm 1: liveness-only JSON emit ---
  make_functions '["cron-a"]' > "$ff"
  run_inv_logcap "$d" "$ff" INVENTORY_LIVENESS_ONLY=1 SOLEUR_HOST_ID_OVERRIDE=hetzner-777
  assert_eq "liveness success emits host_id" "hetzner-777" "$(echo "$STDOUT_CAP" | jq -r '.host_id')"
  assert_eq "liveness success stays a pure JSON object" "object" "$(echo "$STDOUT_CAP" | jq -r 'type')"

  # --- SUCCESS arm 2: full-inventory JSON emit ---
  run_inv_logcap "$d" "$ff" SOLEUR_HOST_ID_OVERRIDE=hetzner-777
  assert_eq "full success emits host_id" "hetzner-777" "$(echo "$STDOUT_CAP" | jq -r '.host_id')"

  # --- FAILURE arm 1: DEGRADED (functions read fails, /health=200) — plain text, exit 1 ---
  printf '%s' '{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}' > "$ff"
  run_inv_logcap "$d" "$ff" INVENTORY_LIVENESS_ONLY=1 INVENTORY_INNGEST_HEALTH_CODE=200 \
    INVENTORY_EXECSTART='--postgres-max-open-conns 10' INVENTORY_REDIS_ACTIVE=active \
    SOLEUR_HOST_ID_OVERRIDE=hetzner-777
  assert_eq "DEGRADED exits non-zero" "1" "$RC"
  case "$STDOUT_CAP" in
    *"DEGRADED"*"host_id=hetzner-777"*) echo "  PASS: DEGRADED plain-text body carries host_id"; PASS=$((PASS+1));;
    *) echo "  FAIL: DEGRADED body has no host_id"; echo "    body: $STDOUT_CAP"; FAIL=$((FAIL+1));;
  esac
  case "$MARKERS_CAP" in
    *"SOLEUR_INNGEST_LIVENESS_VERDICT"*"host_id=hetzner-777"*) echo "  PASS: VERDICT marker carries host_id"; PASS=$((PASS+1));;
    *) echo "  FAIL: VERDICT marker has no host_id"; echo "    markers: $MARKERS_CAP"; FAIL=$((FAIL+1));;
  esac

  # --- FAILURE arm 2: FATAL (functions read fails, /health!=200) — THE #6425 incident shape ---
  run_inv_logcap "$d" "$ff" INVENTORY_LIVENESS_ONLY=1 INVENTORY_INNGEST_HEALTH_CODE=500 \
    SOLEUR_HOST_ID_OVERRIDE=hetzner-777
  assert_eq "FATAL exits non-zero" "1" "$RC"
  case "$STDOUT_CAP" in
    "inngest-inventory: FATAL host_id=hetzner-777 "*"/v0/gql functions"*) echo "  PASS: FATAL body carries host_id BEFORE the unbounded errors= payload (the alert surface)"; PASS=$((PASS+1));;
    *) echo "  FAIL: FATAL body has no host_id, or host_id sits after the unbounded errors= payload — the watchdog truncates the body at 400 chars (scheduled-inngest-health.yml), so a few ordinary GraphQL errors push host_id out of the alert and it goes anonymous again: the #6425 defect"; echo "    body: $STDOUT_CAP"; FAIL=$((FAIL+1));;
  esac

  # --- FAILURE arm 2b: host_id must survive the watchdog's TRUNCATION, not just be present ---
  # scheduled-inngest-health.yml reads the failure body as
  #   cause=$(strip_log_injection "$(printf '%s' "$BODY" | tr '\n' ' ' | head -c 400)")
  # `fn_errs` is the scrubbed GraphQL errors[] — UNBOUNDED. So "host_id is in the body" is NOT
  # the property that matters; "host_id is in the first 400 chars" is. An earlier revision put
  # host_id AFTER fn_errs and passed every other arm here, because those arms use the 20-char
  # `__FETCH_FAILED__` fixture — a few ordinary GraphQL errors pushed host_id out of the alert
  # and the P1 went anonymous again (the exact #6425 defect). This arm uses a realistic
  # multi-error payload so field ORDER is pinned, not just field presence.
  LONG_ERRS='["connection refused dialing postgres backend 10.0.1.40:5432 pool exhausted after 30s","context deadline exceeded while awaiting response headers from upstream registry","failed to resolve function registry: transient DNS failure resolving inngest.internal","panic recovered in function loader: index out of range reading manifest"]'
  jq -nc --argjson e "$LONG_ERRS" '{errors:($e | map({message:.})), data:null}' > "$ff"
  run_inv_logcap "$d" "$ff" INVENTORY_LIVENESS_ONLY=1 INVENTORY_INNGEST_HEALTH_CODE=500 \
    SOLEUR_HOST_ID_OVERRIDE=hetzner-777
  TRUNCATED=$(printf '%s' "$STDOUT_CAP" | tr '\n' ' ' | head -c 400)
  case "$TRUNCATED" in
    *"host_id=hetzner-777"*) echo "  PASS: host_id survives the watchdog's 400-char truncation on a realistic multi-error FATAL"; PASS=$((PASS+1));;
    *) echo "  FAIL: host_id truncated OUT of the alert — the P1 the watchdog files names no host (#6425 defect reintroduced by field order)"; echo "    alert sees: $TRUNCATED"; FAIL=$((FAIL+1));;
  esac

  # --- FAILURE arm 3: FATAL on the NON-liveness (full inventory) path ---
  printf '%s' '{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}' > "$ff"
  run_inv_logcap "$d" "$ff" SOLEUR_HOST_ID_OVERRIDE=hetzner-777
  assert_eq "full-inventory FATAL exits non-zero" "1" "$RC"
  case "$STDOUT_CAP" in
    "inngest-inventory: FATAL host_id=hetzner-777 "*"/v0/gql functions"*) echo "  PASS: full-inventory FATAL body carries host_id before the unbounded payload"; PASS=$((PASS+1));;
    *) echo "  FAIL: full-inventory FATAL body has no host_id, or it sits after the unbounded errors= payload (truncated out of the 400-char alert)"; FAIL=$((FAIL+1));;
  esac
}

# --- #6425 AC4: resolve_host_id cross-file drift tripwire (parameterised) ---
# Token co-occurrence guard, NOT an equivalence proof — the behavioral tests (AC2/AC3 + the
# ci-deploy.sh SOLEUR_HOST_ID_OVERRIDE tests) pin each copy's behavior; this trips on a RENAME.
# The durability precedent greps hardcoded $SCRIPT_DIR paths and so cannot be handed a fixture;
# this one is parameterised over (file, fn) so the negative arm below can prove it goes RED on a
# mutated copy. A guard whose failure mode is never exercised is not a guard.
extract_fn_body() {  # $1=file $2=fn-name — the fn's body, brace-delimited at col 0
  awk -v fn="$2" '
    $0 ~ "^" fn "\\(\\) \\{" { inside = 1 }
    inside { print }
    inside && /^\}/ { exit }
  ' "$1"
}
host_id_tokens_missing() {  # $1=file — "" when every load-bearing token is present
  local f="$1" tok body missing=""
  local tokens=(SOLEUR_HOST_ID_OVERRIDE SOLEUR_HOST_ID_METADATA_URL 'hetzner-%s' 'machine-%s')
  body=$(extract_fn_body "$f" resolve_host_id)
  [[ -n "$body" ]] || { printf '%s' "$(basename "$f"):resolve_host_id-not-found"; return; }
  for tok in "${tokens[@]}"; do
    printf '%s' "$body" | grep -qF -- "$tok" || missing="$missing $(basename "$f"):$tok"
  done
  printf '%s' "$missing"
}
test_host_id_drift_guard() {
  local f missing=""
  for f in "$SCRIPT_DIR/ci-deploy.sh" "$SCRIPT_DIR/cat-deploy-state.sh" "$TARGET"; do
    missing="$missing$(host_id_tokens_missing "$f")"
  done
  assert_eq "all 3 resolve_host_id copies carry the load-bearing tokens" "" "$missing"

  # Negative arm: a mutated copy MUST trip the guard. Without this the guard could be
  # asserting nothing (e.g. a broken extract that always returns empty and silently passes).
  local tmp; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  sed 's/SOLEUR_HOST_ID_METADATA_URL/SOLEUR_RENAMED_METADATA_URL/' "$SCRIPT_DIR/ci-deploy.sh" > "$tmp/mutated.sh"
  local mutated; mutated=$(host_id_tokens_missing "$tmp/mutated.sh")
  case "$mutated" in
    *SOLEUR_HOST_ID_METADATA_URL*) echo "  PASS: guard goes RED on a renamed token (non-vacuous)"; PASS=$((PASS+1));;
    *) echo "  FAIL: guard stayed green on a mutated copy — it proves nothing"; FAIL=$((FAIL+1));;
  esac
  # And a file with no resolve_host_id at all must report, not silently pass.
  printf 'echo hi\n' > "$tmp/absent.sh"
  case "$(host_id_tokens_missing "$tmp/absent.sh")" in
    *resolve_host_id-not-found*) echo "  PASS: guard reports an absent resolve_host_id"; PASS=$((PASS+1));;
    *) echo "  FAIL: guard silently passed a file with no resolve_host_id"; FAIL=$((FAIL+1));;
  esac
}

# --- Test 17 (#5553 AC5): cross-file ExecStart-durability drift tripwire ---
# Token co-occurrence guard (NOT a verdict-equivalence proof — the five Phase-2.2
# verdicts pin THIS parser). #5560: durability is detected by the NON-SECRET
# --postgres-max-open-conns sentinel + redis activeness (the postgres/redis URIs are
# env-delivered now, never on argv). The sentinel+active rule is shared by the
# source-of-truth (ci-deploy.sh) and the mirror (inngest-inventory.sh): both must
# carry the load-bearing tokens. inngest-wiped-volume-verify.sh is a *secondary*
# member of the ExecStart-parse family — its gate only checks the sentinel presence
# on inngest-server.service (it deliberately does not parse redis), so it is asserted
# only against the subset it genuinely shares. If the sentinel flag or a unit name is
# renamed in ci-deploy.sh, the matching token disappears from the mirror's required
# set and the guard trips, forcing a human re-look at all parsers.
test_durability_drift_guard() {
  local f tok missing=""
  local full_tokens=(--postgres-max-open-conns inngest-redis.service inngest-server.service)
  local subset_tokens=(--postgres-max-open-conns inngest-server.service)
  for f in "$SCRIPT_DIR/ci-deploy.sh" "$TARGET"; do
    for tok in "${full_tokens[@]}"; do
      grep -qF -- "$tok" "$f" || missing="$missing $(basename "$f"):$tok"
    done
  done
  for tok in "${subset_tokens[@]}"; do
    grep -qF -- "$tok" "$SCRIPT_DIR/inngest-wiped-volume-verify.sh" \
      || missing="$missing inngest-wiped-volume-verify.sh:$tok"
  done
  assert_eq "ExecStart-durability parsers reference their load-bearing tokens" "" "$missing"
}

# ===========================================================================
# #6374 (Defect 2) — INVENTORY_LIVENESS_ONLY mode: the external health watchdog
# reuses THIS script as a lightweight liveness probe. In liveness mode it runs
# ONLY the cheap /v0/gql functions query + durability_state and SKIPS the heavy
# paginated eventsV2 scan (the false-positive source: a deadline/pool/gateway
# fault on the 365-day read declared inngest_down while the executor kept firing
# crons — the #6374 root cause). Emits {functions, event_names:[], armed_reminders:[],
# durability_state}. functions/durability purity + fail-loud on a real down are unchanged.
# ===========================================================================

# Run in liveness-only mode. Deliberately passes NO INNGEST_GQL_FIXTURE_DIR: if the
# script wrongly ran the eventsV2 scan it would curl 127.0.0.1:8288 (no inngest in CI)
# and loud-abort exit 1 — so a clean exit 0 with empty event scans PROVES the scan was
# skipped. $1 = functions-fixture file, plus optional trailing KEY=VAL durability seams.
run_inv_liveness() {
  local ff="$1"; shift
  INVENTORY_LIVENESS_ONLY=1 INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" \
    env "$@" bash "$TARGET" 2>/dev/null
}

# --- #6374 T-L1: liveness mode returns functions + empty event scans, exit 0, NO eventsV2 ---
test_liveness_only_skips_eventsv2() {
  local ff; ff=$(mktemp); trap 'rm -f "$ff"' RETURN
  make_functions '["cron-daily-triage","cron-bug-fixer"]' > "$ff"
  local out rc=0
  # No fixture dir + no network: if eventsV2 ran it would abort exit 1.
  out=$(run_inv_liveness "$ff" INVENTORY_EXECSTART='/usr/bin/inngest start --postgres-max-open-conns 10' INVENTORY_REDIS_ACTIVE=active) || rc=$?
  assert_eq "liveness mode exits 0 without an eventsV2 fixture (heavy scan skipped)" "0" "$rc"
  assert_eq "liveness functions still projected + sorted" "cron-bug-fixer,cron-daily-triage" "$(echo "$out" | jq -r '.functions | join(",")')"
  assert_eq "liveness event_names is empty (eventsV2 skipped)" "[]" "$(echo "$out" | jq -c '.event_names')"
  assert_eq "liveness armed_reminders is empty (eventsV2 skipped)" "[]" "$(echo "$out" | jq -c '.armed_reminders')"
  assert_eq "liveness preserves durability_state enum" "durable" "$(echo "$out" | jq -r '.durability_state')"
  assert_eq "liveness body is a 4-key object" "object" "$(echo "$out" | jq -r 'type')"
}

# --- #6374 T-L2: liveness mode preserves the full durability enum (advisory wiring) ---
test_liveness_only_durability_enum() {
  local ff; ff=$(mktemp); trap 'rm -f "$ff"' RETURN
  make_functions '["cron-a"]' > "$ff"
  assert_eq "liveness degraded (sentinel present, redis inactive)" "degraded" \
    "$(run_inv_liveness "$ff" INVENTORY_EXECSTART='--postgres-max-open-conns 10' INVENTORY_REDIS_ACTIVE=inactive | jq -r '.durability_state')"
  assert_eq "liveness sqlite_only (no sentinel)" "sqlite_only" \
    "$(run_inv_liveness "$ff" INVENTORY_EXECSTART='/usr/bin/inngest start' INVENTORY_REDIS_ACTIVE=inactive | jq -r '.durability_state')"
}

# --- #6374 T-L3: a genuinely-down inngest still fails LOUD in liveness mode (no false-clean) ---
test_liveness_only_fails_loud_on_down() {
  local ff; ff=$(mktemp); trap 'rm -f "$ff"' RETURN
  # functions query returns a GraphQL error envelope (inngest unreachable) → must exit 1
  # with the FATAL sentinel body, NOT a false-clean {functions:[]}.
  printf '%s' '{"errors":[{"message":"connection refused"}],"data":null}' > "$ff"
  local out rc=0
  out=$(run_inv_liveness "$ff") || rc=$?
  assert_eq "liveness down exits non-zero (fail-loud, no false-clean)" "1" "$rc"
  if [[ "$out" == "inngest-inventory: FATAL "* && "$out" == *"/v0/gql functions"* ]]; then echo "  PASS: liveness down emits the FATAL sentinel (classifier maps to inngest_down)"; PASS=$((PASS+1));
  else echo "  FAIL: liveness down did not emit the FATAL sentinel"; FAIL=$((FAIL+1)); fi
}

# #6374 review (security-sentinel): the FATAL body liveness mode returns on a real down is
# the webhook response (include-command-output-in-response-on-error) → it MUST scrub a DSN in
# the functions-query errors[].message (the #6283 class, pinned here for the LIVENESS path —
# the pre-existing DSN test only covered the eventsV2 read path).
test_liveness_only_scrubs_dsn_from_fatal() {
  local ff; ff=$(mktemp); trap 'rm -f "$ff"' RETURN
  printf '%s' '{"errors":[{"message":"FATAL: password authentication failed for postgres://u:p@10.0.1.40:5432/db"}],"data":null}' > "$ff"
  local out rc=0
  out=$(run_inv_liveness "$ff") || rc=$?
  assert_eq "liveness DSN-in-error exits non-zero (fail-loud)" "1" "$rc"
  if [[ "$out" == *"postgres://u:p@10.0.1.40"* ]]; then echo "  FAIL: DSN leaked verbatim into the liveness FATAL webhook body (#6283 regression)"; FAIL=$((FAIL+1));
  else echo "  PASS: DSN scrubbed from the liveness FATAL webhook body"; PASS=$((PASS+1)); fi
}

# ===========================================================================
# #6407 (Defect A) — loopback /health corroboration before declaring inngest_down.
# In LIVENESS_ONLY mode, a transient /v0/gql functions failure is corroborated
# against the SAME loopback server's /health endpoint (seam INVENTORY_INNGEST_HEALTH_CODE):
#   /health=200  → inngest IS serving; the GQL read blipped → SOFT DEGRADED sentinel
#                  (classifier → functions_query_degraded → NO restart). #6407 false positive.
#   /health !=200 → wedged/stopped → keep the FATAL sentinel (inngest_down → restart recovers).
# ===========================================================================

# --- #6407 T-H1: functions-query fail + /health=200 → DEGRADED (soft, no restart) ---
test_liveness_health_200_degrades() {
  local ff; ff=$(mktemp); trap 'rm -f "$ff"' RETURN
  printf '%s' '{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}' > "$ff"
  local out rc=0
  out=$(run_inv_liveness "$ff" INVENTORY_INNGEST_HEALTH_CODE=200) || rc=$?
  assert_eq "functions-fail + /health=200 exits non-zero (webhook surfaces the soft body)" "1" "$rc"
  if [[ "$out" == *"inngest-inventory: DEGRADED"* ]]; then echo "  PASS: emits the DEGRADED soft sentinel (classifier → functions_query_degraded)"; PASS=$((PASS+1));
  else echo "  FAIL: no DEGRADED sentinel on /health=200 corroboration (would false-page as inngest_down)"; FAIL=$((FAIL+1)); fi
  if [[ "$out" == *"inngest-inventory: FATAL"* ]]; then echo "  FAIL: emitted FATAL despite /health=200 (the #6407 false down)"; FAIL=$((FAIL+1));
  else echo "  PASS: did NOT emit FATAL when /health=200"; PASS=$((PASS+1)); fi
}

# --- #6407 T-H2: functions-query fail + /health != 200 → real down/wedged preserved (FATAL) ---
test_liveness_health_non200_stays_fatal() {
  local ff; ff=$(mktemp); trap 'rm -f "$ff"' RETURN
  printf '%s' '{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}' > "$ff"
  local code
  for code in 000 503; do
    local out rc=0
    out=$(run_inv_liveness "$ff" INVENTORY_INNGEST_HEALTH_CODE="$code") || rc=$?
    assert_eq "functions-fail + /health=$code exits non-zero" "1" "$rc"
    if [[ "$out" == *"inngest-inventory: FATAL"* ]]; then echo "  PASS: /health=$code keeps FATAL (real down/wedged → restart preserved)"; PASS=$((PASS+1));
    else echo "  FAIL: /health=$code did not emit FATAL (masked a real down)"; FAIL=$((FAIL+1)); fi
    if [[ "$out" == *"inngest-inventory: DEGRADED"* ]]; then echo "  FAIL: /health=$code emitted DEGRADED (would soft-mask a real down)"; FAIL=$((FAIL+1));
    else echo "  PASS: /health=$code did NOT soft-mask (no DEGRADED)"; PASS=$((PASS+1)); fi
  done
}

# ===========================================================================
# #6258 (ADR-106) — bounding + markers + completeness-by-construction
# ===========================================================================

# Run the script with a logger stub that captures every marker/summary line, plus
# fixtures. Sets globals RC, STDOUT_CAP, MARKERS_CAP (called DIRECTLY, not in $(...) — a
# command-substitution subshell would discard the globals). $1=page-dir (all-events),
# $2=functions-fixture, extra args = env assignments (KEY=VAL ...).
RC=0; STDOUT_CAP=""; MARKERS_CAP=""
run_inv_logcap() {
  local d="$1" ff="$2"; shift 2
  local bindir logout; bindir=$(mktemp -d); logout=$(mktemp)
  cat > "$bindir/logger" <<STUB
#!/usr/bin/env bash
# skip the leading "-t <tag>" so we capture the message body only
shift 2 2>/dev/null || true
echo "\$*" >> "$logout"
STUB
  chmod +x "$bindir/logger"
  RC=0
  # `env "$@"` — an expanded "$@" token is NOT recognized as an assignment prefix (bash
  # decides assignment-vs-command at parse time, before expansion), so pass extra KEY=VAL
  # seams through `env`, which DOES apply them (with $@ empty, `env bash …` is a clean no-op).
  STDOUT_CAP=$(PATH="$bindir:$PATH" INNGEST_GQL_FIXTURE_DIR="$d" INVENTORY_FUNCTIONS_FIXTURE="$ff" \
    INVENTORY_NOW_MS="$NOW_MS" env "$@" bash "$TARGET" 2>/dev/null) || RC=$?
  MARKERS_CAP=$(cat "$logout")
  rm -rf "$bindir" "$logout"
}

# --- #6258 T1: deadline hit → exit 1 (NOT break) + TIMEOUT marker + non-JSON stdout ---
test_deadline_abort() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '[]' > "$ff"
  # a next-page fixture (so the loop would continue) — deadline 0 aborts at the top of page 1.
  make_page true "CUR1" "[$(make_edge 01A reminder.scheduled rem1 "$FUTURE_MS" "[]")]" > "$d/page-1.json"
  run_inv_logcap "$d" "$ff" PREFLIGHT_DEADLINE_S=0; local markers="$MARKERS_CAP"
  assert_eq "deadline hit exits 1 (loud-abort, not break)" "1" "$RC"
  if echo "$STDOUT_CAP" | jq -e '.armed_reminders' >/dev/null 2>&1; then
    echo "  FAIL: stdout is a jq-parseable armed_reminders object on a deadline abort (truncated false-clean)"; FAIL=$((FAIL+1));
  else echo "  PASS: stdout NOT a jq-parseable armed_reminders object on abort"; PASS=$((PASS+1)); fi
  if echo "$markers" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_TIMEOUT .*reason=deadline'; then
    echo "  PASS: SOLEUR_INNGEST_PREFLIGHT_TIMEOUT reason=deadline emitted"; PASS=$((PASS+1));
  else echo "  FAIL: no TIMEOUT reason=deadline marker (markers=$markers)"; FAIL=$((FAIL+1)); fi
}

# --- #6258 T2: page ceiling hit → exit 1 + reason=page_ceiling; exact-fit breaks clean ---
test_page_ceiling_abort() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '[]' > "$ff"
  # 5 pages, hasNextPage true through page-4. MAX_PAGES=2 → abort when about to fetch page 3.
  local i
  for i in 1 2 3 4; do make_page true "CUR$i" "[$(make_edge 01P$i "cron/p$i" "" "$PAST_MS" "[]")]" > "$d/page-$i.json"; done
  make_page false "" "[$(make_edge 01P5 reminder.scheduled rem5 "$FUTURE_MS" "[]")]" > "$d/page-5.json"
  run_inv_logcap "$d" "$ff" INNGEST_MAX_PAGES=2; local markers="$MARKERS_CAP"
  assert_eq "page ceiling hit exits 1 (loud-abort)" "1" "$RC"
  if echo "$markers" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_TIMEOUT .*reason=page_ceiling'; then
    echo "  PASS: SOLEUR_INNGEST_PREFLIGHT_TIMEOUT reason=page_ceiling emitted"; PASS=$((PASS+1));
  else echo "  FAIL: no TIMEOUT reason=page_ceiling marker (markers=$markers)"; FAIL=$((FAIL+1)); fi
  # A page-ceiling abort is a distinct trigger from the deadline — assert it also refuses to
  # emit a truncated (false-clean) parseable body on stdout.
  if echo "$STDOUT_CAP" | jq -e '.armed_reminders' >/dev/null 2>&1; then
    echo "  FAIL: stdout is a jq-parseable armed_reminders object on a page-ceiling abort (false-clean)"; FAIL=$((FAIL+1));
  else echo "  PASS: stdout NOT a jq-parseable armed_reminders object on page-ceiling abort"; PASS=$((PASS+1)); fi
  # Exact-fit: a 2-page corpus (hasNextPage=false on page 2) with MAX_PAGES=2 breaks CLEAN.
  local d2; d2=$(mktemp -d); trap 'rm -rf "$d" "$ff" "$d2"' RETURN
  make_page true "CURx" "[$(make_edge 02A "cron/a" "" "$PAST_MS" "[]")]" > "$d2/page-1.json"
  make_page false "" "[$(make_edge 02B reminder.scheduled remx "$FUTURE_MS" "[]")]" > "$d2/page-2.json"
  local out2 rc2=0
  out2=$(INNGEST_GQL_FIXTURE_DIR="$d2" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" INNGEST_MAX_PAGES=2 bash "$TARGET" 2>/dev/null) || rc2=$?
  assert_eq "exact-fit corpus (pages == MAX_PAGES, last hasNextPage=false) breaks clean (exit 0)" "0" "$rc2"
  assert_eq "exact-fit corpus still emits well-formed object" "object" "$(echo "$out2" | jq -r 'type')"
}

# --- #6258 T3: START marker is the literal first line — emitted even on a functions-query fail ---
test_start_marker_first_on_functions_fail() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  printf '%s' '{"errors":[{"message":"connection refused"}],"data":null}' > "$ff"
  make_page false "" "[]" > "$d/page-1.json"
  run_inv_logcap "$d" "$ff"; local markers="$MARKERS_CAP"
  assert_eq "functions-fail still exits 1" "1" "$RC"
  if echo "$markers" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_START op=inventory'; then
    echo "  PASS: START marker emitted before the functions query (absence-of-START = host-down)"; PASS=$((PASS+1));
  else echo "  FAIL: no START marker on a functions-query failure (markers=$markers)"; FAIL=$((FAIL+1)); fi
}

# --- #6258 T4: happy path → START+DONE in journald, stdout stays pure JSON (markers journald-only) ---
test_markers_journald_only() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '["cron-a"]' > "$ff"
  make_page false "" "[$(make_edge 01A reminder.scheduled rem1 "$FUTURE_MS" "[]")]" > "$d/page-1.json"
  run_inv_logcap "$d" "$ff"; local markers="$MARKERS_CAP"
  assert_eq "happy path exits 0" "0" "$RC"
  assert_eq "stdout stays a pure JSON object (no marker leaked to stdout)" "object" "$(echo "$STDOUT_CAP" | jq -r 'type')"
  if echo "$STDOUT_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT'; then
    echo "  FAIL: a SOLEUR marker leaked onto stdout (would corrupt the webhook JSON body)"; FAIL=$((FAIL+1));
  else echo "  PASS: no SOLEUR marker on stdout (journald-only)"; PASS=$((PASS+1)); fi
  echo "$markers" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_START op=inventory' \
    && { echo "  PASS: START in journald"; PASS=$((PASS+1)); } || { echo "  FAIL: no START in journald"; FAIL=$((FAIL+1)); }
  echo "$markers" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_DONE op=inventory pages=' \
    && { echo "  PASS: DONE (with pages) in journald"; PASS=$((PASS+1)); } || { echo "  FAIL: no DONE in journald"; FAIL=$((FAIL+1)); }
}

# --- #6258 T5: completeness DIFFERENTIAL — new-reduced ⊇ old-unbounded ---
# old = armed derived from the all-events edges (the pre-#6258 projection); new = armed from
# the dedicated eventNames:["reminder.scheduled"] scan. Corpus: a reminder on each of two
# all-events pages + a cron name appearing ONLY on page 2, PLUS a reminder (rem-extra) present
# ONLY in the dedicated scan — so the assertions are non-vacuous: if the code regressed to
# re-deriving armed from the all-events edges, rem-extra would vanish. FROM_TS byte-identical.
# (Fixture mode `cat`s pages, so the load-bearing completeness guards are the two structural
# greps below — dedicated query + 365-day clamp — which are mutation-RED.)
test_completeness_differential() {
  local da; da=$(mktemp -d); local dr; dr=$(mktemp -d); local ff; ff=$(mktemp)
  trap 'rm -rf "$da" "$dr" "$ff"' RETURN
  make_functions '["cron-a","cron-b"]' > "$ff"
  # all-events corpus (2 pages): page-1 cron/a + rem-early; page-2 cron/only-p2 + rem-late.
  make_page true "CUR1" "[$(make_edge 01A "cron/a" "" "$PAST_MS" "[]"),$(make_edge 01R1 reminder.scheduled rem-early "$FUTURE_MS" "[]")]" > "$da/page-1.json"
  make_page false "" "[$(make_edge 02A "cron/only-p2" "" "$PAST_MS" "[]"),$(make_edge 02R2 reminder.scheduled rem-late "$FUTURE_MS" "[]")]" > "$da/page-2.json"
  # dedicated reminder corpus: both all-events reminders PLUS rem-extra (only the dedicated
  # scan surfaces it — proves new armed set is NOT re-derived from all-events).
  make_page false "" "[$(make_edge 01R1 reminder.scheduled rem-early "$FUTURE_MS" "[]"),$(make_edge 02R2 reminder.scheduled rem-late "$FUTURE_MS" "[]"),$(make_edge 03R3 reminder.scheduled rem-extra "$FUTURE_MS" "[]")]" > "$dr/page-1.json"

  local old_out new_out
  old_out=$(INNGEST_GQL_FIXTURE_DIR="$da" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" 2>/dev/null)
  new_out=$(INNGEST_GQL_FIXTURE_DIR="$da" INNGEST_REMINDER_FIXTURE_DIR="$dr" INVENTORY_FUNCTIONS_FIXTURE="$ff" INVENTORY_NOW_MS="$NOW_MS" bash "$TARGET" 2>/dev/null)

  local old_fn new_fn old_ev new_ev old_ar new_ar
  old_fn=$(echo "$old_out" | jq -c '.functions'); new_fn=$(echo "$new_out" | jq -c '.functions')
  old_ev=$(echo "$old_out" | jq -c '.event_names'); new_ev=$(echo "$new_out" | jq -c '.event_names')
  old_ar=$(echo "$old_out" | jq -c '[.armed_reminders[].reminder_id]|sort'); new_ar=$(echo "$new_out" | jq -c '[.armed_reminders[].reminder_id]|sort')
  assert_eq "functions identical (raised PAGE_SIZE is lossless)" "$old_fn" "$new_fn"
  # reduced ⊇ old (superset) for event_names and armed_reminders
  assert_eq "event_names: reduced ⊇ old" "true" "$(jq -nc --argjson o "$old_ev" --argjson n "$new_ev" '($o - $n) | length == 0')"
  assert_eq "armed_reminders: reduced ⊇ old (no armed reminder dropped)" "true" "$(jq -nc --argjson o "$old_ar" --argjson n "$new_ar" '($o - $n) | length == 0')"
  # Non-vacuity: the new armed set is sourced from the DEDICATED scan, not re-derived off
  # all-events — rem-extra exists only in $dr, so its presence proves the code path.
  assert_eq "armed set sourced from the dedicated reminder.scheduled scan (rem-extra present)" "true" "$(echo "$new_ar" | jq -c 'index("rem-extra") != null')"
  assert_eq "old (all-events projection) does NOT contain the dedicated-only rem-extra" "true" "$(echo "$old_ar" | jq -c 'index("rem-extra") == null')"
  assert_eq "cron name appearing only on page 2 present in reduced event_names" "true" "$(echo "$new_ev" | jq -c 'index("cron/only-p2") != null')"
  # FROM_TS byte-identical: the 365-day clamp is unchanged and never narrowed for cost.
  if grep -q '365 days ago' "$TARGET"; then echo "  PASS: FROM_TS 365-day clamp unchanged (never narrowed)"; PASS=$((PASS+1));
  else echo "  FAIL: FROM_TS 365-day clamp missing (window narrowed for cost — completeness risk)"; FAIL=$((FAIL+1)); fi
  if grep -qF 'eventNames:["reminder.scheduled"]' "$TARGET" || grep -qF "'[\"reminder.scheduled\"]'" "$TARGET"; then
    echo "  PASS: dedicated reminder.scheduled query present (armed by construction)"; PASS=$((PASS+1));
  else echo "  FAIL: no dedicated reminder.scheduled query (armed completeness not by construction)"; FAIL=$((FAIL+1)); fi
}

# --- #6258 T6: marker purity — no connection string / actor@host:port / URI in any marker ---
test_marker_purity() {
  local d; d=$(mktemp -d); local ff; ff=$(mktemp); trap 'rm -rf "$d" "$ff"' RETURN
  make_functions '[]' > "$ff"
  # a malformed GraphQL page → gql_error abort path; assert the marker maps to an ENUM,
  # never the raw errors[].message verbatim, and carries no URI/DSN.
  printf '%s' '{"errors":[{"message":"FATAL: password authentication failed for postgres://u:p@10.0.1.40:5432/db"}],"data":null}' > "$d/page-1.json"
  run_inv_logcap "$d" "$ff"; local markers="$MARKERS_CAP"
  local soleur_lines; soleur_lines=$(echo "$markers" | grep 'SOLEUR_INNGEST_PREFLIGHT' || true)
  assert_eq "gql_error marker present on a malformed page" "1" "$([[ -n "$soleur_lines" ]] && echo 1 || echo 0)"
  assert_eq "no '://' URI in any SOLEUR marker" "0" "$(echo "$soleur_lines" | grep -c '://' || true)"
  assert_eq "no user:pass@host in any SOLEUR marker" "0" "$(echo "$soleur_lines" | grep -cE '@[^ ]+:[0-9]+' || true)"
  assert_eq "raw GraphQL message never verbatim (reason is an enum)" "0" "$(echo "$soleur_lines" | grep -c 'password authentication' || true)"
  if echo "$soleur_lines" | grep -q 'reason=gql_error'; then echo "  PASS: reason mapped to enum gql_error"; PASS=$((PASS+1));
  else echo "  FAIL: reason not mapped to the gql_error enum"; FAIL=$((FAIL+1)); fi
  # #6258 review P1: the DSN must ALSO be scrubbed from the sibling FATAL/ERROR
  # diagnostic lines — journald (→ Better Stack) AND stdout (→ the Actions run log) —
  # not just the SOLEUR markers. Assert against the FULL capture, not the SOLEUR subset.
  assert_eq "no '://' URI in ANY journald line (incl. error diagnostics)" "0" "$(echo "$markers" | grep -c '://' || true)"
  assert_eq "no user:pass@host:port DSN in ANY journald line" "0" "$(echo "$markers" | grep -cE '@[^ ]+:[0-9]+' || true)"
  assert_eq "no '://' URI on stdout (webhook body / run log)" "0" "$(echo "$STDOUT_CAP" | grep -c '://' || true)"
  assert_eq "no user:pass@host:port DSN on stdout" "0" "$(echo "$STDOUT_CAP" | grep -cE '@[^ ]+:[0-9]+' || true)"
}

# --- #6258 T7: connect-timeout + remaining-budget clamp present (sum-bound by construction) ---
test_connect_timeout_and_clamp() {
  if grep -qE 'curl[^|]*--connect-timeout' "$TARGET"; then echo "  PASS: --connect-timeout on the per-page curl"; PASS=$((PASS+1));
  else echo "  FAIL: no --connect-timeout on the curl"; FAIL=$((FAIL+1)); fi
  # SUM bound: the per-page curl --max-time is the REMAINING budget, not a fixed constant.
  if grep -qE 'max-time "\$max_time"' "$TARGET" && grep -qE 'remaining=\$\(\( PREFLIGHT_DEADLINE_S - elapsed \)\)' "$TARGET"; then
    echo "  PASS: per-page curl clamped to remaining budget (deadline − elapsed)"; PASS=$((PASS+1));
  else echo "  FAIL: per-page curl not clamped to the remaining budget (sum-bound broken)"; FAIL=$((FAIL+1)); fi
  if grep -qE 'remaining < 1 \)\) && remaining=1' "$TARGET"; then echo "  PASS: remaining budget floored ≥1"; PASS=$((PASS+1));
  else echo "  FAIL: remaining budget not floored ≥1"; FAIL=$((FAIL+1)); fi
}

# --- #6258 T8: marker tags grep-asserted present in vector.toml allowlist (THE drift guard) ---
test_marker_tag_in_vector_allowlist() {
  local vector="$SCRIPT_DIR/vector.toml"
  assert_eq "vector.toml exists" "1" "$([[ -f "$vector" ]] && echo 1 || echo 0)"
  if grep -qE '^[[:space:]]*"inngest-inventory",' "$vector"; then echo "  PASS: inngest-inventory tag in vector.toml allowlist"; PASS=$((PASS+1));
  else echo "  FAIL: inngest-inventory tag NOT in vector.toml (marker would not ship to Better Stack)"; FAIL=$((FAIL+1)); fi
}

test_liveness_only_skips_eventsv2
test_liveness_only_durability_enum
test_liveness_only_fails_loud_on_down
test_liveness_only_scrubs_dsn_from_fatal
test_liveness_health_200_degrades
test_liveness_health_non200_stays_fatal
test_durability_states
test_durability_no_secret_leak
test_durability_purity_preserved
test_host_id_success_x_failure_axis
test_host_id_drift_guard
test_durability_drift_guard
test_deadline_abort
test_page_ceiling_abort
test_start_marker_first_on_functions_fail
test_markers_journald_only
test_completeness_differential
test_marker_purity
test_connect_timeout_and_clamp
test_marker_tag_in_vector_allowlist
test_combined_is_pure_json_object
test_functions_fetch_failure_is_loud
test_functions_from_gql_shape
test_functions_names
test_event_names_distinct_all
test_armed_projection
test_pagination
test_summary_no_body_leak
test_jq_n_body
test_empty_state
test_large_accumulator_no_argv_overflow
test_no_argv_accumulation
test_fatal_cleans_spool_tempfile
test_argv_ceiling_final_emit_armed

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]

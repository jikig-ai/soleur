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
  if [[ "$out" == *"FATAL /v0/gql functions"* ]]; then echo "  PASS: emits a diagnosable FATAL cause"; PASS=$((PASS+1));
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

test_durability_states
test_durability_no_secret_leak
test_durability_purity_preserved
test_durability_drift_guard
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

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]

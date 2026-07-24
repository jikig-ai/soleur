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
# #6919 — the clamp now FLOORS the per-page budget to PREFLIGHT_PAGE_MIN_S (anti-starvation)
# and CAPS it at PREFLIGHT_PAGE_MAX_S, on top of the remaining-budget derivation. The floor is
# the load-bearing fix: without it a drained budget hands late pages ~0s → empty → false
# "malformed". SUM bound stays airtight: DEADLINE + PAGE_MIN ≤ outer curl.
test_df_connect_timeout_and_clamp() {
  echo "TEST: doublefire-probe — --connect-timeout + remaining-budget curl clamp (floored, #6919)"
  if grep -qE 'curl[^|]*--connect-timeout' "$TARGET"; then echo "  PASS: --connect-timeout present"; PASS=$((PASS+1));
  else echo "  FAIL: no --connect-timeout"; FAIL=$((FAIL+1)); fi
  if grep -qE 'max-time "\$max_time"' "$TARGET" && grep -qE 'remaining=\$\(\( PREFLIGHT_DEADLINE_S - elapsed \)\)' "$TARGET"; then
    echo "  PASS: per-page curl clamped to remaining budget"; PASS=$((PASS+1));
  else echo "  FAIL: per-page curl not clamped to remaining budget"; FAIL=$((FAIL+1)); fi
  # #6919 anti-starvation FLOOR: the per-page budget is floored to PREFLIGHT_PAGE_MIN_S.
  if grep -qE 'max_time < PREFLIGHT_PAGE_MIN_S \)\) && max_time=\$PREFLIGHT_PAGE_MIN_S' "$TARGET"; then
    echo "  PASS: per-page budget floored to PREFLIGHT_PAGE_MIN_S (anti-starvation)"; PASS=$((PASS+1));
  else echo "  FAIL: per-page budget NOT floored to PREFLIGHT_PAGE_MIN_S — late pages can starve"; FAIL=$((FAIL+1)); fi
  # SUM bound must remain airtight: DEADLINE default + PAGE_MIN default < the 120s outer curl.
  local dl pmin; dl=$(grep -oP 'PREFLIGHT_DEADLINE_S:-\K[0-9]+' "$TARGET" | head -1)
  pmin=$(grep -oP 'PREFLIGHT_PAGE_MIN_S:-\K[0-9]+' "$TARGET" | head -1)
  if [[ -n "$dl" && -n "$pmin" && $(( dl + pmin )) -lt 120 ]]; then
    echo "  PASS: SUM bound DEADLINE($dl)+PAGE_MIN($pmin) < 120 outer curl"; PASS=$((PASS+1));
  else echo "  FAIL: SUM bound violated: DEADLINE($dl)+PAGE_MIN($pmin) not < 120"; FAIL=$((FAIL+1)); fi
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

# ===========================================================================
# #6919 — per-page budget starvation fix: transient-empty (retry) vs
# genuinely-malformed (fail loud) vs transport exhaustion (accurate, not "malformed").
# The live op=verify HTTP 500 was a late page starved to ~0s → empty body → the
# fail-loud guard mislabeled the empty body "malformed runs response on page 6".
# ===========================================================================

# --- #6919 A: a transient EMPTY page RECOVERS on the retry → probe completes correctly ---
test_df_transient_page_recovers_on_retry() {
  echo "TEST: doublefire-probe — a transient EMPTY page RECOVERS on retry (#6919)"
  local dir; dir=$(mktemp -d)
  # page-1 is EMPTY on attempt 1 (the starvation/truncation signal) and VALID on the retry
  # (the _fetch_runs_page retry seam prefers page-N.retry.json on attempt >= 2).
  : > "$dir/page-1.json"
  make_page false "" "[$(make_edge run-1 fn-a 2026-07-08T10:00:00Z)]" > "$dir/page-1.retry.json"
  run_probe_logcap "$dir"
  if [[ "$RC" -eq 0 ]]; then echo "  PASS: probe completes (exit 0) after the transient page recovers"; PASS=$((PASS+1));
  else echo "  FAIL: transient-recover rc=$RC (want 0; markers=$MARKERS_CAP)"; FAIL=$((FAIL+1)); fi
  assert_eq "recovered run is reported (1 run)" "1" "$(echo "$STDOUT_CAP" | jq -r '.runs | length' 2>/dev/null || echo x)"
  assert_eq "recovered run functionID projected" "fn-a" "$(echo "$STDOUT_CAP" | jq -r '.runs[0].functionID' 2>/dev/null || echo x)"
  # a recovered transient must NOT leave a false malformed/transport marker.
  if echo "$MARKERS_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_TIMEOUT'; then
    echo "  FAIL: a recovered transient emitted a TIMEOUT abort marker (markers=$MARKERS_CAP)"; FAIL=$((FAIL+1));
  else echo "  PASS: no abort marker on a recovered transient"; PASS=$((PASS+1)); fi
  rm -rf "$dir"
}

# --- #6919 B: a page still EMPTY after the retry → LOUD reason=transport, NOT "malformed" ---
test_df_transport_exhaustion_fails_loud() {
  echo "TEST: doublefire-probe — persistent empty page fails LOUD as transport, not 'malformed' (#6919)"
  local dir; dir=$(mktemp -d)
  : > "$dir/page-1.json"   # empty on attempt 1 AND the retry (no page-1.retry.json)
  run_probe_logcap "$dir"
  if [[ "$RC" -eq 1 ]]; then echo "  PASS: transport exhaustion exits 1"; PASS=$((PASS+1));
  else echo "  FAIL: transport exhaustion rc=$RC (want 1)"; FAIL=$((FAIL+1)); fi
  # NEVER a false-clean parseable {runs} object.
  if echo "$STDOUT_CAP" | jq -e '.runs' >/dev/null 2>&1; then
    echo "  FAIL: emitted a false-clean {runs} object on transport exhaustion"; FAIL=$((FAIL+1));
  else echo "  PASS: no false-clean runs object on transport exhaustion"; PASS=$((PASS+1)); fi
  # ACCURATE marker: reason=transport (NOT gql_error/malformed).
  if echo "$MARKERS_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_TIMEOUT .*reason=transport'; then
    echo "  PASS: TIMEOUT reason=transport marker"; PASS=$((PASS+1));
  else echo "  FAIL: no reason=transport marker (markers=$MARKERS_CAP)"; FAIL=$((FAIL+1)); fi
  # the transient empty must NOT be mislabeled as the (misleading) 'malformed runs response'.
  if echo "$STDOUT_CAP" | grep -q 'malformed runs response'; then
    echo "  FAIL: transient empty mislabeled as 'malformed runs response' (the #6919 bug)"; FAIL=$((FAIL+1));
  else echo "  PASS: transient empty NOT mislabeled 'malformed runs response'"; PASS=$((PASS+1)); fi
  # and it carries the accurate operator remediation.
  if echo "$STDOUT_CAP" | grep -q 'increase PREFLIGHT_DEADLINE_S'; then
    echo "  PASS: accurate remediation (increase PREFLIGHT_DEADLINE_S / scope functionIDs)"; PASS=$((PASS+1));
  else echo "  FAIL: no accurate remediation in the FATAL message (out=$STDOUT_CAP)"; FAIL=$((FAIL+1)); fi
  rm -rf "$dir"
}

# --- #6919 C: a NON-EMPTY invalid body still fails loud as 'malformed', NOT transport ---
test_df_nonempty_malformed_still_loud() {
  echo "TEST: doublefire-probe — NON-EMPTY invalid body still fails as 'malformed' not transport (#6919)"
  local dir; dir=$(mktemp -d)
  # non-empty, valid JSON, but .data.runs.edges is NOT an array → a GENUINE malformed response.
  echo '{"data":{"runs":{"edges":"not-an-array"}}}' > "$dir/page-1.json"
  run_probe_logcap "$dir"
  if [[ "$RC" -eq 1 ]]; then echo "  PASS: malformed non-empty body exits 1"; PASS=$((PASS+1));
  else echo "  FAIL: malformed non-empty rc=$RC (want 1)"; FAIL=$((FAIL+1)); fi
  if echo "$STDOUT_CAP" | jq -e '.runs' >/dev/null 2>&1; then
    echo "  FAIL: emitted a false-clean {runs} object on a malformed body"; FAIL=$((FAIL+1));
  else echo "  PASS: no false-clean runs object on a malformed body"; PASS=$((PASS+1)); fi
  # classified as gql_error (genuine malformed), NOT transport — the body was non-empty.
  if echo "$MARKERS_CAP" | grep -q 'SOLEUR_INNGEST_PREFLIGHT_TIMEOUT .*reason=gql_error'; then
    echo "  PASS: TIMEOUT reason=gql_error (genuine malformed)"; PASS=$((PASS+1));
  else echo "  FAIL: expected reason=gql_error (markers=$MARKERS_CAP)"; FAIL=$((FAIL+1)); fi
  if echo "$MARKERS_CAP" | grep -q 'reason=transport'; then
    echo "  FAIL: a NON-EMPTY malformed body was WRONGLY treated as transient/transport"; FAIL=$((FAIL+1));
  else echo "  PASS: non-empty malformed body NOT treated as transport"; PASS=$((PASS+1)); fi
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

# --- Test: argv ceiling — the collapsed run set EXCEEDS MAX_ARG_STRLEN (#6736) ---
#
# The final emit used to bind the whole paginated run set as `--argjson r "$all_runs"`,
# i.e. ONE argv argument. The kernel caps a SINGLE argv argument at
# MAX_ARG_STRLEN = 131,072 B (NOT `getconf ARG_MAX`, the 2,097,152 B argv+envp total);
# bisected on this host: 131,071 B passes, 131,072 B fails E2BIG.
#
# This was the #5523 defect RE-INTRODUCED ONE LINE AFTER ITS OWN FIX: the pagination loop
# spools every page to disk precisely to avoid an argv-sized accumulator, and then the emit
# handed the collapsed result straight back to execve. The spool bought nothing. The probe
# now keeps the collapsed set in a file and emits with `jq -c '{runs: .}' "$runs_file"`.
#
# ROW COUNT IS NOT THE LOAD-BEARING PARAMETER — BYTES PER RUN IS. The projection keeps only
# {functionID, startedAt}, so short synthetic ids give ~60 B/run and even 1,500 runs would
# stay under the ceiling and PASS ON UNMODIFIED CODE (vacuous). These fixture runs carry
# production-shaped functionIDs (the app-slug/function-slug form Inngest actually returns),
# which is what carries the bytes.
test_df_argv_ceiling_collapsed_runs() {
  echo "TEST: doublefire-probe — >MAX_ARG_STRLEN collapsed run set (#6736)"
  # Named at every use, never bare.
  local MAX_ARG_STRLEN=131072
  local pages=5 per_page=400
  local dir; dir=$(mktemp -d)
  # Owning trap for this case's scratch dir (#6734). RETURN, not EXIT: this harness
  # allocates per test function, so function-scoped cleanup is the correct lifetime --
  # and an EXIT trap here would silently replace any other the file later registers.
  trap 'rm -rf "$dir"' RETURN

  local p edges
  for p in 1 2 3 4 5; do
    edges=$(jq -nc --argjson n "$per_page" --argjson pg "$p" '
      [ range(0; $n) as $i
        | { cursor: "cur-\($pg)-\($i)",
            node: { id: "01SYNTHESIZEDRUNIDFIXTURE\($pg)\($i)",
                    functionID: "synthesized-fixture-app/scheduled-reminder-dispatch-worker-with-a-production-shaped-slug-\($pg)-\($i)",
                    status: "COMPLETED",
                    queuedAt: "2026-07-08T10:00:00Z",
                    startedAt: "2026-07-08T10:00:00Z",
                    endedAt: "2026-07-08T10:00:00Z" } } ]')
    if [[ "$p" -lt "$pages" ]]; then
      make_page true "cursor-$p" "$edges" > "$dir/page-$p.json"
    else
      make_page false "" "$edges" > "$dir/page-$p.json"
    fi
  done

  # Generator cardinality: an under-filled generator makes every assert below vacuous.
  local want=$(( pages * per_page ))
  local gen
  gen=$(jq -s '[.[].data.runs.edges | length] | add' "$dir"/page-*.json)
  assert_eq "argv-ceiling fixture generated $want edges across $pages pages" "$want" "$gen"

  local out rc=0
  out=$(INNGEST_DOUBLEFIRE_RUNS_FIXTURE="$dir" bash "$TARGET" 2>/dev/null) || rc=$?
  assert_eq ">ceiling run set exits 0 (pre-fix: 'Argument list too long')" "0" "$rc"

  # FIXTURE ADEQUACY, asserted IN-SUITE so this cannot silently degrade to vacuous as the
  # projection, the fixture, or jq's encoding changes. A PR-body demonstration is
  # unrunnable post-merge — there is no pre-fix code left to run it against.
  local runs_bytes over="no"
  runs_bytes=$(printf '%s' "$out" | jq -c '.runs' | wc -c)
  [[ "$runs_bytes" -gt "$MAX_ARG_STRLEN" ]] && over="yes"
  assert_eq "collapsed runs payload (${runs_bytes} B) exceeds MAX_ARG_STRLEN ($MAX_ARG_STRLEN)" "yes" "$over"

  # EXACT count asserted RELATIONALLY against the generated edge count, not a literal pin.
  # Fully discriminating against a truncating collapse (and against the --slurpfile
  # array-of-arrays undercount, which would yield 1).
  assert_eq "runs|length == generated edge count (all pages, no truncation)" "$gen" \
    "$(printf '%s' "$out" | jq -r '.runs | length')"

  # The rows really carry their projected fields at >ceiling size, not empty shells.
  assert_eq "every run carries functionID + startedAt at >ceiling size" "$gen" \
    "$(printf '%s' "$out" | jq -r '[.runs[] | select(.functionID != null and .startedAt != null)] | length')"

  rm -rf "$dir"
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
test_df_transient_page_recovers_on_retry
test_df_transport_exhaustion_fails_loud
test_df_nonempty_malformed_still_loud
test_df_marker_purity
test_df_marker_tag_in_vector
test_df_argv_ceiling_collapsed_runs
# ===========================================================================
# #6617 — build_request_body must produce VALID JSON on the empty-CSV path
#
# WHY THIS NEEDS ITS OWN HARNESS: the INNGEST_DOUBLEFIRE_RUNS_FIXTURE seam
# short-circuits fetch_page at :164-165 and RETURNS BEFORE build_request_body
# is called at :170. So every fixture-driven test above passes green while
# the real request-construction path is never executed. This test calls
# build_request_body directly.
#
# THE DEFECT: `printf '%s' "$FUNCTION_IDS_CSV"` emits ZERO BYTES when the CSV
# is empty — the documented "empty CSV => [] => all functions" default. jq -R
# then has no line to read and emits NOTHING, so fn_ids_json becomes the empty
# string and `--argjson fnids ""` aborts with
#   jq: invalid JSON text passed to --argjson
# This is the DEFAULT path: op=verify step 2.6 passes no FUNCTION_IDS, so the
# cutover's exactly-once check could never run. Observed live as HTTP 500 on
# GET /hooks/inngest-doublefire-probe (run 29729623865, 2026-07-20).
# ===========================================================================

# Extract build_request_body from the target and evaluate it with the same
# variable set the script establishes, so the assertion pins the REAL function
# rather than a re-implementation of it.
call_build_request_body() {
  local csv="$1" out rc=0
  # `set +e` MUST be in the CALLING shell: under `set -e` a failing command
  # substitution aborts the whole suite at the assignment, so the RED case
  # (which fails by design) would kill the runner instead of being asserted.
  set +e
  out=$(
    eval "$(sed -n '/^build_request_body() {$/,/^}$/p' "$TARGET")"
    # SC2034: these five ARE consumed — by the eval'd build_request_body body
    # above, which shellcheck cannot resolve statically. They mirror the
    # variable set the real script establishes at :58-68.
    # shellcheck disable=SC2034
    {
      GQL_QUERY="query { runs { id } }"
      PAGE_SIZE=100
      FROM_TS="2026-07-19T00:00:00Z"
      UNTIL_TS=""
      FUNCTION_IDS_CSV="$csv"
    }
    build_request_body "" 2>&1
  )
  rc=$?
  set -e
  BRB_OUT="$out"; BRB_RC=$rc
}

test_df_build_body_empty_csv() {
  echo "TEST: doublefire — build_request_body emits valid JSON for the empty-CSV default (#6617)"
  call_build_request_body ""

  if [[ "$BRB_RC" -eq 0 ]]; then echo "  PASS: exits 0 on the empty-CSV default path"; PASS=$((PASS+1));
  else echo "  FAIL: exits $BRB_RC — $BRB_OUT"; FAIL=$((FAIL+1)); fi

  if jq -e . >/dev/null 2>&1 <<<"$BRB_OUT"; then echo "  PASS: output is valid JSON"; PASS=$((PASS+1));
  else echo "  FAIL: output is NOT valid JSON: $BRB_OUT"; FAIL=$((FAIL+1)); fi

  # The documented contract: empty CSV means ALL functions, encoded as [].
  local fnids; fnids=$(jq -c '.variables.filter.functionIDs' <<<"$BRB_OUT" 2>/dev/null || echo "<unparseable>")
  assert_eq "empty CSV yields functionIDs: [] (all functions)" "[]" "$fnids"
}

test_df_build_body_nonempty_csv() {
  echo "TEST: doublefire — build_request_body still encodes a non-empty CSV correctly"
  call_build_request_body "fn-a,fn-b"

  if [[ "$BRB_RC" -eq 0 ]]; then echo "  PASS: exits 0"; PASS=$((PASS+1));
  else echo "  FAIL: exits $BRB_RC — $BRB_OUT"; FAIL=$((FAIL+1)); fi

  local fnids; fnids=$(jq -c '.variables.filter.functionIDs' <<<"$BRB_OUT" 2>/dev/null || echo "<unparseable>")
  assert_eq "non-empty CSV yields the id array" '["fn-a","fn-b"]' "$fnids"
}

# Harness self-check: if the extraction ever stops yielding a callable
# function, both tests above would pass vacuously on an empty string.
test_df_build_body_harness_is_live() {
  echo "TEST: doublefire — build_request_body extraction is non-vacuous"
  local body; body=$(sed -n '/^build_request_body() {$/,/^}$/p' "$TARGET")
  if [[ $(wc -l <<<"$body") -gt 5 ]]; then echo "  PASS: extracted $(wc -l <<<"$body") lines"; PASS=$((PASS+1));
  else echo "  FAIL: extraction yielded $(wc -l <<<"$body") lines — harness is vacuous"; FAIL=$((FAIL+1)); fi

  # WIRING: the harness above proves build_request_body BEHAVES, not that
  # anything CALLS it. Without this, reintroducing the #6617 defect inline in
  # _fetch_runs_page — leaving build_request_body intact but dead — reproduces
  # the live HTTP 500 with this suite fully green.
  if grep -qF 'body=$(build_request_body' "$TARGET"; then echo "  PASS: build_request_body is wired into the request path"; PASS=$((PASS+1));
  else echo "  FAIL: build_request_body is DEAD — nothing calls it"; FAIL=$((FAIL+1)); fi

  # ORDER: the fixture seam must sit BELOW body construction, else every
  # fixture-driven test bypasses the real path again (how #6617 shipped green).
  local build_ln seam_ln
  build_ln=$(grep -n 'body=$(build_request_body' "$TARGET" | head -1 | cut -d: -f1)
  seam_ln=$(grep -n 'if \[\[ -n "$FIXTURE_DIR" \]\]' "$TARGET" | head -1 | cut -d: -f1)
  if [[ -z "$build_ln" || -z "$seam_ln" ]]; then
    echo "  FAIL: could not locate anchors (build=$build_ln seam=$seam_ln)"; FAIL=$((FAIL+1))
  elif [[ "$build_ln" -lt "$seam_ln" ]]; then
    echo "  PASS: body built (line $build_ln) BEFORE the fixture seam (line $seam_ln)"; PASS=$((PASS+1))
  else
    echo "  FAIL: fixture seam (line $seam_ln) precedes construction (line $build_ln)"; FAIL=$((FAIL+1))
  fi
}

test_df_build_body_harness_is_live
test_df_build_body_empty_csv
test_df_build_body_nonempty_csv

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi

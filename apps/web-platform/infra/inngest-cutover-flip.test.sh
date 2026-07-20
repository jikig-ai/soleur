#!/usr/bin/env bash
# Tests for inngest-cutover-flip.sh — the 2.2b+2.3 dedicated-host cutover flip FSM
# (#6178, ADR-100). Drives the full 8-state machine through the fixture seams with NO
# real redis / systemd / doppler. The seam recorders append to a single COMBINED trace
# so the assertions prove INTERMEDIATE ordering (which would fail without the FSM), not
# just the final flag:
#   * forward path is stop -> FLUSHALL -> flushed -> start (P1-4) and flag:flipping is
#     written BEFORE Redis is touched (P1-5 / #5450);
#   * DBSIZE!=0 aborts to terminal `aborted` with NO start + exit 1 (P0-3);
#   * `rollback` stops the server and sets `rolled-back` (P0-1);
#   * the transient is SPLIT so a crash can neither skip nor re-flush a prod queue:
#       - a `flipping` (PRE-flush) resume DOES re-run stop->FLUSHALL->assert (server still
#         dark → safe; closes the skip-flush window);
#       - a `flushed` (POST-flush) resume does NOT re-FLUSHALL (#5450 trap);
#   * an unhandled failure (stop/start/flag_set) emits a marker AND lands the flag in
#     terminal `aborted` — never a silent exit, never a false `done` (#5934 class);
#   * done/rolled-back/aborted/unset are idempotent no-ops;
#   * the timer is NEVER disabled by the script (P0-1);
#   * EVERY branch emits a `logger -t inngest-cutover-flip` line (P0-2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-cutover-flip.sh"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$desc";
  else fail "$desc"; echo "    expected: $expected"; echo "    actual:   $actual"; fi
}
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then pass "$desc";
  else fail "$desc (needle '$needle' not in '$haystack')"; fi
}
assert_absent() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then pass "$desc";
  else fail "$desc (unexpected '$needle' in '$haystack')"; fi
}
assert_logger() {
  local desc="$1"
  if [[ -s "$LOGTRACE" ]]; then pass "$desc"; else fail "$desc (no logger line emitted)"; fi
}

WORK=""
TRACE="" STATE="" LOGTRACE=""
SYSCTL="" REDIS="" FLAGSET="" LOGGER=""

setup_case() {
  WORK=$(mktemp -d)
  TRACE="$WORK/trace"
  STATE="$WORK/state.json"
  LOGTRACE="$WORK/logtrace"
  : > "$TRACE"
  : > "$LOGTRACE"

  # All three mutating seams append to ONE combined trace so cross-op ordering is
  # assertable. systemctl -> the verb (stop/start); redis -> lowercased subcommand
  # (flushall); flag transitions -> flag:<value>.
  SYSCTL="$WORK/sysctl.sh"
  cat > "$SYSCTL" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$TRACE"
EOF
  REDIS="$WORK/redis.sh"
  cat > "$REDIS" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$(printf '%s' "\$1" | tr '[:upper:]' '[:lower:]')" >> "$TRACE"
EOF
  FLAGSET="$WORK/flagset.sh"
  cat > "$FLAGSET" <<EOF
#!/usr/bin/env bash
printf 'flag:%s\n' "\$1" >> "$TRACE"
EOF
  LOGGER="$WORK/logger.sh"
  cat > "$LOGGER" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$LOGTRACE"
EOF
  chmod +x "$SYSCTL" "$REDIS" "$FLAGSET" "$LOGGER"
}

teardown_case() { rm -rf "$WORK"; }

# run_flip <flag> [EXTRA_VAR=val ...] -> echoes the exit code; populates the traces.
run_flip() {
  local flag="$1"; shift
  local -a extra=("$@")
  local rc=0
  env CUTOVER_FLIP_FLAG="$flag" \
      CUTOVER_SYSTEMCTL_CMD="$SYSCTL" \
      CUTOVER_REDIS_CLI_CMD="$REDIS" \
      CUTOVER_FLAG_SET_CMD="$FLAGSET" \
      CUTOVER_LOGGER_CMD="$LOGGER" \
      INNGEST_CUTOVER_STATE="$STATE" \
      ${extra[@]+"${extra[@]}"} \
      bash "$TARGET" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

trace_csv() { paste -sd, "$TRACE" 2>/dev/null || true; }

echo "=== inngest-cutover-flip.sh FSM test suite ==="

# --- Test 1: armed + DBSIZE==0 => forward FSM, exact ordered trace ---
echo "TEST: armed+DBSIZE=0 => stop->FLUSHALL->flushed->start, armed->flipping->done, exit 0"
setup_case
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0)
order=$(trace_csv)
assert_eq "exit 0 on forward flip" "0" "$rc"
# The FULL intermediate sequence — proves flag:flipping BEFORE stop (P1-5/#5450),
# FLUSHALL AFTER stop (P1-4), the flag:flushed POST-assert checkpoint written BEFORE
# start (the skip-flush-window fix), start AFTER the flush, flag:done LAST. A non-FSM
# implementation (e.g. flush-then-restart, done before start, or the old no-`flushed`
# ordering) fails this.
assert_eq "combined order flipping,stop,flushall,flushed,start,done" \
  "flag:flipping,stop,flushall,flag:flushed,start,flag:done" "$order"
assert_eq "state exit_code is 0" "0" "$(jq -r '.exit_code' "$STATE")"
assert_eq "state reason is flip-complete" "flip-complete" "$(jq -r '.reason' "$STATE")"
assert_logger "logger line emitted (armed branch)"
assert_contains "logger tagged inngest-cutover-flip" "$(cat "$LOGTRACE")" "inngest-cutover-flip"
teardown_case

# --- Test 2: armed + DBSIZE!=0 => abort, NO start, terminal aborted, exit 1 ---
echo "TEST: armed+DBSIZE=5 => abort (no start), flag->aborted, exit 1 (P0-3)"
setup_case
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=5)
order=$(trace_csv)
assert_eq "exit 1 on dirty Redis" "1" "$rc"
assert_contains "stop happened" "$order" "stop"
assert_contains "FLUSHALL happened" "$order" "flushall"
assert_absent "inngest-server NOT started on abort" "$order" "start"
assert_contains "flag transitioned to aborted" "$order" "flag:aborted"
assert_absent "flag NEVER reached done on abort" "$order" "flag:done"
assert_eq "state exit_code is 1" "1" "$(jq -r '.exit_code' "$STATE")"
assert_eq "state dbsize recorded" "5" "$(jq -r '.dbsize' "$STATE")"
assert_logger "logger line emitted (abort branch)"
teardown_case

# --- Test 3: rollback => stop server, terminal rolled-back, exit 0 ---
echo "TEST: rollback => stop inngest-server, flag->rolled-back, exit 0 (P0-1)"
setup_case
rc=$(run_flip rollback)
order=$(trace_csv)
assert_eq "exit 0 on rollback" "0" "$rc"
assert_contains "stop happened on rollback" "$order" "stop"
assert_absent "no FLUSHALL on rollback" "$order" "flushall"
assert_absent "no start on rollback" "$order" "start"
assert_contains "flag transitioned to rolled-back" "$order" "flag:rolled-back"
assert_eq "state reason is rolled-back" "rolled-back" "$(jq -r '.reason' "$STATE")"
assert_logger "logger line emitted (rollback branch)"
teardown_case

# --- Test 4: flipping (PRE-flush resume) => DOES re-run stop->FLUSHALL->assert->flushed
#     ->start->done. The transient `flipping` is set BEFORE the flush, so a resume here
#     means the flush may NOT have completed and the server is still dark — re-running the
#     full flush is SAFE and closes the skip-flush window. (The OLD behavior — skip the
#     flush and jump straight to start — would start against an un-flushed dark Redis.) ---
echo "TEST: flipping => PRE-flush resume RE-RUNS stop->FLUSHALL->flushed->start->done"
setup_case
rc=$(run_flip flipping CUTOVER_REDIS_DBSIZE=0)
order=$(trace_csv)
assert_eq "exit 0 on flipping resume" "0" "$rc"
# Intermediate-ordering assertion that FAILS without the split-checkpoint fix (the old
# flipping branch produced only "start,flag:done" with no flush).
assert_eq "flipping resume re-runs full flush: stop,flushall,flushed,start,done" \
  "stop,flushall,flag:flushed,start,flag:done" "$order"
assert_contains "re-FLUSHALL DID happen on flipping (PRE-flush) resume" "$order" "flushall"
assert_contains "flag transitioned to done" "$order" "flag:done"
assert_logger "logger line emitted (flipping branch)"
teardown_case

# --- Test 4b: flushed (POST-flush resume) => NO re-FLUSHALL, start + done (#5450 trap) ---
# Reaching `flushed` proves the flush already succeeded and the queue is on prod Postgres;
# the resume MUST NOT re-FLUSHALL. This is the #5450-safe no-reflush path.
echo "TEST: flushed => POST-flush resume start + done, NO re-FLUSHALL (#5450 trap)"
setup_case
rc=$(run_flip flushed)
order=$(trace_csv)
assert_eq "exit 0 on flushed resume" "0" "$rc"
assert_absent "NO re-FLUSHALL on flushed (POST-flush) resume" "$order" "flushall"
assert_contains "start happened on flushed resume" "$order" "start"
assert_contains "flag transitioned to done" "$order" "flag:done"
assert_logger "logger line emitted (flushed branch)"
teardown_case

# --- Test 4d: armed AFTER a terminal `done` => REFUSE, NO FLUSHALL, loud marker (P2-d/#5450).
# A completed flip left the queue on LIVE prod; a stray flag flip back to `armed` must NOT
# re-enter the flush path and FLUSHALL a now-live prod Redis. The latch reads the recorded
# `done` from the state slot and refuses (no stop, no flush, no start) with a loud marker. ---
echo "TEST: armed after done => refuse (no FLUSHALL/stop/start), flag:aborted, marker, exit 1 (P2-d)"
setup_case
# Pre-seed the state slot with a completed-flip latch (flag done) — a prior flip reached prod.
printf '%s\n' '{"exit_code":0,"dbsize":"0","reason":"flip-complete","flag":"done","start_ts":"x"}' > "$STATE"
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0)
order=$(trace_csv)
assert_eq "exit 1 on armed-after-done refuse" "1" "$rc"
assert_absent "NO FLUSHALL when re-armed after done (#5450 catastrophe guard)" "$order" "flushall"
assert_absent "NO stop when re-armed after done" "$order" "stop"
assert_absent "NO start when re-armed after done" "$order" "start"
assert_contains "flag transitioned to aborted on refuse" "$order" "flag:aborted"
assert_absent "flag NEVER re-reached done" "$order" "flag:done"
assert_contains "refuse marker emitted (refuse-rearm-after-done)" "$(cat "$LOGTRACE")" "refuse-rearm-after-done"
assert_logger "logger line emitted (refuse branch)"
teardown_case

# --- Test 4c: telemetry-blind give-up guard (#5934) — an unhandled stop/start/flag_set
#     failure must EMIT a marker AND land the flag in terminal `aborted` (never a silent
#     non-zero exit, never a stuck `flipping`/false `done`). Uses a failing seam per case;
#     asserts the ERR trap wrote flag:aborted and NOT flag:done. ---
run_flip_failing_sysctl() {  # $1=flag $2=verb-to-fail [extra...]
  local flag="$1" failverb="$2"; shift 2
  local rc=0
  # SYSCTL that fails on $failverb, records+succeeds otherwise.
  cat > "$SYSCTL" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "$failverb" ]]; then exit 1; fi
printf '%s\n' "\$1" >> "$TRACE"
EOF
  chmod +x "$SYSCTL"
  env CUTOVER_FLIP_FLAG="$flag" \
      CUTOVER_SYSTEMCTL_CMD="$SYSCTL" CUTOVER_REDIS_CLI_CMD="$REDIS" \
      CUTOVER_FLAG_SET_CMD="$FLAGSET" CUTOVER_LOGGER_CMD="$LOGGER" \
      INNGEST_CUTOVER_STATE="$STATE" "$@" \
      bash "$TARGET" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

echo "TEST: stop_server failure after flag->flipping => marker + flag:aborted, exit != 0 (#5934)"
setup_case
rc=$(run_flip_failing_sysctl armed stop CUTOVER_REDIS_DBSIZE=0)
order=$(trace_csv)
assert_eq "non-zero exit on stop_server failure" "1" "$rc"
assert_contains "flag reached terminal aborted (not stuck flipping)" "$order" "flag:aborted"
assert_absent "flag NEVER reached done on stop failure" "$order" "flag:done"
assert_contains "marker emitted with unexpected-exit reason" "$(cat "$LOGTRACE")" "unexpected-exit"
assert_logger "logger marker emitted on stop_server failure"
teardown_case

echo "TEST: start_server failure (post-flushed) => marker + flag:aborted, exit != 0 (#5934)"
setup_case
rc=$(run_flip_failing_sysctl armed start CUTOVER_REDIS_DBSIZE=0)
order=$(trace_csv)
assert_eq "non-zero exit on start_server failure" "1" "$rc"
assert_contains "flushed checkpoint was reached before start" "$order" "flag:flushed"
assert_contains "flag reached terminal aborted on start failure" "$order" "flag:aborted"
assert_absent "flag NEVER reached done on start failure" "$order" "flag:done"
assert_contains "marker emitted with unexpected-exit reason" "$(cat "$LOGTRACE")" "unexpected-exit"
teardown_case

echo "TEST: flag_set(done) failure => marker + flag:aborted, exit != 0 (#5934)"
setup_case
# FLAGSET that fails specifically on the `done` transition, records others.
cat > "$FLAGSET" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "done" ]]; then exit 1; fi
printf 'flag:%s\n' "\$1" >> "$TRACE"
EOF
chmod +x "$FLAGSET"
rc=0
env CUTOVER_FLIP_FLAG="armed" CUTOVER_SYSTEMCTL_CMD="$SYSCTL" \
    CUTOVER_REDIS_CLI_CMD="$REDIS" CUTOVER_FLAG_SET_CMD="$FLAGSET" \
    CUTOVER_LOGGER_CMD="$LOGGER" INNGEST_CUTOVER_STATE="$STATE" \
    CUTOVER_REDIS_DBSIZE=0 \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
order=$(trace_csv)
assert_eq "non-zero exit on flag_set(done) failure" "1" "$rc"
assert_contains "flag reached terminal aborted after done-write failure" "$order" "flag:aborted"
assert_absent "flag NEVER recorded done (the write failed)" "$order" "flag:done"
assert_contains "marker emitted with unexpected-exit reason" "$(cat "$LOGTRACE")" "unexpected-exit"
teardown_case

# --- Test 5: idempotent no-op states (done/rolled-back/aborted/unset) ---
for state in "done" rolled-back aborted ""; do
  label="${state:-unset}"
  echo "TEST: no-op state '$label' => exit 0, no host mutation, logger still emitted"
  setup_case
  rc=$(run_flip "$state")
  order=$(trace_csv)
  assert_eq "exit 0 on no-op '$label'" "0" "$rc"
  assert_eq "no host mutation on no-op '$label'" "" "$order"
  assert_logger "logger line emitted (no-op '$label')"
  teardown_case
done

# --- Test 6: the script NEVER disables the flip timer (P0-1, static guard) ---
echo "TEST: script never disables inngest-cutover-flip.timer (P0-1)"
if grep -qE 'disable[^\n]*flip\.timer' "$TARGET"; then
  fail "script disables the flip timer — P0-1 no-SSH rollback channel would be killed"
else
  pass "no 'systemctl disable ...flip.timer' in the script"
fi
if grep -qE '\bsystemctl[^\n]*disable\b' "$TARGET"; then
  fail "script contains a systemctl disable (P0-1 forbids disabling the timer)"
else
  pass "no systemctl disable anywhere in the script"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi

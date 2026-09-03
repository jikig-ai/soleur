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

# INSTRUMENT SELF-TEST (#7761 review, P0). Every claim in this file dispatches through pass()/fail(),
# and the assertion floor at the bottom used to dispatch through fail() too — so ONE edit (fail()
# stops incrementing FAIL) made every assertion AND the floor that backstops them report green
# together. Measured on this suite: with the seam gate deleted the suite printed
# "116 passed, 0 failed" and exit 0, with 11 real FAIL: lines on stdout that nothing counted. CI
# reads the exit code. Note the asymmetry — neutering pass() IS caught, because the floor sums
# PASS; neutering fail() was not. So prove both counters move before trusting anything, then reset.
# Output suppressed so the deliberate FAIL row cannot be misread as a real one.
pass "instrument self-test" >/dev/null
fail "instrument self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'FATAL: assertion counters are broken (PASS=%s FAIL=%s, expected 1/1).\n' "$PASS" "$FAIL" >&2
  exit 1
fi
PASS=0
FAIL=0

WORK=""
LATCH=""
TRACE="" STATE="" LOGTRACE=""
SYSCTL="" REDIS="" FLAGSET="" LOGGER=""
# (#7761) A SINGLE OWNING TRAP (ADR-129). setup_case/teardown_case are per-case cleanup and only
# run on the happy path — a suite that dies mid-case leaves its scratch root behind in $TMPDIR,
# which on this repo's shared 4 GiB tmpfs is a real leak rather than a tidiness nit. One EXIT trap
# owns every root this file allocates, including the alternate root the argv-authorisation case
# needs (it must be differently-named to prove the gate does not key on a path prefix, so it
# cannot live under $WORK).
ALT_ROOT=""
cleanup_all() {
  [[ -n "${WORK:-}" ]] && rm -rf "$WORK"
  [[ -n "${ALT_ROOT:-}" ]] && rm -rf "$ALT_ROOT"
  # Explicit: the last [[ ]] above is false whenever ALT_ROOT is unset, and this trap runs on the
  # EXIT path where that status would become the script's own.
  return 0
}
trap cleanup_all EXIT

# (#7761) The HOST-DEFAULT state slot. A refusal case runs with INNGEST_CUTOVER_STATE unset by the
# gate, so emit_state falls back to this path — a best-effort `>` write that is `|| true`-guarded
# and therefore silent either way. Clear it around every case so one case's fallback write cannot
# bleed into a later case's assertions. Guarded: on a runner /var/lock is root-owned and the write
# never lands at all, which is fine — this must never be the reason a case fails.
clean_host_state_slot() { rm -f /var/lock/inngest-cutover-flip.state 2>/dev/null || true; }

setup_case() {
  clean_host_state_slot
  WORK=$(mktemp -d)
  TRACE="$WORK/trace"
  STATE="$WORK/state.json"
  LOGTRACE="$WORK/logtrace"
  # (#7228 P0-5) The monotonic re-flush latch is a real side effect of the forward path, so it
  # needs a seamed location here exactly like redis/systemctl/doppler do. Its mountpoint gate is
  # disabled (empty) because a mktemp dir is not a mountpoint — the gate's own behaviour is
  # covered by inngest-cutover-latch.test.sh, which owns the latch contract. Without these two
  # the forward-flip cases abort against the real /mnt/data, which is correct fail-closed
  # behaviour and useless as an FSM fixture.
  LATCH="$WORK/latch/flip-done.latch"
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
  LOGGER="$WORK/logger.sh"
  cat > "$LOGGER" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$LOGTRACE"
EOF
  # --- #7228: the serving-verification seam ---------------------------------------------
  # `done` is now PROBE-DERIVED: the FSM will not record it until a bounded-window /health
  # returns 200 AND the v0/gql registry comes back non-empty. Seamed at the CURL COMMAND, not
  # at the verdict, so the bounded-window/classification logic stays under test rather than
  # being stubbed away — a verdict seam would let the loop be deleted with this suite green.
  #
  # The DEFAULT stub is the HEALTHY host, so every pre-existing forward-flip case keeps
  # asserting what it always asserted. Cases that need a broken host overwrite it.
  # It dispatches on argv: `-w '%{http_code}'` present => the health probe (echo 200);
  # otherwise => the GQL POST (echo a one-function registry). A stub that answered
  # identically for both could not tell the two conditions apart, which is the whole point.
  # Parameterised by ENV at call time (STUB_HEALTH_CODE / STUB_REGISTRY_BODY) rather than by
  # regenerating the file per case: one stub, and each case states its scenario in the same
  # `env` line as the rest of its fixture.
  CURLSTUB="$WORK/curl.sh"
  cat > "$CURLSTUB" <<'CURLEOF'
#!/usr/bin/env bash
# The health probe is the invocation carrying -w '%{http_code}'; everything else is the GQL
# POST. Dispatching on argv (not answering identically) is what lets a fixture drive "listener
# up but registry empty" — the arm that distinguishes serving from serving-something.
for a in "$@"; do
  case "$a" in '%{http_code}') printf '%s' "${STUB_HEALTH_CODE:-200}"; exit 0 ;; esac
done
# An explicit branch, NOT a ${VAR:-default} with a JSON default: the first `}` inside the
# expansion terminates it, silently yielding malformed JSON that jq parses as "nan" — the
# healthy fixture would then drive the registry-unreadable arm and every forward case would
# abort for a harness reason that looks exactly like a SUT failure.
if [ -n "${STUB_REGISTRY_BODY:-}" ]; then
  printf '%s' "$STUB_REGISTRY_BODY"
else
  printf '%s' '{"data":{"functions":[{"id":"fn-1"}]}}'
fi
CURLEOF
  chmod +x "$CURLSTUB"
  # --- #7228: the done-OWNER marker seam -------------------------------------------------
  # The FSM refuses to write an unowned `done`, so a fixture without a writable marker path
  # would abort on verify-owner-unrecordable rather than exercising the path under test.
  # It is a FILE, not a command, so it leaves no command trace — which is why the flag stub
  # below stamps whether it exists at the moment `flag_set` runs. That is a strictly better
  # anchor than the command trace it replaces: the guarantee is "the marker is recorded BEFORE
  # the flag reaches done", and stamping at flag-time is what actually pins the ordering.
  OWNER_MARKER="$WORK/owner/done-owner"
  FLAGSET="$WORK/flagset.sh"
  cat > "$FLAGSET" <<EOF
#!/usr/bin/env bash
printf 'flag:%s\n' "\$1" >> "$TRACE"
[ -e "$OWNER_MARKER" ] && printf 'owner@%s\n' "\$1" >> "$TRACE"
exit 0
EOF
  chmod +x "$SYSCTL" "$REDIS" "$FLAGSET" "$LOGGER"
}

teardown_case() { rm -rf "$WORK"; clean_host_state_slot; }

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
      INNGEST_CUTOVER_LATCH="$LATCH" \
      INNGEST_CUTOVER_LATCH_MOUNT="" \
      CUTOVER_CURL_CMD="$CURLSTUB" \
      CUTOVER_DONE_OWNER_MARKER="$OWNER_MARKER" \
      CUTOVER_VERIFY_WINDOW_S=0 \
      CUTOVER_VERIFY_INTERVAL_S=0 \
      ${extra[@]+"${extra[@]}"} \
      bash "$TARGET" --fixture-seams >/dev/null 2>&1 || rc=$?
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
# #7228: `instance:` now sits between `start` and `flag:done`, and the ORDER is a guarantee, not
# an artifact. The stamp is written BEFORE the flag so a crash in between cannot leave a `done`
# with no stamp — which inngest-server-flip-guard.sh must treat as foreign, wedging a host that
# genuinely served. Reversing the two would still pass a set-membership check; only the sequence
# catches it.
assert_eq "combined order flipping,stop,flushall,flushed,start,instance-stamp,done" \
  "flag:flipping,stop,flushall,flag:flushed,start,flag:done,owner@done" "$order"
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
assert_eq "flipping resume re-runs full flush: stop,flushall,flushed,start,instance-stamp,done" \
  "stop,flushall,flag:flushed,start,flag:done,owner@done" "$order"
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
      INNGEST_CUTOVER_STATE="$STATE" INNGEST_CUTOVER_LATCH="$LATCH" INNGEST_CUTOVER_LATCH_MOUNT="" \
      CUTOVER_CURL_CMD="$CURLSTUB" CUTOVER_DONE_OWNER_MARKER="$OWNER_MARKER" CUTOVER_VERIFY_WINDOW_S=0 CUTOVER_VERIFY_INTERVAL_S=0 "$@" \
      bash "$TARGET" --fixture-seams >/dev/null 2>&1 || rc=$?
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
    CUTOVER_LOGGER_CMD="$LOGGER" INNGEST_CUTOVER_STATE="$STATE" INNGEST_CUTOVER_LATCH="$LATCH" INNGEST_CUTOVER_LATCH_MOUNT="" \
    CUTOVER_CURL_CMD="$CURLSTUB" CUTOVER_DONE_OWNER_MARKER="$OWNER_MARKER" CUTOVER_VERIFY_WINDOW_S=0 CUTOVER_VERIFY_INTERVAL_S=0 \
    CUTOVER_REDIS_DBSIZE=0 \
    bash "$TARGET" --fixture-seams >/dev/null 2>&1 || rc=$?
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

# --- Test 7 (#7228 3.5/3.6): `done` is PROBE-DERIVED, never asserted ------------------------
# THE DEFECT. `done` was written immediately after `start_server`, which is `systemctl start` —
# a call that succeeds when systemd ACCEPTED the unit, not when inngest bound :8288. So the
# terminal state asserted a live host condition it never measured, and because the flag lives in
# Doppler it OUTLIVED THE HOST: the 2026-07-30 machine recorded `done`, never bound, and the flag
# read `done` for twelve days across a host serving nothing. Nothing self-healed because nothing
# ever re-derived it.
#
# Each arm below is fixtured ALONE. A single "unhealthy" fixture that failed both conditions at
# once would pass against an implementation that checked only one of them.
echo "TEST: #7228 done is refused unless the host actually SERVES"

# ARM 1 — listener never comes up. The live state of 10.0.1.40 since 2026-07-30.
setup_case
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0 STUB_HEALTH_CODE=000)
order=$(trace_csv)
assert_eq "health never 200 => non-zero exit" "1" "$rc"
assert_absent "health never 200 => flag NEVER reached done" "$order" "flag:done"
assert_contains "health never 200 => flag driven terminal aborted" "$order" "flag:aborted"
assert_absent "health never 200 => no owner marker was recorded" "$order" "owner@"
assert_eq "health never 200 => state reason is the stable verify-health token" \
  "verify-health" "$(jq -r '.reason' "$STATE")"
assert_contains "health never 200 => a loud sibling line names the failure" \
  "$(cat "$LOGTRACE")" "SOLEUR_INNGEST_CUTOVER_VERIFY_FAILED"
# THE SERVER MUST BE STOPPED. start_server has already succeeded by the time verification runs,
# and inngest-server.service is Type=simple with Restart=on-failure — so returning without a
# stop leaves a RUNNING scheduler while the flag records `aborted`. On the registry-empty arm
# that process has already adopted PROD Postgres, and ADR-100's Context states scheduling is
# driven by the shared Postgres tables REGARDLESS of local registration: a live prod scheduler
# the FSM has just declared dead, which the guard can never legitimately restart but is already
# past. Every other abort in this FSM means "no scheduler is running here"; this one must too.
# Asserted on ORDER, not membership: a `stop` before the `start` is the pre-flush stop and
# would satisfy a bare contains-check while the post-start stop was missing entirely.
assert_eq "health never 200 => the started server is STOPPED before the flag goes terminal" \
  "stop,flushall,start,stop" \
  "$(printf '%s' "$order" | tr ',' '\n' | grep -E '^(start|stop|flushall)$' | paste -sd, -)"
# The flush still happened — this is a post-flush refusal, not a pre-flush one. Asserting it
# keeps the refusal from being mistaken for "the FSM aborted before doing anything".
assert_contains "health never 200 => the FLUSHALL still ran (refusal is POST-flush)" "$order" "flushall"
teardown_case

# ARM 2 — the listener is UP and the registry is EMPTY. The arm that makes this a check on
# SERVICE rather than on liveness: every reachability probe passes and the scheduler owns
# nothing, which during a cutover is the difference between "healthy" and "moved zero work".
setup_case
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0 STUB_REGISTRY_BODY='{"data":{"functions":[]}}')
order=$(trace_csv)
assert_eq "200 + EMPTY registry => non-zero exit" "1" "$rc"
assert_absent "200 + EMPTY registry => flag NEVER reached done" "$order" "flag:done"
assert_eq "200 + EMPTY registry => state reason is the stable verify-registry-empty token" \
  "verify-registry-empty" "$(jq -r '.reason' "$STATE")"
teardown_case

# ARM 3 — the endpoint answers with something that is not a registry (a 5xx body, a proxy page,
# a GraphQL error envelope). Never go green over a response we did not understand.
setup_case
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0 STUB_REGISTRY_BODY='{"errors":[{"message":"boom"}],"data":null}')
assert_eq "200 + unparseable registry => non-zero exit" "1" "$rc"
assert_eq "200 + unparseable registry => state reason is verify-registry-unreadable" \
  "verify-registry-unreadable" "$(jq -r '.reason' "$STATE")"
teardown_case

# ARM 4 — the host SERVES but cannot RECORD that it owns the done. Fail CLOSED: an unstamped `done` is exactly
# the inheritable state the guard cannot audit, so writing one would re-open the hazard the
# stamp exists to close.
setup_case
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0 CUTOVER_DONE_OWNER_MARKER=/proc/cannot/create/here)
order=$(trace_csv)
assert_eq "serving but marker unwritable => non-zero exit (fails CLOSED)" "1" "$rc"
assert_absent "serving but marker unwritable => flag NEVER reached done" "$order" "flag:done"
assert_eq "serving but marker unwritable => state reason is verify-owner-unrecordable" \
  "verify-owner-unrecordable" "$(jq -r '.reason' "$STATE")"
teardown_case

# ARM 5 — the `flushed)` RESUME arm must be gated too. Without this leg the verification could be
# wired into the forward path only, leaving a resume able to reach `done` unverified — and the
# resume arm is the one a crashed cutover actually takes.
setup_case
rc=$(run_flip flushed STUB_HEALTH_CODE=503)
order=$(trace_csv)
assert_eq "flushed-resume + non-200 => non-zero exit (the resume arm is gated too)" "1" "$rc"
assert_absent "flushed-resume + non-200 => flag NEVER reached done" "$order" "flag:done"
assert_contains "flushed-resume + non-200 => started the server, then refused" "$order" "start"
teardown_case

# NON-VACUITY. Every arm above asserts a REFUSAL, and a `verify_serving` hard-wired to `return 1`
# would satisfy all five while making the cutover impossible to complete. This is the positive
# control: the same fixture, healthy, must still reach `done`.
setup_case
rc=$(run_flip flushed)
order=$(trace_csv)
assert_eq "non-vacuity: a HEALTHY host still completes the flushed resume (exit 0)" "0" "$rc"
assert_contains "non-vacuity: a HEALTHY host still reaches done" "$order" "flag:done"
assert_contains "non-vacuity: a HEALTHY host records its owner marker" "$order" "owner@done"
teardown_case

# --- The GQL query is DRIFT-PINNED against inngest-registry-probe.sh ------------------------
# It is inlined here rather than sourced because inngest-registry-probe.sh is delivered to the
# WEB host only (server.tf + the infra-config push) and this FSM runs on the DEDICATED host.
# Sourcing an absent file would make the `done` gate fail-closed on an asset-delivery problem,
# i.e. wedge a cutover for a reason unrelated to whether the host serves. The cost of inlining is
# a third copy, so it is pinned byte-identical here AND in inngest-consumer-probe.test.sh.
echo "TEST: #7228 the inlined GQL query matches inngest-registry-probe.sh byte-for-byte"
REGISTRY_PROBE_SH="$SCRIPT_DIR/inngest-registry-probe.sh"
fsm_q=$(grep -oE "^readonly FUNCTIONS_GQL_QUERY=.*" "$TARGET" | head -1 || true)
probe_q=$(grep -oE "^readonly FUNCTIONS_GQL_QUERY=.*" "$REGISTRY_PROBE_SH" | head -1 || true)
if [[ -z "$fsm_q" || -z "$probe_q" ]]; then
  fail "could not extract FUNCTIONS_GQL_QUERY from both files (fsm='$fsm_q' probe='$probe_q') — the drift pin is vacuous"
elif [[ "$fsm_q" != "$probe_q" ]]; then
  fail "GQL query DRIFT: FSM has [$fsm_q] but inngest-registry-probe.sh has [$probe_q]"
else
  pass "inlined GQL query is byte-identical to inngest-registry-probe.sh's"
fi

# --- #7228: the verify window must DOMINATE the server's poll interval ----------------------
# THE DEFECT THIS PINS. The dedicated host does not learn its registry at startup — it polls the
# web-platform's --sdk-url, and inngest-bootstrap.sh starts the unit with `--poll-interval 60`.
# At the original 90s window that is 1.5 poll cycles, so a HEALTHY cutover whose registry
# populates on the second poll reads as EMPTY and is driven to TERMINAL `aborted` — not
# retryable, indistinguishable from a genuinely dark host, and requiring an operator re-arm.
#
# AND NOTHING PINNED IT. Every fixture in this suite and in inngest-cutover-latch.test.sh sets
# CUTOVER_VERIFY_WINDOW_S=0 to keep the cases fast, so the PRODUCTION default — the value that
# decides whether a real cutover survives — was asserted by zero tests. A constant the tests
# always override is a constant nothing guards.
#
# BOTH operands are extracted BY SHAPE, neither restated: a hardcoded copy of either number
# would agree with itself while disagreeing with the file it came from, which is the silent
# drift this exists to catch.
# --- #7228: the window must apply to the REGISTRY, not only to /health ----------------------
# THE DEFECT THIS PINS, and it is the one the numeric pin below could not see. An earlier
# revision broke out of the retry loop the moment /health returned 200 and then sampled the
# registry EXACTLY ONCE. /health comes up within seconds of `systemctl start`; the registry is
# discovered by polling --sdk-url at --poll-interval 60. So the single shot landed before the
# first poll, read EMPTY, and drove a HEALTHY cutover to terminal `aborted` — with the FLUSHALL
# already performed and the web scheduler quiesced. Raising the window did nothing for it,
# because the window was never applied to that condition.
#
# STATIC fixtures cannot distinguish the two loop shapes: they probe t=0 and t=infinity and never
# the transition, so both a retrying loop and a single-shot one pass. The discriminator is a
# STATEFUL stub that changes on the Nth invocation — empty registry on the first call, populated
# on the second — which is exactly the population a real cutover passes through.
echo "TEST: #7228 the verify window covers the REGISTRY, not just /health"
setup_case
STATE_COUNTER="$WORK/gql-calls"
: > "$STATE_COUNTER"
cat > "$CURLSTUB" <<CURLEOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in '%{http_code}') printf '200'; exit 0 ;; esac
done
# GQL call: empty on the FIRST invocation, populated from the second onward.
printf 'x' >> "$STATE_COUNTER"
if [ "\$(wc -c < "$STATE_COUNTER")" -le 1 ]; then
  printf '%s' '{"data":{"functions":[]}}'
else
  printf '%s' '{"data":{"functions":[{"id":"fn-1"}]}}'
fi
CURLEOF
chmod +x "$CURLSTUB"
# A non-zero window with a zero sleep: the loop may retry, and does so without wall-clock cost.
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0 CUTOVER_VERIFY_WINDOW_S=30 CUTOVER_VERIFY_INTERVAL_S=0)
order=$(trace_csv)
assert_eq "a registry that populates on the SECOND poll still reaches done (exit 0)" "0" "$rc"
assert_contains "a registry that populates on the SECOND poll still reaches done (flag)" "$order" "flag:done"
assert_absent "a registry that populates on the SECOND poll is NOT aborted" "$order" "flag:aborted"
# Non-vacuity: prove the stub really did serve an empty registry first, so the pass above is a
# RETRY and not a stub that was populated all along.
assert_eq "non-vacuity: the GQL endpoint was polled more than once (the loop retried)" \
  "yes" "$([[ $(wc -c < "$STATE_COUNTER") -ge 2 ]] && echo yes || echo no)"
teardown_case

# --- #7228: the window must also fit UNDER the unit's start timeout -------------------------
# A Type=oneshot with no TimeoutStartSec inherits DefaultTimeoutStartUSec (90s on this image),
# so raising the window above it does not lengthen the wait — it makes systemd SIGTERM the unit
# mid-verify, AFTER the FLUSHALL has committed, with no verify-* marker emitted (the script traps
# ERR, not TERM). The window was drift-pinned to the poll interval it must EXCEED and unpinned to
# the ceiling that KILLS it, which is the more dangerous of the two directions.
# --- S1: the /HEALTH retry direction, which was fixtured at cardinality one ------------------
# The registry case above varies the registry across calls but holds STUB_HEALTH_CODE constant,
# so no fixture ever exercised health non-200-then-200 — and deleting the health retry left the
# suite fully green. That is the identical defect just fixed for the registry, in the other
# operand, and the health retry is the loop's PRIMARY stated rationale ("inngest takes seconds
# to bind after systemctl start"). Same stateful instrument, applied to the sibling.
echo "TEST: #7228 the verify window covers /HEALTH retries, not just the registry"
setup_case
HEALTH_COUNTER="$WORK/health-calls"
: > "$HEALTH_COUNTER"
cat > "$CURLSTUB" <<CURLEOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in '%{http_code}')
    printf 'x' >> "$HEALTH_COUNTER"
    if [ "\$(wc -c < "$HEALTH_COUNTER")" -le 1 ]; then printf '000'; else printf '200'; fi
    exit 0 ;;
  esac
done
printf '%s' '{"data":{"functions":[{"id":"fn-1"}]}}'
CURLEOF
chmod +x "$CURLSTUB"
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0 CUTOVER_VERIFY_WINDOW_S=30 CUTOVER_VERIFY_INTERVAL_S=0)
order=$(trace_csv)
assert_eq "a listener that binds on the SECOND probe still reaches done (exit 0)" "0" "$rc"
assert_contains "a listener that binds on the SECOND probe still reaches done (flag)" "$order" "flag:done"
assert_absent "a listener that binds on the SECOND probe is NOT aborted" "$order" "flag:aborted"
assert_eq "non-vacuity: /health was probed more than once (the loop retried)" \
  "yes" "$([[ $(wc -c < "$HEALTH_COUNTER") -ge 2 ]] && echo yes || echo no)"
teardown_case

echo "TEST: #7228 the verify window fits under the unit's TimeoutStartSec"
WINDOW_DEFAULT=$(grep -oE '^CUTOVER_VERIFY_WINDOW_S="\$\{CUTOVER_VERIFY_WINDOW_S:-[0-9]+\}"' "$TARGET" \
  | grep -oE '[0-9]+' | tail -1 || true)
FLIP_UNIT="$SCRIPT_DIR/inngest-cutover-flip.service"
UNIT_TIMEOUT=$(grep -oE '^TimeoutStartSec=[0-9]+' "$FLIP_UNIT" | grep -oE '[0-9]+' | head -1 || true)
if [[ -z "$UNIT_TIMEOUT" ]]; then
  fail "inngest-cutover-flip.service declares no TimeoutStartSec — the oneshot inherits the 90s default and will be killed mid-verify"
elif [[ -z "$WINDOW_DEFAULT" ]]; then
  fail "could not extract the verify window default — this pin is vacuous"
elif [[ $(( WINDOW_DEFAULT )) -ge $(( UNIT_TIMEOUT )) ]]; then
  fail "verify window ${WINDOW_DEFAULT}s >= TimeoutStartSec ${UNIT_TIMEOUT}s: systemd kills the oneshot mid-verify, after the FLUSHALL, emitting no marker"
else
  pass "verify window ${WINDOW_DEFAULT}s < TimeoutStartSec ${UNIT_TIMEOUT}s (the wait can actually complete)"
fi

echo "TEST: #7228 the verify window dominates inngest-server's --poll-interval"
BOOTSTRAP_SH="$SCRIPT_DIR/inngest-bootstrap.sh"
POLL_INTERVAL=$(grep -oE -- '--poll-interval [0-9]+' "$BOOTSTRAP_SH" | grep -oE '[0-9]+' | sort -u | head -1 || true)
if [[ -z "$WINDOW_DEFAULT" || -z "$POLL_INTERVAL" ]]; then
  fail "could not extract both operands by shape (window='$WINDOW_DEFAULT' poll='$POLL_INTERVAL') — the pin is vacuous"
elif [[ "$(grep -cE -- '--poll-interval [0-9]+' "$BOOTSTRAP_SH")" -eq 0 ]]; then
  fail "no --poll-interval literal found in inngest-bootstrap.sh — extraction broke"
elif [[ $(( WINDOW_DEFAULT )) -lt $(( POLL_INTERVAL * 3 )) ]]; then
  fail "verify window ${WINDOW_DEFAULT}s is under 3x the --poll-interval (${POLL_INTERVAL}s): a healthy cutover whose registry lands on a later poll would be driven to TERMINAL aborted"
else
  pass "verify window ${WINDOW_DEFAULT}s >= 3x --poll-interval ${POLL_INTERVAL}s (registry has room to populate)"
fi

# --- S2: the production probe URLs are asserted by nothing otherwise ------------------------
# The curl stub dispatches on argv and never reads the URL, and every fixture injects the seam —
# so mutating BOTH defaults to a wrong port and path left the suite fully green. A typo there
# makes verify_serving fail on every host, driving every real cutover to terminal `aborted`
# AFTER the FLUSHALL: the non-retryable state the window fix exists to avoid. Exactly the class
# already pinned for CUTOVER_VERIFY_WINDOW_S one line below it; the reasoning was not carried up.
echo "TEST: #7228 the production probe URLs target the port the server actually binds"
BOOTSTRAP_FOR_URL="$SCRIPT_DIR/inngest-bootstrap.sh"
H_URL=$(grep -oE '^CUTOVER_HEALTH_URL="\$\{CUTOVER_HEALTH_URL:-[^}]+\}"' "$TARGET" | sed -E 's/.*:-([^}]+)\}"/\1/' | head -1 || true)
G_URL=$(grep -oE '^CUTOVER_GQL_URL="\$\{CUTOVER_GQL_URL:-[^}]+\}"' "$TARGET" | sed -E 's/.*:-([^}]+)\}"/\1/' | head -1 || true)
BIND_PORT=$(grep -oE -- '--port [0-9]+' "$BOOTSTRAP_FOR_URL" | grep -oE '[0-9]+' | sort -u | head -1 || true)
if [[ -z "$H_URL" || -z "$G_URL" || -z "$BIND_PORT" ]]; then
  fail "could not extract both probe URLs and the bound port by shape (health='$H_URL' gql='$G_URL' port='$BIND_PORT') — this pin is vacuous"
elif [[ "$H_URL" != "http://127.0.0.1:$BIND_PORT/health" ]]; then
  fail "the health probe URL '$H_URL' does not target the bound port $BIND_PORT on loopback — verify_serving would fail on every host"
elif [[ "$G_URL" != "http://127.0.0.1:$BIND_PORT/v0/gql" ]]; then
  fail "the GQL probe URL '$G_URL' does not target the bound port $BIND_PORT on loopback"
else
  pass "both probe URLs target 127.0.0.1:$BIND_PORT, the port inngest-server binds"
fi

# --- #7761 GUARD 1: the argv seam gate, and its completeness tripwire ----------------------
#
# THE DEFECT. inngest-cutover-flip.service runs as root under `doppler run`, which injects the
# WHOLE soleur-inngest/prd config into the environment. This script's fixture seams read straight
# from that environment and EXECUTE what they find, so a Doppler secret NAME — e.g. a secret
# literally called CUTOVER_REDIS_CLI_CMD — was arbitrary command execution as root at the next
# 30-second poll, inside the same unit that performs the irreversible FLUSHALL. The trust boundary
# was documented as "root on the host"; it was actually "Doppler config-write access".
#
# THE FIX HAS TWO HALVES and they close different holes. The unit's --only-secrets bounds what is
# injected AT ALL (it is the only half that can reach BASH_ENV/PATH/LD_PRELOAD/IFS, which bash
# honours without this script ever naming them). This half — the argv gate — closes the seams the
# script itself reads, and it is unforgeable by any environment writer for the simple reason that
# argv is not the environment.
#
# WHY THE ASSERTIONS BELOW ARE MOSTLY STRUCTURAL. The gate's whole purpose is to make the seams
# unobservable, so a refusal cannot be watched THROUGH the seams it just unset. It is therefore
# observed as an ABSENCE (a canary that is not written) plus shape assertions on the gate itself.
# Deliberately NO PATH shadowing is introduced: infra-validation.yml runs ubuntu-24.04 with a real
# systemctl, and that workflow's own comment records the standing safety property — "It mocks
# systemctl + redis inside a mktemp -d, so no real Redis is reached and no FLUSHALL is executed."
# That guarantee exists BECAUSE commands are seamed explicitly and PATH is never touched; shadowing
# PATH to observe a refusal would invert it.

FLIP_SRC="$TARGET"

# Comments stripped FIRST. The script carries ${VAR+x} and ${VAR-default} inside explanatory prose,
# and a derivation that reads those would demand names the script never actually reads.
flip_src_nocomments() { sed -E 's/(^|[^\\])#.*$/\1/' "$FLIP_SRC"; }

# The seam-name set DERIVED FROM THE SCRIPT BY SHAPE — the tripwire's left-hand side.
#
# Scoped to the CUTOVER_ and INNGEST_CUTOVER_ prefixes. Unscoped it would sweep in
# ${INNGEST_REDIS_PASSWORD:-}, forcing it into the unset list and breaking `redis-cli -a ""`
# against a password-protected Redis. INNGEST_CUTOVER_FLIP is inside the prefix and is a real
# input rather than a seam, which is why the expected set is the unset list PLUS that one name.
#
# Matches the WHOLE expansion grammar, not the three idioms this file happens to use today:
# ${NAME}, ${NAME:-}, ${NAME-}, ${NAME:+}, ${NAME+}, ${NAME:=}, ${NAME=}, ${NAME:?}, ${NAME?} and
# bare $NAME. Stopping at :- / +x / - would miss a future ${CUTOVER_X:+...} or bare $CUTOVER_X and
# re-open the hole silently. The bare forms are redundant in today's file — every bare read also
# appears in a default form — but that is a property of this file today, not of the shape.
derived_prefixed_names() {
  flip_src_nocomments \
    | grep -oE '\$\{(CUTOVER_|INNGEST_CUTOVER_)[A-Za-z0-9_]+(\}|:-|-|:\+|\+|:=|=|:\?|\?)|\$(CUTOVER_|INNGEST_CUTOVER_)[A-Za-z0-9_]+' \
    | grep -oE '(CUTOVER_|INNGEST_CUTOVER_)[A-Za-z0-9_]+' \
    | sort -u || true
}

# The gate's own unset list — the tripwire's right-hand side. Extracted from the `for` construct
# itself, NOT from a comment sentinel: the list is load-bearing code, and anchoring a completeness
# check on prose would let the check pass against a gate whose actual list had drifted.
gate_unset_names() {
  # COMMENT-STRIPPED, and that is load-bearing rather than symmetry with the sibling above. Read
  # raw, this window is satisfied by PROSE: a comment naming a seam between the list's last entry
  # and `do` is valid bash, sits inside the extraction, and makes the completeness tripwire pass
  # against a gate whose list no longer carries that name — reopening the exact hole the tripwire
  # exists to close. Measured: dropping CUTOVER_GQL_URL from the list while leaving such a comment
  # kept the suite green at 126/0 with a live seam un-unset.
  flip_src_nocomments \
    | awk '/^[[:space:]]*for[[:space:]]+_seam[[:space:]]+in/{f=1} f{print} f&&/^[[:space:]]*do[[:space:]]*$/{exit}' \
    | grep -oE '(CUTOVER_|INNGEST_CUTOVER_)[A-Za-z0-9_]+' \
    | sort -u || true
}

echo "TEST: #7761 the gate's unset list is COMPLETE against the script's own seam reads"
DERIVED="$(derived_prefixed_names)"
UNSET_LIST="$(gate_unset_names)"
EXPECTED="$(printf '%s\nINNGEST_CUTOVER_FLIP\n' "$UNSET_LIST" | grep -vE '^$' | sort -u || true)"
assert_eq "derived seam set == unset list + INNGEST_CUTOVER_FLIP (the completeness tripwire)" \
  "$DERIVED" "$EXPECTED"
# A FLOOR on the list's size, so the tripwire cannot be satisfied by an EMPTY gate agreeing with an
# empty derivation. Measured at 15 seams this session; a floor, never -eq, so adding a seam and its
# list entry together stays green.
UNSET_COUNT="$(printf '%s\n' "$UNSET_LIST" | grep -cE '^(CUTOVER_|INNGEST_CUTOVER_)' || true)"
if [[ "$UNSET_COUNT" -ge 15 ]]; then
  pass "the gate unsets at least 15 seam names (got $UNSET_COUNT)"
else
  fail "the gate's unset list holds only $UNSET_COUNT names, expected >= 15"
fi
assert_absent "INNGEST_REDIS_PASSWORD is NOT unset (it is a real input, not a seam)" \
  "$UNSET_LIST" "INNGEST_REDIS_PASSWORD"
assert_absent "INNGEST_CUTOVER_FLIP is NOT unset (it is the FSM's real input)" \
  "$UNSET_LIST" "INNGEST_CUTOVER_FLIP"

echo "TEST: #7761 the companion assertion — no UNPREFIXED external value in command position"
# The tripwire above is prefix-scoped, so a future seam named outside both prefixes is invisible to
# it. This pairs with it: every expansion appearing in COMMAND POSITION must either be prefix-scoped
# (and therefore covered by the gate) or be assigned somewhere in this file (and therefore not
# externally supplied). Without this pairing the gate's property does not hold.
CMD_POS_VARS="$(flip_src_nocomments \
  | grep -oE '(^|[;&|]|\bthen\b|\belse\b|\bdo\b|\{)[[:space:]]*"?\$\{?[A-Za-z_][A-Za-z0-9_]*' \
  | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' \
  | grep -oE '[A-Za-z_][A-Za-z0-9_]*' | sort -u || true)"
# ASSIGNED_VARS is a FALSE-POSITIVE SUPPRESSOR, and as of #7761 it is inert — measured, every
# command-position expansion in this script today is prefix-scoped, so it has nothing to suppress.
# It survived its own mutation (emptying it left the suite green) and that survivor is EQUIVALENT,
# not a gap: emptying it makes the assertion STRICTER, never weaker, so the degenerate direction
# fails closed. It is kept because a future in-file-assigned variable used in command position
# would otherwise trip this assertion for no reason. Recorded here so the next reader does not
# re-litigate the surviving mutant. The assertion's real teeth were verified separately against
# three shapes — an indented call on its own line, a call after a pipe, and the braced
# ${NAME:-} form — each of which reds it.
ASSIGNED_VARS="$(grep -oE '^[[:space:]]*(local |readonly |export )?[A-Za-z_][A-Za-z0-9_]*=' "$FLIP_SRC" \
  | grep -oE '[A-Za-z_][A-Za-z0-9_]*=' | tr -d '=' | sort -u || true)"
UNGOVERNED=""
while IFS= read -r v; do
  [[ -n "$v" ]] || continue
  case "$v" in CUTOVER_*|INNGEST_CUTOVER_*) continue ;; esac
  if ! printf '%s\n' "$ASSIGNED_VARS" | grep -qxF "$v"; then
    UNGOVERNED="$UNGOVERNED $v"
  fi
done <<< "$CMD_POS_VARS"
assert_eq "no unprefixed externally-supplied expansion sits in command position" "" "${UNGOVERNED# }"

echo "TEST: #7761 the gate's POSITION, its predicate, and its pre-trap-window safety"
# Position asserted BY SHAPE, never a hardcoded line number. It must sit after `readonly
# SERVER_UNIT` (the earliest point at which $LOG_TAG is safe to reference under set -u) and before
# the STATE_FILE assignment (the FIRST seam read). Specified against STATE_FILE and not "after
# read_flag": read_flag is only a DEFINITION and its seam is not evaluated until run_flip, so a gate
# moved below it would still precede every deferred read and would stay green.
SERVER_UNIT_LN="$(grep -nE '^readonly SERVER_UNIT=' "$FLIP_SRC" | head -1 | cut -d: -f1 || true)"
STATE_FILE_LN="$(grep -nE '^STATE_FILE=' "$FLIP_SRC" | head -1 | cut -d: -f1 || true)"
# Anchored on the PREDICATE CONSTRUCT, not the bare flag name: a body-grep sees comments too, and
# the script's own header documents this flag in prose. A bare-token anchor would resolve to that
# header line — above `readonly SERVER_UNIT` — and fail a correctly-placed gate
# (cq-assert-anchor-not-bare-token).
GATE_LN="$(grep -nE '\$\{1:-\}.*--fixture-seams' "$FLIP_SRC" | head -1 | cut -d: -f1 || true)"
if [[ -n "$GATE_LN" && -n "$SERVER_UNIT_LN" && -n "$STATE_FILE_LN" \
      && "$GATE_LN" -gt "$SERVER_UNIT_LN" && "$GATE_LN" -lt "$STATE_FILE_LN" ]]; then
  pass "the gate sits between readonly SERVER_UNIT ($SERVER_UNIT_LN) and STATE_FILE ($STATE_FILE_LN), at $GATE_LN"
else
  fail "gate position wrong: gate=$GATE_LN server_unit=$SERVER_UNIT_LN state_file=$STATE_FILE_LN"
fi
# The predicate must be ARGV, not an environment marker. An env-keyed sentinel would be forgeable by
# exactly the writer this gate exists to exclude, and — if it were named CUTOVER_* — would put the
# gate's own input inside the tripwire's derivation prefix, reddening it on its first green run.
assert_contains "the gate's predicate reads positional argv, not the environment" \
  "$(flip_src_nocomments | grep -F -- '--fixture-seams' | head -1 || true)" '${1:-}'
# The gate runs ~460 lines BEFORE `trap on_unexpected_exit ERR` is installed, so under
# `set -Eeuo pipefail` any stray non-zero there is a SILENT death: no marker, no transition — the
# one failure shape this FSM exists never to have. Pin the two constructs that would cause it.
# Same anchoring discipline as GATE_LN above: start at the predicate construct, not at the first
# prose mention of the flag, and stop at the block's own closing `fi` at column 0.
GATE_BODY="$(flip_src_nocomments | awk '/\$\{1:-\}.*--fixture-seams/{f=1} f{print} f&&/^fi[[:space:]]*$/{exit}' || true)"
assert_absent "the gate's counter uses n=\$((n+1)), never (( n++ )) which returns 1 on 0->1" \
  "$GATE_BODY" '((_seams_present++))'
assert_absent "no loop body in the gate ends in a bare [[ ... ]] && ... short-circuit" \
  "$GATE_BODY" ']] &&'
assert_contains "the refusal marker's logger call is failure-tolerant in the pre-trap window" \
  "$GATE_BODY" '2>/dev/null || true'
# Mutation row 8: a gate that sanitised PATH/BASH_ENV/IFS/LD_PRELOAD would silently BLIND its own
# refusal tests rather than redden them. Those names are --only-secrets' job, at the unit.
for forbidden in PATH BASH_ENV IFS LD_PRELOAD; do
  assert_absent "the gate does not touch $forbidden (that is --only-secrets' job, at the unit)" \
    "$GATE_BODY" "unset $forbidden"
done
# Scenario 2 / 3: the refusal marker is emitted, and its emission is CONDITIONAL on a seam actually
# having been present — a marker fired on every ordinary production poll would be noise that trains
# the operator to ignore the channel. Asserted structurally because the marker rides the RAW logger:
# CUTOVER_LOGGER_CMD is itself one of the seams the gate has just unset, so it cannot be observed
# through the harness sink without the PATH shadowing this suite deliberately does not introduce.
assert_contains "a refusal emits the SEAM_REFUSED marker on the inngest-cutover-flip tag" \
  "$GATE_BODY" 'SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED'
assert_contains "the refusal marker is gated on a non-zero count of seams actually present" \
  "$GATE_BODY" '"$_seams_present" -gt 0'

echo "TEST: #7761 REFUSAL is observable as an absence — the canary is not written"
# The discriminator. CUTOVER_LOGGER_CMD is the seam every branch reaches, including the terminal
# no-ops, so it observes the gate without going anywhere near the destructive arm.
#
# The flag is left ABSENT so the run takes `noop-unset`, which touches neither systemctl nor
# redis-cli nor the latch and cannot reach anything destructive. CUTOVER_FLIP_FLAG is set to
# "armed" precisely so the case is a real test of the gate: if the gate did not unset it, the
# ${VAR+x} set-versus-absent distinction would resolve to "armed" and drive the forward path.
setup_case
CANARY="$WORK/canary"
CANARY_STUB="$WORK/canary.sh"
cat > "$CANARY_STUB" <<EOF
#!/usr/bin/env bash
printf 'pwned\n' >> "$CANARY"
EOF
chmod +x "$CANARY_STUB"
rc=0
env CUTOVER_LOGGER_CMD="$CANARY_STUB" CUTOVER_FLIP_FLAG="armed" \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
assert_eq "a refused run still exits 0 (it takes the noop-unset arm)" "0" "$rc"
if [[ -e "$CANARY" ]]; then
  fail "REFUSAL FAILED: the seam ran — canary exists at $CANARY"
else
  pass "the environment-supplied command seam did NOT execute (canary absent)"
fi
teardown_case

echo "TEST: #7761 the must-PASS control — with --fixture-seams the same seam IS honoured"
# Without this control the matrix cannot distinguish a correct gate from one that refuses
# everything, which would pass every absence assertion above while breaking all 147 existing cases.
setup_case
CANARY="$WORK/canary"
CANARY_STUB="$WORK/canary.sh"
cat > "$CANARY_STUB" <<EOF
#!/usr/bin/env bash
printf 'ok\n' >> "$CANARY"
EOF
chmod +x "$CANARY_STUB"
rc=0
env CUTOVER_LOGGER_CMD="$CANARY_STUB" CUTOVER_FLIP_FLAG="" \
    bash "$TARGET" --fixture-seams >/dev/null 2>&1 || rc=$?
assert_eq "an authorised run exits 0" "0" "$rc"
if [[ -e "$CANARY" ]]; then
  pass "with --fixture-seams the seam IS honoured (canary written)"
else
  fail "the gate refuses even an authorised run — canary absent at $CANARY"
fi
teardown_case

echo "TEST: #7761 a repointed state slot is not written when the seams are refused"
# Scenario 9. Without the gate, INNGEST_CUTOVER_STATE lets any environment writer choose a path the
# root script truncates with `>`. With it, the name is unset and STATE_FILE falls back to the
# host default, so nothing appears at the caller-named path.
setup_case
PWNED_STATE="$WORK/pwned.state"
rc=0
env INNGEST_CUTOVER_STATE="$PWNED_STATE" CUTOVER_FLIP_FLAG="" \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
assert_eq "the refused run exits 0" "0" "$rc"
if [[ -e "$PWNED_STATE" ]]; then
  fail "REFUSAL FAILED: the caller-named state slot was written at $PWNED_STATE"
else
  pass "no file appeared at the caller-named state path"
fi
teardown_case

echo "TEST: #7761 the must-PASS non-canonical — seams honoured under a second temp root"
# Scenario 11. The gate authorises on argv alone and must not have acquired a hidden dependency on
# any particular fixture location; a gate keyed on a path prefix would pass every case above and
# fail here.
setup_case
ALT_ROOT="$(mktemp -d)"
ALT_CANARY="$ALT_ROOT/elsewhere"
ALT_STUB="$ALT_ROOT/stub.sh"
cat > "$ALT_STUB" <<EOF
#!/usr/bin/env bash
printf 'ok\n' >> "$ALT_CANARY"
EOF
chmod +x "$ALT_STUB"
rc=0
env CUTOVER_LOGGER_CMD="$ALT_STUB" CUTOVER_FLIP_FLAG="" \
    bash "$TARGET" --fixture-seams >/dev/null 2>&1 || rc=$?
assert_eq "the alternate-root authorised run exits 0" "0" "$rc"
if [[ -e "$ALT_CANARY" ]]; then
  pass "seams are honoured under a differently-named fixture root (argv, not path, authorises)"
else
  fail "the gate refused an authorised run under an alternate root"
fi
rm -rf "$ALT_ROOT"
teardown_case

# --- #7761 THE UNIT'S SANDBOXING SHAPE ------------------------------------------------------
#
# WHY THESE EXIST. The five sandboxing directives were added by this PR and pinned by NOTHING —
# repo-wide there was not one assertion on any of them for this unit. That matters more than the
# usual "untested config" case, because the unit's own comment calls the correct spelling
# non-obvious ("wrong twice") and names the failure mode: a `ReadWritePaths=` entry naming a
# directory that does not exist makes systemd fail mount-namespace setup, so the unit dies on
# EVERY 30-second fire after a host replace, emitting nothing, on the one host with no inbound
# control channel. A later hygiene edit — adding ProtectHome, `-`-prefixing /mnt/data, dropping
# StateDirectory — would have reddened nothing and surfaced only as a permanently silent host.
#
# inngest.test.sh's all-members PrivateTmp check derives its population from heredocs inside
# inngest-bootstrap.sh, and this is a STANDALONE .service file, so it was never in that set.
UNIT_SRC="$SCRIPT_DIR/inngest-cutover-flip.service"
echo "TEST: #7761 the unit's sandboxing directives are pinned"
assert_eq "the unit file exists" "yes" "$([[ -f "$UNIT_SRC" ]] && echo yes || echo no)"
for d in 'NoNewPrivileges=yes' 'ProtectSystem=strict' 'PrivateTmp=true' 'StateDirectory=inngest-cutover'; do
  # Anchored at column 0 on the directive itself: the unit documents every one of these in prose
  # directly above it, so a bare-substring check would be satisfied by the comment explaining it
  # (cq-assert-anchor-not-bare-token — this PR has already been bitten by that twice).
  if grep -qE "^${d}\$" "$UNIT_SRC"; then pass "unit sets ${d}"; else fail "unit does not set ${d}"; fi
done
# PrivateTmp must be spelled `true`: inngest.test.sh asserts `^PrivateTmp=true$` by regex, and
# every inngest-family unit uses it. git-data-gc.service is the repo's lone `yes`.
if grep -qE '^PrivateTmp=yes$' "$UNIT_SRC"; then fail "PrivateTmp spelled 'yes' — inngest family uses 'true'"; else pass "PrivateTmp is not spelled 'yes'"; fi
# ProtectHome would mask /root and break the Doppler CLI's home resolution, defeating the
# Environment=HOME=/root above it. git-data-gc.service records this.
if grep -qE '^ProtectHome' "$UNIT_SRC"; then fail "ProtectHome is set — it masks /root and breaks the Doppler CLI"; else pass "ProtectHome is NOT set (it would break the Doppler CLI)"; fi
# The writable paths must name the MOUNTS, never the lazily-created subdirectories inside them —
# and must not be `-`-prefixed, which would leave them read-only under ProtectSystem=strict and
# abort `latch-unrecordable` on every fire.
assert_contains "ReadWritePaths names the mounts, not the lazily-created subdirs" \
  "$(grep -E '^ReadWritePaths=' "$UNIT_SRC" || true)" "/var/lock /mnt/data"
RWP="$(grep -E '^ReadWritePaths=' "$UNIT_SRC" || true)"
assert_absent "no ReadWritePaths entry is '-'-prefixed (that would make it read-only)" "$RWP" "=-"
assert_absent "ReadWritePaths does not name a lazily-created subdirectory" "$RWP" "inngest-cutover"
# The unit's own stderr must be tagged, or journald derives the tag from the ExecStart basename —
# `doppler` — which no Vector source admits, and every diagnostic the unit writes is dark.
assert_contains "the unit sets SyslogIdentifier (else journald tags it 'doppler')" \
  "$(grep -E '^SyslogIdentifier=' "$UNIT_SRC" || true)" "SyslogIdentifier=inngest-cutover-flip"
# The shipped unit must NOT authorise the fixture seams. Nothing else in the repo pins this, and
# it is a one-word edit that would disable the entire gate in production while leaving Guard 2
# green (the flag sits after the `--`, so the --only-secrets bound is untouched).
UNIT_EXEC="$(sed -n '/^ExecStart=/,/[^\\]$/p' "$UNIT_SRC" | sed 's/\\$//' | tr -d '\n')"
assert_absent "the SHIPPED unit does not pass --fixture-seams (that would disable the gate)" \
  "$UNIT_EXEC" "--fixture-seams"

# --- S8: an assertion-count FLOOR ----------------------------------------------------------
# Every suite here gates only on FAIL. Deleting a whole test block drops the PASS count and
# still exits 0, so "all assertions passed" and "fewer assertions ran" are the same signal.
# A FLOOR, never -eq: adding tests must not red the suite.
# 102 -> 138: +24 for the #7761 seam-gate block (tripwire, companion assertion, position/predicate/
# pre-trap-window shape, the four behavioural refusal + must-PASS cases), then +12 for the
# unit sandboxing-shape block review found pinned by nothing. Derived from a green run, never
# guessed; raise in lockstep when adding tests.
MIN_ASSERTIONS=138
if [[ "$PASS" -lt "$MIN_ASSERTIONS" ]]; then
  # printf + exit, NOT fail() (ADR-193): routing the floor through the counter it exists to
  # protect means one edit disarms both. See the instrument self-test at the top.
  printf 'FAIL: assertion-count floor: only %s assertions ran, expected >= %s — a block was skipped or emptied.\n' \
    "$PASS" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi

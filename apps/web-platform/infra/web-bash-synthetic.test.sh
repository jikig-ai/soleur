#!/usr/bin/env bash
# Tests the runtime Bash synthetic (web-bash-synthetic.sh; follow-up to #10445 via #10455, ADR-079 addendum 2026-10-20).
#
# The synthetic `docker exec`s ONE real wrapped Bash call into the RUNNING web container and pings a per-host dead-man heartbeat
# ONLY on a verified pass. This suite drives the real script against a mock `docker` that copies the real output shapes and
# preserves exit statuses, and pins GUARD 1 of the plan (no false green, no false red on a deploy):
#   - a `no_ping` run never pings; a failed run pings /fail; a run overlapped by a container swap is never a `fail`;
#   - the ping happens AFTER the probe returned (the mock stamps PROBE_DONE into the same log the ping seam writes to);
#   - the verdict mapping is the ONE function in lib/sdk-bash-verdict.sh, sourced by this script AND ci-deploy.sh.
# Each Guard 1 mutation row is applied to a COPY of the SUT/lib and must turn the core cases RED; the control (unmutated) run must be
# GREEN first, and each mutation is asserted to have LANDED against a pristine copy (a mutation that does not land reports the baseline).
#
# Run: bash apps/web-platform/infra/web-bash-synthetic.test.sh
# shellcheck disable=SC2034  # ERR / CURLS / CURL_ARGV / PINGS / JOURNAL / EC are read inside the eval strings of ok_if
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/web-bash-synthetic.sh"
LIB="$SCRIPT_DIR/lib/sdk-bash-verdict.sh"
DEPLOY="$SCRIPT_DIR/ci-deploy.sh"
SERVICE="$SCRIPT_DIR/web-bash-synthetic.service"
TIMER="$SCRIPT_DIR/web-bash-synthetic.timer"

export TMPDIR="${TMPDIR:-/var/tmp}"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Canonical helper, byte-for-byte from plugins/soleur/test/test-helpers.sh (comments stripped). Edit there, then re-sync here.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$TMP_ROOT"

passes=0
fails=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }
ok_if() { if eval "$2"; then pass "$1"; else fail "$1"; echo "        condition: $2"; fi; }

# Instrument self-test (ADR-193): drive both helpers before any real case; reported with printf + exit, never through them.
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path, expected and subtracted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: assertion helpers are not dispatching (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 1
fi
passes=0; fails=0

echo "=== web-bash-synthetic (runtime Bash synthetic) tests ==="
for f in "$SUT" "$LIB" "$SERVICE" "$TIMER"; do ok_if "$(basename "$f") exists" "[[ -f '$f' ]]"; done
ok_if "SUT is syntactically valid bash" "bash -n '$SUT'"
ok_if "lib is syntactically valid bash" "bash -n '$LIB'"

# ---- Mock docker ---------------------------------------------------------------------------------------------------------
# Output shapes copied from real docker: inspect prints "<running> <64-hex id> <RFC3339 start>"; stats prints "<pct>%"; a missing
# container is rc 1 with `Error: No such object`; the probe exec prints SDK_BASH_DISPATCHED then SDK_BASH_RESULT {json} and
# exits with the probe's rc. The mock REFUSES (rc 64) an argv shape the SUT is not allowed to send: that is what keeps the
# fixture seam from sitting above the code under test (a mock that answers any argv cannot detect a wrong request).
BIN="$TMP_ROOT/bin"; assert_fixture_dir "$BIN"; mkdir -p "$BIN"
cat > "$BIN/docker" <<'MOCK'
#!/usr/bin/env bash
LOG="${MOCK_LOG:?}"
printf 'docker %s\n' "$*" >> "$LOG/calls"
viol() { printf 'MOCK_ARGV_VIOLATION %s\n' "$1" >> "$LOG/calls"; echo "mock docker: refused argv: $1" >&2; exit 64; }
case "${1:-}" in
  inspect)
    [[ "${2:-}" == "-f" && "$#" -eq 4 && "$4" == "${MOCK_CTR:-soleur-web-platform}" ]] || viol "inspect shape: $*"
    n=$(( $(cat "$LOG/inspect.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$LOG/inspect.n"
    [[ "${MOCK_INSPECT_RC:-0}" -eq 0 ]] || { echo "Error: No such object: ${MOCK_CTR:-soleur-web-platform}" >&2; exit "$MOCK_INSPECT_RC"; }
    if [[ "$n" -ge 2 && -n "${MOCK_ID2:-}" ]]; then
      printf '%s %s %s\n' "${MOCK_RUNNING2:-true}" "$MOCK_ID2" "${MOCK_START2:-${MOCK_START:-2026-10-20T10:00:00.123456789Z}}"
    else
      printf '%s %s %s\n' "${MOCK_RUNNING:-true}" "${MOCK_ID:-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}" "${MOCK_START:-2026-10-20T10:00:00.123456789Z}"
    fi
    ;;
  stats)
    [[ "$*" == "stats --no-stream --format {{.MemPerc}} ${MOCK_CTR:-soleur-web-platform}" ]] || viol "stats shape: $*"
    printf '%s\n' "${MOCK_MEM:-12.34%}"
    ;;
  exec)
    shift
    if [[ "${1:-}" == "-w" ]]; then
      # the probe exec: env -i allowlist, decoy key, runtime flags; NEVER -u / -e / --env (no real env, no uid change)
      [[ "${2:-}" == "/app" && "${3:-}" == "${MOCK_CTR:-soleur-web-platform}" ]] || viol "probe exec head: $*"
      shift 3
      [[ "${1:-}" == "/usr/bin/env" && "${2:-}" == "-i" ]] || viol "probe exec not under env -i: $*"
      args=" $* "
      for need in ' SMOKE=1 ' ' SDK_BASH_PROBE_RUNTIME=1 ' ' ANTHROPIC_API_KEY=decoy-api-key-sentinel ' " SDK_BASH_PROBE_SELECTOR=${MOCK_SELECTOR:-base} "; do
        [[ "$args" == *"$need"* ]] || viol "probe exec missing$need"
      done
      nonce=""; for a in "$@"; do [[ "$a" == NONCE=* ]] && nonce="${a#NONCE=}"; done
      [[ "$nonce" =~ ^[0-9a-f]{32}$ ]] || viol "probe exec NONCE shape"
      [[ "$args" == *" timeout -k 5 "*" node /app/infra/lib/sdk-bash-probe.mjs "* ]] || viol "probe exec lacks in-container timeout -k"
      printf 'NONCE_SEEN %s\n' "$nonce" >> "$LOG/calls"
      if [[ -n "${MOCK_PROBE_SLEEP:-}" ]]; then
        [[ "${MOCK_DISPATCHED:-1}" == 1 ]] && echo SDK_BASH_DISPATCHED
        exec sleep "$MOCK_PROBE_SLEEP"
      fi
      [[ -n "${MOCK_PRE_OUT:-}" ]] && printf '%b' "$MOCK_PRE_OUT"
      [[ "${MOCK_DISPATCHED:-1}" == 1 ]] && echo SDK_BASH_DISPATCHED
      [[ -n "${MOCK_MID_LINE:-}" ]] && printf 'noise SDK_BASH_RESULT %s trailing\n' "$MOCK_MID_LINE"
      [[ "${MOCK_NO_RESULT:-0}" == 1 ]] || printf 'SDK_BASH_RESULT %s\n' "${MOCK_RESULT:-{\"verdict\":\"pass\",\"reason\":\"ok\",\"coverage\":\"sdk_wrapper_shim_prodtuple\",\"selector\":\"base\",\"masks_missing\":0\}}"
      [[ -n "${MOCK_POST_OUT:-}" ]] && printf '%b' "$MOCK_POST_OUT"
      [[ -n "${MOCK_PING_LOG:-}" ]] && printf 'PROBE_DONE\n' >> "$MOCK_PING_LOG"
      [[ -z "${MOCK_PROBE_STDERR:-}" ]] || echo "$MOCK_PROBE_STDERR" >&2
      exit "${MOCK_PROBE_RC:-0}"
    fi
    [[ "${1:-}" == "${MOCK_CTR:-soleur-web-platform}" ]] || viol "exec head: $*"
    shift
    if [[ "${1:-}" == "/bin/sh" && "${2:-}" == "-c" ]]; then
      # pre-exec: probe + resolver presence (rc 66 = absent) and the container's HOME
      [[ "${4:-}" == "sh" && "${5:-}" == "/app/infra/lib/sdk-bash-probe.mjs" && "${6:-}" == "/app/infra/lib/resolve-sandbox-selector.mjs" ]] || viol "preexec shape: $*"
      [[ "${MOCK_PRE_RC:-0}" -eq 0 ]] || { [[ -z "${MOCK_PRE_ERR:-}" ]] || echo "$MOCK_PRE_ERR" >&2; exit "$MOCK_PRE_RC"; }
      printf '%s' "${MOCK_HOME:-/home/soleur}"
    elif [[ "${1:-}" == "timeout" ]]; then
      # the selector resolver runs in the container's FULL env (the live flag read), bounded in-container
      [[ "$*" == "timeout -k 5 20 node /app/infra/lib/resolve-sandbox-selector.mjs" ]] || viol "resolver shape: $*"
      printf 'RESOLVER_RAN\n' >> "$LOG/calls"
      [[ "${MOCK_SEL_RC:-0}" -eq 0 ]] || exit "$MOCK_SEL_RC"
      echo "pepper warning on stderr" >&2
      printf '%b' "${MOCK_SEL_OUT:-SOLEUR_SELECTOR=${MOCK_SELECTOR:-base}\n}"
    else
      viol "exec shape: $*"
    fi
    ;;
  *) viol "subcommand: $*" ;;
esac
MOCK
chmod +x "$BIN/docker"

# ---- Runner --------------------------------------------------------------------------------------------------------------
# run_case <sut> <lib> -- sets RUN_DIR (fresh), EC, ERR (stderr text), PINGS (ping-log text). The case's env is the caller's.
run_case() {
  local sut="$1" lib="$2" ec=0
  RUN_DIR="$(mktemp -d "$TMP_ROOT/run.XXXXXX")"
  assert_fixture_dir "$RUN_DIR"
  mkdir -p "$RUN_DIR/state" "$RUN_DIR/log"
  : > "$RUN_DIR/ping.log"
  : > "$RUN_DIR/log/calls"
  [[ -n "${CASE_STATE_DIR:-}" ]] || CASE_STATE_DIR="$RUN_DIR/state"
  MOCK_LOG="$RUN_DIR/log" MOCK_PING_LOG="$RUN_DIR/ping.log" \
    SOLEUR_WBS_PATH_PREFIX="$BIN" SOLEUR_WBS_PING_LOG="$RUN_DIR/ping.log" \
    SOLEUR_WBS_STATE_DIR="$CASE_STATE_DIR" SOLEUR_WBS_VERDICT_LIB="$lib" \
    SOLEUR_WBS_LOCK_FILE="${CASE_LOCK_FILE:-$RUN_DIR/no-such-lock}" SOLEUR_WBS_PROC_LOCKS="${CASE_PROC_LOCKS:-$RUN_DIR/proc-locks}" \
    SOLEUR_WBS_PROBE_TIMEOUT="${CASE_PROBE_TIMEOUT:-5}" \
    WEB_BASH_SYNTHETIC_URL_KEY="${CASE_URL_KEY-WBS_TEST_URL}" WBS_TEST_URL="${CASE_URL-https://uptime.example.invalid/api/v1/heartbeat/abc123}" \
    bash "$sut" > "$RUN_DIR/out" 2> "$RUN_DIR/err" || ec=$?
  EC=$ec
  ERR="$(cat "$RUN_DIR/err")"
  PINGS="$(cat "$RUN_DIR/ping.log")"
  JOURNAL="$(grep -a 'SOLEUR_WEB_BASH_SYNTHETIC ' "$RUN_DIR/err" | tail -n 1 || true)"
}
field() { printf '%s\n' "$JOURNAL" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -n 1; }
pings_ok() { printf '%s\n' "$PINGS" | grep -c '^PING ok$' || true; }
pings_fail() { printf '%s\n' "$PINGS" | grep -c '^PING fail$' || true; }
pings_any() { printf '%s\n' "$PINGS" | grep -c '^PING ' || true; }
reset_case_env() { unset CASE_STATE_DIR CASE_LOCK_FILE CASE_PROC_LOCKS CASE_PROBE_TIMEOUT CASE_URL CASE_URL_KEY; unset "${!MOCK_@}"; }

# expect_no_ping <label> <reason>: the run journals verdict=no_ping with that reason, and NOTHING reached the heartbeat.
expect_no_ping() {
  local label="$1" reason="$2"
  ok_if "$label: verdict=no_ping reason=$reason" "[[ \"\$(field verdict)\" == no_ping && \"\$(field reason)\" == '$reason' ]]"
  ok_if "$label: zero heartbeat pings" "[[ \"\$(pings_any)\" -eq 0 ]]"
  ok_if "$label: exit 0 (a skip is not a failed unit)" "[[ '$EC' -eq 0 ]]"
}

SEL_OK='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":0}'

# ---- Core cases (run against the real SUT, and again against every mutant) ------------------------------------------------
# core_cases <sut> <lib>: returns via CORE_FAILS the number of failed expectations. Output is suppressed for mutants.
core_cases() {
  local sut="$1" lib="$2" before="$fails"
  reset_case_env
  # pass: probe verified -> exactly one ok ping, AFTER the probe returned
  run_case "$sut" "$lib"
  ok_if "pass: verdict=pass" "[[ \"\$(field verdict)\" == pass ]]"
  ok_if "pass: exactly one ok ping and no fail ping" "[[ \"\$(pings_ok)\" -eq 1 && \"\$(pings_fail)\" -eq 0 ]]"
  ok_if "pass: the ping comes AFTER the probe returned (PROBE_DONE precedes PING ok)" "[[ \"\$(printf '%s\n' \"\$PINGS\" | tr '\n' ' ')\" == 'PROBE_DONE PING ok ' ]]"
  ok_if "pass: exit 0" "[[ '$EC' -eq 0 ]]"
  ok_if "pass: coverage and selector are journaled" "[[ \"\$(field coverage)\" == sdk_wrapper_shim_prodtuple && \"\$(field selector)\" == base ]]"

  # nonce missing: the probe dispatched Bash and no verified nonce came back -> fail, /fail ping, failed unit
  reset_case_env
  MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"no_nonce: apply-seccomp: Operation not permitted","coverage":"sdk_wrapper_shim_prodtuple"}' run_case "$sut" "$lib"
  ok_if "nonce missing: verdict=fail" "[[ \"\$(field verdict)\" == fail ]]"
  ok_if "nonce missing: one /fail ping, no ok ping" "[[ \"\$(pings_fail)\" -eq 1 && \"\$(pings_ok)\" -eq 0 ]]"
  ok_if "nonce missing: exit 3 (the unit shows failed)" "[[ '$EC' -eq 3 ]]"

  # rc 124 BEFORE dispatch is a daemon stall, never a fail; AFTER dispatch it is the #10445 shape
  reset_case_env
  MOCK_PROBE_SLEEP=5 MOCK_DISPATCHED=0 CASE_PROBE_TIMEOUT=1 run_case "$sut" "$lib"
  ok_if "rc 124 before dispatch: no_ping host_timeout_before_dispatch, zero pings" "[[ \"\$(field verdict)\" == no_ping && \"\$(field reason)\" == host_timeout_before_dispatch && \"\$(pings_any)\" -eq 0 ]]"
  reset_case_env
  MOCK_PROBE_SLEEP=5 MOCK_DISPATCHED=1 CASE_PROBE_TIMEOUT=1 run_case "$sut" "$lib"
  ok_if "rc 124 after dispatch: fail (host_timeout), /fail ping" "[[ \"\$(field verdict)\" == fail && \"\$(pings_fail)\" -eq 1 && \"\$(pings_ok)\" -eq 0 ]]"

  # a container swapped mid-run is a skip even when the probe says fail
  reset_case_env
  MOCK_ID2=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple"}' run_case "$sut" "$lib"
  expect_no_ping "container id changed mid-run (probe said fail)" container_restarted
  reset_case_env
  MOCK_ID2=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef MOCK_START2=2026-10-20T10:07:00.000000001Z run_case "$sut" "$lib"
  expect_no_ping "container start time changed mid-run (same id)" container_restarted

  # killed after dispatch (OOM killer, container stop) is not a Bash result
  reset_case_env
  MOCK_PROBE_RC=137 MOCK_NO_RESULT=1 run_case "$sut" "$lib"
  ok_if "rc 137 after dispatch: no_ping, zero pings" "[[ \"\$(field verdict)\" == no_ping && \"\$(pings_any)\" -eq 0 ]]"
  CORE_FAILS=$((fails - before))
}

echo "--- control: unmutated SUT ---"
core_cases "$SUT" "$LIB"
CONTROL_FAILS=$CORE_FAILS
ok_if "control run has no failed expectation (a red control voids every mutation row)" "[[ '$CONTROL_FAILS' -eq 0 ]]"

echo "--- every no_ping reason: zero pings ---"
reset_case_env; echo "1: FLOCK  ADVISORY  WRITE 4242 00:2a:0 0 EOF" > "$TMP_ROOT/locks-seed"
LOCKF="$TMP_ROOT/deploy.lock"; : > "$LOCKF"; INO="$(stat -c %i "$LOCKF")"
printf '1: FLOCK  ADVISORY  WRITE 4242 00:2a:%s 0 EOF\n' "$INO" > "$TMP_ROOT/proc-locks-held"
printf '1: FLOCK  ADVISORY  WRITE 4242 00:2a:%s 0 EOF\n' "$((INO + 1))" > "$TMP_ROOT/proc-locks-other"
CASE_LOCK_FILE="$LOCKF" CASE_PROC_LOCKS="$TMP_ROOT/proc-locks-held" run_case "$SUT" "$LIB"
expect_no_ping "deploy lock held" deploy_lock
ok_if "deploy lock held: the probe was never exec'd" "! grep -q 'SMOKE=1' '$RUN_DIR/log/calls'"
reset_case_env
CASE_LOCK_FILE="$LOCKF" CASE_PROC_LOCKS="$TMP_ROOT/proc-locks-other" run_case "$SUT" "$LIB"
ok_if "a lock on a DIFFERENT inode does not block the run" "[[ \"\$(field verdict)\" == pass ]]"
reset_case_env
CASE_LOCK_FILE="$LOCKF" CASE_PROC_LOCKS="$TMP_ROOT/does-not-exist" run_case "$SUT" "$LIB"
expect_no_ping "lock table unreadable (cannot tell, so do not test)" infra_error
reset_case_env; MOCK_RUNNING=false run_case "$SUT" "$LIB"; expect_no_ping "container not running" container_down
reset_case_env; MOCK_INSPECT_RC=1 run_case "$SUT" "$LIB"; expect_no_ping "container missing (inspect rc 1)" container_down
reset_case_env; MOCK_MEM=91.20% run_case "$SUT" "$LIB"; expect_no_ping "memory above threshold" memory_pressure
ok_if "memory pressure: no exec into the container at all" "! grep -q 'docker exec' '$RUN_DIR/log/calls'"
reset_case_env; MOCK_MEM=garbage run_case "$SUT" "$LIB"; expect_no_ping "memory reading unparseable" infra_error
reset_case_env; CASE_URL="" run_case "$SUT" "$LIB"; expect_no_ping "heartbeat URL unset" no_heartbeat_url
reset_case_env; CASE_URL_KEY="lower_case" run_case "$SUT" "$LIB"; expect_no_ping "heartbeat URL key name malformed" no_heartbeat_url
reset_case_env; MOCK_PRE_RC=66 run_case "$SUT" "$LIB"; expect_no_ping "probe or resolver absent from the image (rc 66)" probe_absent
reset_case_env; MOCK_PRE_RC=124 run_case "$SUT" "$LIB"; expect_no_ping "pre-exec timed out" host_timeout_before_dispatch
reset_case_env; MOCK_PRE_RC=125 MOCK_PRE_ERR="docker: Error response from daemon" run_case "$SUT" "$LIB"; expect_no_ping "pre-exec docker error" infra_error
reset_case_env; MOCK_SEL_OUT='{"not":"a selector"}\n' run_case "$SUT" "$LIB"; expect_no_ping "resolver output is neither base nor unixdeny" infra_error
reset_case_env; MOCK_SEL_OUT='SOLEUR_SELECTOR=base\nSOLEUR_SELECTOR=unixdeny\n' run_case "$SUT" "$LIB"; expect_no_ping "resolver printed two selector lines (exactly one is required)" infra_error
reset_case_env; MOCK_SEL_OUT='base\n' run_case "$SUT" "$LIB"; expect_no_ping "resolver output without the sentinel prefix is not a selector" infra_error
reset_case_env; MOCK_SEL_RC=1 run_case "$SUT" "$LIB"; expect_no_ping "resolver exits non-zero" infra_error
reset_case_env; MOCK_PROBE_RC=125 MOCK_NO_RESULT=1 MOCK_DISPATCHED=0 run_case "$SUT" "$LIB"; expect_no_ping "docker exec rc 125 before dispatch" infra_error
reset_case_env; MOCK_RESULT='{"verdict":"pass","reason":"ok","coverage":"replay_only"}' run_case "$SUT" "$LIB"; expect_no_ping "pass-shaped result with replay_only coverage (a HOLD)" infra_error
reset_case_env; MOCK_NO_RESULT=1 run_case "$SUT" "$LIB"; expect_no_ping "rc 0 with no result line" infra_error
reset_case_env; run_case "$SUT" "$SCRIPT_DIR/lib/no-such-lib.sh"; expect_no_ping "verdict lib absent" infra_error
ok_if "verdict lib absent: names the cause" "[[ \"\$ERR\" == *verdict_lib_absent* ]]"

echo "--- result-line parsing ---"
reset_case_env; MOCK_SEL_OUT='{"level":40,"msg":"unix-deny-flag-unresolved"}\nSOLEUR_SELECTOR=unixdeny\n' MOCK_SELECTOR=unixdeny run_case "$SUT" "$LIB"
ok_if "logger noise around the selector sentinel line is tolerated" "[[ \"\$(field verdict)\" == pass && \"\$(field selector)\" == unixdeny ]]"
reset_case_env; MOCK_PRE_OUT='(node:7) Warning: x\nline two\n' MOCK_POST_OUT='trailing noise\n' run_case "$SUT" "$LIB"
ok_if "non-canonical stdout (extra lines before and after the result line) still passes" "[[ \"\$(field verdict)\" == pass && \"\$(pings_ok)\" -eq 1 ]]"
reset_case_env; MOCK_NO_RESULT=1 MOCK_MID_LINE="$SEL_OK" run_case "$SUT" "$LIB"
ok_if "a result marker embedded MID-LINE is not a result (anchored on line start): no ping" "[[ \"\$(field verdict)\" == no_ping && \"\$(pings_any)\" -eq 0 ]]"
reset_case_env; MOCK_PROBE_RC=1 run_case "$SUT" "$LIB"
ok_if "rc 1 after dispatch is the #10445 shape: fail with /fail ping" "[[ \"\$(field verdict)\" == fail && \"\$(pings_fail)\" -eq 1 ]]"
reset_case_env; MOCK_SELECTOR=unixdeny MOCK_RESULT='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"unixdeny","masks_missing":2}' run_case "$SUT" "$LIB"
ok_if "selector flows from the resolver to the probe exec (mock refuses a mismatch) and is journaled" "[[ \"\$(field verdict)\" == pass && \"\$(field selector)\" == unixdeny ]]"
ok_if "masks_missing from the probe is journaled" "[[ \"\$(field masks_missing)\" == 2 ]]"
ok_if "the resolver ran BEFORE the probe exec" "[[ \"\$(grep -n 'RESOLVER_RAN\|SMOKE=1' '$RUN_DIR/log/calls' | head -n 1 | cut -d: -f2)\" == RESOLVER_RAN ]]"
ok_if "no -u / -e / --env on any docker exec (no uid change, no env copied from the host)" "! grep -E 'docker exec.* (-u|-e|--user|--env|--env-file)( |=)' '$RUN_DIR/log/calls'"
nonce1="$(grep -h NONCE_SEEN "$RUN_DIR/log/calls")"
reset_case_env; run_case "$SUT" "$LIB"
nonce2="$(grep -h NONCE_SEEN "$RUN_DIR/log/calls")"
ok_if "the nonce is fresh per run (two runs differ)" "[[ -n '$nonce1' && -n '$nonce2' && '$nonce1' != '$nonce2' ]]"

echo "--- consecutive_no_ping counter ---"
reset_case_env; CASE_STATE_DIR="$TMP_ROOT/counter-state"; mkdir -p "$CASE_STATE_DIR"
MOCK_RUNNING=false run_case "$SUT" "$LIB"; c1="$(field consecutive_no_ping)"
MOCK_RUNNING=false run_case "$SUT" "$LIB"; c2="$(field consecutive_no_ping)"
MOCK_RUNNING=false run_case "$SUT" "$LIB"; c3="$(field consecutive_no_ping)"
run_case "$SUT" "$LIB"; c4="$(field consecutive_no_ping)"
ok_if "no_ping x3 counts 1,2,3 and a pass resets to 0" "[[ '$c1 $c2 $c3 $c4' == '1 2 3 0' ]]"
printf 'not-a-number\n' > "$CASE_STATE_DIR/consecutive_no_ping"
MOCK_RUNNING=false run_case "$SUT" "$LIB"
ok_if "a corrupt counter restarts at 1 instead of aborting the run" "[[ \"\$(field consecutive_no_ping)\" == 1 ]]"
reset_case_env

echo "--- heartbeat discipline (real curl path, stub curl) ---"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
printf 'ARGV %s\n' "$*" >> "${MOCK_LOG:?}/curl.calls"
if [[ " $* " == *" --config - "* ]]; then printf 'STDIN %s\n' "$(cat)" >> "$MOCK_LOG/curl.calls"; fi
exit "${MOCK_CURL_RC:-0}"
STUB
chmod +x "$BIN/curl"
curl_run() {  # like run_case, but with the real ping path (no ping-log seam)
  local ec=0
  RUN_DIR="$(mktemp -d "$TMP_ROOT/run.XXXXXX")"; assert_fixture_dir "$RUN_DIR"; mkdir -p "$RUN_DIR/state" "$RUN_DIR/log"; : > "$RUN_DIR/log/calls"
  MOCK_LOG="$RUN_DIR/log" SOLEUR_WBS_PATH_PREFIX="$BIN" SOLEUR_WBS_STATE_DIR="$RUN_DIR/state" SOLEUR_WBS_VERDICT_LIB="$LIB" \
    SOLEUR_WBS_LOCK_FILE="$RUN_DIR/no-such-lock" SOLEUR_WBS_PROC_LOCKS="$RUN_DIR/proc-locks" SOLEUR_WBS_PROBE_TIMEOUT=5 \
    WEB_BASH_SYNTHETIC_URL_KEY="${CASE_URL_KEY-WBS_TEST_URL}" WBS_TEST_URL="${CASE_URL-https://uptime.example.invalid/api/v1/heartbeat/abc123}" \
    bash "$SUT" > "$RUN_DIR/out" 2> "$RUN_DIR/err" || ec=$?
  EC=$ec; ERR="$(cat "$RUN_DIR/err")"; CURLS="$(cat "$RUN_DIR/log/curl.calls" 2>/dev/null || true)"
}
reset_case_env; curl_run
CURL_ARGV="$(printf '%s\n' "$CURLS" | grep '^ARGV' || true)"
ok_if "ok ping: the URL rides the stdin config, never argv" "[[ \"\$CURLS\" == *'STDIN url = \"https://uptime.example.invalid/api/v1/heartbeat/abc123\"'* && -n \"\$CURL_ARGV\" && \"\$CURL_ARGV\" != *abc123* ]]"
ok_if "ok ping: --disable first and --noproxy confine the transport" "[[ \"\$CURLS\" == *'ARGV --disable --noproxy'* ]]"
reset_case_env; MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple"}' curl_run
ok_if "fail ping goes to <url>/fail" "[[ \"\$CURLS\" == *'STDIN url = \"https://uptime.example.invalid/api/v1/heartbeat/abc123/fail\"'* ]]"
reset_case_env; CASE_URL="http://uptime.example.invalid/hb" curl_run
ok_if "a non-https URL is refused: curl never invoked" "[[ -z \"\$CURLS\" && \"\$ERR\" == *SOLEUR_CREDENTIAL_REFUSED* && \"\$ERR\" != *uptime.example.invalid* ]]"
reset_case_env; CASE_URL='https://uptime.example.invalid/hb"
header = "x' curl_run
ok_if "a URL that could add curl config directives is refused: curl never invoked, value not echoed" "[[ -z \"\$CURLS\" && \"\$ERR\" == *SOLEUR_CREDENTIAL_REFUSED* && \"\$ERR\" != *header* ]]"
reset_case_env; MOCK_CURL_RC=22 curl_run
ok_if "a failed ping is retried once and warned, never aborting the unit" "[[ \"\$(printf '%s\n' \"\$CURLS\" | grep -c '^STDIN')\" -eq 2 && \"\$ERR\" == *'heartbeat ping FAILED'* ]]"
reset_case_env
xtrace_ec=0; bash -x "$SUT" > /dev/null 2>&1 || xtrace_ec=$?
ok_if "refuses to run under xtrace (exit 78): the heartbeat URL is a credential" "[[ '$xtrace_ec' -eq 78 ]]"

echo "--- AC4: the host side writes only its state dir (scratch lives there) ---"
reset_case_env
W="$TMP_ROOT/watched"; assert_fixture_dir "$W"; mkdir -p "$W/tmp" "$W/home"
before="$(find "$TMP_ROOT" -type f | sort)"
TMPDIR="$W/tmp" HOME="$W/home" run_case "$SUT" "$LIB"
after="$(find "$TMP_ROOT" -type f | sort)"
extra="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -v "^$RUN_DIR/" || true)"
ok_if "no file created outside this run's directory (state, mock logs, ping log)" "[[ -z '$extra' ]]"
ok_if "the run left nothing in TMPDIR or HOME" "[[ \"\$(find '$W' -mindepth 2 | wc -l)\" -eq 0 ]]"
ok_if "the state dir holds no leftover scratch files after a run (only the counter)" "[[ \"\$(ls -A '$RUN_DIR/state' | tr '\\n' ' ')\" == 'consecutive_no_ping ' ]]"

echo "--- unit files ---"
ok_if "service: SyslogIdentifier=web-bash-synthetic (shipped by vector host_scripts_journald)" "grep -qx 'SyslogIdentifier=web-bash-synthetic' '$SERVICE'"
ok_if "service: oneshot with HOME=/root and the per-host env file" "grep -qx 'Type=oneshot' '$SERVICE' && grep -qx 'Environment=HOME=/root' '$SERVICE' && grep -qx 'EnvironmentFile=/etc/default/web-bash-synthetic' '$SERVICE'"
ok_if "service: ExecStart expands nothing (the heartbeat URL is a credential, #9639)" "grep -E '^ExecStart=' '$SERVICE' | grep -qx \"ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- /usr/local/bin/web-bash-synthetic.sh'\""
ok_if "service: bounded (TimeoutStartSec) so a wedged run cannot pile up" "grep -qE '^TimeoutStartSec=[0-9]+$' '$SERVICE'"
ok_if "service: the run-state dir persists between oneshot runs" "grep -qx 'RuntimeDirectory=web-bash-synthetic' '$SERVICE' && grep -qx 'RuntimeDirectoryPreserve=yes' '$SERVICE'"
ok_if "timer: every 15 minutes, first run at timer start, not persistent" "grep -qx 'OnUnitActiveSec=15min' '$TIMER' && grep -qE '^OnActiveSec=' '$TIMER' && grep -qx 'Persistent=false' '$TIMER'"
ok_if "timer: a small randomized delay (the two hosts do not exec in lockstep)" "grep -qE '^RandomizedDelaySec=[0-9]+' '$TIMER'"

echo "--- Guard 1 row 6: one verdict function, two callers ---"
callers_share() {  # <ci-deploy path> <synthetic path>: both source the lib and call the one function; neither re-implements it
  local d="$1" s="$2"
  grep -q 'sdk_bash_map_result "\$exec_rc"' "$d" && grep -q 'sdk_bash_map_result' "$s" \
    && ! grep -qE 'SDK_BASH_DISPATCHED' <(grep -v '^[[:space:]]*#' "$d") \
    && ! grep -qE 'SDK_BASH_DISPATCHED' <(grep -v '^[[:space:]]*#' "$s")
}
ok_if "ci-deploy.sh and web-bash-synthetic.sh both call sdk_bash_map_result and neither inlines the marker mapping" "callers_share '$DEPLOY' '$SUT'"

# ---- Mutation battery (Guard 1 rows 1-6) ---------------------------------------------------------------------------------
echo "--- mutation battery: each row must turn the core cases RED ---"
MUT="$TMP_ROOT/mut"; assert_fixture_dir "$MUT"; mkdir -p "$MUT"
PRISTINE_SUT="$MUT/pristine.sh"; PRISTINE_LIB="$MUT/pristine-lib.sh"
cp "$SUT" "$PRISTINE_SUT"; cp "$LIB" "$PRISTINE_LIB"

# mutate <file-key: sut|lib> <label> <python-replace-old> <python-replace-new>: lands the mutation on a COPY and proves it landed.
mutate() {
  local which="$1" label="$2" old="$3" new="$4" src out
  if [[ "$which" == sut ]]; then src="$SUT"; else src="$LIB"; fi
  out="$MUT/m.$which.$label"
  OLD="$old" NEW="$new" SRC="$src" OUT="$out" python3 - <<'PY' || { fail "mutation $label did NOT apply (anchor missing)"; return 1; }
import os, sys
s = open(os.environ["SRC"]).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if s.count(old) < 1:
    sys.exit(1)
open(os.environ["OUT"], "w").write(s.replace(old, new, 1))
PY
  if cmp -s "$src" "$out"; then fail "mutation $label LANDED as a no-op (identical to pristine)"; return 1; fi
  MUTANT="$out"
}
red_with() {  # <label> <sut> <lib>
  local label="$1" sut="$2" lib="$3" before_p="$passes" before_f="$fails" out
  out="$(core_cases "$sut" "$lib" 2>&1)"
  # core_cases ran in a subshell: count its FAIL lines
  local n; n="$(printf '%s\n' "$out" | grep -c '^  FAIL:' || true)"
  [[ "$passes" -eq "$before_p" && "$fails" -eq "$before_f" ]] || true
  if [[ "$n" -ge 1 ]]; then pass "mutation $label turns the core cases RED ($n failing expectation(s))"; else fail "mutation $label SURVIVED (core cases stayed green)"; fi
}

# Row 1: the verdict acceptance (the host-side counterpart of the nonce check; the nonce itself is verified inside the probe)
if mutate lib nonce_true 'case "$SBV_VERDICT" in' 'SBV_VERDICT=pass; SBV_COVERAGE=sdk_wrapper_shim_prodtuple; case "$SBV_VERDICT" in'; then red_with "1 (any result line is a pass)" "$SUT" "$MUTANT"; fi
# Row 2: ping on a no_ping path
if mutate sut ping_on_noping 'no_ping) :' 'no_ping) ping_heartbeat ok'; then red_with "2 (ping on a no_ping path)" "$MUTANT" "$LIB"; fi
# Row 3: rc 124 before dispatch mapped to fail
if mutate lib timeout_before_dispatch 'SBV_VERDICT="smoke_infra_error"; SBV_REASON="host_timeout_before_dispatch' 'SBV_VERDICT="sdk_bash_smoke_failed"; SBV_REASON="host_timeout_before_dispatch'; then red_with "3 (rc 124 before dispatch is a fail)" "$SUT" "$MUTANT"; fi
# Row 4: a changed container start time treated as a fail
if mutate sut restart_is_fail 'finish no_ping container_restarted' 'finish fail container_restarted'; then red_with "4 (container swap mid-run is a fail)" "$MUTANT" "$LIB"; fi
# Row 5: heartbeat pinged before the verdict is computed
if mutate sut ping_before_verdict 'nonce="$(od -An -N16' 'ping_heartbeat ok; nonce="$(od -An -N16'; then red_with "5 (ping before the probe returned)" "$MUTANT" "$LIB"; fi
# Row 6: ci-deploy.sh stops using the shared function
if mutate_deploy_out="$MUT/m.deploy"; python3 - "$DEPLOY" "$mutate_deploy_out" <<'PY'
import sys
s = open(sys.argv[1]).read()
old = 'sdk_bash_map_result "$exec_rc"'
if old not in s:
    sys.exit(1)
open(sys.argv[2], "w").write(s.replace(old, 'inline_map "$exec_rc"', 1))
PY
then
  if callers_share "$mutate_deploy_out" "$SUT"; then fail "mutation 6 SURVIVED (parity row accepted a ci-deploy.sh that no longer calls the shared function)"; else pass "mutation 6 (ci-deploy.sh stops using the shared function) turns the parity row RED"; fi
else
  fail "mutation 6 did NOT apply (anchor missing in ci-deploy.sh)"
fi
ok_if "the pristine SUT/lib copies still equal the files under test (no mutation leaked into the tree)" "cmp -s '$SUT' '$PRISTINE_SUT' && cmp -s '$LIB' '$PRISTINE_LIB'"

# Assertion floor (anti-vacuity): reported with printf + exit, never through the helpers it backstops.
FLOOR=121
total=$((passes + fails))
if [[ "$total" -lt "$FLOOR" ]]; then printf 'FAIL: only %s assertions ran (floor %s): the suite lost coverage\n' "$total" "$FLOOR"; exit 1; fi
echo "=== $passes passed, $fails failed ($total assertions) ==="
[[ "$fails" -eq 0 ]]

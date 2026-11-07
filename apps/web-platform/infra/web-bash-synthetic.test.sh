#!/usr/bin/env bash
# Tests the runtime Bash synthetic (web-bash-synthetic.sh; follow-up to #10445 via #10455, ADR-079 "Addendum — 2026-10-22 (#10455 b)").
#
# The synthetic `docker exec`s ONE real wrapped Bash call into the RUNNING web container and pings a per-host dead-man heartbeat
# ONLY on a verified pass. This suite drives the real script against a mock `docker` that copies the real output shapes and
# preserves exit statuses, and pins GUARD 1 of the plan (no false green, no false red on a deploy):
#   - a `no_ping` run never pings; a failed run pings /fail; a run overlapped by a container swap is never a `fail`;
#   - the ping happens AFTER the probe returned (the mock stamps PROBE_DONE into the same log the ping seam writes to);
#   - NOTHING else reaches curl: a stub `curl` on PATH records every call, and a static scan pins that `_hb_curl` is called only
#     inside `ping_heartbeat` and `ping_heartbeat` only inside `finish`, over the script AND the lib;
#   - the verdict mapping is the ONE function in sdk-bash-verdict.sh, sourced by this script AND ci-deploy.sh.
# Each mutation row is applied to a COPY of the SUT/lib and must turn its cases RED; the control (unmutated) run must be GREEN first,
# and each mutation is asserted to have LANDED against a pristine copy (a mutation that does not land reports the baseline).
#
# Run: bash apps/web-platform/infra/web-bash-synthetic.test.sh
# shellcheck disable=SC2034  # ERR / CURLS / CURL_ARGV / PINGS / JOURNAL / EC are read inside the eval strings of ok_if
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/web-bash-synthetic.sh"
LIB="$SCRIPT_DIR/sdk-bash-verdict.sh"
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

# What the SUT sends, read from the SUT so a changed cap cannot slip past a mock that hard-codes the old value.
INNER_T="$(sed -n 's/^INNER_TIMEOUT=\([0-9][0-9]*\)$/\1/p' "$SUT")"
PROBE_T_DEFAULT="$(sed -n 's/^PROBE_TIMEOUT="\${SOLEUR_WBS_PROBE_TIMEOUT:-\([0-9][0-9]*\)}".*/\1/p' "$SUT")"
ok_if "the in-container cap sits strictly inside the host cap (INNER_TIMEOUT=$INNER_T < default PROBE_TIMEOUT=$PROBE_T_DEFAULT)" \
  "[[ '$INNER_T' =~ ^[0-9]+\$ && '$PROBE_T_DEFAULT' =~ ^[0-9]+\$ && '$INNER_T' -lt '$PROBE_T_DEFAULT' ]]"
PROBE_INTERNAL_MS="$(sed -n 's/^const SMOKE_INTERNAL_CAP_MS = \([0-9]*\);.*/\1/p' "$SCRIPT_DIR/lib/sdk-bash-probe.mjs")"
ok_if "the probe's own internal cap (${PROBE_INTERNAL_MS:-?} ms) sits strictly inside the in-container cap (${INNER_T} s)" \
  "[[ '$PROBE_INTERNAL_MS' =~ ^[0-9]+\$ && '$INNER_T' =~ ^[0-9]+\$ && '$PROBE_INTERNAL_MS' -lt \$(( INNER_T * 1000 )) ]]"

# ---- Mock docker ---------------------------------------------------------------------------------------------------------
# Output shapes copied from real docker: inspect prints "<running> <64-hex id> <RFC3339 start>"; stats prints "<pct>%"; a missing
# container is rc 1 with `Error: No such object`; the probe exec prints SDK_BASH_DISPATCHED then SDK_BASH_RESULT {json} and
# exits with the probe's rc. The mock REFUSES (rc 64) an argv shape the SUT is not allowed to send, down to the inspect format string,
# the pre-exec `sh -c` body, the exact `env -i` allowlist and the oom_score_adj wrapper: that is what keeps the fixture seam from
# sitting above the code under test (a mock that answers any argv cannot detect a wrong request).
BIN="$TMP_ROOT/bin"; assert_fixture_dir "$BIN"; mkdir -p "$BIN"
cat > "$BIN/docker" <<'MOCK'
#!/usr/bin/env bash
LOG="${MOCK_LOG:?}"
printf 'docker %s\n' "$*" >> "$LOG/calls"
viol() { printf 'MOCK_ARGV_VIOLATION %s\n' "$1" >> "$LOG/calls"; echo "mock docker: refused argv: $1" >&2; exit 64; }
INSPECT_FMT='{{.State.Running}} {{.Id}} {{.State.StartedAt}}'
PREEXEC_BODY='test -f "$1" && test -f "$2" || exit 66; printf %s "$HOME"'
OOM_BODY='echo 1000 > /proc/self/oom_score_adj 2>/dev/null; exec "$@"'
case "${1:-}" in
  inspect)
    [[ "${2:-}" == "-f" && "$#" -eq 4 && "${3:-}" == "$INSPECT_FMT" && "$4" == "${MOCK_CTR:-soleur-web-platform}" ]] || viol "inspect shape: $*"
    n=$(( $(cat "$LOG/inspect.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$LOG/inspect.n"
    if [[ "${MOCK_INSPECT_RC:-0}" -ne 0 ]]; then
      echo "${MOCK_INSPECT_ERR:-Error: No such object: ${MOCK_CTR:-soleur-web-platform}}" >&2; exit "$MOCK_INSPECT_RC"
    fi
    if [[ "$n" -ge 2 && -n "${MOCK_ID2:-}" ]]; then
      printf '%s %s %s\n' "${MOCK_RUNNING2:-true}" "$MOCK_ID2" "${MOCK_START2:-${MOCK_START:-2026-10-20T10:00:00.123456789Z}}"
    elif [[ "$n" -ge 2 && -n "${MOCK_RUNNING2:-}" ]]; then
      printf '%s %s %s\n' "$MOCK_RUNNING2" "${MOCK_ID:-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}" "${MOCK_START:-2026-10-20T10:00:00.123456789Z}"
    else
      printf '%s %s %s\n' "${MOCK_RUNNING:-true}" "${MOCK_ID:-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}" "${MOCK_START:-2026-10-20T10:00:00.123456789Z}"
    fi
    ;;
  stats)
    [[ "$*" == "stats --no-stream --format {{.MemPerc}} ${MOCK_CTR:-soleur-web-platform}" ]] || viol "stats shape: $*"
    n=$(( $(cat "$LOG/stats.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$LOG/stats.n"
    # a lock taken between the first memory sample and the pre-exec re-sample (the SUT looks at the lock again right before the exec)
    [[ "$n" -eq 2 && -n "${MOCK_TAKE_LOCK_ON_STATS2:-}" ]] && printf '%s\n' "$MOCK_TAKE_LOCK_ON_STATS2" >> "${MOCK_PROC_LOCKS:?}"
    if [[ "${MOCK_STATS_RC:-0}" -ne 0 ]]; then echo "${MOCK_STATS_ERR:-Error response from daemon: stats unavailable}" >&2; exit "$MOCK_STATS_RC"; fi
    if [[ "$n" -ge 2 && -n "${MOCK_MEM2:-}" ]]; then printf '%s\n' "$MOCK_MEM2"; else printf '%s\n' "${MOCK_MEM:-12.34%}"; fi
    ;;
  exec)
    shift
    if [[ "${1:-}" == "-w" ]]; then
      # the probe exec: env -i allowlist, decoy key, runtime flags, the oom_score_adj wrapper, the capped probe; NEVER -u / -e / --env
      [[ "${2:-}" == "/app" && "${3:-}" == "${MOCK_CTR:-soleur-web-platform}" ]] || viol "probe exec head: $*"
      shift 3
      [[ "${1:-}" == "/usr/bin/env" && "${2:-}" == "-i" ]] || viol "probe exec not under env -i: $*"
      shift 2
      vars=(); while [[ "${1:-}" == *=* ]]; do vars+=("$1"); shift; done
      [[ "${#vars[@]}" -eq 8 ]] || viol "env -i allowlist is not exactly the 8 modelled names: ${vars[*]}"
      args=" ${vars[*]} "
      for need in ' SMOKE=1 ' ' SDK_BASH_PROBE_RUNTIME=1 ' ' APP=/app ' ' PATH=/usr/local/bin:/usr/bin:/bin ' " HOME=${MOCK_HOME:-/home/soleur} " \
        ' ANTHROPIC_API_KEY=decoy-api-key-sentinel ' " SDK_BASH_PROBE_SELECTOR=${MOCK_SELECTOR:-base} "; do
        [[ "$args" == *"$need"* ]] || viol "probe exec missing$need"
      done
      nonce=""; for a in "${vars[@]}"; do [[ "$a" == NONCE=* ]] && nonce="${a#NONCE=}"; done
      [[ "$nonce" =~ ^[0-9a-f]{32}$ ]] || viol "probe exec NONCE shape"
      [[ "${1:-}" == "/bin/sh" && "${2:-}" == "-c" && "${3:-}" == "$OOM_BODY" && "${4:-}" == "sh" ]] || viol "probe exec lacks the oom_score_adj wrapper: $*"
      shift 4
      [[ "$*" == "timeout -k 5 ${MOCK_INNER_TIMEOUT:?} node /app/infra/lib/sdk-bash-probe.mjs" ]] || viol "probe exec tail: $*"
      printf 'NONCE_SEEN %s\n' "$nonce" >> "$LOG/calls"
      [[ -z "${MOCK_TAKE_LOCK:-}" ]] || printf '%s\n' "$MOCK_TAKE_LOCK" >> "${MOCK_PROC_LOCKS:?}"
      if [[ -n "${MOCK_PROBE_SLEEP:-}" ]]; then
        [[ "${MOCK_DISPATCHED:-1}" == 1 ]] && echo SDK_BASH_DISPATCHED
        exec sleep "$MOCK_PROBE_SLEEP"
      fi
      if [[ -n "${MOCK_PROBE_DELAY:-}" ]]; then echo SDK_BASH_DISPATCHED; sleep "$MOCK_PROBE_DELAY"; fi
      [[ -n "${MOCK_PRE_OUT:-}" ]] && printf '%b' "$MOCK_PRE_OUT"
      [[ "${MOCK_DISPATCHED:-1}" == 1 && -z "${MOCK_PROBE_DELAY:-}" ]] && echo SDK_BASH_DISPATCHED
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
      [[ "${3:-}" == "$PREEXEC_BODY" && "${4:-}" == "sh" && "${5:-}" == "/app/infra/lib/sdk-bash-probe.mjs" && "${6:-}" == "/app/infra/lib/resolve-sandbox-selector.mjs" && "$#" -eq 6 ]] || viol "preexec shape: $*"
      [[ "${MOCK_PRE_RC:-0}" -eq 0 ]] || { [[ -z "${MOCK_PRE_ERR:-}" ]] || printf '%b\n' "$MOCK_PRE_ERR" >&2; exit "$MOCK_PRE_RC"; }
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
# The stub curl records EVERY call (argv, and the stdin config when --config - is used). A heartbeat call that skips the
# `ping_heartbeat` chokepoint reaches this stub even in the ping-log fixture mode, which the chokepoint answers before curl.
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
printf 'ARGV %s\n' "$*" >> "${MOCK_LOG:?}/curl.calls"
if [[ " $* " == *" --config - "* ]]; then printf 'STDIN %s\n' "$(cat)" >> "$MOCK_LOG/curl.calls"; fi
if [[ "${MOCK_CURL_RC:-0}" -ne 0 ]]; then exit "$MOCK_CURL_RC"; fi
# a real `curl -f` exits 22 on an HTTP error status; the stub models a revoked heartbeat (404) the same way
if [[ -n "${MOCK_CURL_HTTP_STATUS:-}" && "${MOCK_CURL_HTTP_STATUS}" -ge 400 && " $* " == *" -gfsS "* ]]; then exit 22; fi
exit 0
STUB
chmod +x "$BIN/curl"

# ---- Fixtures ------------------------------------------------------------------------------------------------------------------
MUT="$TMP_ROOT/mut"; assert_fixture_dir "$MUT"; mkdir -p "$MUT"
URL_OK='https://uptime.betterstack.com/api/v1/heartbeat/abc123'
KEY_OK='WEB_BASH_SYNTHETIC_URL_WEB_TEST'
printf 'MemTotal:        4045000 kB\nMemFree:          500000 kB\nMemAvailable:    3000000 kB\n' > "$TMP_ROOT/meminfo-ok"
printf 'MemTotal:        4045000 kB\nMemFree:          100000 kB\nMemAvailable:     300000 kB\n' > "$TMP_ROOT/meminfo-low"
printf 'MemTotal:        4045000 kB\nMemFree:          100000 kB\n' > "$TMP_ROOT/meminfo-nokey"
LOCKF="$TMP_ROOT/deploy.lock"; : > "$LOCKF"
LOCKF2="$TMP_ROOT/deploy2.lock"; : > "$LOCKF2"
# /proc/locks prints `maj:min:ino` in hex/hex/decimal; build the exact field for a file the way the SUT must (stat's device and inode).
lock_field() {  # <file> [dev-delta]: the maj:min:ino field of <file>, with the device's minor shifted by dev-delta
  local maj min ino; read -r maj min ino < <(stat -c '%Hd %Ld %i' "$1")
  printf '%02x:%02x:%s' "$maj" "$(( min + ${2:-0} ))" "$ino"
}
lock_line() { printf '1: FLOCK  ADVISORY  WRITE 4242 %s 0 EOF\n' "$(lock_field "$@")"; }
lock_line "$LOCKF" > "$TMP_ROOT/proc-locks-held"
lock_line "$LOCKF2" > "$TMP_ROOT/proc-locks-other"
lock_line "$LOCKF" 1 > "$TMP_ROOT/proc-locks-otherdev"
HELD_LINE="$(lock_line "$LOCKF")"
: > "$TMP_ROOT/proc-locks-empty"

# ---- Runner --------------------------------------------------------------------------------------------------------------
# run_case <sut> <lib> -- sets RUN_DIR (fresh), EC, ERR (stderr text), PINGS (ping-log text), CURLS (every curl call). The case's env is
# the caller's. CASE_REAL_PING=1 drops the ping-log seam so the REAL ping path (stub curl) runs.
run_case() {
  local sut="$1" lib="$2" ec=0
  RUN_DIR="$(mktemp -d "$TMP_ROOT/run.XXXXXX")"
  assert_fixture_dir "$RUN_DIR"
  mkdir -p "$RUN_DIR/state" "$RUN_DIR/log"
  : > "$RUN_DIR/ping.log"
  : > "$RUN_DIR/log/calls"
  : > "$RUN_DIR/log/curl.calls"
  [[ -n "${CASE_PROC_LOCKS:-}" ]] || { cp "$TMP_ROOT/proc-locks-empty" "$RUN_DIR/proc-locks"; }
  # Decoy variables that hold a VALID heartbeat URL under names the SUT must never resolve: a key check that lets one through pings.
  local pl="$RUN_DIR/ping.log"; [[ -z "${CASE_REAL_PING:-}" ]] || pl=""
  env MOCK_LOG="$RUN_DIR/log" MOCK_PING_LOG="$RUN_DIR/ping.log" MOCK_INNER_TIMEOUT="$INNER_T" \
    MOCK_PROC_LOCKS="${CASE_PROC_LOCKS:-$RUN_DIR/proc-locks}" \
    SOLEUR_WBS_PATH_PREFIX="$BIN" SOLEUR_WBS_PING_LOG="$pl" \
    SOLEUR_WBS_STATE_DIR="${CASE_STATE_DIR:-$RUN_DIR/state}" SOLEUR_WBS_VERDICT_LIB="$lib" \
    SOLEUR_WBS_LOCK_FILE="${CASE_LOCK_FILE:-$RUN_DIR/no-such-lock}" SOLEUR_WBS_PROC_LOCKS="${CASE_PROC_LOCKS:-$RUN_DIR/proc-locks}" \
    SOLEUR_WBS_MEMINFO="${CASE_MEMINFO:-$TMP_ROOT/meminfo-ok}" \
    SOLEUR_WBS_PROBE_TIMEOUT="${CASE_PROBE_TIMEOUT:-5}" \
    WEB_BASH_SYNTHETIC_URL_KEY="${CASE_URL_KEY-$KEY_OK}" "$KEY_OK=${CASE_URL-$URL_OK}" \
    WEB_NIC_GUARD_URL_WEB_1="$URL_OK" WEB_BASH_SYNTHETIC_URL="$URL_OK" WEB_BASH_SYNTHETIC_URL_="$URL_OK" lower_case="$URL_OK" \
    WBS_TEST_SECRET="${CASE_SECRET:-}" \
    bash "$sut" --fixture-seams > "$RUN_DIR/out" 2> "$RUN_DIR/err" || ec=$?
  EC=$ec
  ERR="$(cat "$RUN_DIR/err")"
  PINGS="$(cat "$RUN_DIR/ping.log")"
  CURLS="$(cat "$RUN_DIR/log/curl.calls")"
  JOURNAL="$(grep -a 'SOLEUR_WEB_BASH_SYNTHETIC ' "$RUN_DIR/err" | tail -n 1 || true)"
}
field() { printf '%s\n' "$JOURNAL" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -n 1; }
detail_text() { printf '%s\n' "$JOURNAL" | sed -n 's/.* detail=//p'; }
allowlisted() { local LC_ALL=C; [[ "$1" =~ ^[A-Za-z0-9._:/\ =-]*$ ]]; }
pings_ok() { printf '%s\n' "$PINGS" | grep -c '^PING ok$' || true; }
pings_fail() { printf '%s\n' "$PINGS" | grep -c '^PING fail$' || true; }
pings_any() { printf '%s\n' "$PINGS" | grep -c '^PING ' || true; }
curl_calls_n() { printf '%s\n' "$CURLS" | grep -c '^ARGV' || true; }
reset_case_env() { unset CASE_STATE_DIR CASE_LOCK_FILE CASE_PROC_LOCKS CASE_PROBE_TIMEOUT CASE_URL CASE_URL_KEY CASE_MEMINFO CASE_SECRET CASE_REAL_PING; unset "${!MOCK_@}"; }

# expect_no_ping <label> <reason>: the run journals verdict=no_ping with that reason, and NOTHING reached the heartbeat: not the ping
# seam, and not curl (a raw heartbeat call outside the chokepoint would reach the stub curl even in fixture mode).
expect_no_ping() {
  local label="$1" reason="$2"
  ok_if "$label: verdict=no_ping reason=$reason" "[[ \"\$(field verdict)\" == no_ping && \"\$(field reason)\" == '$reason' ]]"
  ok_if "$label: zero heartbeat pings" "[[ \"\$(pings_any)\" -eq 0 ]]"
  ok_if "$label: curl never invoked" "[[ \"\$(curl_calls_n)\" -eq 0 ]]"
  ok_if "$label: exit 0 (a skip is not a failed unit)" "[[ '$EC' -eq 0 ]]"
}

SEL_OK='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":0}'

# ---- Focused case groups (run on the real SUT, and again on the mutant that each one guards) --------------------------------------
# Each prints through ok_if; a mutation row counts the FAIL lines of ONE group on a mutated copy.

case_noping_curl() {  # <sut> <lib>: three no_ping paths a raw heartbeat call could ride (mutants E, F, G of the plan's Guard 1)
  local sut="$1" lib="$2"
  reset_case_env; CASE_LOCK_FILE="$LOCKF" CASE_PROC_LOCKS="$TMP_ROOT/proc-locks-held" run_case "$sut" "$lib"
  expect_no_ping "deploy lock held" deploy_lock
  ok_if "deploy lock held: the probe was never exec'd" "! grep -q 'SMOKE=1' '$RUN_DIR/log/calls'"
  reset_case_env; MOCK_MEM=91.20% run_case "$sut" "$lib"
  expect_no_ping "container memory above the threshold" memory_pressure
  ok_if "memory pressure: no exec into the container at all" "! grep -q 'docker exec' '$RUN_DIR/log/calls'"
  reset_case_env; MOCK_ID2=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple"}' run_case "$sut" "$lib"
  expect_no_ping "container id changed mid-run (probe said fail)" container_restarted
}

case_restart_stopped() {  # <sut> <lib>: the container STOPPED in place (same id and start) during the run, probe said fail
  reset_case_env
  MOCK_RUNNING2=false MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple"}' run_case "$1" "$2"
  expect_no_ping "container stopped in place mid-run (same id and start, running=false, probe said fail)" container_restarted
}

case_selector() {  # <sut> <lib>
  local sut="$1" lib="$2"
  reset_case_env; MOCK_SEL_OUT='SOLEUR_SELECTOR=unresolved\n' run_case "$sut" "$lib"
  expect_no_ping "resolver says unresolved (Flagsmith did not answer)" selector_unresolved
  ok_if "unresolved selector: the probe is never exec'd and the journal names it" "! grep -q 'SMOKE=1' '$RUN_DIR/log/calls' && [[ \"\$(field selector)\" == unresolved ]]"
  reset_case_env; MOCK_SEL_OUT='SOLEUR_SELECTOR=unresolved\nSOLEUR_SELECTOR=base\n' run_case "$sut" "$lib"
  expect_no_ping "an unresolved line next to a base line is not a single answer" infra_error
  reset_case_env; MOCK_RESULT='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"unixdeny","masks_missing":0}' run_case "$sut" "$lib"
  expect_no_ping "probe ran under a different selector than the host asked for (pass)" selector_mismatch
  reset_case_env; MOCK_RESULT='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","masks_missing":0}' run_case "$sut" "$lib"
  expect_no_ping "a pass that does not echo any selector (a stale probe) is not a pass" selector_mismatch
  reset_case_env; MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple","selector":"unixdeny","masks_missing":0}' run_case "$sut" "$lib"
  expect_no_ping "a fail under a different selector than asked is a skip, never a /fail page" selector_mismatch
  reset_case_env; MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple"}' run_case "$sut" "$lib"
  ok_if "a fail that names no selector is still a fail (nothing to compare)" "[[ \"\$(field verdict)\" == fail && \"\$(pings_fail)\" -eq 1 ]]"
}

case_mem() {  # <sut> <lib>: host MemAvailable gate, container gate, and the re-sample right before the probe exec
  local sut="$1" lib="$2"
  reset_case_env; CASE_MEMINFO="$TMP_ROOT/meminfo-low" run_case "$sut" "$lib"
  expect_no_ping "host MemAvailable 300 MB (< 700 MB)" memory_pressure_host
  ok_if "host memory pressure: neither docker stats nor any exec was made" "! grep -qE 'docker (stats|exec)' '$RUN_DIR/log/calls'"
  reset_case_env; CASE_MEMINFO="$TMP_ROOT/meminfo-nokey" run_case "$sut" "$lib"
  expect_no_ping "meminfo without a MemAvailable line (cannot tell, so do not test)" infra_error
  reset_case_env; CASE_MEMINFO="$TMP_ROOT/does-not-exist" run_case "$sut" "$lib"
  expect_no_ping "meminfo unreadable" infra_error
  reset_case_env; MOCK_MEM=garbage run_case "$sut" "$lib"
  expect_no_ping "container memory reading unparseable" infra_error
  reset_case_env; MOCK_MEM=70.00% run_case "$sut" "$lib"
  expect_no_ping "container memory exactly at the 70% default threshold" memory_pressure
  reset_case_env; MOCK_MEM=69.90% run_case "$sut" "$lib"
  ok_if "container memory 69.9% (just under the threshold) still runs" "[[ \"\$(field verdict)\" == pass ]]"
  reset_case_env; MOCK_MEM=10% MOCK_MEM2=91% run_case "$sut" "$lib"
  expect_no_ping "memory fine at the start, high at the re-sample right before the probe exec" memory_pressure
  ok_if "re-sample: stats ran twice and the probe was never exec'd" "[[ \"\$(grep -c 'docker stats' '$RUN_DIR/log/calls')\" -eq 2 ]] && ! grep -q 'SMOKE=1' '$RUN_DIR/log/calls'"
  reset_case_env; MOCK_STATS_RC=3 MOCK_STATS_ERR='Error response from daemon: stats are unavailable' run_case "$sut" "$lib"
  expect_no_ping "docker stats fails (rc 3) with no output" infra_error
  ok_if "docker stats failure: the rc and docker's own words reach the journal (not 'unparseable')" "[[ \"\$(detail_text)\" == *docker_stats_rc_3*stats\ are\ unavailable* ]]"
}

case_lock() {  # <sut> <lib>
  local sut="$1" lib="$2"
  reset_case_env; CASE_LOCK_FILE="$LOCKF" CASE_PROC_LOCKS="$TMP_ROOT/proc-locks-other" run_case "$sut" "$lib"
  ok_if "a lock on a DIFFERENT inode does not block the run" "[[ \"\$(field verdict)\" == pass ]]"
  reset_case_env; CASE_LOCK_FILE="$LOCKF" CASE_PROC_LOCKS="$TMP_ROOT/proc-locks-otherdev" run_case "$sut" "$lib"
  ok_if "a lock on the SAME inode number but another device does not block the run (maj:min is compared too)" "[[ \"\$(field verdict)\" == pass ]]"
  reset_case_env; CASE_LOCK_FILE="$LOCKF" CASE_PROC_LOCKS="$TMP_ROOT/proc-locks-held" run_case "$sut" "$lib"
  expect_no_ping "the same device and inode" deploy_lock
  reset_case_env; CASE_LOCK_FILE="$LOCKF" CASE_PROC_LOCKS="$TMP_ROOT/does-not-exist" run_case "$sut" "$lib"
  expect_no_ping "lock table unreadable (cannot tell, so do not test)" infra_error
  # a deploy that takes the lock AFTER the start check: before the exec (caught by the re-check) and during it (voids the verdict)
  reset_case_env; cp "$TMP_ROOT/proc-locks-other" "$TMP_ROOT/pl-stats2"
  CASE_LOCK_FILE="$LOCKF" CASE_PROC_LOCKS="$TMP_ROOT/pl-stats2" MOCK_TAKE_LOCK_ON_STATS2="$HELD_LINE" run_case "$sut" "$lib"
  expect_no_ping "a deploy took the lock between the start check and the probe exec" deploy_lock
  ok_if "late lock before the exec: the probe was never exec'd" "! grep -q 'SMOKE=1' '$RUN_DIR/log/calls'"
  reset_case_env; cp "$TMP_ROOT/proc-locks-other" "$TMP_ROOT/pl-during"
  CASE_LOCK_FILE="$LOCKF" CASE_PROC_LOCKS="$TMP_ROOT/pl-during" MOCK_TAKE_LOCK="$HELD_LINE" \
    MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple","selector":"base"}' run_case "$sut" "$lib"
  expect_no_ping "a deploy took the lock while the probe ran (probe said fail)" deploy_lock
  ok_if "lock during the run: the probe did run, and the journal says when" "grep -q 'SMOKE=1' '$RUN_DIR/log/calls' && [[ \"\$(detail_text)\" == *after\ the\ probe* ]]"
}

case_keys() {  # <sut> <lib>: the heartbeat key NAME is judged before it is expanded (${!name} runs array subscripts as root)
  local sut="$1" lib="$2" plant="$TMP_ROOT/key-plant" k label bad=""
  local -a keys
  keys=("WEB_BASH_SYNTHETIC_URL_X[\$(touch $plant)]" "WEB_BASH_SYNTHETIC_URL_X Y" "WEB_BASH_SYNTHETIC_URL_X-Y" "WEB_BASH_SYNTHETIC_URL_X=Y"
    "WEB_BASH_SYNTHETIC_URL_X.Y" "WEB_BASH_SYNTHETIC_URL_X/Y" "WEB_BASH_SYNTHETIC_URL_X(Y)" "WEB_BASH_SYNTHETIC_URL_X\$Y" "WEB_BASH_SYNTHETIC_URL_X[0]"
    "WEB_BASH_SYNTHETIC_URL_x" "WEB_BASH_SYNTHETIC_URL_" "WEB_BASH_SYNTHETIC_URL" $'WEB_BASH_SYNTHETIC_URL_X\nY'
    "A[\$(touch $plant)]" "lower_case" "WEB_NIC_GUARD_URL_WEB_1" "DOPPLER_TOKEN" "PATH" "1WEB_BASH_SYNTHETIC_URL_X" "" )
  for k in "${keys[@]}"; do
    rm -f "$plant"; reset_case_env; CASE_URL_KEY="$k" run_case "$sut" "$lib"
    label="$(printf '%s' "$k" | tr '\n' '~')"
    { [[ ! -e "$plant" && "$(field verdict)" == no_ping && "$(field reason)" == no_heartbeat_url && "$(pings_any)" -eq 0 && "$(curl_calls_n)" -eq 0 ]] \
      && [[ "$ERR" != *"$plant"* ]]; } || bad+=" [$label]"
  done
  ok_if "every hostile or foreign heartbeat key name is refused: no command ran, no ping, no curl (offenders:${bad:- none})" "[[ -z '$bad' ]]"
  for k in WEB_BASH_SYNTHETIC_URL_WEB_1 WEB_BASH_SYNTHETIC_URL_WEB_2; do
    reset_case_env; CASE_URL_KEY="$k" run_case "$sut" "$lib"
    # the run's URL variable is named $KEY_OK, so a production-shaped key resolves to nothing here: refused as unset, not as malformed
    ok_if "production-shaped key [$k] passes the name check (url unset in this fixture)" "[[ \"\$(field reason)\" == no_heartbeat_url && \"\$(detail_text)\" == 'url unset' ]]"
  done
}

case_urls() {  # <sut> <lib>: single-bad-character heartbeat URLs; curl must never be invoked and the value must never be echoed
  local sut="$1" lib="$2" bad="" label u
  local -a urls
  urls=('https://uptime.betterstack.com/api/v1/heartbeat/abc"123' 'https://uptime.betterstack.com/api/v1/heartbeat/abc 123'
    'https://uptime.betterstack.com/api/v1/heartbeat/abc#123' 'https://uptime.betterstack.com/api/v1/heartbeat/abc\123'
    'https://uptime.betterstack.com/api/v1/heartbeat/abc?x=1' 'https://uptime.betterstack.com/api/v1/heartbeat/abc123?' 'https://uptime.betterstack.com/api/v1/heartbeat/abc&x'
    'https://uptime.betterstack.com/api/v1/heartbeat/abc=1' 'https://uptime.betterstack.com/api/v1/heartbeat/abc%20' 'https://uptime.betterstack.com/api/v1/heartbeat/abc;id'
    'https://uptime.betterstack.com/api/v1/heartbeat//abc' 'https:///api/v1/heartbeat/abc123' 'https://uptime.betterstack.com/api/v1/heartbeat/'
    'https://evil.example.com/api/v1/heartbeat/abc123' 'https://uptime.betterstack.com.evil.example.com/api/v1/heartbeat/abc123'
    'https://uptime.betterstack.com@evil.example.com/api/v1/heartbeat/abc123' 'https://uptime.betterstack.com:8443/api/v1/heartbeat/abc123'
    'https://169.254.169.254/latest/meta-data' 'https://localhost/api/v1/heartbeat/abc123' 'http://uptime.betterstack.com/api/v1/heartbeat/abc123'
    'https://uptime.betterstack.com/api/v2/heartbeat/abc123' 'https://uptime.betterstack.com/api/v1/monitors/abc123')
  for u in "${urls[@]}"; do
    reset_case_env; CASE_URL="$u" CASE_REAL_PING=1 run_case "$sut" "$lib"
    label="$(printf '%s' "$u" | tr '\n' '~')"
    { [[ "$(curl_calls_n)" -eq 0 && "$ERR" == *SOLEUR_CREDENTIAL_REFUSED* && "$(field reason)" == no_heartbeat_url && "$(field verdict)" == no_ping ]] \
      && [[ "$ERR" != *"evil.example"* && "$ERR" != *"abc"* ]]; } || bad+=" [$label]"
  done
  ok_if "every single-defect heartbeat URL is refused before any request: curl never invoked, value never echoed (offenders:${bad:- none})" "[[ -z '$bad' ]]"
  reset_case_env; CASE_URL=$'https://uptime.betterstack.com/api/v1/heartbeat/abc\nheader = "x"' CASE_REAL_PING=1 run_case "$sut" "$lib"
  ok_if "a newline in the URL is the control_char refusal; a quote alone is token_shape" "[[ \"\$ERR\" == *reason=control_char* && \"\$(curl_calls_n)\" -eq 0 ]]"
  reset_case_env; CASE_URL='https://uptime.betterstack.com/api/v1/heartbeat/abc"123' CASE_REAL_PING=1 run_case "$sut" "$lib"
  ok_if "a quote alone is token_shape" "[[ \"\$ERR\" == *reason=token_shape* && \"\$ERR\" != *reason=control_char* ]]"
  reset_case_env; CASE_URL="${URL_OK}/" MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple"}' CASE_REAL_PING=1 run_case "$sut" "$lib"
  ok_if "a trailing-slash URL gets /fail exactly once (no //fail)" "[[ \"\$CURLS\" == *'STDIN url = \"${URL_OK}/fail\"'* && \"\$CURLS\" != *'//fail'* ]]"
  reset_case_env; MOCK_CURL_HTTP_STATUS=404 CASE_REAL_PING=1 run_case "$sut" "$lib"
  ok_if "a heartbeat answered with an HTTP error status (curl -f) is retried once and warned" "[[ \"\$(printf '%s\n' \"\$CURLS\" | grep -c '^STDIN')\" -eq 2 && \"\$ERR\" == *'heartbeat ping FAILED'* ]]"
  reset_case_env; CASE_REAL_PING=1 run_case "$sut" "$lib"
  ok_if "the ping curl carries the full flag set (-gfsS -m 10, --disable first, --noproxy)" "[[ \"\$CURLS\" == *'ARGV --disable --noproxy * -gfsS -m 10 -o /dev/null --config -'* ]]"
}

case_counter() {  # <sut> <lib>
  local sut="$1" lib="$2" st="$TMP_ROOT/counter-state"
  rm -rf "$st"; mkdir -p "$st"
  reset_case_env; CASE_STATE_DIR="$st"
  MOCK_RUNNING=false run_case "$sut" "$lib"; c1="$(field consecutive_no_ping)"
  MOCK_RUNNING=false run_case "$sut" "$lib"; c2="$(field consecutive_no_ping)"
  MOCK_RUNNING=false run_case "$sut" "$lib"; c3="$(field consecutive_no_ping)"
  run_case "$sut" "$lib"; c4="$(field consecutive_no_ping)"
  ok_if "no_ping x3 counts 1,2,3 and a pass resets to 0" "[[ '$c1 $c2 $c3 $c4' == '1 2 3 0' ]]"
  printf 'not-a-number\n' > "$st/consecutive_no_ping"; MOCK_RUNNING=false run_case "$sut" "$lib"
  ok_if "a corrupt counter restarts at 1 instead of aborting the run" "[[ \"\$(field consecutive_no_ping)\" == 1 ]]"
  printf '08\n' > "$st/consecutive_no_ping"; MOCK_RUNNING=false run_case "$sut" "$lib"
  ok_if "a counter file holding 08 is the number 8 (not an invalid octal that aborts the run): the next value is 9" "[[ \"\$(field consecutive_no_ping)\" == 9 ]]"
  printf '99999999999999999999\n' > "$st/consecutive_no_ping"; MOCK_RUNNING=false run_case "$sut" "$lib"
  ok_if "a counter longer than 6 digits restarts at 1" "[[ \"\$(field consecutive_no_ping)\" == 1 ]]"
  : > "$st/consecutive_no_ping"; MOCK_RUNNING=false run_case "$sut" "$lib"
  ok_if "an empty counter file restarts at 1" "[[ \"\$(field consecutive_no_ping)\" == 1 ]]"
  printf '3\n' > "$st/consecutive_no_ping"
  MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple"}' run_case "$sut" "$lib"
  ok_if "a verified FAIL resets the no_ping counter (it is a claim, not a missing run)" "[[ \"\$(field verdict)\" == fail && \"\$(field consecutive_no_ping)\" == 0 && \"\$(cat '$st/consecutive_no_ping')\" == 0 ]]"
  reset_case_env
}

case_journal() {  # <sut> <lib>: what reaches the journal from docker's stderr and from the probe's result
  local sut="$1" lib="$2" d long
  long="$(printf 'A%.0s' $(seq 1 300))"
  reset_case_env
  MOCK_PRE_RC=125 MOCK_PRE_ERR=$'boom $(touch /tmp/never) "q" `id`; `rm`\nsecond line' run_case "$sut" "$lib"; d="$(detail_text)"
  ok_if "docker's stderr reaches the journal as ONE allowlisted line: first line only, no \$ \" \` ; ( )" "[[ \"\$d\" == *boom* && \"\$d\" != *second* ]] && allowlisted \"\$d\""
  MOCK_PRE_RC=125 MOCK_PRE_ERR="$long" run_case "$sut" "$lib"; d="$(detail_text)"
  ok_if "a 300-character stderr line is cut to at most 120 characters" "[[ \${#d} -le 120 && \${#d} -ge 60 ]]"
  CASE_SECRET='synthetic-secret-value-0123456789' MOCK_PRE_RC=125 MOCK_PRE_ERR='denied for synthetic-secret-value-0123456789 ok' run_case "$sut" "$lib"; d="$(detail_text)"
  ok_if "the VALUE of a secret-named environment variable is redacted before it reaches the journal" "[[ \"\$d\" != *synthetic-secret-value* && \"\$d\" == *REDACTED_* ]]"
  MOCK_PRE_RC=125 MOCK_PRE_ERR='token dp.st.prd.abcDEF123xyz rejected' run_case "$sut" "$lib"; d="$(detail_text)"
  ok_if "a credential-shaped token (dp.*) is redacted by shape" "[[ \"\$d\" != *abcDEF123xyz* && \"\$d\" == *dp.REDACTED* ]]"
  MOCK_RESULT='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":"9;touch x"}' run_case "$sut" "$lib"
  ok_if "a non-numeric masks_missing is journaled as - (digits only)" "[[ \"\$(field masks_missing)\" == '-' && \"\$(field verdict)\" == pass ]]"
  reset_case_env
}

case_masks_created() {  # <sut> <lib>: masks_created is one digit 0-4, else `-`
  local sut="$1" lib="$2"
  reset_case_env
  local base='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":0'
  # masks_created: one digit 0-4 (the probe's closed set has four dirs); anything else is `-` and never reaches the journal
  for bad in '"9;touch x"' '5' '-1' '12' '"4 forged=1"' '"4\nforged=1"' 'true' '[4]' '{"a":4}' '4.5'; do
    MOCK_RESULT="$base,\"masks_created\":$bad}" run_case "$sut" "$lib"
    ok_if "masks_created $bad is journaled as - (one digit 0-4 only), the run still passes" "[[ \"\$(field masks_created)\" == '-' && \"\$(field verdict)\" == pass && \"\$(pings_ok)\" -eq 1 ]]"
  done
  for good in 0 1 2 3 4; do
    MOCK_RESULT="$base,\"masks_created\":$good}" run_case "$sut" "$lib"
    ok_if "masks_created $good is journaled as that digit" "[[ \"\$(field masks_created)\" == '$good' ]]"
  done
  reset_case_env
}

case_masks_note() {  # <sut> <lib>: masks_note is a whole-string match against the closed enum, else `-`
  local sut="$1" lib="$2"
  reset_case_env
  local base='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":0'
  # masks_note: whole-string match against the closed enum, else `-`; never text from the probe, never a path or an errno
  for good in uid_mismatch pid1_unreadable pid1_env_unreadable home_mismatch env_divergence; do
    MOCK_RESULT="$base,\"masks_note\":\"$good\"}" run_case "$sut" "$lib"
    ok_if "masks_note $good is journaled as itself" "[[ \"\$(field masks_note)\" == '$good' ]]"
  done
  for bad in '"uid_mismatch\nforged=1"' '"forged=1\nuid_mismatch"' '"uid_mismatch forged=1"' '"uid_mismatch,"' '"EACCES: /tmp/cc-socks"' '"UID_MISMATCH"' '""' '"-"' '7' 'true' '["uid_mismatch"]' 'null'; do
    MOCK_RESULT="$base,\"masks_note\":$bad}" run_case "$sut" "$lib"
    ok_if "masks_note $bad is journaled as - (closed enum), no forged field, the run still passes" "[[ \"\$(field masks_note)\" == '-' && -z \"\$(field forged)\" && \"\$(field verdict)\" == pass && \"\$(printf '%s\\n' \"\$JOURNAL\" | wc -l)\" -eq 1 ]]"
  done
  reset_case_env
}

case_masks_missing() {  # <sut> <lib>: masks_missing is one digit 0-4; an over-range count is `5+` AND partial; only non-numeric is `-`
  local sut="$1" lib="$2"
  reset_case_env
  local base='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":0'
  # Non-numeric or non-integer text is `-` (unknown): no forged field, no journal pollution, the run still passes with the tuple it claimed.
  for bad in '-1' '"4 forged=1"' '"4\nforged=1"' 'true' '[1]' '4.5' '"9;touch x"'; do
    MOCK_RESULT="${base/\"masks_missing\":0/\"masks_missing\":$bad}}" run_case "$sut" "$lib"
    ok_if "masks_missing $bad is journaled as - (not a count), the run still passes" "[[ \"\$(field masks_missing)\" == '-' && -z \"\$(field forged)\" && \"\$(field verdict)\" == pass && \"\$(pings_ok)\" -eq 1 ]]"
  done
  # An all-digit count above 4 is something the closed set cannot produce: it is NOT unknown. It is journaled as the bounded token 5+ and
  # the pass is downgraded exactly like any non-zero count (the ping is unchanged). A `-` here would read as "no gap" and keep the full tuple.
  for over in 5 12 99999999999999999999 '"7"' 007; do
    MOCK_RESULT="${base/\"masks_missing\":0/\"masks_missing\":$over}}" run_case "$sut" "$lib"
    ok_if "masks_missing $over (over-range count) is journaled as 5+, downgrades coverage to prodtuple_partial, and still pings ok" "[[ \"\$(field masks_missing)\" == '5+' && \"\$(field coverage)\" == prodtuple_partial && \"\$(field verdict)\" == pass && \"\$(pings_ok)\" -eq 1 ]]"
  done
  for good in 0 1 2 3 4; do
    MOCK_RESULT="${base/\"masks_missing\":0/\"masks_missing\":$good}}" run_case "$sut" "$lib"
    ok_if "masks_missing $good is journaled as that digit; coverage is the full tuple only for 0" "[[ \"\$(field masks_missing)\" == '$good' && ( ( '$good' == 0 && \"\$(field coverage)\" == sdk_wrapper_shim_prodtuple ) || ( '$good' != 0 && \"\$(field coverage)\" == prodtuple_partial ) ) ]]"
  done
  reset_case_env
}

case_masks_absent() {  # <sut> <lib>: an old probe emits neither new field, and the journal line shape
  local sut="$1" lib="$2"
  reset_case_env
  local base='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":0'
  # an old probe (the apply lands before the release) emits neither field: both read `-`
  MOCK_RESULT="$base}" run_case "$sut" "$lib"
  ok_if "an old probe's output (no masks_created, no masks_note) journals - for both and still passes with the full tuple" "[[ \"\$(field masks_created)\" == '-' && \"\$(field masks_note)\" == '-' && \"\$(field coverage)\" == sdk_wrapper_shim_prodtuple && \"\$(pings_ok)\" -eq 1 ]]"
  # the line shape: the new fields sit right after masks_missing, before consecutive_no_ping
  ok_if "journal field order: masks_missing, masks_created, masks_note, consecutive_no_ping" "[[ \"\$JOURNAL\" == *' masks_missing='*' masks_created=- masks_note=- consecutive_no_ping='* ]]"
  reset_case_env
}

case_masks() {  # <sut> <lib>: every masks_* journal field (the control run; each mutation row runs only the group that guards it)
  case_masks_created "$1" "$2"
  case_masks_note "$1" "$2"
  case_masks_missing "$1" "$2"
  case_masks_absent "$1" "$2"
}

case_pass_shape() {  # <sut> <lib>: one pass run exercising every argv assertion of the mock (a changed request is refused with rc 64)
  reset_case_env; run_case "$1" "$2"
  ok_if "the pass run reached the mock with every modelled argv shape (no MOCK_ARGV_VIOLATION)" "[[ \"\$(field verdict)\" == pass ]] && ! grep -q MOCK_ARGV_VIOLATION '$RUN_DIR/log/calls'"
}

case_inspect() {  # <sut> <lib>
  local sut="$1" lib="$2"
  reset_case_env; MOCK_INSPECT_RC=1 MOCK_INSPECT_ERR='Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?' run_case "$sut" "$lib"
  expect_no_ping "docker daemon unreachable (inspect rc 1, not 'no such object')" infra_error
  ok_if "a dark daemon is not decoded as a stopped container" "[[ \"\$(detail_text)\" == *docker_inspect_rc_1* ]]"
  reset_case_env; MOCK_INSPECT_RC=1 run_case "$sut" "$lib"
  expect_no_ping "container missing (inspect rc 1, 'No such object')" container_down
}

case_umask() {  # <sut> <lib>: the state dir and the counter are root-only (the dir also holds docker's captured stderr)
  local sut="$1" lib="$2" st="$TMP_ROOT/umask-state"
  rm -rf "$st"; reset_case_env; CASE_STATE_DIR="$st"; (umask 022; run_case "$sut" "$lib")
  ok_if "a state dir the script creates is mode 700 and its counter mode 600, whatever the caller's umask" \
    "[[ \"\$(stat -c %a '$st')\" == 700 && \"\$(stat -c %a '$st/consecutive_no_ping')\" == 600 ]]"
  reset_case_env
}

case_pass_curl_zero() {  # <sut> <lib>: a pass reaches the heartbeat only through the ping seam (no trap, no stray call)
  reset_case_env; run_case "$1" "$2"
  ok_if "a pass run: verdict=pass, one ok ping through the seam, curl never invoked" "[[ \"\$(field verdict)\" == pass && \"\$(pings_ok)\" -eq 1 && \"\$(curl_calls_n)\" -eq 0 ]]"
}

case_timeouts() {  # <sut> <lib>: which cap fired, and what an rc 124 means before and after dispatch (each row waits out a real 1 s `timeout`)
  local sut="$1" lib="$2"
  # rc 124 BEFORE dispatch is a daemon stall, never a fail; AFTER dispatch it is the #10445 shape
  reset_case_env
  MOCK_PROBE_SLEEP=30 MOCK_DISPATCHED=0 CASE_PROBE_TIMEOUT=1 run_case "$sut" "$lib"
  ok_if "rc 124 before dispatch: no_ping host_timeout_before_dispatch, zero pings" "[[ \"\$(field verdict)\" == no_ping && \"\$(field reason)\" == host_timeout_before_dispatch && \"\$(pings_any)\" -eq 0 ]]"
  reset_case_env
  MOCK_PROBE_SLEEP=30 MOCK_DISPATCHED=1 CASE_PROBE_TIMEOUT=1 run_case "$sut" "$lib"
  ok_if "rc 124 after dispatch: fail (host_timeout), /fail ping" "[[ \"\$(field verdict)\" == fail && \"\$(pings_fail)\" -eq 1 && \"\$(pings_ok)\" -eq 0 ]]"
  ok_if "rc 124 after dispatch, HOST cap fired: the reason names that cap (host_timeout_1s)" "[[ \"\$(detail_text)\" == host_timeout_1s* ]]"
  reset_case_env
  MOCK_PROBE_RC=124 CASE_PROBE_TIMEOUT=50 run_case "$sut" "$lib"
  ok_if "rc 124 after dispatch, IN-CONTAINER cap fired (no host wait): the reason names ${INNER_T}s, not the host cap" "[[ \"\$(field verdict)\" == fail && \"\$(detail_text)\" == host_timeout_${INNER_T}s* ]]"

}

# ---- Core cases (run against the real SUT, and again against the first mutants) ---------------------------------------------
# core_cases <sut> <lib>: returns via CORE_FAILS the number of failed expectations. Output is suppressed for mutants.
core_cases() {
  local sut="$1" lib="$2" before="$fails"
  reset_case_env
  # pass: probe verified -> exactly one ok ping, AFTER the probe returned
  run_case "$sut" "$lib"
  ok_if "pass: verdict=pass" "[[ \"\$(field verdict)\" == pass ]]"
  ok_if "pass: exactly one ok ping and no fail ping" "[[ \"\$(pings_ok)\" -eq 1 && \"\$(pings_fail)\" -eq 0 ]]"
  ok_if "pass: the ping comes AFTER the probe returned (PROBE_DONE precedes PING ok)" "[[ \"\$(printf '%s\n' \"\$PINGS\" | tr '\n' ' ')\" == 'PROBE_DONE PING ok ' ]]"
  ok_if "pass: curl is reached only through the ping seam (no direct call)" "[[ \"\$(curl_calls_n)\" -eq 0 ]]"
  ok_if "pass: exit 0" "[[ '$EC' -eq 0 ]]"
  ok_if "pass: coverage and selector are journaled" "[[ \"\$(field coverage)\" == sdk_wrapper_shim_prodtuple && \"\$(field selector)\" == base ]]"

  # nonce missing: the probe dispatched Bash and no verified nonce came back -> fail, /fail ping, failed unit
  reset_case_env
  MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"no_nonce: apply-seccomp: Operation not permitted","coverage":"sdk_wrapper_shim_prodtuple"}' run_case "$sut" "$lib"
  ok_if "nonce missing: verdict=fail" "[[ \"\$(field verdict)\" == fail ]]"
  ok_if "nonce missing: one /fail ping, no ok ping, curl only through the seam" "[[ \"\$(pings_fail)\" -eq 1 && \"\$(pings_ok)\" -eq 0 && \"\$(curl_calls_n)\" -eq 0 ]]"
  ok_if "nonce missing: exit 3 (the unit shows failed)" "[[ '$EC' -eq 3 ]]"

  # a container swapped mid-run is a skip even when the probe says fail
  reset_case_env
  MOCK_ID2=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple"}' run_case "$sut" "$lib"
  expect_no_ping "container id changed mid-run (probe said fail)" container_restarted
  reset_case_env
  MOCK_ID2=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef MOCK_START2=2026-10-20T10:07:00.000000001Z run_case "$sut" "$lib"
  expect_no_ping "container start time changed mid-run (same id)" container_restarted
  case_restart_stopped "$sut" "$lib"

  # a deploy lock or memory pressure is a skip that no heartbeat call may ride (mutants E and G of the plan's Guard 1)
  case_noping_curl "$sut" "$lib"

  # killed after dispatch (OOM killer, container stop) is not a Bash result
  reset_case_env
  MOCK_PROBE_RC=137 MOCK_NO_RESULT=1 run_case "$sut" "$lib"
  ok_if "rc 137 after dispatch: no_ping, zero pings" "[[ \"\$(field verdict)\" == no_ping && \"\$(pings_any)\" -eq 0 ]]"
  CORE_FAILS=$((fails - before))
}

echo "--- control: unmutated SUT ---"
core_cases "$SUT" "$LIB"
CONTROL_FAILS=$CORE_FAILS
case_timeouts "$SUT" "$LIB"
ok_if "control run has no failed expectation (a red control voids every mutation row)" "[[ '$CONTROL_FAILS' -eq 0 ]]"

echo "--- every no_ping reason: zero pings ---"
case_lock "$SUT" "$LIB"
case_mem "$SUT" "$LIB"
case_selector "$SUT" "$LIB"
case_inspect "$SUT" "$LIB"
reset_case_env; CASE_URL="" run_case "$SUT" "$LIB"; expect_no_ping "heartbeat URL unset" no_heartbeat_url
reset_case_env; MOCK_PRE_RC=66 run_case "$SUT" "$LIB"; expect_no_ping "probe or resolver absent from the image (rc 66)" probe_absent
reset_case_env; MOCK_PRE_RC=124 run_case "$SUT" "$LIB"; expect_no_ping "pre-exec timed out" host_timeout_before_dispatch
reset_case_env; MOCK_PRE_RC=125 MOCK_PRE_ERR="docker: Error response from daemon" run_case "$SUT" "$LIB"; expect_no_ping "pre-exec docker error" infra_error
reset_case_env; MOCK_HOME="relative/home" run_case "$SUT" "$LIB"; expect_no_ping "container HOME is not an absolute path" infra_error
reset_case_env; MOCK_SEL_OUT='{"not":"a selector"}\n' run_case "$SUT" "$LIB"; expect_no_ping "resolver output is neither base, unixdeny nor unresolved" infra_error
reset_case_env; MOCK_SEL_OUT='SOLEUR_SELECTOR=base\nSOLEUR_SELECTOR=unixdeny\n' run_case "$SUT" "$LIB"; expect_no_ping "resolver printed two selector lines (exactly one is required)" infra_error
reset_case_env; MOCK_SEL_OUT='base\n' run_case "$SUT" "$LIB"; expect_no_ping "resolver output without the sentinel prefix is not a selector" infra_error
reset_case_env; MOCK_SEL_RC=1 run_case "$SUT" "$LIB"; expect_no_ping "resolver exits non-zero" infra_error
reset_case_env; MOCK_SEL_RC=124 run_case "$SUT" "$LIB"; expect_no_ping "resolver cap fires (rc 124): a daemon stall, not a verdict" host_timeout_before_dispatch
reset_case_env; MOCK_PROBE_RC=125 MOCK_NO_RESULT=1 MOCK_DISPATCHED=0 run_case "$SUT" "$LIB"; expect_no_ping "docker exec rc 125 before dispatch" infra_error
reset_case_env; MOCK_RESULT='{"verdict":"pass","reason":"ok","coverage":"replay_only"}' run_case "$SUT" "$LIB"; expect_no_ping "pass-shaped result with replay_only coverage (a HOLD)" infra_error
reset_case_env; MOCK_NO_RESULT=1 run_case "$SUT" "$LIB"; expect_no_ping "rc 0 with no result line" infra_error
reset_case_env; run_case "$SUT" "$SCRIPT_DIR/no-such-lib.sh"; expect_no_ping "verdict lib absent" infra_error
ok_if "verdict lib absent: names the cause" "[[ \"\$ERR\" == *verdict_lib_absent* ]]"

echo "--- heartbeat key name and URL shape ---"
case_keys "$SUT" "$LIB"
case_urls "$SUT" "$LIB"

echo "--- result-line parsing ---"
reset_case_env; MOCK_SEL_OUT='{"level":40,"msg":"unix-deny-flag-unresolved"}\nSOLEUR_SELECTOR=unixdeny\n' MOCK_SELECTOR=unixdeny \
  MOCK_RESULT='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"unixdeny","masks_missing":0}' run_case "$SUT" "$LIB"
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
ok_if "a pass with masks_missing > 0 is labelled prodtuple_partial, not the full tuple (the ping is unchanged)" "[[ \"\$(field coverage)\" == prodtuple_partial && \"\$(pings_ok)\" -eq 1 ]]"
reset_case_env; MOCK_RESULT='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":0,"masks_created":4,"masks_note":null}' run_case "$SUT" "$LIB"
ok_if "a cold-container run that created all four dirs journals masks_created=4 masks_missing=0, keeps the full tuple and pings" "[[ \"\$(field masks_created)\" == 4 && \"\$(field masks_missing)\" == 0 && \"\$(field masks_note)\" == - && \"\$(field coverage)\" == sdk_wrapper_shim_prodtuple && \"\$(pings_ok)\" -eq 1 ]]"
reset_case_env; MOCK_RESULT='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":1,"masks_created":3,"masks_note":"home_mismatch"}' run_case "$SUT" "$LIB"
ok_if "created 3 of 4 with a note: all three fields journaled, prodtuple_partial, and the heartbeat is NOT withheld (it is a claim)" "[[ \"\$(field masks_created)\" == 3 && \"\$(field masks_missing)\" == 1 && \"\$(field masks_note)\" == home_mismatch && \"\$(field coverage)\" == prodtuple_partial && \"\$(pings_ok)\" -eq 1 && \"\$(pings_any)\" -eq 1 ]]"
reset_case_env; MOCK_RESULT='{"verdict":"pass","reason":"ok","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":0,"masks_created":0,"masks_note":"env_divergence"}' run_case "$SUT" "$LIB"
ok_if "an informational note (env_divergence) with nothing missing does not downgrade the tuple" "[[ \"\$(field masks_note)\" == env_divergence && \"\$(field coverage)\" == sdk_wrapper_shim_prodtuple && \"\$(pings_ok)\" -eq 1 ]]"
reset_case_env; MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple","selector":"base","masks_missing":4,"masks_created":0,"masks_note":"uid_mismatch"}' run_case "$SUT" "$LIB"
ok_if "a verified fail still journals the new fields and still pings /fail" "[[ \"\$(field verdict)\" == fail && \"\$(field masks_note)\" == uid_mismatch && \"\$(field masks_created)\" == 0 && \"\$(pings_fail)\" -eq 1 ]]"
ok_if "the resolver ran BEFORE the probe exec" "[[ \"\$(grep -n 'RESOLVER_RAN\|SMOKE=1' '$RUN_DIR/log/calls' | head -n 1 | cut -d: -f2)\" == RESOLVER_RAN ]]"
ok_if "no -u / -e / --env on any docker exec (no uid change, no env copied from the host)" "! grep -E 'docker exec.* (-u|-e|--user|--env|--env-file)( |=)' '$RUN_DIR/log/calls'"
nonce1="$(grep -h NONCE_SEEN "$RUN_DIR/log/calls")"
reset_case_env; run_case "$SUT" "$LIB"
nonce2="$(grep -h NONCE_SEEN "$RUN_DIR/log/calls")"
ok_if "the nonce is fresh per run (two runs differ)" "[[ -n '$nonce1' && -n '$nonce2' && '$nonce1' != '$nonce2' ]]"
case_pass_shape "$SUT" "$LIB"

echo "--- consecutive_no_ping counter, journal scrub, state dir mode ---"
case_counter "$SUT" "$LIB"
case_journal "$SUT" "$LIB"
case_masks "$SUT" "$LIB"
case_umask "$SUT" "$LIB"

echo "--- heartbeat discipline (real curl path, stub curl) ---"
reset_case_env; CASE_REAL_PING=1 run_case "$SUT" "$LIB"
CURL_ARGV="$(printf '%s\n' "$CURLS" | grep '^ARGV' || true)"
ok_if "ok ping: exactly ONE curl call for a pass" "[[ \"\$(curl_calls_n)\" -eq 1 ]]"
ok_if "ok ping: the URL rides the stdin config, never argv" "[[ \"\$CURLS\" == *'STDIN url = \"$URL_OK\"'* && -n \"\$CURL_ARGV\" && \"\$CURL_ARGV\" != *abc123* ]]"
ok_if "ok ping: --disable first and --noproxy confine the transport" "[[ \"\$CURLS\" == *'ARGV --disable --noproxy'* ]]"
reset_case_env; MOCK_RESULT='{"verdict":"sdk_bash_smoke_failed","reason":"x","coverage":"sdk_wrapper_shim_prodtuple"}' CASE_REAL_PING=1 run_case "$SUT" "$LIB"
ok_if "fail ping goes to <url>/fail, once" "[[ \"\$CURLS\" == *'STDIN url = \"$URL_OK/fail\"'* && \"\$(curl_calls_n)\" -eq 1 ]]"
reset_case_env; MOCK_RUNNING=false CASE_REAL_PING=1 run_case "$SUT" "$LIB"
ok_if "a no_ping run reaches curl zero times on the real ping path too" "[[ \"\$(curl_calls_n)\" -eq 0 ]]"
reset_case_env; MOCK_CURL_RC=22 CASE_REAL_PING=1 run_case "$SUT" "$LIB"
ok_if "a failed ping is retried once and warned, never aborting the unit" "[[ \"\$(printf '%s\n' \"\$CURLS\" | grep -c '^STDIN')\" -eq 2 && \"\$ERR\" == *'heartbeat ping FAILED'* ]]"
reset_case_env
xtrace_ec=0; bash -x "$SUT" > /dev/null 2>&1 || xtrace_ec=$?
ok_if "refuses to run under xtrace (exit 78): the heartbeat URL is a credential" "[[ '$xtrace_ec' -eq 78 ]]"

echo "--- Guard 1 static: the heartbeat chokepoint has exactly its call sites, in the script and the lib ---"
# guard1_static <sut> <lib>: prints "<function>:<count>" for every function that calls `_hb_curl` / `ping_heartbeat` (definitions and whole-line
# comments excluded) plus the number of `curl` command words; the expected set is exactly the two chokepoint edges.
guard1_static() {
  local f
  for f in "$1" "$2"; do
    grep -vE '^[[:space:]]*#' "$f" | awk -v F="$(basename "$f")" '
      { l = $0; isdef = 0
        if (l ~ /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/) { isdef = 1; fn = l; sub(/\(\).*/, "", fn); sub(/^[A-Za-z_][A-Za-z0-9_]*\(\) \{/, "", l) }
        else if (l ~ /^\}/) { fn = ""; next }
        where = (fn == "" ? "<toplevel>" : fn)
        m = l
        if (l !~ /^[[:space:]]*$/) {
          n = gsub(/(^|[^A-Za-z0-9_])_hb_curl([^A-Za-z0-9_]|$)/, "&", m); if (n > 0) c["hb_curl@" F ":" where] += n
          m = l
          n = gsub(/(^|[^A-Za-z0-9_])ping_heartbeat([^A-Za-z0-9_]|$)/, "&", m); if (n > 0) c["ping@" F ":" where] += n
          m = l
          n = gsub(/(^|[^A-Za-z0-9_-])curl([^A-Za-z0-9_]|$)/, "&", m); if (n > 0) c["curlword@" F ":" where] += n
        }
        if (isdef && $0 ~ /\}[[:space:]]*$/) fn = ""
      }
      END { for (k in c) print k "=" c[k] }'
  done | sed 's/@[^:]*:/:/' | sort | tr '\n' ' '
}
G1_EXPECT="curlword:_hb_curl=1 hb_curl:ping_heartbeat=2 ping:finish=2 "
G1_NOW="$(guard1_static "$SUT" "$LIB")"
ok_if "static: curl is spelled once (inside _hb_curl), _hb_curl is called twice (inside ping_heartbeat) and ping_heartbeat twice (inside finish), none in the lib (got: $G1_NOW)" \
  "[[ '$G1_NOW' == '$G1_EXPECT' ]]"

echo "--- seams are inert without --fixture-seams (an injected secret cannot steer the root script) ---"
# The unflagged rows must not reach the machine's real docker, lock or state dir, and the real SUT resets PATH to /usr/sbin:/usr/bin:/bin
# (so a fixture PATH prefix cannot hide a real docker, which CI runners have). They therefore run a COPY of the SUT/lib whose only
# differences are the four default paths and the PATH tail, redirected to fixtures by test-only variables; the seam gate (the unset
# block) and every seam read are the SUT's own text. Each seam gets one behavioural row with an observable that differs honoured vs ignored.
make_unflagged() {  # <sut> <lib> -> prints the copy's path (the lib sits next to it, where the SUT looks first)
  local d="$MUT/unflagged.$RANDOM.$RANDOM"; mkdir -p "$d"
  SRC="$1" OUT="$d/web-bash-synthetic.sh" python3 - <<'PY' || return 1
import os
s = open(os.environ["SRC"]).read()
for old, new in (
    ("${SOLEUR_WBS_STATE_DIR:-/run/web-bash-synthetic}", "${SOLEUR_WBS_STATE_DIR:-${WBS_T_DEF_STATE:?}}"),
    ("${SOLEUR_WBS_LOCK_FILE:-/var/lock/ci-deploy.lock}", "${SOLEUR_WBS_LOCK_FILE:-${WBS_T_DEF_LOCK:?}}"),
    ("${SOLEUR_WBS_PROC_LOCKS:-/proc/locks}", "${SOLEUR_WBS_PROC_LOCKS:-${WBS_T_DEF_PROC:?}}"),
    ("${SOLEUR_WBS_MEMINFO:-/proc/meminfo}", "${SOLEUR_WBS_MEMINFO:-${WBS_T_DEF_MEMINFO:?}}"),
    ('PATH="${SOLEUR_WBS_PATH_PREFIX:+$SOLEUR_WBS_PATH_PREFIX:}/usr/sbin:/usr/bin:/bin"', 'PATH="${SOLEUR_WBS_PATH_PREFIX:+$SOLEUR_WBS_PATH_PREFIX:}${WBS_T_BIN:?}:/usr/sbin:/usr/bin:/bin"'),
):
    assert s.count(old) == 1, old
    s = s.replace(old, new)
open(os.environ["OUT"], "w").write(s)
PY
  cp "$2" "$d/sdk-bash-verdict.sh"
  printf '%s' "$d/web-bash-synthetic.sh"
}
# unflagged_run <copy> <VAR=value>...: run the copy WITHOUT --fixture-seams with exactly those (hostile) seam variables set.
unflagged_run() {
  local copy="$1" ec=0; shift
  RUN_DIR="$(mktemp -d "$TMP_ROOT/run.XXXXXX")"; assert_fixture_dir "$RUN_DIR"; mkdir -p "$RUN_DIR/state" "$RUN_DIR/log"
  : > "$RUN_DIR/log/calls"; : > "$RUN_DIR/log/curl.calls"; : > "$RUN_DIR/ping.log"; cp "$TMP_ROOT/proc-locks-other" "$RUN_DIR/proc-locks-default"
  env "$@" MOCK_LOG="$RUN_DIR/log" MOCK_PING_LOG="$RUN_DIR/ping.log" MOCK_INNER_TIMEOUT="$INNER_T" MOCK_PROC_LOCKS="$RUN_DIR/proc-locks-default" \
    WBS_T_BIN="$BIN" WBS_T_DEF_STATE="$RUN_DIR/state" WBS_T_DEF_LOCK="$LOCKF" WBS_T_DEF_PROC="$RUN_DIR/proc-locks-default" WBS_T_DEF_MEMINFO="$TMP_ROOT/meminfo-ok" \
    WEB_BASH_SYNTHETIC_URL_KEY="$KEY_OK" "$KEY_OK=$URL_OK" \
    bash "$copy" > "$RUN_DIR/out" 2> "$RUN_DIR/err" || ec=$?
  EC=$ec; ERR="$(cat "$RUN_DIR/err")"; CURLS="$(cat "$RUN_DIR/log/curl.calls")"; PINGS=""
  JOURNAL="$(grep -a 'SOLEUR_WEB_BASH_SYNTHETIC ' "$RUN_DIR/err" | tail -n 1 || true)"
}
# seam_unset_list <sut>: the names the gate unsets, from the SUT's own unset statement.
seam_unset_list() { awk '/^if \[ "\$\{1:-\}" != "--fixture-seams" \]; then$/{f=1;next} f&&/^fi$/{exit} f' "$1" | grep -oE 'SOLEUR_WBS_[A-Z_]+' | sort -u | tr '\n' ' '; }
# case_seam <seam-name> <sut> <lib>: one hostile value for one seam, run unflagged; the expectation is the baseline pass plus the seam's own observable.
case_seam() {
  local seam="$1" sut="$2" lib="$3" copy h="$TMP_ROOT/hostile.$RANDOM"
  copy="$(make_unflagged "$sut" "$lib")" || { fail "unflagged copy of the SUT could not be built"; return; }
  mkdir -p "$h/evil-bin"; assert_fixture_dir "$h"
  case "$seam" in
    SOLEUR_WBS_PATH_PREFIX)
      printf '#!/bin/sh\ntouch "%s/evil-docker-ran"\nexit 0\n' "$h" > "$h/evil-bin/docker"; chmod +x "$h/evil-bin/docker"
      unflagged_run "$copy" SOLEUR_WBS_PATH_PREFIX="$h/evil-bin"
      ok_if "WITHOUT --fixture-seams SOLEUR_WBS_PATH_PREFIX is ignored: the hostile docker never ran and the run passed" "[[ ! -e '$h/evil-docker-ran' && \"\$(field verdict)\" == pass ]]" ;;
    SOLEUR_WBS_CONTAINER)
      unflagged_run "$copy" SOLEUR_WBS_CONTAINER=attacker-chosen
      ok_if "WITHOUT --fixture-seams SOLEUR_WBS_CONTAINER is ignored: the mock docker is never asked about it" "! grep -q attacker-chosen '$RUN_DIR/log/calls' && [[ \"\$(field verdict)\" == pass ]]" ;;
    SOLEUR_WBS_STATE_DIR)
      unflagged_run "$copy" SOLEUR_WBS_STATE_DIR="$h/hostile-state"
      ok_if "WITHOUT --fixture-seams SOLEUR_WBS_STATE_DIR is ignored: the hostile directory was not created" "[[ ! -e '$h/hostile-state' && \"\$(field verdict)\" == pass ]]" ;;
    SOLEUR_WBS_LOCK_FILE)
      # the default lock table holds a lock on LOCKF2 only; the default lock file is LOCKF (not held)
      unflagged_run "$copy" SOLEUR_WBS_LOCK_FILE="$LOCKF2"
      ok_if "WITHOUT --fixture-seams SOLEUR_WBS_LOCK_FILE is ignored: the default lock file is the one consulted (a hostile, held lock file does not skip the run)" "[[ \"\$(field verdict)\" == pass ]]" ;;
    SOLEUR_WBS_PROC_LOCKS)
      unflagged_run "$copy" SOLEUR_WBS_PROC_LOCKS="$TMP_ROOT/proc-locks-held"
      ok_if "WITHOUT --fixture-seams SOLEUR_WBS_PROC_LOCKS is ignored: a lock table that says held does not skip the run" "[[ \"\$(field verdict)\" == pass ]]" ;;
    SOLEUR_WBS_VERDICT_LIB)
      unflagged_run "$copy" SOLEUR_WBS_VERDICT_LIB="$h/no-such-lib.sh"
      ok_if "WITHOUT --fixture-seams SOLEUR_WBS_VERDICT_LIB is ignored: a hostile path does not yield verdict_lib_absent and is never sourced" "[[ \"\$ERR\" != *verdict_lib_absent* && \"\$(field verdict)\" == pass ]]"
      printf 'touch "%s/lib-sourced"\n' "$h" > "$h/evil-lib.sh"
      unflagged_run "$copy" SOLEUR_WBS_VERDICT_LIB="$h/evil-lib.sh"
      ok_if "WITHOUT --fixture-seams a hostile verdict lib is never sourced as root" "[[ ! -e '$h/lib-sourced' ]]" ;;
    SOLEUR_WBS_PING_LOG)
      unflagged_run "$copy" SOLEUR_WBS_PING_LOG="$h/hostile-ping.log"
      ok_if "WITHOUT --fixture-seams SOLEUR_WBS_PING_LOG is ignored: the ping went to curl (once), nothing to the hostile log" "[[ ! -e '$h/hostile-ping.log' && \"\$(curl_calls_n)\" -eq 1 && \"\$(field verdict)\" == pass ]]" ;;
    SOLEUR_WBS_PROBE_TIMEOUT)
      unflagged_run "$copy" SOLEUR_WBS_PROBE_TIMEOUT=1 MOCK_PROBE_DELAY=2
      ok_if "WITHOUT --fixture-seams SOLEUR_WBS_PROBE_TIMEOUT is ignored: a 2 s probe is not cut at 1 s" "[[ \"\$(field verdict)\" == pass ]]" ;;
    SOLEUR_WBS_MEM_PCT_MAX)
      unflagged_run "$copy" SOLEUR_WBS_MEM_PCT_MAX=1 MOCK_MEM=12.34%
      ok_if "WITHOUT --fixture-seams SOLEUR_WBS_MEM_PCT_MAX is ignored: 12% memory is not skipped at a hostile 1% threshold" "[[ \"\$(field verdict)\" == pass ]]" ;;
    SOLEUR_WBS_MEMINFO)
      unflagged_run "$copy" SOLEUR_WBS_MEMINFO="$TMP_ROOT/meminfo-low"
      ok_if "WITHOUT --fixture-seams SOLEUR_WBS_MEMINFO is ignored: a hostile low-memory meminfo does not skip the run" "[[ \"\$(field verdict)\" == pass ]]" ;;
    *) fail "seam $seam has NO behavioural unflagged row (add a case_seam arm: a new seam cannot skip the gate)" ;;
  esac
}
reset_case_env
copy0="$(make_unflagged "$SUT" "$LIB")"; unflagged_run "$copy0"
ok_if "control: the unflagged harness itself runs the SUT to a pass with no seam set (so the rows below can discriminate)" "[[ \"\$(field verdict)\" == pass && \"\$(curl_calls_n)\" -eq 1 ]]"
seam_run() {  # <extra arg or empty> <VAR=value...>: runs the REAL SUT with exactly those seam variables; sets RUN_DIR / SEAM_ERR
  local arg="$1" ec=0; shift
  RUN_DIR="$(mktemp -d "$TMP_ROOT/run.XXXXXX")"; assert_fixture_dir "$RUN_DIR"; mkdir -p "$RUN_DIR/state" "$RUN_DIR/log"; : > "$RUN_DIR/ping.log"; : > "$RUN_DIR/log/calls"
  env "$@" MOCK_LOG="$RUN_DIR/log" MOCK_INNER_TIMEOUT="$INNER_T" SOLEUR_WBS_STATE_DIR="$RUN_DIR/state" SOLEUR_WBS_PING_LOG="$RUN_DIR/ping.log" \
    SOLEUR_WBS_MEMINFO="$TMP_ROOT/meminfo-ok" SOLEUR_WBS_LOCK_FILE="$RUN_DIR/no-such-lock" SOLEUR_WBS_PROC_LOCKS="$RUN_DIR/no-such-proc-locks" \
    WEB_BASH_SYNTHETIC_URL_KEY="$KEY_OK" "$KEY_OK=$URL_OK" \
    bash "$SUT" ${arg:+"$arg"} > "$RUN_DIR/out" 2> "$RUN_DIR/err" || ec=$?
  SEAM_ERR="$(cat "$RUN_DIR/err")"
}
seam_run --fixture-seams SOLEUR_WBS_PATH_PREFIX="$BIN" SOLEUR_WBS_CONTAINER=attacker-chosen
ok_if "control: WITH --fixture-seams the PATH and container seams take effect (the mock docker sees the chosen name)" "grep -q 'attacker-chosen' '$RUN_DIR/log/calls'"
seam_run --fixture-seams SOLEUR_WBS_PATH_PREFIX="$BIN" SOLEUR_WBS_VERDICT_LIB="$RUN_DIR/no-such-lib.sh"
ok_if "control: WITH --fixture-seams a bogus verdict-lib seam takes effect (verdict_lib_absent)" "[[ \"\$SEAM_ERR\" == *verdict_lib_absent* ]]"
sut_seams="$(grep -vE '^[[:space:]]*#' "$SUT" | grep -oE 'SOLEUR_WBS_[A-Z_]+' | sort -u | tr '\n' ' ')"
unset_seams="$(seam_unset_list "$SUT")"
ok_if "every SOLEUR_WBS_* name the script reads is in the unset statement (a new seam cannot silently skip the gate)" "[[ -n '$unset_seams' && '$sut_seams' == '$unset_seams' ]]"
for seam in $unset_seams; do case_seam "$seam" "$SUT" "$LIB"; done

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
# unit_ok <service file>: the unit shape this suite pins; every row below is also a mutation target further down.
sum_caps() {  # the sum of the script's own caps in seconds, from the SUT: inspect x2, stats x2, pre-exec, resolver, probe + kill grace, 2 pings of 10 s
  local g; g() { sed -n "s/^$1=\\([0-9][0-9]*\\)\$/\\1/p" "$SUT"; }
  echo $(( $(g INSPECT_TIMEOUT) * 2 + $(g STATS_TIMEOUT) * 2 + $(g PREEXEC_TIMEOUT) + $(g RESOLVER_HOST_TIMEOUT) + PROBE_T_DEFAULT + 5 + 20 ))
}
unit_ok() {
  local svc="$1" tim="$2" t cap
  grep -qx 'SyslogIdentifier=web-bash-synthetic' "$svc" || return 1
  grep -qx 'Type=oneshot' "$svc" && grep -qx 'Environment=HOME=/root' "$svc" && grep -qx 'EnvironmentFile=/etc/default/web-bash-synthetic' "$svc" || return 1
  [[ "$(grep -E '^ExecStart=' "$svc")" == "ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- /bin/bash -p /usr/local/bin/web-bash-synthetic.sh'" ]] || return 1
  [[ "$(grep -cE '^Exec[A-Za-z]*=' "$svc")" -eq 1 ]] || return 1
  ! grep -qE '^(OnFailure|OnSuccess|ExecStartPre|ExecStartPost|ExecStop|ExecStopPost|ExecReload|ExecCondition)=' "$svc" || return 1
  grep -qx 'RuntimeDirectory=web-bash-synthetic' "$svc" && grep -qx 'RuntimeDirectoryPreserve=yes' "$svc" || return 1
  grep -qx 'RuntimeDirectoryMode=0700' "$svc" && grep -qx 'UMask=0077' "$svc" || return 1
  t="$(sed -n 's/^TimeoutStartSec=\([0-9][0-9]*\)$/\1/p' "$svc")"; cap="$(sum_caps)"
  [[ -n "$t" && "$t" -gt $(( cap + 55 )) ]] || return 1   # the caps, plus up to ~55 s of `doppler run` retries before the script starts
  grep -qx 'OnUnitActiveSec=15min' "$tim" && grep -qE '^OnActiveSec=' "$tim" && grep -qx 'Persistent=false' "$tim" || return 1
  [[ "$(sed -n 's/^RandomizedDelaySec=\([0-9][0-9]*\)$/\1/p' "$tim")" -ge 1 ]] || return 1
  grep -qx 'After=network-online.target docker.service' "$svc" || return 1
}
ok_if "service and timer: oneshot with ExecStart ONLY the bash -p doppler wrapper (expands nothing, #9639; no other Exec*/OnFailure/OnSuccess), root-only state dir (0700, umask 077), TimeoutStartSec $(sed -n 's/^TimeoutStartSec=//p' "$SERVICE") above the script's own sum of caps ($(sum_caps)) plus the doppler retry allowance, 15 min timer jittered >= 1 s" "unit_ok '$SERVICE' '$TIMER'"

echo "--- Guard 1 row 6: one verdict function, two callers ---"
callers_share() {  # <ci-deploy path> <synthetic path>: both source the lib and call the one function; neither re-implements it
  local d="$1" s="$2"
  grep -q 'sdk_bash_map_result "\$exec_rc"' "$d" && grep -q 'sdk_bash_map_result' "$s" \
    && ! grep -qE 'SDK_BASH_DISPATCHED' <(grep -v '^[[:space:]]*#' "$d") \
    && ! grep -qE 'SDK_BASH_DISPATCHED' <(grep -v '^[[:space:]]*#' "$s")
}
ok_if "ci-deploy.sh and web-bash-synthetic.sh both call sdk_bash_map_result and neither inlines the marker mapping" "callers_share '$DEPLOY' '$SUT'"

# ---- Mutation battery ------------------------------------------------------------------------------------------------------
echo "--- mutation battery: each row must turn its cases RED ---"
PRISTINE_SUT="$MUT/pristine.sh"; PRISTINE_LIB="$MUT/pristine-lib.sh"
cp "$SUT" "$PRISTINE_SUT"; cp "$LIB" "$PRISTINE_LIB"

# _mutate_try <sut|lib|service|timer> <label> <old> <new>: lands one replacement on a COPY (sets MUTANT); rc 1 when the anchor is missing
# or the copy equals the original (a mutation that does not land would report the baseline and pass for the wrong reason).
_mutate_try() {
  local which="$1" label="$2" old="$3" new="$4" src out
  case "$which" in sut) src="$SUT" ;; lib) src="$LIB" ;; service) src="$SERVICE" ;; timer) src="$TIMER" ;; esac
  out="$MUT/m.$which.$label"
  OLD="$old" NEW="$new" SRC="$src" OUT="$out" python3 - <<'PY' || return 1
import os, sys
s = open(os.environ["SRC"]).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if s.count(old) < 1:
    sys.exit(1)
open(os.environ["OUT"], "w").write(s.replace(old, new, 1))
PY
  if cmp -s "$src" "$out"; then return 1; fi
  MUTANT="$out"
}
mutate() {
  if ! _mutate_try "$@"; then fail "mutation $2 did NOT apply (anchor missing, or it landed as a no-op identical to pristine)"; return 1; fi
}
# mutant_fails <fn> <sut> <lib>: how many expectations of one case group fail on that (mutated) copy; the group's own output is not shown.
mutant_fails() { local out; out="$("$1" "$2" "$3" 2>&1)"; printf '%s\n' "$out" | grep -c '^  FAIL:' || true; }
red_with() {  # <label> <sut> <lib> [case-fn: default core_cases]
  local label="$1" sut="$2" lib="$3" fn="${4:-core_cases}" n
  n="$(mutant_fails "$fn" "$sut" "$lib")"
  if [[ "$n" -ge 1 ]]; then pass "mutation $label turns $fn RED ($n failing expectation(s))"; else fail "mutation $label SURVIVED ($fn stayed green)"; fi
}
# mut_sut / mut_lib <label> <fn> <old> <new>: mutate the SUT (or the lib), then require that case group to go RED on it.
mut_sut() { local label="$1" fn="$2"; if mutate sut "$label" "$3" "$4"; then red_with "$label" "$MUTANT" "$LIB" "$fn"; fi; }
mut_lib() { local label="$1" fn="$2"; if mutate lib "$label" "$3" "$4"; then red_with "$label" "$SUT" "$MUTANT" "$fn"; fi; }

# Instrument self-check: a mutation that cannot change behaviour (a comment) must be reported SURVIVED, and one that does not land at
# all must be refused. A `red_with` that always reported RED, or a landing guard that was removed, would fail here.
if _mutate_try sut comment_only 'THE ONE RULE (Guard 1)' 'THE ONE RULE (Guard 1) .'; then
  n="$(mutant_fails core_cases "$MUTANT" "$LIB")"
  ok_if "instrument: a comment-only mutant is reported SURVIVED (0 failing expectations, got $n)" "[[ '$n' -eq 0 ]]"
else fail "instrument: the comment-only mutant did not land"; fi
ok_if "instrument: a mutation whose anchor is absent is refused, and an identical replacement is refused" "! _mutate_try sut absent 'THIS ANCHOR IS NOT IN THE FILE' x && ! _mutate_try sut noop 'set -u' 'set -u'"

# Rows 1-6 (core cases)
mut_lib 1_any_result_is_pass core_cases 'case "$SBV_VERDICT" in' 'SBV_VERDICT=pass; SBV_COVERAGE=sdk_wrapper_shim_prodtuple; case "$SBV_VERDICT" in'
mut_sut 2_ping_on_noping core_cases 'no_ping) :' 'no_ping) ping_heartbeat ok'
mut_lib 3_timeout_before_dispatch case_timeouts 'SBV_VERDICT="smoke_infra_error"; SBV_REASON="host_timeout_before_dispatch' 'SBV_VERDICT="sdk_bash_smoke_failed"; SBV_REASON="host_timeout_before_dispatch'
mut_sut 4_restart_is_fail core_cases 'finish no_ping container_restarted' 'finish fail container_restarted'
mut_sut 5_ping_before_verdict core_cases 'nonce="$(od -An -N16' 'ping_heartbeat ok; nonce="$(od -An -N16'
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

# Rows E, F, G: a raw heartbeat call on a no_ping path (the ping chokepoint bypassed). Behavioural (the stub curl is reached) AND static.
mut_sut E_raw_curl_on_deploy_lock case_noping_curl '0) finish no_ping deploy_lock' '0) _hb_curl "$URL"; finish no_ping deploy_lock'
if mutate sut E2_static_scan '0) finish no_ping deploy_lock' '0) _hb_curl "$URL"; finish no_ping deploy_lock'; then
  ok_if "mutation E: the static scan also goes RED (a third _hb_curl call site, outside ping_heartbeat)" "[[ \"\$(guard1_static '$MUTANT' '$LIB')\" != '$G1_EXPECT' ]]"
fi
mut_sut F_raw_curl_on_restart case_noping_curl 'finish no_ping container_restarted' '_hb_curl "$URL"; finish no_ping container_restarted'
mut_sut G_raw_fail_on_memory case_noping_curl 'finish no_ping memory_pressure ' '_hb_curl "${URL%/}/fail"; finish no_ping memory_pressure '
if _mutate_try lib lib_pings 'sdk_bash_map_result() {' '_hb_curl "$URL"; sdk_bash_map_result() {'; then
  ok_if "mutation: a heartbeat call added to the verdict lib turns the static scan RED" "[[ \"\$(guard1_static '$SUT' '$MUTANT')\" != '$G1_EXPECT' ]]"
else fail "mutation lib_pings did NOT apply"; fi
if _mutate_try sut trap_ping "trap '[ \"\$ERRF\" = /dev/null ] || rm -f \"\$ERRF\" 2>/dev/null' EXIT" "trap '[ -n \"\${URL:-}\" ] && _hb_curl \"\$URL\"' EXIT"; then
  red_with "H_ping_from_an_EXIT_trap" "$MUTANT" "$LIB" case_pass_curl_zero
else fail "mutation H_ping_from_an_EXIT_trap did NOT apply"; fi

# Unit: any extra Exec*/OnFailure directive is a way to run something else (a curl) outside the script
for extra in 'ExecStopPost=/bin/true' 'ExecStartPost=/bin/true' 'OnFailure=x.service' 'ExecStartPre=/bin/true'; do
  svc_m="$MUT/m.service.${extra%%=*}"; { cat "$SERVICE"; printf '%s\n' "$extra"; } > "$svc_m"
  ok_if "mutation: a unit with an added $extra fails the unit shape row" "! unit_ok '$svc_m' '$TIMER'"
done
if _mutate_try service timeout_low 'TimeoutStartSec=420' 'TimeoutStartSec=330'; then ok_if "mutation: TimeoutStartSec=330 (below the caps plus doppler) fails the unit shape row" "! unit_ok '$MUTANT' '$TIMER'"; else fail "mutation timeout_low did NOT apply"; fi
if _mutate_try service no_p 'doppler run --project soleur --config prd -- /bin/bash -p ' 'doppler run --project soleur --config prd -- /bin/bash '; then ok_if "mutation: ExecStart without bash -p fails the unit shape row" "! unit_ok '$MUTANT' '$TIMER'"; else fail "mutation no_p did NOT apply"; fi
if _mutate_try service no_umask 'UMask=0077' 'UMask=0022'; then ok_if "mutation: UMask=0022 fails the unit shape row" "! unit_ok '$MUTANT' '$TIMER'"; else fail "mutation no_umask did NOT apply"; fi
if _mutate_try timer no_jitter 'RandomizedDelaySec=60' 'RandomizedDelaySec=0'; then ok_if "mutation: RandomizedDelaySec=0 fails the unit shape row" "! unit_ok '$SERVICE' '$MUTANT'"; else fail "mutation no_jitter did NOT apply"; fi

# A1 selector
mut_sut A1_unresolved_sentinel_dropped case_selector '(base|unixdeny|unresolved)$' '(base|unixdeny)$'
mut_sut A1_mismatch_check_dropped case_selector 'if [ "$_psel" != "$SEL" ] &&' 'if false &&'
# A2 memory
mut_sut A2_host_gate_dropped case_mem 'if [ "$avail" -lt "$HOST_MEM_MIN_MB" ]; then' 'if false; then'
mut_sut A2_resample_dropped case_mem '_mem_gate "before the probe"' ':'
mut_sut A2_threshold_85 case_mem 'SOLEUR_WBS_MEM_PCT_MAX:-70' 'SOLEUR_WBS_MEM_PCT_MAX:-85'
mut_sut A2_stats_rc_after_parse case_mem '[ "$rc" -eq 0 ] || finish no_ping infra_error "docker_stats_rc_$rc: $(_err_tail)"' ':'
mut_sut A2_no_oom_wrapper case_pass_shape "/bin/sh -c 'echo 1000 > /proc/self/oom_score_adj 2>/dev/null; exec \"\$@\"' sh \\" ' \\'
mut_sut A10_home_dropped case_pass_shape 'HOME="$HOME_C" ' ''
mut_sut A10_app_dropped case_pass_shape 'APP=/app ' ''
mut_sut A10_path_dropped case_pass_shape 'PATH=/usr/local/bin:/usr/bin:/bin HOME=' 'HOME='
mut_sut A10_inner_timeout case_pass_shape 'INNER_TIMEOUT=130' 'INNER_TIMEOUT=200'
mut_sut A10_inspect_format case_pass_shape "{{.State.Running}} {{.Id}} {{.State.StartedAt}}" "{{.State.Running}} {{.Id}}"
mut_sut A10_preexec_body case_pass_shape 'test -f "$1" && test -f "$2" || exit 66;' 'test -f "$1" || exit 66;'
# A6 lock
mut_sut A6_lock_recheck_before_dropped case_lock '_lock_gate "before the probe"' ':'
mut_sut A6_lock_recheck_after_dropped case_lock '_lock_gate "after the probe"' ':'
mut_sut A6_inode_only case_lock 'if ($i == want) found = 1' 'if ($i ~ (":" substr(want, 7) "$")) found = 1'
mut_sut A6_stopped_in_place case_restart_stopped '[ "$C_RUNNING" != true ] || [ "$C_ID" != "$BASE_ID" ]' '[ "$C_ID" != "$BASE_ID" ]'
# A5 keys and URLs
mut_sut A5_key_check_off case_keys 'if ! _key_ok "${WEB_BASH_SYNTHETIC_URL_KEY:-}"; then' 'if false; then'
mut_sut A5_key_body_clause_dropped case_keys 'case "$1" in *[!A-Z0-9_]*) return 1 ;; esac;' ':;'
mut_sut A5_key_prefix_dropped case_keys 'WEB_BASH_SYNTHETIC_URL_?*) ;; *) return 1 ;; esac' '*) ;; esac'
mut_sut A5_host_pin_dropped case_urls "local LC_ALL=C pre='https://uptime.betterstack.com/api/v1/heartbeat/'" "local LC_ALL=C pre='https://'"
mut_sut A5_query_allowed case_urls '*[!A-Za-z0-9_/-]*|*//*|/*) return 1 ;; esac' '*//*|/*) return 1 ;; esac'
mut_sut A5_fail_suffix_slash case_urls 'target="${URL%/}/fail"' 'target="${URL}/fail"'
mut_sut A5_curl_f_dropped case_urls '-gfsS -m 10' '-gsS -m 10'
mut_sut A5_curl_timeout_dropped case_urls '-gfsS -m 10' '-gfsS'
mut_sut A5_curl_g_dropped case_urls '-gfsS -m 10' '-fsS -m 10'
# P3 hygiene
mut_sut P3_inspect_rc1_is_down case_inspect 'if [ "$_rc" -eq 1 ] && grep -qiE' 'if [ "$_rc" -eq 1 ] && true || grep -qiE'
mut_sut P3_counter_no_base10 case_counter 'n=$((10#$prev + 1))' 'n=$((prev + 1))'
mut_sut P3_fail_increments case_counter 'if [ "$verdict" = no_ping ]; then n=' 'if [ "$verdict" != pass ]; then n='
mut_sut P3_counter_cap_dropped case_counter '[ "${#prev}" -le 6 ] || prev=0' ':'
mut_sut P3_counter_digit_guard_dropped case_counter "case \"\$prev\" in ''|*[!0-9]*) prev=0 ;; esac" ':'
mut_sut P3_scrub_allowlist_dropped case_journal "tr -cd 'A-Za-z0-9._:/ =-' | cut -c1-120" 'cut -c1-120'
mut_sut P3_scrub_cut_dropped case_journal "tr -cd 'A-Za-z0-9._:/ =-' | cut -c1-120" "tr -cd 'A-Za-z0-9._:/ =-'"
mut_sut P3_scrub_env_values_dropped case_journal 'if [ "${#v}" -ge 8 ]; then' 'if false; then'
mut_sut P3_scrub_shapes_dropped case_journal 's/dp\.[a-z]{2,}\.[A-Za-z0-9._-]*/dp.REDACTED/g' 's/ZZZZ/ZZZZ/g'
# The masks_missing guard line, as written in the SUT (the empty pattern is spelled with a quote pair inside single quotes).
MASKS_M_CASE='case "$_m" in [0-4]) MASKS="$_m" ;; '"''"'|*[!0-9]*) MASKS="-" ;; *) MASKS="5+" ;; esac'
mut_sut P3_masks_digit_guard_dropped case_journal "$MASKS_M_CASE" 'MASKS="$_m"'
mut_sut P3_masks_missing_guard_loosened case_masks_missing "$MASKS_M_CASE" 'case "$_m" in '"''"'|*[!0-9]*) MASKS="-" ;; *) MASKS="$_m" ;; esac'
# The over-range count read as unknown (`-`): the pre-fix shape, where 5 or 12 kept the full tuple.
mut_sut P4_masks_overrange_is_unknown case_masks_missing "$MASKS_M_CASE" 'case "$_m" in [0-4]) MASKS="$_m" ;; *) MASKS="-" ;; esac'
# The over-range count journaled but not downgraded.
mut_sut P4_masks_overrange_keeps_full_tuple case_masks_missing 'case "$MASKS" in -|0) : ;; *) COV=prodtuple_partial ;; esac' 'case "$MASKS" in -|0|5+) : ;; *) COV=prodtuple_partial ;; esac'
mut_sut P3_masks_created_guard_dropped case_masks_created 'case "$_c" in [0-4]) MCREATED="$_c" ;; *) MCREATED="-" ;; esac' 'MCREATED="$_c"'
mut_sut P3_masks_note_enum_dropped case_masks_note 'case "$_n" in uid_mismatch|pid1_unreadable|pid1_env_unreadable|home_mismatch|env_divergence) MNOTE="$_n" ;; *) MNOTE="-" ;; esac' 'MNOTE="$_n"'
mut_sut P3_masks_note_enum_prefix_match case_masks_note 'case "$_n" in uid_mismatch|pid1_unreadable|pid1_env_unreadable|home_mismatch|env_divergence) MNOTE="$_n" ;;' 'case "$_n" in uid_mismatch*|pid1_unreadable*|pid1_env_unreadable*|home_mismatch*|env_divergence*) MNOTE="$_n" ;;'
mut_sut P3_umask_dropped case_umask $'\numask 077\n' $'\n'
# A rc 124 label: the cap that fired, not always the host one
mut_sut P3_cap_label_always_host case_timeouts 'if [ "$_elapsed" -ge "$PROBE_TIMEOUT" ]; then _cap="$PROBE_TIMEOUT"; else _cap="$INNER_TIMEOUT"; fi' '_cap="$PROBE_TIMEOUT"'

# A8: every seam, one mutant each: the name stays readable by the script but is no longer unset when the flag is absent
CUR_SEAM=""
case_seam_cur() { case_seam "$CUR_SEAM" "$1" "$2"; }
unset_mutant() {  # <seam> -> sets MUTANT: the SUT with that name removed from the unset statement ONLY (its reads are untouched)
  local out="$MUT/m.sut.unset.$1"
  SEAM="$1" SRC="$SUT" OUT="$out" python3 - <<'PY' || return 1
import os, re, sys
s = open(os.environ["SRC"]).read()
head = 'if [ "${1:-}" != "--fixture-seams" ]; then\n'
a = s.index(head) + len(head)
b = s.index("\nfi\n", a)
block = s[a:b]
seam = os.environ["SEAM"]
new = re.sub(r"(?<![A-Z_])" + re.escape(seam) + r"(?![A-Z_])", "", block, count=1)
if new == block:
    sys.exit(1)
open(os.environ["OUT"], "w").write(s[:a] + new + s[b:])
PY
  if cmp -s "$SUT" "$out"; then return 1; fi
  MUTANT="$out"
}
for CUR_SEAM in $unset_seams; do
  if unset_mutant "$CUR_SEAM"; then red_with "G_seam_left_armed_${CUR_SEAM#SOLEUR_WBS_}" "$MUTANT" "$LIB" case_seam_cur
  else fail "mutation G_seam_left_armed_$CUR_SEAM did NOT apply"; fi
done

ok_if "the pristine SUT/lib copies still equal the files under test (no mutation leaked into the tree)" "cmp -s '$SUT' '$PRISTINE_SUT' && cmp -s '$LIB' '$PRISTINE_LIB'"

# Assertion floor (anti-vacuity): reported with printf + exit, never through the helpers it backstops.
FLOOR=381
total=$((passes + fails))
if [[ "$total" -lt "$FLOOR" ]]; then printf 'FAIL: only %s assertions ran (floor %s): the suite lost coverage\n' "$total" "$FLOOR"; exit 1; fi
echo "=== $passes passed, $fails failed ($total assertions) ==="
[[ "$fails" -eq 0 ]]

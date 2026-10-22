#!/usr/bin/env bash
set -u
# Refuse to run under xtrace (#7797): this script resolves a secret heartbeat URL (the variable named by
# WEB_BASH_SYNTHETIC_URL_KEY), so tracing would print it into the journal that Vector ships off-box. Unconditional on
# purpose: it tests the STATE (`$-`), so `bash -x`, SHELLOPTS=xtrace and a BASH_ENV `set -x` are all caught. The unit's ExecStart
# runs this script under `doppler run` and expands nothing (#9639): the URL is resolved BELOW, after this refusal.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
# --- Runtime Bash synthetic (follow-up to #10445 via #10455; ADR-079 addendum 2026-10-20) ----------------------------------------
# The deploy-time SDK Bash smoke only runs at deploy, so a sandbox that breaks BETWEEN deploys was invisible: the 2026-10-06..16
# outage lasted ten days. Every 15 minutes this runs ONE real wrapped Bash call, end to end (the real Agent SDK, the shipped
# bwrap shim, the production sandbox config), inside the RUNNING web container, and pings this host's own Better Stack
# heartbeat ONLY on a verified pass. Absence of the ping (a stopped timer, a dark host, a failed unit, a broken Doppler token)
# alarms through the heartbeat's grace; a verified FAIL pings <url>/fail for an immediate incident.
#
#   pass     the per-run NONCE came back in the real tool_result (verified inside the probe) under the shim-and-wrapper tuple
#            -> ping the heartbeat.
#   fail     Bash was dispatched and no verified nonce came back (an error result, no nonce, a hang, a death after dispatch)
#            -> ping <url>/fail, exit 3 (the unit shows failed; the timer keeps firing).
#   no_ping  the run could not make a claim either way (reason= says why) -> NO ping; the beat's grace is what pages if this
#            persists. consecutive_no_ping= in the journal line tells a long deploy lock from a dead host.
#
# THE ONE RULE (Guard 1): every exit flows through finish(), and finish() is the only caller of ping_heartbeat(), AFTER the
# verdict is computed. A no_ping run never reaches the heartbeat; a container swapped mid-run is never a fail.
#
# THE MAPPING from "what docker exec returned" to pass/fail/skip is NOT here: it is sdk-bash-verdict.sh (next to this file), sourced by this
# script AND by ci-deploy.sh's deploy-time smoke, so the two cannot drift.
#
# SAFETY toward the shared production container (this execs into the container that serves tenants): the run SKIPS
#   - while a deploy holds /var/lock/ci-deploy.lock (read from /proc/locks, never by taking the lock: a ci-deploy `flock -n`
#     racing even a millisecond of ours would fail a real deploy),
#   - when the container is not running, or above the memory threshold (MEM_PCT_MAX),
#   - and DISCARDS its own verdict when the container id or start time changed during the run (a deploy swap kills the probe
#     mid-run; that is a skip, never a fail).
# The probe exec is `env -i` with an explicit allowlist and a decoy key (the SDK child copies process.env), bounded in-container
# by `timeout -k` (120 s probe cap < 130 s here < 150 s host cap) so a hang cannot leave orphan node trees behind a killed
# `docker exec` client. No `-u` (the container's own user; a root pass would not prove uid 1001, recorded in the ADR addendum).
# The probe writes only its own scratch dirs (runtime mode creates no masked dir); this script writes only STATE_DIR.
#
# SEAMS (SOLEUR_WBS_*) exist for web-bash-synthetic.test.sh and are NEVER set by the unit. They are honored ONLY when the script is
# started with `--fixture-seams` (the unit passes no argument): otherwise every one is unset below, so a stray secret of that name
# in the shared soleur/prd config that `doppler run` injects can neither redirect PATH, the sourced verdict lib or the container,
# nor silence the ping. (The script runs as root with the whole prd root in its environment: doppler-injection-bound.test.sh.)
if [ "${1:-}" != "--fixture-seams" ]; then
  unset SOLEUR_WBS_PATH_PREFIX SOLEUR_WBS_CONTAINER SOLEUR_WBS_STATE_DIR SOLEUR_WBS_LOCK_FILE SOLEUR_WBS_PROC_LOCKS \
    SOLEUR_WBS_VERDICT_LIB SOLEUR_WBS_PING_LOG SOLEUR_WBS_PROBE_TIMEOUT SOLEUR_WBS_MEM_PCT_MAX
fi

PATH="${SOLEUR_WBS_PATH_PREFIX:+$SOLEUR_WBS_PATH_PREFIX:}/usr/sbin:/usr/bin:/bin"
export PATH

CTR="${SOLEUR_WBS_CONTAINER:-soleur-web-platform}"
PROBE_PATH="/app/infra/lib/sdk-bash-probe.mjs"
RESOLVER_PATH="/app/infra/lib/resolve-sandbox-selector.mjs"
STATE_DIR="${SOLEUR_WBS_STATE_DIR:-/run/web-bash-synthetic}"
LOCK_FILE="${SOLEUR_WBS_LOCK_FILE:-/var/lock/ci-deploy.lock}"
PROC_LOCKS="${SOLEUR_WBS_PROC_LOCKS:-/proc/locks}"

_posint() { case "${1:-}" in ''|0*|*[!0-9]*) return 1 ;; esac; }
# Container memory above this percent (docker stats MemPerc) skips the run: the synthetic must not add pressure to a container
# that already has it.
MEM_PCT_MAX="${SOLEUR_WBS_MEM_PCT_MAX:-85}"; _posint "$MEM_PCT_MAX" || MEM_PCT_MAX=85
# Host cap on the probe `docker exec`, above the in-container cap (INNER_TIMEOUT), above the probe's own 120 s internal cap.
PROBE_TIMEOUT="${SOLEUR_WBS_PROBE_TIMEOUT:-150}"; _posint "$PROBE_TIMEOUT" || PROBE_TIMEOUT=150
INNER_TIMEOUT=130
PREEXEC_TIMEOUT=20
INSPECT_TIMEOUT=20
STATS_TIMEOUT=30
RESOLVER_HOST_TIMEOUT=30

SEL="-"; COV="-"; MASKS="-"
mkdir -p "$STATE_DIR" 2>/dev/null || true
ERRF="$STATE_DIR/.docker-err"
[ -w "$STATE_DIR" ] || ERRF=/dev/null
trap '[ "$ERRF" = /dev/null ] || rm -f "$ERRF" 2>/dev/null' EXIT

# --- the heartbeat URL (a credential) -------------------------------------------------------------------------------------------
# The NAME comes from an env file, and `${!name}` evaluates array subscripts and command substitutions inside `name`, so it is
# judged first: an upper-case identifier or nothing (LC_ALL=C pins ASCII ranges). No fallback to a variable of any other name.
_key_ok() { local LC_ALL=C; case "${1:-}" in ''|[!A-Z]*|*[!A-Z0-9_]*) return 1 ;; esac; }
# The URL's PATH is the secret, so it rides curl's stdin config (`--config -`), never argv (/proc/<pid>/cmdline is world-readable;
# ADR-280, #9757). Judged before any request, with no trimming: https:// only, and only bytes that cannot add a config directive.
_hb_url_ok() {
  local LC_ALL=C
  case "$1" in https://*) ;; *) return 1 ;; esac
  case "${1#https://}" in ''|*[!A-Za-z0-9._~:/?\&=%+-]*) return 1 ;; esac
}
_hb_curl() { curl --disable --noproxy '*' -gfsS -m 10 -o /dev/null --config - 2>/dev/null < <(printf 'url = "%s"\n' "$1"); }

# The ONE heartbeat chokepoint. Reached only from finish().
ping_heartbeat() {  # <ok|fail>
  local target="$URL"
  if [ -n "${SOLEUR_WBS_PING_LOG:-}" ]; then
    printf 'PING %s\n' "$1" >> "$SOLEUR_WBS_PING_LOG"
    return 0
  fi
  [ "$1" = fail ] && target="${URL%/}/fail"
  _hb_curl "$target" || _hb_curl "$target" || echo "[wbs] WARN: heartbeat ping FAILED ($1, url_present=yes)" >&2
}

# The ONE exit. Computes the counter, journals the verdict, THEN pings (Guard 1: never before the verdict exists).
finish() {  # <pass|fail|no_ping> <reason> [detail]
  local verdict="$1" reason="$2" detail="${3:-}" n=0 prev=0 cnt="$STATE_DIR/consecutive_no_ping"
  detail="$(printf '%s' "$detail" | LC_ALL=C tr -cd 'A-Za-z0-9._:/ =-' | cut -c1-120)"
  if [ -r "$cnt" ]; then prev="$(cat "$cnt" 2>/dev/null || echo 0)"; fi
  case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
  [ "${#prev}" -le 6 ] || prev=0
  if [ "$verdict" = no_ping ]; then n=$((10#$prev + 1)); fi
  if [ -w "$STATE_DIR" ]; then printf '%s\n' "$n" > "$cnt" 2>/dev/null || true; fi
  echo "SOLEUR_WEB_BASH_SYNTHETIC verdict=$verdict reason=$reason selector=$SEL coverage=$COV masks_missing=$MASKS consecutive_no_ping=$n detail=${detail:--}" >&2
  case "$verdict" in
    pass) ping_heartbeat ok ;;
    fail) ping_heartbeat fail ;;
    no_ping) : ;;
  esac
  [ "$verdict" = fail ] && exit 3
  exit 0
}

URL=""
if ! _key_ok "${WEB_BASH_SYNTHETIC_URL_KEY:-}"; then
  echo "[wbs] WARN: WEB_BASH_SYNTHETIC_URL_KEY is unset or is not an upper-case variable name (the value is not shown); the heartbeat URL cannot be resolved." >&2
  finish no_ping no_heartbeat_url "key name unset or malformed"
fi
URL="${!WEB_BASH_SYNTHETIC_URL_KEY:-}"
if [ -z "$URL" ]; then
  finish no_ping no_heartbeat_url "url unset"
fi
if ! _hb_url_ok "$URL"; then
  # var=WEB_BASH_SYNTHETIC_URL is a stable decode label (the runbook keys on it), not the name of a variable this script reads.
  reason=token_shape; case "$URL" in *[[:cntrl:]]*) reason=control_char ;; esac
  echo "SOLEUR_CREDENTIAL_REFUSED script=web-bash-synthetic reason=$reason var=WEB_BASH_SYNTHETIC_URL" >&2
  finish no_ping no_heartbeat_url "url refused"
fi

# --- the shared verdict mapping ------------------------------------------------------------------------------------------------
VLIB="${SOLEUR_WBS_VERDICT_LIB:-}"
if [ -z "$VLIB" ]; then
  for _c in "$(dirname "${BASH_SOURCE[0]}")/sdk-bash-verdict.sh" /usr/local/bin/sdk-bash-verdict.sh; do
    if [ -r "$_c" ]; then VLIB="$_c"; break; fi
  done
fi
if [ -n "$VLIB" ] && [ -r "$VLIB" ]; then
  # shellcheck source=sdk-bash-verdict.sh
  . "$VLIB" || true
fi
if ! declare -F sdk_bash_map_result >/dev/null 2>&1; then
  finish no_ping infra_error "verdict_lib_absent"
fi

# --- helpers --------------------------------------------------------------------------------------------------------------------
# A scrubbed, capped one-liner from docker's stderr (it rides the journal): the allowlist drops everything else.
_err_tail() { head -n 1 "$ERRF" 2>/dev/null | LC_ALL=C tr -cd 'A-Za-z0-9._:/ =-' | cut -c1-120; }

# 0 = a deploy holds the lock, 1 = it does not, 2 = cannot tell. Reads /proc/locks for the lock file's inode; never takes the lock.
_deploy_lock_held() {
  local ino
  [ -e "$LOCK_FILE" ] || return 1
  ino="$(stat -c %i "$LOCK_FILE" 2>/dev/null)" || return 2
  case "$ino" in ''|*[!0-9]*) return 2 ;; esac
  [ -r "$PROC_LOCKS" ] || return 2
  local rc=0
  awk -v ino="$ino" '{ for (i = 5; i <= NF; i++) { n = split($i, a, ":"); if (n == 3 && a[3] == ino) found = 1 } } END { exit found ? 0 : 1 }' "$PROC_LOCKS" 2>/dev/null || rc=$?
  case "$rc" in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
}

# Sets C_RUNNING / C_ID / C_START; returns the docker rc.
_inspect() {
  local out rc=0
  out="$(timeout "$INSPECT_TIMEOUT" docker inspect -f '{{.State.Running}} {{.Id}} {{.State.StartedAt}}' "$CTR" 2>"$ERRF")" || rc=$?
  C_RUNNING=""; C_ID=""; C_START=""
  # shellcheck disable=SC2034  # C_ID/C_START are read by the caller
  read -r C_RUNNING C_ID C_START <<<"$out"
  return "$rc"
}

# --- 1. skip while a deploy holds the lock --------------------------------------------------------------------------------------
_lock_rc=0; _deploy_lock_held || _lock_rc=$?
case "$_lock_rc" in
  0) finish no_ping deploy_lock "ci-deploy lock held" ;;
  1) : ;;
  *) finish no_ping infra_error "deploy lock state unreadable" ;;
esac

# --- 2. the container must be up ------------------------------------------------------------------------------------------------
_rc=0; _inspect || _rc=$?
if [ "$_rc" -eq 1 ] || { [ "$_rc" -eq 0 ] && [ "$C_RUNNING" != true ]; }; then
  finish no_ping container_down "container not running"
elif [ "$_rc" -ne 0 ]; then
  finish no_ping infra_error "docker_inspect_rc_$_rc: $(_err_tail)"
fi
case "$C_ID" in ''|*[!0-9a-f]*) finish no_ping infra_error "container id unreadable" ;; esac
[ "${#C_ID}" -eq 64 ] || finish no_ping infra_error "container id unreadable"
[ -n "$C_START" ] || finish no_ping infra_error "container start time unreadable"
BASE_ID="$C_ID"; BASE_START="$C_START"

# --- 3. memory pressure ---------------------------------------------------------------------------------------------------------
_rc=0; _mem="$(timeout "$STATS_TIMEOUT" docker stats --no-stream --format '{{.MemPerc}}' "$CTR" 2>"$ERRF")" || _rc=$?
_mem="${_mem%\%}"
case "$_mem" in
  ''|*[!0-9.]*|.*|*.*.*) finish no_ping infra_error "memory reading unparseable" ;;
esac
[ "$_rc" -eq 0 ] || finish no_ping infra_error "docker_stats_rc_$_rc: $(_err_tail)"
if [ "${_mem%%.*}" -ge "$MEM_PCT_MAX" ]; then
  finish no_ping memory_pressure "container memory ${_mem}% >= ${MEM_PCT_MAX}%"
fi

# --- 4. pre-exec: probe and resolver present in this image, and the container's real HOME ---------------------------------------
# rc 66 is the ONLY "absent" answer (an image that predates the probe or the resolver bundle).
_rc=0
HOME_C="$(timeout "$PREEXEC_TIMEOUT" docker exec "$CTR" /bin/sh -c 'test -f "$1" && test -f "$2" || exit 66; printf %s "$HOME"' sh "$PROBE_PATH" "$RESOLVER_PATH" 2>"$ERRF")" || _rc=$?
case "$_rc" in
  0) : ;;
  66) finish no_ping probe_absent "probe or resolver not in the running image" ;;
  124) finish no_ping host_timeout_before_dispatch "pre-exec" ;;
  *) finish no_ping infra_error "preflight_rc_$_rc: $(_err_tail)" ;;
esac
if ! [[ "$HOME_C" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
  finish no_ping infra_error "container_home_unresolved"
fi

# --- 5. which seccomp artifact would a no-egress session get RIGHT NOW? ----------------------------------------------------------
# Asked of the dispatcher's own resolver (CTO ruling), in the container's FULL env so the live flag read works; never the env
# mirror. The result rides a sentinel line because the resolver's logger may write to stdout too.
_rc=0
_sel_out="$(timeout "$RESOLVER_HOST_TIMEOUT" docker exec "$CTR" timeout -k 5 20 node "$RESOLVER_PATH" 2>"$ERRF")" || _rc=$?
case "$_rc" in
  0) : ;;
  124) finish no_ping host_timeout_before_dispatch "resolver" ;;
  *) finish no_ping infra_error "resolver_rc_$_rc: $(_err_tail)" ;;
esac
_sel_lines="$(printf '%s\n' "$_sel_out" | { grep -aE '^SOLEUR_SELECTOR=(base|unixdeny)$' || true; })"
case "$_sel_lines" in
  SOLEUR_SELECTOR=base) SEL=base ;;
  SOLEUR_SELECTOR=unixdeny) SEL=unixdeny ;;
  *) finish no_ping infra_error "selector_unresolved" ;;
esac

# --- 6. the run -----------------------------------------------------------------------------------------------------------------
# A nonce /dev/urandom could not supply is an infra error, never a $RANDOM-derived one: the nonce is the proof the tool_result
# came from THIS run.
nonce="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || true)"
if ! [[ "$nonce" =~ ^[0-9a-f]{32}$ ]]; then
  finish no_ping infra_error "nonce_unavailable"
fi
_rc=0
_out="$(timeout -k 5 "$PROBE_TIMEOUT" docker exec -w /app "$CTR" /usr/bin/env -i \
  PATH=/usr/local/bin:/usr/bin:/bin HOME="$HOME_C" APP=/app SMOKE=1 SDK_BASH_PROBE_RUNTIME=1 SDK_BASH_PROBE_SELECTOR="$SEL" \
  NONCE="$nonce" ANTHROPIC_API_KEY=decoy-api-key-sentinel \
  timeout -k 5 "$INNER_TIMEOUT" node "$PROBE_PATH" 2>"$ERRF")" || _rc=$?
_docker_err="$(_err_tail)"

# --- 7. a container swapped during the run voids the verdict ---------------------------------------------------------------------
_irc=0; _inspect || _irc=$?
if [ "$_irc" -ne 0 ] || [ "$C_RUNNING" != true ] || [ "$C_ID" != "$BASE_ID" ] || [ "$C_START" != "$BASE_START" ]; then
  finish no_ping container_restarted "container replaced or stopped during the run"
fi

# --- 8. map and finish ----------------------------------------------------------------------------------------------------------
sdk_bash_map_result "$_rc" "$_out" "$_docker_err" "$PROBE_TIMEOUT"
COV="${SBV_COVERAGE:--}"; [ -n "$COV" ] || COV="-"
_line="$(printf '%s\n' "$_out" | { grep -a '^SDK_BASH_RESULT ' || true; } | tail -n 1)"
_m="$(printf '%s' "${_line#SDK_BASH_RESULT }" | jq -r '(.masks_missing // "-") | tostring' 2>/dev/null || echo -)"
case "$_m" in ''|*[!0-9]*) MASKS="-" ;; *) MASKS="$_m" ;; esac
case "$SBV_VERDICT" in
  pass) finish pass ok ;;
  sdk_bash_smoke_failed) finish fail sdk_bash_smoke_failed "$SBV_REASON" ;;
  *)
    case "$SBV_REASON" in
      host_timeout_before_dispatch*) finish no_ping host_timeout_before_dispatch "$SBV_REASON" ;;
      probe_absent*) finish no_ping probe_absent "$SBV_REASON" ;;
      *) finish no_ping infra_error "$SBV_REASON" ;;
    esac ;;
esac

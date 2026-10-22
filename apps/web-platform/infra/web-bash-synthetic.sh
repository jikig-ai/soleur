#!/usr/bin/env bash
set -u
# Refuse to run under xtrace (#7797): this script resolves a secret heartbeat URL (the variable named by
# WEB_BASH_SYNTHETIC_URL_KEY), so tracing would print it into the journal that Vector ships off-box. Unconditional on
# purpose: it tests the STATE (`$-`), so `bash -x`, SHELLOPTS=xtrace and a BASH_ENV `set -x` are all caught. The unit's ExecStart
# runs this script under `doppler run` and expands nothing (#9639): the URL is resolved BELOW, after this refusal.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
# --- Runtime Bash synthetic (follow-up to #10445 via #10455; ADR-079 "Addendum — 2026-10-22 (#10455 b)") --------------------------
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
#     racing even a millisecond of ours would fail a real deploy); re-read right before the probe exec and again after it,
#   - when the container is not running, above the container memory threshold (MEM_PCT_MAX), or the HOST is short of memory
#     (MemAvailable below HOST_MEM_MIN_MB: the container's cgroup cap is the whole host on a 4 GB web host); both memory
#     gates are sampled again immediately before the probe exec,
#   - and DISCARDS its own verdict when the container id or start time changed during the run (a deploy swap kills the probe
#     mid-run; that is a skip, never a fail).
# Measured cost of ONE run (perf review of #10697, recorded in the ADR addendum; node 22 image, not re-measured per run): the probe
# tree (node, the SDK's native claude binary, bwrap and its helpers) peaks at 172-293 MB of cgroup memory for about 2 s, the
# resolver node adds about 108 MB RSS earlier in the run (never concurrent). The thresholds below leave at least 3x that:
# 30% of the 4096m cap is about 1.2 GB.
# The probe exec is `env -i` with an explicit allowlist and a decoy key (the SDK child copies process.env), bounded in-container
# by `timeout -k` (120 s probe cap < 130 s here < 150 s host cap) so a hang cannot leave orphan node trees behind a killed
# `docker exec` client. The tree runs at oom_score_adj=1000, so the OOM killer picks the probe, not the Next server that serves
# tenants. No `-u` (the container's own user; a root pass would not prove uid 1001, recorded in the ADR addendum).
# The probe writes only its own scratch dirs (runtime mode creates no masked dir, and the SDK CLI's temp base is inside its scratch
# dir; it sweeps its own day-old leftovers); this script writes only STATE_DIR (mode 0700, umask 077).
#
# SEAMS (SOLEUR_WBS_*) exist for web-bash-synthetic.test.sh and are NEVER set by the unit. They are honored ONLY when the script is
# started with `--fixture-seams` (the unit passes no argument): otherwise every one is unset below, so a stray secret of that name
# in the shared soleur/prd config that `doppler run` injects can neither redirect PATH, the sourced verdict lib or the container,
# nor silence the ping. (The script runs as root with the whole prd root in its environment: doppler-injection-bound.test.sh.)
if [ "${1:-}" != "--fixture-seams" ]; then
  unset SOLEUR_WBS_PATH_PREFIX SOLEUR_WBS_CONTAINER SOLEUR_WBS_STATE_DIR SOLEUR_WBS_LOCK_FILE SOLEUR_WBS_PROC_LOCKS \
    SOLEUR_WBS_VERDICT_LIB SOLEUR_WBS_PING_LOG SOLEUR_WBS_PROBE_TIMEOUT SOLEUR_WBS_MEM_PCT_MAX SOLEUR_WBS_MEMINFO
fi
# Names the docker client and curl read from the ENVIRONMENT (a stray secret of that name in the injected prd root would steer the
# exec to another daemon, or the ping to another CA, and could fabricate a pass), and the files bash itself would source. The unit
# starts this script as `bash -p`, which already ignores BASH_ENV / ENV / SHELLOPTS / exported functions; this is the same list for
# a launch that is not.
unset BASH_ENV ENV DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG DOCKER_CERT_PATH DOCKER_TLS_VERIFY CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR
umask 077

PATH="${SOLEUR_WBS_PATH_PREFIX:+$SOLEUR_WBS_PATH_PREFIX:}/usr/sbin:/usr/bin:/bin"
export PATH

CTR="${SOLEUR_WBS_CONTAINER:-soleur-web-platform}"
PROBE_PATH="/app/infra/lib/sdk-bash-probe.mjs"
RESOLVER_PATH="/app/infra/lib/resolve-sandbox-selector.mjs"
STATE_DIR="${SOLEUR_WBS_STATE_DIR:-/run/web-bash-synthetic}"
LOCK_FILE="${SOLEUR_WBS_LOCK_FILE:-/var/lock/ci-deploy.lock}"
PROC_LOCKS="${SOLEUR_WBS_PROC_LOCKS:-/proc/locks}"
MEMINFO="${SOLEUR_WBS_MEMINFO:-/proc/meminfo}"

_posint() { case "${1:-}" in ''|0*|*[!0-9]*) return 1 ;; esac; }
# Container memory at or above this percent (docker stats MemPerc) skips the run: the synthetic must not add pressure to a container
# that already has it. 70% of the 4096m cap leaves about 1.2 GB, 3x the measured peak of the tree this run adds (header).
MEM_PCT_MAX="${SOLEUR_WBS_MEM_PCT_MAX:-70}"; _posint "$MEM_PCT_MAX" || MEM_PCT_MAX=70
# Host MemAvailable below this many MB skips the run. The percent gate above is relative to the container's cgroup cap, which is
# the WHOLE host on a 4 GB web host, so only the host number protects the other tenants of the kernel (about 2x the measured peak).
HOST_MEM_MIN_MB=700
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
# judged first: this unit's own prefix and then upper-case letters, digits and underscores only (LC_ALL=C pins ASCII ranges). No
# fallback to a variable of any other name, so a wrong name in the env file cannot select another unit's beat (or any other
# secret of the prd root).
_key_ok() { local LC_ALL=C; case "${1:-}" in WEB_BASH_SYNTHETIC_URL_?*) ;; *) return 1 ;; esac; case "$1" in *[!A-Z0-9_]*) return 1 ;; esac; }
# The URL's PATH is the secret, so it rides curl's stdin config (`--config -`), never argv (/proc/<pid>/cmdline is world-readable;
# ADR-280, #9757). Judged before any request, with no trimming: https:// only, and only bytes that cannot add a config directive.
_hb_url_ok() {
  local LC_ALL=C
  case "$1" in https://*) ;; *) return 1 ;; esac
  case "${1#https://}" in ''|*[!A-Za-z0-9._~:/?\&=%+-]*) return 1 ;; esac
}
# This unit's beat is a Better Stack heartbeat: the pinned host and the `/api/v1/heartbeat/<token>` path, with no query or
# fragment (the `/fail` suffix is appended to the path, so a `?` would land it inside a query string and turn a verified fail into a
# success ping). Stricter than `_hb_url_ok`, which stays a sibling-identical byte-shape gate.
_hb_target_ok() {
  local LC_ALL=C pre='https://uptime.betterstack.com/api/v1/heartbeat/'
  case "${1:-}" in "$pre"?*) ;; *) return 1 ;; esac
  case "${1#"$pre"}" in *[!A-Za-z0-9_/-]*|*//*|/*) return 1 ;; esac
}
_hb_curl() { curl --disable --noproxy '*' -gfsS -m 10 -o /dev/null --config - 2>/dev/null < <(printf 'url = "%s"\n' "$1"); }

# The ONE heartbeat chokepoint. Reached only from finish() (sdk_bash_verdict.sh never pings, and web-bash-synthetic.test.sh pins
# that `_hb_curl` has exactly its two call sites here and `ping_heartbeat` exactly its two in finish(), over this file and the lib).
# It judges its own target again, so no caller can reach curl with a URL that skipped the checks below.
ping_heartbeat() {  # <ok|fail>
  local target="$URL"
  if [ -n "${SOLEUR_WBS_PING_LOG:-}" ]; then
    # tee, not a redirect: same effect, and the write site stays out of the fixture-relative-assert ratchet (the path is a test seam).
    printf 'PING %s\n' "$1" | tee -a "$SOLEUR_WBS_PING_LOG" >/dev/null
    return 0
  fi
  if ! _hb_url_ok "$URL" || ! _hb_target_ok "$URL"; then
    echo "[wbs] WARN: heartbeat ping REFUSED ($1, url_present=yes): the URL is not this unit's Better Stack heartbeat shape" >&2
    return 0
  fi
  [ "$1" = fail ] && target="${URL%/}/fail"
  _hb_curl "$target" || _hb_curl "$target" || echo "[wbs] WARN: heartbeat ping FAILED ($1, url_present=yes)" >&2
}

# A one-line, credential-free rendering of text that came from docker or the probe (it rides the journal, which Vector ships
# off-box): credential shapes first (the same four rules as ci-deploy.sh `_cred_err_tail`), then the VALUE of any exported variable
# whose name says it holds a secret (this script runs as root with the whole prd root in its environment, and the container's env
# is largely the same set), and only then the byte allowlist and the 120-char cut, so a value straddling the cut cannot leak.
_scrub_line() {  # <text>
  local e="${1:-}" n v
  if [ "${#e}" -gt 4096 ]; then e="${e:0:4096}"; fi
  e="$(printf '%s' "$e" | LC_ALL=C tr -c '[:print:]' ' ' \
    | sed -E -e 's/dp\.[a-z]{2,}\.[A-Za-z0-9._-]*/dp.REDACTED/g' \
      -e 's/(^|[^A-Za-z0-9])(sk|pk|rk)_(live|test)_[A-Za-z0-9]+/\1\2_\3_REDACTED/g' \
      -e 's/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+/eyJ.REDACTED/g' \
      -e 's/(^|[^A-Za-z0-9])(gh[pousr]|sbp|dop_v1|whsec|xox[baprs])_[A-Za-z0-9_-]+/\1\2_REDACTED/g')" || e="<sanitize_failed>"
  while IFS= read -r n; do
    case "$n" in *TOKEN*|*KEY*|*SECRET*|*PASS*|*DSN*|*CREDENTIAL*|*AUTH*|*URL*) ;; *) continue ;; esac
    v="${!n:-}"
    if [ "${#v}" -ge 8 ]; then e="${e//"$v"/REDACTED_$n}"; fi
  done < <(compgen -e)
  printf '%s' "$e" | LC_ALL=C tr -cd 'A-Za-z0-9._:/ =-' | cut -c1-120
}

# The ONE exit. Computes the counter, journals the verdict, THEN pings (Guard 1: never before the verdict exists).
finish() {  # <pass|fail|no_ping> <reason> [detail]
  local verdict="$1" reason="$2" detail="${3:-}" n=0 prev=0 cnt="$STATE_DIR/consecutive_no_ping"
  detail="$(_scrub_line "$detail")"
  if [ -r "$cnt" ]; then prev="$(cat "$cnt" 2>/dev/null || echo 0)"; fi
  case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
  [ "${#prev}" -le 6 ] || prev=0
  # Only a no_ping run advances the counter; a pass AND a fail reset it (a verified fail is a claim, not a missing one). 10# so a
  # stray `08` is a number, not an invalid octal that aborts the run before it journals anything.
  if [ "$verdict" = no_ping ]; then n=$((10#$prev + 1)); fi
  if [ -w "$STATE_DIR" ]; then printf '%s\n' "$n" | tee "$cnt" >/dev/null 2>&1 || true; fi
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
  echo "[wbs] WARN: WEB_BASH_SYNTHETIC_URL_KEY is unset or is not a WEB_BASH_SYNTHETIC_URL_<UPPER> variable name (the value is not shown); the heartbeat URL cannot be resolved." >&2
  finish no_ping no_heartbeat_url "key name unset or malformed"
fi
URL="${!WEB_BASH_SYNTHETIC_URL_KEY:-}"
if [ -z "$URL" ]; then
  finish no_ping no_heartbeat_url "url unset"
fi
if ! _hb_url_ok "$URL" || ! _hb_target_ok "$URL"; then
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
# A scrubbed, capped one-liner from docker's stderr (it rides the journal).
_err_tail() { _scrub_line "$(head -c 4096 "$ERRF" 2>/dev/null | head -n 1)"; }

# 0 = a deploy holds the lock, 1 = it does not, 2 = cannot tell. Reads /proc/locks for the lock file's device AND inode (the
# `maj:min:ino` of a FLOCK line; an inode number alone repeats across filesystems, and /proc/locks is host-global, so a lock held
# elsewhere with the same number must not read as a deploy); never takes the lock.
_deploy_lock_held() {
  local maj min ino want rc=0
  [ -e "$LOCK_FILE" ] || return 1
  read -r maj min ino < <(stat -c '%Hd %Ld %i' "$LOCK_FILE" 2>/dev/null) || return 2
  case "$maj$min$ino" in ''|*[!0-9]*) return 2 ;; esac
  [ -r "$PROC_LOCKS" ] || return 2
  # maj:min as /proc/locks prints them; matches stat's st_dev on tmpfs (/var/lock in prod). On a filesystem where the two differ
  # (e.g. btrfs) this reads "not held", i.e. the run proceeds during a deploy; it never produces a false /fail.
  want="$(printf '%02x:%02x:%d' "$maj" "$min" "$ino")"
  awk -v want="$want" '{ for (i = 5; i <= NF; i++) if ($i == want) found = 1 } END { exit found ? 0 : 1 }' "$PROC_LOCKS" 2>/dev/null || rc=$?
  case "$rc" in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
}
# <stage>: skip (no_ping) while a deploy holds the lock; cannot-tell is an infra error, never a test.
_lock_gate() {
  local rc=0
  _deploy_lock_held || rc=$?
  case "$rc" in
    0) finish no_ping deploy_lock "ci-deploy lock held ($1)" ;;
    1) : ;;
    *) finish no_ping infra_error "deploy lock state unreadable ($1)" ;;
  esac
}

# <stage>: skip (no_ping) when the HOST or the container is short of memory. Host first (a /proc read, no docker call).
_mem_gate() {
  local avail mem rc=0
  avail="$(awk '/^MemAvailable:/ { print int($2 / 1024); exit }' "$MEMINFO" 2>/dev/null)"
  case "$avail" in ''|*[!0-9]*) finish no_ping infra_error "host MemAvailable unreadable ($1)" ;; esac
  if [ "$avail" -lt "$HOST_MEM_MIN_MB" ]; then
    finish no_ping memory_pressure_host "host MemAvailable ${avail}MB < ${HOST_MEM_MIN_MB}MB ($1)"
  fi
  mem="$(timeout "$STATS_TIMEOUT" docker stats --no-stream --format '{{.MemPerc}}' "$CTR" 2>"$ERRF")" || rc=$?
  [ "$rc" -eq 0 ] || finish no_ping infra_error "docker_stats_rc_$rc: $(_err_tail)"
  mem="${mem%\%}"
  case "$mem" in
    ''|*[!0-9.]*|.*|*.*.*) finish no_ping infra_error "memory reading unparseable ($1)" ;;
  esac
  if [ "${mem%%.*}" -ge "$MEM_PCT_MAX" ]; then
    finish no_ping memory_pressure "container memory ${mem}% >= ${MEM_PCT_MAX}% ($1)"
  fi
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
_lock_gate "start"

# --- 2. the container must be up ------------------------------------------------------------------------------------------------
# docker inspect rc 1 is BOTH "no such container" and "cannot reach the daemon": only the first is a container that is down.
_rc=0; _inspect || _rc=$?
if [ "$_rc" -eq 1 ] && grep -qiE 'no such (object|container)' "$ERRF" 2>/dev/null; then
  finish no_ping container_down "container not found"
elif [ "$_rc" -eq 0 ] && [ "$C_RUNNING" != true ]; then
  finish no_ping container_down "container not running"
elif [ "$_rc" -ne 0 ]; then
  finish no_ping infra_error "docker_inspect_rc_$_rc: $(_err_tail)"
fi
case "$C_ID" in ''|*[!0-9a-f]*) finish no_ping infra_error "container id unreadable" ;; esac
[ "${#C_ID}" -eq 64 ] || finish no_ping infra_error "container id unreadable"
[ -n "$C_START" ] || finish no_ping infra_error "container start time unreadable"
BASE_ID="$C_ID"; BASE_START="$C_START"

# --- 3. memory pressure (host and container) ------------------------------------------------------------------------------------
_mem_gate "start"

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
# Asked of the dispatcher's own flag read (CTO ruling), in the container's FULL env so the live flag read works; never the env
# mirror. The result rides a sentinel line because the resolver's logger may write to stdout too. `unresolved` is the resolver
# saying Flagsmith did not answer (the read fell back to the mirror, or lost its 3 s race): testing a guessed artifact would ping
# green for the wrong one, so the run is skipped and a persistent `selector_unresolved` pages through the beat's grace.
_rc=0
_sel_out="$(timeout "$RESOLVER_HOST_TIMEOUT" docker exec "$CTR" timeout -k 5 20 node "$RESOLVER_PATH" 2>"$ERRF")" || _rc=$?
case "$_rc" in
  0) : ;;
  124) finish no_ping host_timeout_before_dispatch "resolver" ;;
  *) finish no_ping infra_error "resolver_rc_$_rc: $(_err_tail)" ;;
esac
_sel_lines="$(printf '%s\n' "$_sel_out" | { grep -aE '^SOLEUR_SELECTOR=(base|unixdeny|unresolved)$' || true; })"
case "$_sel_lines" in
  SOLEUR_SELECTOR=base) SEL=base ;;
  SOLEUR_SELECTOR=unixdeny) SEL=unixdeny ;;
  SOLEUR_SELECTOR=unresolved) SEL=unresolved; finish no_ping selector_unresolved "flag read did not answer" ;;
  *) finish no_ping infra_error "selector_unresolved: no single sentinel line" ;;
esac

# --- 6. the run -----------------------------------------------------------------------------------------------------------------
# A nonce /dev/urandom could not supply is an infra error, never a $RANDOM-derived one: the nonce is the proof the tool_result
# came from THIS run.
nonce="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || true)"
if ! [[ "$nonce" =~ ^[0-9a-f]{32}$ ]]; then
  finish no_ping infra_error "nonce_unavailable"
fi
# Everything above takes seconds (two docker stats, the resolver): look at the lock and at memory again immediately before the exec.
_mem_gate "before the probe"
_lock_gate "before the probe"
_rc=0
_t0=$SECONDS
# env -i first (scrubs the environment), then a tiny sh that raises ITS OWN oom_score_adj (no privilege needed to raise it) before
# exec'ing the capped probe: node, the SDK's claude child and bwrap inherit it, so a cgroup OOM kills the probe tree, not the app.
_out="$(timeout -k 5 "$PROBE_TIMEOUT" docker exec -w /app "$CTR" /usr/bin/env -i \
  PATH=/usr/local/bin:/usr/bin:/bin HOME="$HOME_C" APP=/app SMOKE=1 SDK_BASH_PROBE_RUNTIME=1 SDK_BASH_PROBE_SELECTOR="$SEL" \
  NONCE="$nonce" ANTHROPIC_API_KEY=decoy-api-key-sentinel \
  /bin/sh -c 'echo 1000 > /proc/self/oom_score_adj 2>/dev/null; exec "$@"' sh \
  timeout -k 5 "$INNER_TIMEOUT" node "$PROBE_PATH" 2>"$ERRF")" || _rc=$?
_elapsed=$((SECONDS - _t0))
_docker_err="$(_err_tail)"
# Which cap fired on an rc 124: the host `timeout` only after PROBE_TIMEOUT seconds; sooner than that it was the in-container one.
if [ "$_elapsed" -ge "$PROBE_TIMEOUT" ]; then _cap="$PROBE_TIMEOUT"; else _cap="$INNER_TIMEOUT"; fi

# --- 7. a deploy or a swap during the run voids the verdict ----------------------------------------------------------------------
# A deploy that took the lock while the probe ran is loading the host (pull, canary boot): whatever happened to the probe is not a
# claim about the sandbox, so even a fail is a skip.
_lock_gate "after the probe"
_irc=0; _inspect || _irc=$?
if [ "$_irc" -ne 0 ] || [ "$C_RUNNING" != true ] || [ "$C_ID" != "$BASE_ID" ] || [ "$C_START" != "$BASE_START" ]; then
  finish no_ping container_restarted "container replaced or stopped during the run"
fi

# --- 8. map and finish ----------------------------------------------------------------------------------------------------------
sdk_bash_map_result "$_rc" "$_out" "$_docker_err" "$_cap"
COV="${SBV_COVERAGE:--}"
_psel=""
if [ -n "${SBV_JSON:-}" ]; then
  _psel="$(printf '%s' "$SBV_JSON" | jq -r '.selector // ""' 2>/dev/null || true)"
  _m="$(printf '%s' "$SBV_JSON" | jq -r '(.masks_missing // "-") | tostring' 2>/dev/null || echo -)"
  case "$_m" in ''|*[!0-9]*) MASKS="-" ;; *) MASKS="$_m" ;; esac
fi
# The probe echoes the selector it ran under. A pass must carry exactly the one this host asked for (a stale probe that ignores the
# selector env would otherwise ping green for whatever artifact it defaulted to); any other verdict only when it names one.
if [ "$_psel" != "$SEL" ] && { [ "$SBV_VERDICT" = pass ] || [ -n "$_psel" ]; }; then
  finish no_ping selector_mismatch "asked $SEL probe reported ${_psel:-none}"
fi
# Runtime mode masks only the dirs a real session already created; a fresh container has none until its first session, so a pass
# with masks_missing > 0 tested a weaker config than production and does not claim the full tuple (the ping is unchanged).
if [ "$SBV_VERDICT" = pass ]; then
  case "$MASKS" in -|0) : ;; *) COV=prodtuple_partial ;; esac
fi
case "$SBV_VERDICT" in
  pass) finish pass ok ;;
  sdk_bash_smoke_failed) finish fail sdk_bash_smoke_failed "$SBV_REASON" ;;
  *)
    case "$SBV_REASON" in
      host_timeout_before_dispatch*) finish no_ping host_timeout_before_dispatch "$SBV_REASON" ;;
      *) finish no_ping infra_error "$SBV_REASON" ;;
    esac ;;
esac

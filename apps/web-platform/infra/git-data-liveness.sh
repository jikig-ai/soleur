#!/bin/bash
# git-data-liveness.sh — the git-data HOST's own recurring liveness signal (#9438).
#
# WHAT IT IS. A 60 s feeder, run by git-data-liveness.timer, that checks the host's own health and
# pings a DEDICATED Better Stack heartbeat only when every gating check passes. The page is the
# heartbeat's ABSENCE; when a ping is withheld the feeder also says why, off-host, through the
# existing git-data-emit channel (level info, stage liveness), so the soak is readable before the
# monitor is armed and a flapping monitor can be diagnosed afterwards.
#
# WHAT IT PROVES, AND WHAT IT DOES NOT. It proves host and store health: sshd answers on loopback,
# the store is mounted from the LUKS mapper, bytes and inodes are below threshold, and the two
# security units have not failed. It does NOT prove that a particular git operation or erasure
# call succeeds on a healthy host; the erasure path keeps its own reporting. The web-fed probe
# (web-git-data-probe) proves only that some web host can open a TCP connection to the port.
#
# THE URL NEVER TOUCHES user_data. It is read at runtime from the scoped read-only Doppler config
# this host already holds a token for, so a rehearsal host (whose scratch config does not carry
# the secret) is structurally unable to ping the production monitor, and rotation is a replace.
#
# EXIT 0 ON EVERY PATH EXCEPT THE TRACE REFUSAL. A feeder that cannot run produces no beat, and
# the missing beat IS the alert; a non-zero exit would only add a second, redundant failure.
#
# ORDER INSIDE ONE TICK, and its budget: checks, then ping (the primary signal), then persist and
# emit. The emit is bounded because git-data-emit alone can take 40 to 50 s when egress is
# degraded. Worst case: a 10 s cache fetch, two 10 s pings and a 1 s sleep, a 20 s emit = 51 s,
# inside TimeoutStartSec=55, inside the 60 s tick. A failed emit never changes the ping decision.
set -uo pipefail
if [[ $- == *x* ]]; then
  printf '[FATAL] refusing to run under xtrace: the heartbeat URL is a credential\n' >&2
  exit 78
fi

# An explicit PATH: a timer-started unit does not inherit a login shell's, and the sbin
# directories must be present for mountpoint and findmnt. The PREPEND is the suite's seam only.
PATH="${GIT_DATA_LIVENESS_PATH_PREPEND:+${GIT_DATA_LIVENESS_PATH_PREPEND}:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH
umask 077

# Seams exist ONLY so the suite can drive the real script; production sets none of them.
_num() { case "${1:-}" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }
STORE_ROOT="${GIT_DATA_LIVENESS_ROOT:-/mnt/git-data}"
RUN_DIR="${GIT_DATA_LIVENESS_RUN:-/run/git-data-liveness}"
EMIT="${GIT_DATA_LIVENESS_EMIT:-/usr/local/bin/git-data-emit}"
SSH_HOST="${GIT_DATA_LIVENESS_SSH_HOST:-127.0.0.1}"
SSH_PORT="$(_num "${GIT_DATA_LIVENESS_SSH_PORT:-}" 22)"
FETCH_TIMEOUT="$(_num "${GIT_DATA_LIVENESS_FETCH_TIMEOUT:-}" 10)"
EMIT_TIMEOUT="$(_num "${GIT_DATA_LIVENESS_EMIT_TIMEOUT:-}" 20)"
NOW="$(_num "${GIT_DATA_LIVENESS_NOW:-}" "$(date +%s)")"
readonly STORE_ROOT RUN_DIR EMIT SSH_HOST SSH_PORT FETCH_TIMEOUT EMIT_TIMEOUT NOW

# THE CONSTANTS. Each threshold is exercised at the boundary (one below, at, one above) by the
# suite, so relaxing one fails a row it did not edit. Bytes: a fresh store reads about 1 %.
# Inodes exhaust at roughly 55 to 60 % of bytes on this store (git-data-bootstrap.sh), so the
# inode limit is the binding one in practice. root_pct is REPORTED, never gated: its threshold is
# a guess nothing has measured on a fresh host, and a false fail would need a payload PR, a
# rehearsal and a replace to repair.
readonly STORE_MAPPER=/dev/mapper/git-data
readonly DISK_PCT_LIMIT=90
readonly INODE_PCT_LIMIT=90
readonly OK_SUMMARY_S=600
readonly MISS_REEMIT_S=1800
readonly PRODUCTION_CONFIG=prd_git_data
readonly URL_FILE="$RUN_DIR/url"
readonly STATE_FILE="$RUN_DIR/state"
SELF="${BASH_SOURCE[0]}"
readonly SELF

# The accepted URL shape. A newline or a quote would inject a directive into the curl config the
# URL is handed to, so the whole value must be one heartbeat path segment of safe characters.
_url_ok() {
  local LC_ALL=C
  case "${1:-}" in
    ''|*[!A-Za-z0-9_./:-]*) return 1 ;;
    https://uptime.betterstack.com/api/v1/heartbeat/*[!A-Za-z0-9_-]*) return 1 ;;
    https://uptime.betterstack.com/api/v1/heartbeat/?*) return 0 ;;
  esac
  return 1
}

# Re-exec target: runs INSIDE `doppler run`, with exactly one secret in its environment. It only
# validates and caches; it prints nothing, so the URL cannot reach a log.
if [ "${1:-}" = "--write-cache" ]; then
  _u="${GIT_DATA_HOST_HEARTBEAT_URL:-}"
  _url_ok "$_u" || exit 0
  mkdir -p "$RUN_DIR" 2>/dev/null || exit 0
  chmod 700 "$RUN_DIR" 2>/dev/null || true
  _t="$RUN_DIR/url.$$"
  if printf '%s\n' "$_u" > "$_t" 2>/dev/null; then mv -f "$_t" "$URL_FILE" 2>/dev/null || rm -f "$_t"; else rm -f "$_t"; fi
  exit 0
fi

MISSES=()
miss() { MISSES+=("$1"); }

# Percent used from a `df --output=<field>` read; empty output or a non-number is UNMEASURED.
_pct() {  # <field> <path>
  local out="" rc=0 v
  out="$(df --output="$1" "$2" 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  v="$(printf '%s\n' "$out" | tail -n 1 | tr -d ' %')"
  case "$v" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$v"
}

_banner() {
  local line="" rc=0
  line="$(timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2" || exit 1; IFS= read -r -t 4 -u 3 l; printf "%s" "$l"' _ "$SSH_HOST" "$SSH_PORT" 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  case "$line" in SSH-*) return 0 ;; esac
  return 1
}

_unit_state() {  # prints ActiveState; non-zero when unreadable
  local out="" rc=0
  out="$(systemctl show --value -p ActiveState "$1" 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  case "$out" in ''|*[!a-z-]*) return 1 ;; esac
  printf '%s' "$out"
}

run_checks() {
  local mrc=0 src="" rc=0 v st u
  # sshd answers: a banner read, NOT a unit-state check. Ubuntu 24.04 is socket-activated, so
  # ssh.service can be inactive on a healthy idle host and a unit check would false-fail.
  _banner || miss ssh_no_banner

  mountpoint -q "$STORE_ROOT" 2>/dev/null || mrc=$?
  case "$mrc" in
    0)
      src="$(findmnt -n -o SOURCE --target "$STORE_ROOT" 2>/dev/null)" || rc=$?
      src="$(printf '%s\n' "$src" | head -n 1 | tr -d ' ')"
      if [ "$rc" -ne 0 ] || [ -z "$src" ]; then miss unmeasured:mount_source
      elif [ "$src" != "$STORE_MAPPER" ]; then miss store_not_mapper; fi
      if v="$(_pct pcent "$STORE_ROOT")"; then
        [ "$v" -ge "$DISK_PCT_LIMIT" ] && miss disk_full
      else miss unmeasured:df_bytes; fi
      if v="$(_pct ipcent "$STORE_ROOT")"; then
        [ "$v" -ge "$INODE_PCT_LIMIT" ] && miss inodes_full
      else miss unmeasured:df_inodes; fi
      ;;
    1) miss store_unmounted ;;
    *) miss unmeasured:mountpoint ;;
  esac

  # git-data-gc.service is deliberately NOT in this set: whether a failed weekly maintenance run
  # should page is a policy the owner has not decided (#8093), and this feeder neither makes it
  # nor hides it. A failed reopen unit stays failed until its next successful run (up to ~17 min).
  for u in git-data-luks-reopen git-data-nftables; do
    if st="$(_unit_state "$u.service")"; then
      [ "$st" = failed ] && miss "unit_failed:$u"
    else miss unmeasured:units; fi
  done
}

STATE=""; CODE=""; URL=""
_load_url() {
  local u=""
  if [ -s "$URL_FILE" ]; then
    u="$(head -n 1 "$URL_FILE" 2>/dev/null)"
    if _url_ok "$u"; then URL="$u"; return 0; fi
    rm -f "$URL_FILE"
  fi
  [[ "${GIT_DATA_DOPPLER_CONFIG:-}" =~ ^[a-z0-9_]+$ ]] || return 1
  # While the cache is empty every tick retries (no throttle), so a host replaced before its
  # secret existed heals on the next tick without a second replace. A doppler that exits 0 with
  # empty output leaves no cache and is therefore an absent secret, never a valid URL.
  timeout "$FETCH_TIMEOUT" doppler run --project soleur --config "$GIT_DATA_DOPPLER_CONFIG" --only-secrets GIT_DATA_HOST_HEARTBEAT_URL --no-fallback -- "$SELF" --write-cache >/dev/null 2>&1 || true
  [ -s "$URL_FILE" ] || return 1
  u="$(head -n 1 "$URL_FILE" 2>/dev/null)"
  _url_ok "$u" || { rm -f "$URL_FILE"; return 1; }
  URL="$u"
}

# THE ONLY curl CALL SITE. The URL rides curl's stdin config channel, fed by a process
# substitution whose printf is the shell builtin, so it is never in any argument list. Two
# explicit attempts absorb a vendor blip; no --retry flag (a retry flag can turn a throttled
# response into exit 0).
_ping() {
  local n=0
  _url_ok "$URL" || return 2
  while [ "$n" -lt 2 ]; do
    if curl --disable --noproxy '*' -fsS -m 10 -o /dev/null --config - 2>/dev/null < <(printf 'url = "%s"\n' "$URL"); then return 0; fi
    n=$((n + 1))
    [ "$n" -ge 2 ] || sleep 1
  done
  return 1
}

LAST_STATE=none; LAST_CODE=""; LAST_TS=0
read_state() {
  local line="" k v
  [ -r "$STATE_FILE" ] || return 0
  line="$(head -n 1 "$STATE_FILE" 2>/dev/null)"
  for kv in $line; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      s) case "$v" in ok|miss|ping_fail|url_unavailable|disarmed) LAST_STATE="$v" ;; esac ;;
      c) case "$v" in *[!a-z0-9_:.,-]*) : ;; *) LAST_CODE="$v" ;; esac ;;
      t) case "$v" in ''|*[!0-9]*) : ;; *) LAST_TS="$v" ;; esac ;;
    esac
  done
}

main() {
  local cfg="unset" root_pct="?" due=0 detail old_ifs
  mkdir -p "$RUN_DIR" 2>/dev/null || true
  chmod 700 "$RUN_DIR" 2>/dev/null || true
  read_state
  [[ "${GIT_DATA_DOPPLER_CONFIG:-}" =~ ^[a-z0-9_]+$ ]] && cfg="$GIT_DATA_DOPPLER_CONFIG"
  root_pct="$(_pct pcent /)" || root_pct="?"

  run_checks
  if [ "${#MISSES[@]}" -gt 0 ]; then
    STATE=miss
    old_ifs="$IFS"; IFS=,; CODE="${MISSES[*]}"; IFS="$old_ifs"
  elif _load_url; then
    if _ping; then STATE=ok; CODE=ok
    else STATE=ping_fail; CODE=ping_fail; rm -f "$URL_FILE"; fi
  else
    # EXACT equality: the rehearsal's scratch config name shares a prefix with the production
    # one, so a prefix match would misclassify it and a rehearsal host would page as production.
    if [ "$cfg" = "$PRODUCTION_CONFIG" ]; then STATE=url_unavailable; else STATE=disarmed; fi
    CODE="$STATE"
  fi

  if [ "$STATE" != "$LAST_STATE" ] || [ "$CODE" != "$LAST_CODE" ]; then due=1
  elif [ "$STATE" = ok ]; then [ $((NOW - LAST_TS)) -ge "$OK_SUMMARY_S" ] && due=1
  else [ $((NOW - LAST_TS)) -ge "$MISS_REEMIT_S" ] && due=1; fi
  [ "$due" -eq 1 ] || return 0

  detail="git-data liveness: state=$STATE code=$CODE"
  # State is advanced only after the emit returns 0, so a failed or killed emit is retried on
  # the next tick instead of being recorded as delivered.
  if timeout "$EMIT_TIMEOUT" "$EMIT" "SOLEUR_GIT_DATA_LIVENESS $STATE" liveness info "$detail" \
       "state=$STATE" "code=$CODE" "root_pct=$root_pct" "config=$cfg" >/dev/null 2>&1; then
    if printf 's=%s c=%s t=%s\n' "$STATE" "$CODE" "$NOW" > "$STATE_FILE.$$" 2>/dev/null; then
      mv -f "$STATE_FILE.$$" "$STATE_FILE" 2>/dev/null || rm -f "$STATE_FILE.$$"
    else rm -f "$STATE_FILE.$$"; fi
  fi
}

main
exit 0

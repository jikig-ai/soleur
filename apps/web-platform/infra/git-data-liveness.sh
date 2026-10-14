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
# the store is mounted read-write from the LUKS mapper, its root directory lists and one block of the
# mapper reads straight from the device, bytes and inodes are below threshold, and the two security
# units are loaded and have not failed. It does
# NOT prove that a particular git operation or erasure call succeeds on a healthy host; the erasure
# path keeps its own reporting. The web-fed probe (web-git-data-probe) proves only that some web
# host can open a TCP connection to the port. The store is never WRITTEN to: a probe write would
# move the mtime the cutover's quiescence check reads.
#
# THE URL NEVER TOUCHES user_data. It is read at runtime from the scoped read-only Doppler config
# this host already holds a token for, so a rehearsal host (whose scratch config does not carry
# the secret) is structurally unable to ping the production monitor. A cached URL is not re-read
# while pings succeed (there is no TTL): a rotation takes effect on the first rejected ping, or at
# the next boot, because the cache is tmpfs.
#
# EXIT 0 ON EVERY PATH EXCEPT THE TRACE REFUSAL (and a refused run-dir seam, below).
#
# TICK BUDGET (the suite derives these sums from the constants below, never from this prose).
#   Healthy path:   banner 5 + fetch 10 + two pings 2x10 + pause 1 + emit 20 = 56 s.
#   Hung-instrument path: banner 5 + every instrument run at its cap (2 s, then a KILL 1 s later)
#   + emit 20. A hang is a MISS, and a miss skips the fetch and the ping.
#   Root-df path: the one hang that is NOT a miss (root usage is reported, never gated): one
#   instrument cap + fetch 10 + two pings 2x10 + pause 1 + emit 20.
#   All three sit inside TimeoutStartSec=58 and the 60 s period. An instrument either answers in
#   milliseconds or hangs; nothing here is sized for "every instrument just under its cap".
#   The cap bounds a hang that dies on TERM or KILL. A process in uninterruptible sleep on a dead
#   device survives both; the tick is then ended by TimeoutStartSec with nothing emitted, and the
#   page is the heartbeat's absence, which needs no event to fire.
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

# Seams exist ONLY so the suite can drive the real script; production sets none of them, and the
# unit, the timer, cloud-init and the module are asserted to name none. The Doppler child below
# runs with every seam but the run dir stripped.
_num() { case "${1:-}" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }
STORE_ROOT="${GIT_DATA_LIVENESS_ROOT:-/mnt/git-data}"
RUN_DIR="${GIT_DATA_LIVENESS_RUN:-/run/git-data-liveness}"
EMIT="${GIT_DATA_LIVENESS_EMIT:-/usr/local/bin/git-data-emit}"
SSH_HOST="${GIT_DATA_LIVENESS_SSH_HOST:-127.0.0.1}"
SSH_PORT="$(_num "${GIT_DATA_LIVENESS_SSH_PORT:-}" 22)"
FETCH_TIMEOUT="$(_num "${GIT_DATA_LIVENESS_FETCH_TIMEOUT:-}" 10)"
EMIT_TIMEOUT="$(_num "${GIT_DATA_LIVENESS_EMIT_TIMEOUT:-}" 20)"
NOW="$(_num "${GIT_DATA_LIVENESS_NOW:-}" "$(date +%s)")"
# The run dir is the only seam this script WRITES under, so it is refused unless absolute, spelled
# canonically and off the store and the synthetic or mounted-volume trees (an empty or relative
# value would retarget every write below). Production never sets it; this is the one non-zero exit
# besides the trace refusal, and it is a misconfiguration, not a runtime state. It is a guard
# against a mistyped seam, not a sandbox: the seam comes from a root-owned environment.
case "$RUN_DIR" in
  "")            printf '[FATAL] GIT_DATA_LIVENESS_RUN is EMPTY; refusing to write to /\n' >&2; exit 2 ;;
  */../*|*/..)   printf '[FATAL] run dir %s contains ..; refusing\n' "$RUN_DIR" >&2; exit 2 ;;
  *//*|*/./*|*/.) printf '[FATAL] run dir %s is not canonically spelled; refusing\n' "$RUN_DIR" >&2; exit 2 ;;
  /)             printf '[FATAL] run dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
  /proc|/sys|/dev|/mnt|/media|/proc/*|/sys/*|/dev/*|/mnt/*|/media/*) printf '[FATAL] run dir %s is a synthetic-fs or mounted-volume path; refusing\n' "$RUN_DIR" >&2; exit 2 ;;
  /*)            : ;;
  *)             printf '[FATAL] run dir %s is RELATIVE; refusing\n' "$RUN_DIR" >&2; exit 2 ;;
esac
case "$RUN_DIR/" in
  "$STORE_ROOT"/*) printf '[FATAL] run dir %s is on the store; refusing\n' "$RUN_DIR" >&2; exit 2 ;;
esac
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
readonly BANNER_TIMEOUT=5
readonly INSTR_TIMEOUT=2
readonly INSTR_KILL_AFTER=1
readonly PING_TIMEOUT=10
readonly PING_PAUSE=1
readonly PRODUCTION_CONFIG=prd_git_data
readonly URL_FILE="$RUN_DIR/url"
readonly STATE_FILE="$RUN_DIR/state"
SELF="${BASH_SOURCE[0]}"
readonly SELF

# Every instrument read goes through this: a hung statfs, mount-table read or D-Bus call must end
# in a recorded miss, not in the unit being killed with nothing said. TERM first, KILL one second
# later (a bare timeout waits forever on a child that ignores TERM). Uninterruptible sleep on a
# dead device survives both; TimeoutStartSec is the backstop for that, and the absent ping pages.
_i() { timeout -k "$INSTR_KILL_AFTER" "$INSTR_TIMEOUT" "$@"; }

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
  if printf '%s\n' "$_u" > "${RUN_DIR:?run dir unset}/url.$$" 2>/dev/null; then
    mv -f "${RUN_DIR:?}/url.$$" "${RUN_DIR:?}/url" 2>/dev/null || rm -f "${RUN_DIR:?}/url.$$"
  else rm -f "${RUN_DIR:?}/url.$$"; fi
  exit 0
fi

MISSES=()
miss() { MISSES+=("$1"); }

# Percent used from a `df --output=<field>` read; empty output or a non-number is UNMEASURED.
_pct() {  # <field> <path>
  local out="" rc=0 v
  out="$(_i df --output="$1" "$2" 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  v="$(printf '%s\n' "$out" | tail -n 1 | tr -d ' %')"
  case "$v" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$v"
}

_banner() {
  local line="" rc=0
  line="$(timeout "$BANNER_TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$1/$2" || exit 1; IFS= read -r -t 4 -u 3 l; printf "%s" "$l"' _ "$SSH_HOST" "$SSH_PORT" 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  case "$line" in SSH-*) return 0 ;; esac
  return 1
}

# Prints "<LoadState>/<ActiveState>"; non-zero when the service manager cannot be read. A unit
# that does not exist reads ActiveState=inactive with rc 0, so the load state is read too.
_unit_state() {
  local out="" rc=0 l a
  out="$(_i systemctl show -p LoadState -p ActiveState "$1" 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  l="$(printf '%s\n' "$out" | sed -n 's/^LoadState=//p' | head -n 1)"
  a="$(printf '%s\n' "$out" | sed -n 's/^ActiveState=//p' | head -n 1)"
  case "$l$a" in ''|*[!a-z-]*) return 1 ;; esac
  [ -n "$l" ] && [ -n "$a" ] || return 1
  printf '%s/%s' "$l" "$a"
}

run_checks() {
  local mrc=0 line="" src="" opts="" rc=0 v st u bad_units=0 rd=0
  # sshd answers: a banner read, NOT a unit-state check. Ubuntu 24.04 is socket-activated, so
  # ssh.service can be inactive on a healthy idle host and a unit check would false-fail.
  _banner || miss ssh_no_banner

  # mountpoint(1) exits 32 for an existing directory that is not a mountpoint, and 1 for an
  # error such as a missing path; 0 is mounted. Anything else is an unreadable instrument.
  _i mountpoint -q "$STORE_ROOT" 2>/dev/null || mrc=$?
  case "$mrc" in
    0)
      # No pipe into head: under pipefail a second output line would SIGPIPE the writer and read
      # as a failed instrument. Take the first line in the shell; a line with no second field
      # (no options) is unmeasured, never "read-only".
      line="$(_i findmnt -n -o SOURCE,OPTIONS --target "$STORE_ROOT" 2>/dev/null)" || rc=$?
      line="${line%%$'\n'*}"
      read -r src opts _ <<<"$line"
      if [ "$rc" -ne 0 ] || [ -z "$src" ] || [ -z "$opts" ]; then miss unmeasured:mount_source
      else
        [ "$src" = "$STORE_MAPPER" ] || miss store_not_mapper
        # A journal abort or errors=remount-ro flips the mount read-only while every other
        # check here still reads healthy; the volume is then up and refusing every push.
        case ",$opts," in *,rw,*) : ;; *) miss store_readonly ;; esac
      fi
      # Two reads, neither a write (no mtime moves). The first directory entry catches a root that
      # no longer lists; it is usually served from cache, so it proves little about the device.
      # One uncached block of the mapper is the real device read: a detached or erroring volume
      # behind a still-present mount fails there while statfs still answers.
      _i find "$STORE_ROOT" -maxdepth 1 -mindepth 1 -print -quit >/dev/null 2>&1 || rd=1
      _i dd if="$STORE_MAPPER" of=/dev/null bs=4096 count=1 iflag=direct >/dev/null 2>&1 || rd=1
      [ "$rd" -eq 0 ] || miss store_unreadable
      if v="$(_pct pcent "$STORE_ROOT")"; then
        [ "$v" -ge "$DISK_PCT_LIMIT" ] && miss disk_full
      else miss unmeasured:df_bytes; fi
      if v="$(_pct ipcent "$STORE_ROOT")"; then
        [ "$v" -ge "$INODE_PCT_LIMIT" ] && miss inodes_full
      else miss unmeasured:df_inodes; fi
      ;;
    32) miss store_unmounted ;;
    *) miss unmeasured:mountpoint ;;
  esac

  # git-data-gc.service is deliberately NOT in this set: whether a failed weekly maintenance run
  # should page is a policy the owner has not decided (#8093), and this feeder neither makes it
  # nor hides it. A failed reopen unit stays failed until its next successful run: about 17 min
  # after a transient failure, and up to about 1h15 after an exhausted restart ladder (the unit's
  # start-limit window refuses timer ticks). The miss is real for that whole time.
  for u in git-data-luks-reopen git-data-nftables; do
    if st="$(_unit_state "$u.service")"; then
      # Only a loaded unit is judged by its active state; every other load state (not-found,
      # masked, error, bad-setting, stub, merged) is a unit the host cannot rely on.
      case "$st" in
        loaded/failed) miss "unit_failed:$u" ;;
        loaded/*) : ;;
        *) miss "unit_missing:$u" ;;
      esac
    else bad_units=1; fi
  done
  [ "$bad_units" -eq 0 ] || miss unmeasured:units
  return 0
}

STATE=""; CODE=""; URL=""; FROM_LAST=0
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
  # empty output leaves no cache and is therefore an absent secret, never a valid URL. The child
  # runs with every test seam but the run dir stripped.
  timeout "$FETCH_TIMEOUT" doppler run --project soleur --config "$GIT_DATA_DOPPLER_CONFIG" --only-secrets GIT_DATA_HOST_HEARTBEAT_URL --no-fallback -- /usr/bin/env -u GIT_DATA_LIVENESS_PATH_PREPEND -u GIT_DATA_LIVENESS_EMIT -u GIT_DATA_LIVENESS_EMIT_TIMEOUT -u GIT_DATA_LIVENESS_FETCH_TIMEOUT -u GIT_DATA_LIVENESS_ROOT -u GIT_DATA_LIVENESS_SSH_HOST -u GIT_DATA_LIVENESS_SSH_PORT -u GIT_DATA_LIVENESS_NOW "$SELF" --write-cache >/dev/null 2>&1 || true
  if [ -s "$URL_FILE" ]; then
    u="$(head -n 1 "$URL_FILE" 2>/dev/null)"
    if _url_ok "$u"; then rm -f "${RUN_DIR:?}/url.last"; URL="$u"; return 0; fi
    rm -f "$URL_FILE"
  fi
  # The fetch gave nothing. The URL whose ping last failed (a vendor 5xx, say) is still the best
  # evidence we have: dropping it and then meeting a Doppler outage would page a healthy host. A
  # tick that pings from it says so (code ok:last_good) until a fetch replaces it.
  if [ -s "${RUN_DIR:?}/url.last" ]; then
    u="$(head -n 1 "${RUN_DIR:?}/url.last" 2>/dev/null)"
    if _url_ok "$u"; then URL="$u"; FROM_LAST=1; return 0; fi
    rm -f "${RUN_DIR:?}/url.last"
  fi
  return 1
}

# THE ONLY curl CALL SITE. The URL rides curl's stdin config channel, fed by a process
# substitution whose printf is the shell builtin, so it is never in any argument list. Two
# explicit attempts absorb a vendor blip; no --retry flag (a retry flag can turn a throttled
# response into exit 0).
_ping() {
  local n=0
  _url_ok "$URL" || return 2
  while [ "$n" -lt 2 ]; do
    if curl --disable --noproxy '*' -fsS -m "$PING_TIMEOUT" -o /dev/null --config - 2>/dev/null < <(printf 'url = "%s"\n' "$URL"); then return 0; fi
    n=$((n + 1))
    [ "$n" -ge 2 ] || sleep "$PING_PAUSE"
  done
  return 1
}

LAST_STATE=none; LAST_CODE=""; LAST_TS=0
read_state() {
  local line="" k v kv
  local -a kvs=()
  [ -r "$STATE_FILE" ] || return 0
  line="$(head -n 1 "$STATE_FILE" 2>/dev/null)"
  read -ra kvs <<<"$line"
  for kv in "${kvs[@]}"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      s) case "$v" in ok|miss|ping_fail|url_unavailable|disarmed) LAST_STATE="$v" ;; esac ;;
      c) case "$v" in *[!a-z0-9_:.,-]*) : ;; *) LAST_CODE="$v" ;; esac ;;
      t) case "$v" in ''|*[!0-9]*) : ;; *) [ "${#v}" -le 12 ] && LAST_TS=$((10#$v)) ;; esac ;;
    esac
  done
  # A stamp from the future (a clock that stepped back) would make the cadence test negative
  # forever, so it counts as "never emitted".
  [ "$LAST_TS" -le "$NOW" ] || LAST_TS=0
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
    if _ping; then
      STATE=ok; CODE=ok
      # A last-tried URL that just worked is the live one again; the event says it was not fetched.
      if [ "$FROM_LAST" -eq 1 ]; then
        CODE=ok:last_good
        mv -f "${RUN_DIR:?}/url.last" "${RUN_DIR:?}/url" 2>/dev/null || true
      fi
    else
      STATE=ping_fail; CODE=ping_fail
      # Keep the rejected URL as the last-tried fallback; the next tick re-reads the secret first,
      # which is the whole rotation story.
      if [ "$FROM_LAST" -eq 0 ]; then mv -f "${RUN_DIR:?}/url" "${RUN_DIR:?}/url.last" 2>/dev/null || rm -f "$URL_FILE"; fi
    fi
  else
    # EXACT equality: the rehearsal's scratch config name shares a prefix with the production
    # one, so a prefix match would misclassify it and a rehearsal host would page as production.
    # An unreadable config name is a broken production host, never a rehearsal one.
    if [ "$cfg" = "$PRODUCTION_CONFIG" ] || [ "$cfg" = unset ]; then STATE=url_unavailable; else STATE=disarmed; fi
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
    if printf 's=%s c=%s t=%s\n' "$STATE" "$CODE" "$NOW" > "${RUN_DIR:?run dir unset}/state.$$" 2>/dev/null; then
      mv -f "${RUN_DIR:?}/state.$$" "${RUN_DIR:?}/state" 2>/dev/null || rm -f "${RUN_DIR:?}/state.$$"
    else rm -f "${RUN_DIR:?}/state.$$"; fi
  fi
}

main
exit 0

#!/usr/bin/env bash
# monitor-lock.sh — per-(repo, PR) exclusion for monitor-pr-checks.sh (P4c of #10924).
# SOURCED, never executed. It changes no shell option, is `set -u` safe, and is bash 3.2-safe:
# no flock, `timeout`, associative arrays, `${x,,}` or `printf %(%s)T` (stock macOS has none).
#
# THE LOCK is a symlink  $LOCKDIR/pr-checks+<owner>+<repo>+<pr>.lock  whose TARGET is the
# holder record  <pid>|<lstart>|<epoch>.  `ln -s` is an atomic create-or-fail AND an atomic
# record (the Emacs lockfile idiom), so there is no half-written window and no flock. The name
# joins its parts with `+`, which the repo grammar excludes, so `a__b/c` and `a/b__c` cannot
# collide.
#
# HOLDER LIVENESS needs all of: a numeric pid, `ps` still lists it (NOT `kill -0`: EPERM reads
# another user's live process as dead), its state is not zombie, and its recorded start time
# equals the current one (pid reuse). `lstart` follows the caller's TZ, so every read pins
# TZ=UTC LC_ALL=C. A holder that fails any test is stale and is reclaimed.
#
# API (main shell only: a `$(...)` subshell would drop the state and never run the EXIT trap)
#   monitor_lock_acquire <owner/repo | origin-url> <pr>
#       0 acquired (or already ours)   1 held by a live OTHER process   2 not established
#       sets ML_STATE (held|held-by-other|disabled|unavailable), ML_WHY, ML_REPO,
#       ML_HOLDER_PID and ML_HOLDER_AGE (rc 1 only)
#   monitor_lock_release
#       removes the link only if it still names us; idempotent; never branches on $?
#
# Env: SOLEUR_MONITOR_LOCK=off          bypass (loud)
#      SOLEUR_MONITOR_LOCK_DIR          lock directory (default $XDG_RUNTIME_DIR or /tmp, per uid)
#      SOLEUR_MONITOR_LOCK_GRACE_S      spacing of the two release-race retries on a live holder (1)

ML_STATE=""; ML_WHY=""; ML_REPO=""; ML_HOLDER_PID=""; ML_HOLDER_AGE=""
_ML_LINK=""; _ML_VALUE=""; _ML_D=""

# _ml_norm <owner/repo | url> — print lowercase owner/repo, or return 1. Strips any user:token@,
# scheme, host (must be github.com), trailing `/` and `.git`; the credential never reaches a name.
_ml_norm() {
  local s="${1:-}" host path rest auth
  s="${s%/}"; s="${s%.git}"; s="${s%/}"
  case "$s" in
    *://*)  rest="${s#*://}"; auth="${rest%%/*}"
            case "$rest" in */*) path="${rest#*/}" ;; *) path="" ;; esac
            host="${auth##*@}"; host="${host%%:*}" ;;
    *@*:*)  rest="${s#*@}"; host="${rest%%:*}"; path="${rest#*:}" ;;
    *)      host="github.com"; path="$s" ;;
  esac
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  path="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
  case "$host" in github.com|www.github.com) ;; *) return 1 ;; esac
  [[ "$path" =~ ^[a-z0-9][a-z0-9._-]*/[a-z0-9._-]+$ ]] || return 1
  printf '%s' "$path"
}

# _ml_dir — set _ML_D to a usable lock directory (a real directory, ours, writable), or return 1.
# The ownership/symlink test is what stops a pre-created hostile /tmp path becoming the lock root.
_ml_dir() {
  local d="${SOLEUR_MONITOR_LOCK_DIR:-${XDG_RUNTIME_DIR:-/tmp}/soleur-monitor-locks-$(id -u 2>/dev/null || echo 0)}"
  _ML_D=""
  if [ -L "$d" ]; then return 1; fi
  if [ ! -e "$d" ]; then ( umask 077; mkdir -p "$d" ) 2>/dev/null || return 1; fi
  if [ -d "$d" ] && [ -O "$d" ] && [ -w "$d" ]; then _ML_D="$d"; return 0; fi
  return 1
}

# _ml_ident <pid> — print "<stat>|<lstart with spaces as _>", or return 1 when ps cannot read it.
_ml_ident() {
  local out p st rest
  out="$(TZ=UTC LC_ALL=C ps -o pid= -o stat= -o lstart= -p "$1" 2>/dev/null)" || return 1  # mut:tz
  [ -n "$out" ] || return 1
  read -r p st rest <<<"$out"
  [ "$p" = "$1" ] && [ -n "$st" ] || return 1
  printf '%s|%s' "$st" "$(printf '%s' "$rest" | tr -s ' \t' '__')"
}

# _ml_alive <pid> <recorded-lstart> — 0 when that exact process is still running.
_ml_alive() {
  local pid="$1" rec="$2" ident st cur
  [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -ge 1 ] || return 1
  ident="$(_ml_ident "$pid")" || return 1
  st="${ident%%|*}"; cur="${ident#*|}"
  case "$st" in Z*) return 1 ;; esac  # mut:zombie
  [ -n "$rec" ] && [ "$rec" != "$cur" ] && return 1  # mut:lstart
  return 0
}

_ml_unavailable() { ML_STATE="unavailable"; ML_WHY="$1"; return 2; }

monitor_lock_acquire() {
  ML_STATE=""; ML_WHY=""; ML_REPO=""; ML_HOLDER_PID=""; ML_HOLDER_AGE=""; _ML_LINK=""; _ML_VALUE=""
  local pr="${2:-}" key link me ident value now holder hpid hls hep
  local spins=0 reclaims=0 waited=0 grace="${SOLEUR_MONITOR_LOCK_GRACE_S:-1}"
  if [ "${SOLEUR_MONITOR_LOCK:-}" = "off" ]; then ML_STATE="disabled"; ML_WHY="SOLEUR_MONITOR_LOCK=off"; return 2; fi
  ML_REPO="$(_ml_norm "${1:-}")" || { ML_REPO=""; _ml_unavailable "repo not derivable (needs a github.com owner/repo)"; return 2; }
  [[ "$pr" =~ ^[0-9]+$ ]] || { _ml_unavailable "PR number is not numeric"; return 2; }
  _ml_dir || { _ml_unavailable "lock directory unusable (must be a real, writable directory we own)"; return 2; }
  me="$$"
  ident="$(_ml_ident "$me")" || { _ml_unavailable "ps cannot read this process start time"; return 2; }
  now="$(date +%s 2>/dev/null)"; [[ "$now" =~ ^[0-9]+$ ]] || now=0
  value="$me|${ident#*|}|$now"
  key="${ML_REPO//\//+}"
  link="$_ML_D/pr-checks+$key+$pr.lock"  # mut:key
  while :; do
    spins=$((spins + 1))
    if [ "$spins" -gt 8 ]; then _ml_unavailable "lock contended or not creatable"; return 2; fi
    # A real directory must be refused BEFORE `ln`: given a directory as the link name, ln creates the link
    # INSIDE it. -n stops it following an existing symlink-to-directory the same way.
    if [ -d "$link" ] && [ ! -L "$link" ]; then _ml_unavailable "lock path is a directory"; return 2; fi
    if ln -sn "$value" "$link" 2>/dev/null; then
      _ML_LINK="$link"; _ML_VALUE="$value"; ML_STATE="held"; return 0
    fi
    if [ -L "$link" ]; then
      holder="$(readlink "$link" 2>/dev/null)" || holder=""
    elif [ -e "$link" ]; then
      holder=""   # a regular file stand-in: a malformed record, stale
    else
      continue    # vanished between ln and the read (a release race); spins bounds the retries
    fi
    IFS='|' read -r hpid hls hep <<<"$holder"
    if [ "$hpid" = "$me" ]; then
      _ML_LINK="$link"; _ML_VALUE="$holder"; ML_STATE="held"; return 0   # already ours: idempotent
    fi
    if _ml_alive "$hpid" "$hls"; then
      if [ "$waited" -lt 2 ]; then
        waited=$((waited + 1)); sleep "$grace"; continue
      fi
      ML_HOLDER_PID="$hpid"; ML_STATE="held-by-other"
      if [[ "$hep" =~ ^[0-9]+$ ]] && [ "$now" -ge "$hep" ]; then ML_HOLDER_AGE=$((now - hep)); else ML_HOLDER_AGE="?"; fi
      return 1
    fi
    # Stale: dead, reused pid, zombie or malformed. Remove it only if it still names that record.
    if [ "$reclaims" -ge 1 ]; then _ml_unavailable "lock contended (stale record reclaimed twice)"; return 2; fi
    reclaims=1
    if [ ! -L "$link" ] || [ "$(readlink "$link" 2>/dev/null)" = "$holder" ]; then rm -f "$link"; fi
  done
}

monitor_lock_release() {
  [ -n "$_ML_LINK" ] || return 0
  if [ -L "$_ML_LINK" ] && [ "$(readlink "$_ML_LINK" 2>/dev/null)" = "$_ML_VALUE" ]; then rm -f "$_ML_LINK"; fi  # mut:release-cond
  _ML_LINK=""; _ML_VALUE=""
  return 0
}

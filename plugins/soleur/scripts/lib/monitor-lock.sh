# shellcheck shell=bash disable=SC2034
# monitor-lock.sh — per-(repo, PR) exclusion for monitor-pr-checks.sh (P4c of #10924).
# SOURCED, never executed (so no exec bit). It changes no shell option, is `set -u` safe, and is
# bash 3.2-safe: no flock, `timeout`, associative arrays, `${x,,}` or `printf %(%s)T` (stock macOS has none).
# The ML_* variables below are this file's API, read by the sourcing script (hence the SC2034 disable above).
# Trailing `# mut:<name>` comments are load-bearing: plugins/soleur/test/monitor-lock.test.sh anchors its
# mutation battery on them. Keep each on its own statement and leave the marker in place when editing.
#
# THE LOCK is a symlink  $LOCKDIR/pr-checks+<owner>+<repo>+<pr>.lock  whose TARGET is the
# holder record  <pid>|<lstart>|<epoch>.  `ln -s` is an atomic create-or-fail AND an atomic
# record (the Emacs lockfile idiom), so there is no half-written window and no flock. The name
# joins its parts with `+`, which the repo grammar excludes, so `a__b/c` and `a/b__c` cannot
# collide. The PR number is normalised (`007` is `7`).
#
# HOLDER LIVENESS needs all of: a numeric pid, `ps` still lists it (NOT `kill -0`: EPERM reads
# another user's live process as dead), its state is not zombie, and its recorded start time is
# present and equals the current one (pid reuse). `lstart` follows the caller's TZ, so every read
# pins TZ=UTC LC_ALL=C. A holder that fails any test is stale and is reclaimed, under a short
# `mkdir` guard so two contenders cannot both reclaim the same record.
#
# KNOWN RESIDUALS (each degrades to a duplicate monitor, today's behaviour, never to a silent false
# refusal): a holder in another PID namespace reads as dead; two sessions that resolve different lock
# directories never see each other; a wall-clock step can shift `lstart`; a holder whose stdout reader
# vanished keeps the lock until its next write, and INT/QUIT do not stop a backgrounded bash.
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
#
# To see who holds a lock:  readlink <lockdir>/pr-checks+<owner>+<repo>+<pr>.lock   (pid|lstart|epoch)
#                           ps -o args= -p <pid>

ML_STATE=""; ML_WHY=""; ML_REPO=""; ML_HOLDER_PID=""; ML_HOLDER_AGE=""
_ML_LINK=""; _ML_VALUE=""; _ML_D=""

# _ml_norm <owner/repo | url> — print lowercase owner/repo, or return 1. Strips any user:token@,
# scheme, host (must be github.com), trailing `/` and `.git`; the credential never reaches a name.
# Lowercased FIRST so an upper-case `.GIT` suffix is stripped like `.git`.
_ml_norm() {
  local s host path rest auth
  s="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  s="${s%/}"; s="${s%.git}"; s="${s%/}"
  case "$s" in
    *://*)  rest="${s#*://}"; auth="${rest%%/*}"
            case "$rest" in */*) path="${rest#*/}" ;; *) path="" ;; esac
            host="${auth##*@}"; host="${host%%:*}" ;;
    *@*:*)  rest="${s#*@}"; host="${rest%%:*}"; path="${rest#*:}" ;;
    github.com/*) host="github.com"; path="${s#*/}" ;;   # GH_REPO may carry the host: HOST/OWNER/REPO
    *)      host="github.com"; path="$s" ;;
  esac
  case "$host" in github.com|www.github.com) ;; *) return 1 ;; esac
  [[ "$path" =~ ^[a-z0-9][a-z0-9._-]*/[a-z0-9._-]+$ ]] || return 1
  printf '%s' "$path"
}

# _ml_dir — set _ML_D to a usable lock directory (a real directory, ours, writable, and not writable by
# group or other), or return 1. The ownership/symlink/mode test is what stops a pre-created hostile
# /tmp path, or a loosely-shared SOLEUR_MONITOR_LOCK_DIR, from becoming the lock root.
_ml_dir() {
  local d="${SOLEUR_MONITOR_LOCK_DIR:-${XDG_RUNTIME_DIR:-/tmp}/soleur-monitor-locks-$(id -u 2>/dev/null || echo 0)}"
  _ML_D=""
  if [ -L "$d" ]; then return 1; fi
  if [ ! -e "$d" ]; then ( umask 077; mkdir -p "$d" ) 2>/dev/null || return 1; fi
  if [ -d "$d" ] && [ -O "$d" ] && [ -w "$d" ] && [ -z "$(find "$d" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" ]; then
    _ML_D="$d"; return 0
  fi
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

# _ml_alive <pid> <recorded-lstart> — 0 when that exact process is still running. A record with no
# start time cannot prove the pid was not reused, so it is stale.
_ml_alive() {
  local pid="$1" rec="$2" ident st cur
  [[ "$pid" =~ ^[0-9]{1,10}$ ]] && [ "$pid" -ge 1 ] || return 1
  ident="$(_ml_ident "$pid")" || return 1
  st="${ident%%|*}"; cur="${ident#*|}"
  case "$st" in Z*) return 1 ;; esac  # mut:zombie
  [ -n "$rec" ] && [ "$rec" = "$cur" ] || return 1  # mut:lstart
  return 0
}

# _ml_reclaim <link> <stale-record> — remove a stale lock, serialised by a `mkdir` guard so that two
# contenders that both read the same stale record cannot interleave their compare and their remove
# (the loser would delete the winner's fresh lock). 0 when this call did the reclaim step, 1 when
# another process holds the guard (the caller retries).
_ml_reclaim() {
  local g="$1.reclaim"
  if ! mkdir "$g" 2>/dev/null; then
    # A guard left by a reclaimer that died inside its few-microsecond window must not wedge the key.
    if [ -n "$(find "$g" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then rmdir "$g" 2>/dev/null; fi
    return 1
  fi
  # Remove only what we saw: a symlink still naming the stale record, or a regular-file stand-in. An ABSENT link is
  # left alone, since a fresh lock may be created in the instant after we looked.
  if [ -L "$1" ]; then
    if [ "$(readlink "$1" 2>/dev/null)" = "$2" ]; then rm -f "$1"; fi
  elif [ -e "$1" ]; then
    rm -f "$1"
  fi
  rmdir "$g" 2>/dev/null
  return 0
}

_ml_unavailable() { ML_STATE="unavailable"; ML_WHY="$1"; return 2; }

monitor_lock_acquire() {
  ML_STATE=""; ML_WHY=""; ML_REPO=""; ML_HOLDER_PID=""; ML_HOLDER_AGE=""; _ML_LINK=""; _ML_VALUE=""
  local pr="${2:-}" key link me ident mylstart value now holder hpid hls hep
  local spins=0 reclaims=0 waited=0 grace="${SOLEUR_MONITOR_LOCK_GRACE_S:-1}"
  if [ "${SOLEUR_MONITOR_LOCK:-}" = "off" ]; then ML_STATE="disabled"; ML_WHY="SOLEUR_MONITOR_LOCK=off"; return 2; fi
  ML_REPO="$(_ml_norm "${1:-}")" || { ML_REPO=""; _ml_unavailable "repo not derivable (needs a github.com owner/repo)"; return 2; }
  [[ "$pr" =~ ^[0-9]{1,9}$ ]] || { _ml_unavailable "PR number is not numeric"; return 2; }
  pr=$((10#$pr))
  _ml_dir || { _ml_unavailable "lock directory unusable (must be a real directory we own, not writable by others)"; return 2; }
  me="$$"
  ident="$(_ml_ident "$me")" || { _ml_unavailable "ps cannot read this process start time"; return 2; }
  mylstart="${ident#*|}"
  now="$(date +%s 2>/dev/null)"; [[ "$now" =~ ^[0-9]{1,10}$ ]] || now=0
  value="$me|$mylstart|$now"
  key="${ML_REPO//\//+}"
  link="$_ML_D/pr-checks+$key+$pr.lock"  # mut:key
  while :; do
    spins=$((spins + 1))
    if [ "$spins" -gt 12 ]; then _ml_unavailable "lock contended or not creatable"; return 2; fi
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
    # Already ours only when the record is OURS in full: a record that merely names our pid (a killed
    # predecessor, or another PID namespace) carries a foreign start time and must be reclaimed, or
    # the next monitor would read this live holder as pid-reused and steal the lock.
    if [ "$hpid" = "$me" ] && [ "$hls" = "$mylstart" ]; then
      _ML_LINK="$link"; _ML_VALUE="$holder"; ML_STATE="held"; return 0
    fi
    if _ml_alive "$hpid" "$hls"; then
      if [ "$waited" -lt 2 ]; then
        waited=$((waited + 1)); sleep "$grace"; continue
      fi
      ML_HOLDER_PID="$hpid"; ML_STATE="held-by-other"
      if [[ "$hep" =~ ^[0-9]{1,10}$ ]] && [ "$now" -ge "$((10#$hep))" ]; then ML_HOLDER_AGE=$((now - 10#$hep)); else ML_HOLDER_AGE="?"; fi
      return 1
    fi
    # Stale: dead, reused pid, zombie, no start time or malformed.
    if [ "$reclaims" -ge 1 ]; then _ml_unavailable "lock contended (stale record reclaimed twice)"; return 2; fi
    if _ml_reclaim "$link" "$holder"; then reclaims=1; else sleep 0.1 2>/dev/null || sleep 1; fi
  done
}

monitor_lock_release() {
  [ -n "$_ML_LINK" ] || return 0
  if [ -L "$_ML_LINK" ] && [ "$(readlink "$_ML_LINK" 2>/dev/null)" = "$_ML_VALUE" ]; then rm -f "$_ML_LINK"; fi  # mut:release-cond
  _ML_LINK=""; _ML_VALUE=""
  return 0
}

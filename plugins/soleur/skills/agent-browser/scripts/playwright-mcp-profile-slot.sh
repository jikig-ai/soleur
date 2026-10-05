# shellcheck shell=bash
# Profile-slot lease for the project .mcp.json Playwright launch. SOURCED, never executed:
#
#     . plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh || exit 1
#
# Sets `prof` to a --user-data-dir no other LIVE launch holds, and kills nothing. Why a lease at all: the
# pinned @playwright/mcp@0.0.78 already refuses a second server on a locked profile (its isProfileLocked
# check throws "Browser is already in use" BEFORE it launches anything), so the lease does not stop a
# teardown. It exists because (a) the reaper this replaces killed siblings and removed Singleton*, the one
# operation that really lets two Chromes share a profile, and (b) a concurrent session must still get a
# usable browser instead of that error. Each launch therefore leases a slot:
#
#   * slot 0 is the persistent profile $HOME/.cache/playwright-mcp-profile (logins survive);
#     slots 1..31 are $HOME/.cache/playwright-mcp-profile-<n>;
#   * a slot is claimed with a flock on <slot>/.pwslot.lock held on fd 9. fd 9 survives the
#     `exec env ... python3 <proxy>` that follows, belongs to the proxy process for the whole server
#     lifetime (the proxy's own children do not inherit it: subprocess close_fds), and the kernel
#     releases it on ANY exit, SIGKILL included;
#   * after winning the lock the launcher's $PPID is written to <slot>/.pwslot.owner (mode 600). A
#     /mcp reconnect keeps the same launcher, a different session has a different one;
#   * slot 0 waits (PW_PROFILE_SLOT0_WAIT_S, default 7 seconds) only when the recorded owner is THIS
#     session's launcher or cannot be read (fails toward waiting): the old proxy's teardown is usually
#     well under 5 s and up to ~15 s in the worst case (STDIN_CLOSE_WAIT_S + 2x GRACE_S + the child
#     wait, see Proxy.teardown), so 7 s is a heuristic and a miss falls to slot 1 with a note. A slot
#     held by another session is skipped at once; slots 1+ never wait. Whenever slot 0 is skipped ONE
#     stderr line says so and that the persistent profile's logins are not available in this session;
#   * after winning the lock, a SingletonLock whose owner is a live Chrome means a leftover or foreign
#     Chrome owns the profile: the slot is skipped (never kill it, never remove its lock; slot 0 gets
#     the same wait-then-recheck). The probe fails toward BUSY: a pid counts as alive when /proc/<pid>
#     exists or kill -0 does not answer "No such process" (EPERM = alive), and as a Chrome owner when
#     its comm (/proc/<pid>/comm, else ps) is chrome-like or unreadable. A lock naming another host is
#     busy. Only a dead pid, or a live pid that is provably not a Chrome (a recycled pid), makes the
#     Singleton* files stale, and they are then removed (rm -f, never recursive);
#   * a slot that cannot be used (mkdir, lock file, open or an flock error) is skipped for slots >= 1; slot
#     0 or an unusable flock ends the search;
#   * no usable flock (stock macOS has none; busybox flock lacks -E): slot 0 is claimed WITHOUT a lease
#     when its SingletonLock is absent or provably stale, so the first session keeps the persistent
#     profile; otherwise the unique fallback;
#   * the unique fallback is $base-p$$ (a non-numeric infix, so it can never alias slot N), created
#     mode 700, with a stderr note naming the cause (no flock, a lock error, or all slots busy).
#     Never blocks, never kills.
#
# Sourced-script hygiene: `return`, never `exit`; no `set -e`/`set -u` (they would leak into the launch
# shell); every helper and variable carries the _pwslot_ prefix and is unset before returning; fd 9 is
# opened in the surviving shell, never inside $(...). Opening the lock file is pre-tested in a subshell
# because a failing `exec 9>> file` redirection can terminate a POSIX-mode shell.
# Test seam: PW_PROFILE_SLOT0_WAIT_S shortens the slot-0 wait; it changes timing only.

_pwslot_note() { printf 'playwright-mcp-profile-slot: %s\n' "$1" >&2; }

_pwslot_base="$HOME/.cache/playwright-mcp-profile"
_pwslot_max=32
_pwslot_wait0="${PW_PROFILE_SLOT0_WAIT_S:-7}"
case "$_pwslot_wait0" in
  '' | . | *[!0-9.]* | *.*.*)
    _pwslot_note "ignored PW_PROFILE_SLOT0_WAIT_S='$_pwslot_wait0' (not a non-negative number); using 7 seconds"
    _pwslot_wait0=7
    ;;
esac
_pwslot_fallback="$_pwslot_base-p$$"
_pwslot_why=""
_pwslot_cause=""
_pwslot_flockbad=0
_pwslot_skip0=""
prof=""

# _pwslot_owner_busy <SingletonLock target, "host-pid"> -> 0 treat as a live owner (skip) | 1 provably stale.
# Sets _pwslot_why when busy. Fails toward busy: only a definite "no such process" or a live pid that is
# provably not a Chrome is stale.
_pwslot_owner_busy() {
  _pwslot_t=$1
  _pwslot_p=${_pwslot_t##*-}
  case "$_pwslot_p" in
    '' | *[!0-9]*) _pwslot_p=0 ;;
  esac
  # no pid to protect (also keeps kill -0 away from pid 0, the whole process group)
  if ! [ "$_pwslot_p" -gt 0 ] 2>/dev/null; then return 1; fi
  _pwslot_me=$(uname -n 2>/dev/null) || _pwslot_me=""
  if [ -z "$_pwslot_me" ] || [ "${_pwslot_t%-*}" != "$_pwslot_me" ]; then
    _pwslot_why="its SingletonLock names host '${_pwslot_t%-*}', not this host"
    return 0
  fi
  _pwslot_alive=1
  if ! [ -d "/proc/$_pwslot_p" ]; then
    # kill -0 answers EPERM for a live pid that is not ours (hidepid mounts hide it from /proc too)
    if ! _pwslot_m=$(LC_ALL=C; kill -0 "$_pwslot_p" 2>&1); then
      case "$_pwslot_m" in
        *'No such process'*) _pwslot_alive=0 ;;
      esac
    fi
  fi
  if [ "$_pwslot_alive" -eq 0 ]; then return 1; fi
  _pwslot_c=""
  if [ -r "/proc/$_pwslot_p/comm" ]; then
    read -r _pwslot_c 2>/dev/null < "/proc/$_pwslot_p/comm" || :
  fi
  if [ -z "$_pwslot_c" ]; then
    _pwslot_c=$(ps -o comm= -p "$_pwslot_p" 2>/dev/null) || _pwslot_c=""
  fi
  case "$_pwslot_c" in
    *[Cc]hrom* | *headless_shell* | '')
      _pwslot_why="its SingletonLock names a live Chrome (pid $_pwslot_p)"
      return 0
      ;;
  esac
  return 1 # a live pid that is not a Chrome: the pid was recycled, the lock is stale
}

# _pwslot_owner_wait <dir> -> 0 the recorded owner is this session's launcher (or unknown): worth waiting
_pwslot_owner_wait() {
  _pwslot_ow=""
  _pwslot_self=$PPID
  read -r _pwslot_ow 2>/dev/null < "$1/.pwslot.owner" || :
  case "$_pwslot_ow" in
    '' | *[!0-9]*) return 0 ;;
  esac
  [ "$_pwslot_ow" = "$_pwslot_self" ]
}

# _pwslot_pause: one poll tick (0.2 s where sleep takes fractions, else 1 s)
_pwslot_pause() { sleep 0.2 2> /dev/null || sleep 1; }

# _pwslot_ticks <seconds> -> prints the number of 0.2 s ticks that cover it (first decimal only)
_pwslot_ticks() {
  _pwslot_ip=${1%%.*}
  : "${_pwslot_ip:=0}"
  _pwslot_fp=""
  case "$1" in
    *.*) _pwslot_fp=${1#*.} ;;
  esac
  _pwslot_fp=${_pwslot_fp%"${_pwslot_fp#?}"}
  : "${_pwslot_fp:=0}"
  printf '%s' "$((10#$_pwslot_ip * 5 + (_pwslot_fp + 1) / 2))"
}

# _pwslot_claim <dir> <slot-number> -> 0 claimed (fd 9 holds the lease)
#   | 1 busy (_pwslot_why says why) | 2 this slot cannot be used (_pwslot_cause; _pwslot_flockbad=1 when flock itself failed)
_pwslot_claim() {
  _pwslot_d=$1
  _pwslot_n=$2
  # shellcheck disable=SC2174  # the mode is wanted on the slot directory only: the profile holds cookies
  if ! mkdir -p -m 700 "$_pwslot_d" 2> /dev/null; then
    _pwslot_cause="cannot create $_pwslot_d"
    return 2
  fi
  if ! (: >> "$1/.pwslot.lock") 2> /dev/null; then
    _pwslot_cause="cannot create the lock file in $_pwslot_d"
    return 2
  fi
  if ! exec 9>> "$_pwslot_d/.pwslot.lock"; then
    _pwslot_cause="cannot open the lock file in $_pwslot_d"
    return 2
  fi
  _pwslot_waitok=0
  flock -E 75 -n 9
  _pwslot_rc=$?
  if [ "$_pwslot_rc" -eq 75 ]; then
    if [ "$_pwslot_n" -eq 0 ] && _pwslot_owner_wait "$_pwslot_d"; then
      _pwslot_waitok=1
      flock -E 75 -w "$_pwslot_wait0" 9
      _pwslot_rc=$?
    fi
    if [ "$_pwslot_rc" -eq 75 ]; then
      exec 9>&-
      _pwslot_why="its lock is held by another live launch"
      return 1
    fi
  fi
  if [ "$_pwslot_rc" -ne 0 ]; then
    exec 9>&-
    _pwslot_flockbad=1
    _pwslot_cause="flock failed (rc=$_pwslot_rc) on $_pwslot_d/.pwslot.lock"
    return 2
  fi
  _pwslot_left=-1
  while [ -L "$_pwslot_d/SingletonLock" ]; do
    _pwslot_tg=$(readlink "$_pwslot_d/SingletonLock" 2> /dev/null) || _pwslot_tg=""
    if [ -z "$_pwslot_tg" ]; then
      _pwslot_why="its SingletonLock cannot be read"
    elif ! _pwslot_owner_busy "$_pwslot_tg"; then
      break
    fi
    if [ "$_pwslot_n" -eq 0 ] && [ "$_pwslot_waitok" -eq 0 ] && [ "$_pwslot_left" -lt 0 ]; then
      if _pwslot_owner_wait "$_pwslot_d"; then _pwslot_waitok=1; fi
    fi
    if [ "$_pwslot_waitok" -eq 1 ] && [ "$_pwslot_left" -lt 0 ]; then
      _pwslot_left=$(_pwslot_ticks "$_pwslot_wait0")
    fi
    if [ "$_pwslot_left" -gt 0 ]; then
      _pwslot_left=$((_pwslot_left - 1))
      _pwslot_pause
      continue
    fi
    exec 9>&-
    return 1
  done
  (
    umask 077
    rm -f "$_pwslot_d/.pwslot.owner"
    printf '%s\n' "$PPID" > "$1/.pwslot.owner"
  ) 2> /dev/null || :
  rm -f "$_pwslot_d"/Singleton* 2> /dev/null
  return 0
}

# _pwslot_flock_usable -> 0 when `flock -E 75 -w 0 <fd>` works here (util-linux flock; stock macOS has none, busybox lacks -E)
# The probe locks /dev/null, ONE inode every concurrent launch on the host shares, so a probe that loses that race answers
# rc 75: the value -E was given, which only a flock that understands -E can return. 75 therefore proves the capability exactly
# as 0 does; reading it as "unusable" sent simultaneous launches down the no-lease branch and onto one shared slot 0.
# A flock without -E exits with a usage error (not 75), so it still reads as unusable.
_pwslot_flock_usable() {
  command -v flock > /dev/null 2>&1 || return 1
  flock -E 75 -w 0 8 8< /dev/null > /dev/null 2>&1
  case $? in
    0 | 75) return 0 ;;
  esac
  return 1
}

if _pwslot_flock_usable; then
  _pwslot_i=0
  _pwslot_unusable=0
  while [ "$_pwslot_i" -lt "$_pwslot_max" ]; do
    if [ "$_pwslot_i" -eq 0 ]; then
      _pwslot_dir=$_pwslot_base
    else
      _pwslot_dir=$_pwslot_base-$_pwslot_i
    fi
    _pwslot_claim "$_pwslot_dir" "$_pwslot_i"
    _pwslot_st=$?
    if [ "$_pwslot_st" -eq 0 ]; then
      prof=$_pwslot_dir
      break
    fi
    if [ "$_pwslot_st" -eq 1 ]; then
      if [ "$_pwslot_i" -eq 0 ]; then _pwslot_skip0=$_pwslot_why; fi
    else
      _pwslot_unusable=$((_pwslot_unusable + 1))
      if [ "$_pwslot_i" -eq 0 ]; then _pwslot_skip0=$_pwslot_cause; fi
      if [ "$_pwslot_i" -eq 0 ] || [ "$_pwslot_flockbad" -eq 1 ]; then break; fi
    fi
    _pwslot_i=$((_pwslot_i + 1))
  done
  if [ -z "$prof" ]; then
    if [ "$_pwslot_unusable" -eq 0 ]; then
      _pwslot_cause="all $_pwslot_max slots are busy"
    else
      _pwslot_cause="no slot could be leased: $_pwslot_cause"
    fi
  fi
else
  _pwslot_cause="no usable flock (util-linux flock with -E is needed)"
  # shellcheck disable=SC2174
  if mkdir -p -m 700 "$_pwslot_base" 2> /dev/null; then
    _pwslot_tg=""
    if [ -L "$_pwslot_base/SingletonLock" ]; then
      _pwslot_tg=$(readlink "$_pwslot_base/SingletonLock" 2> /dev/null) || _pwslot_tg=""
      if [ -z "$_pwslot_tg" ]; then
        _pwslot_why="its SingletonLock cannot be read"
        _pwslot_skip0=$_pwslot_why
      elif _pwslot_owner_busy "$_pwslot_tg"; then
        _pwslot_skip0=$_pwslot_why
      fi
    fi
    if [ -z "$_pwslot_skip0" ]; then
      rm -f "$_pwslot_base"/Singleton* 2> /dev/null
      prof=$_pwslot_base
      _pwslot_note "$_pwslot_cause; using the persistent profile $prof without a lease"
    fi
  else
    _pwslot_skip0="cannot create $_pwslot_base"
  fi
fi

if [ -n "$_pwslot_skip0" ] && [ -n "$prof" ]; then
  _pwslot_note "slot 0 (the persistent profile $_pwslot_base) was skipped: $_pwslot_skip0; its logins are not available in this session; using $prof"
fi

if [ -z "$prof" ]; then
  prof=$_pwslot_fallback
  # shellcheck disable=SC2174
  mkdir -p -m 700 "$prof" 2> /dev/null || :
  if [ -n "$_pwslot_skip0" ]; then
    _pwslot_note "slot 0 (the persistent profile $_pwslot_base) was skipped: $_pwslot_skip0; its logins are not available in this session"
  fi
  _pwslot_note "$_pwslot_cause; using the unique profile $prof"
fi

for _pwslot_v in $(compgen -A function _pwslot_); do unset -f "$_pwslot_v"; done
for _pwslot_v in $(compgen -v _pwslot_); do unset "$_pwslot_v"; done
unset _pwslot_v
return 0

# shellcheck shell=bash
# Profile-slot lease for the project .mcp.json Playwright launch. SOURCED, never executed:
#
#     . plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh || exit 1; [ -n "$prof" ] || exit 1
#
# Sets `prof` to a --user-data-dir no other LIVE launch holds, and kills nothing. Chrome keeps one
# profile per owner (a second server on the same directory tears the first one's pages down via
# SingletonLock), so each launch leases a slot:
#
#   * slot 0 is the persistent profile $HOME/.cache/playwright-mcp-profile (logins survive);
#     slots 1..31 are $HOME/.cache/playwright-mcp-profile-<n>;
#   * a slot is claimed with a flock on <slot>/.pwslot.lock held on fd 9. fd 9 survives the
#     `exec env ... python3 <proxy>` that follows, belongs to the proxy process for the whole server
#     lifetime (the proxy's own children do not inherit it: subprocess close_fds), and the kernel
#     releases it on ANY exit, SIGKILL included;
#   * after winning the lock, a SingletonLock whose owner pid is alive means a leftover or foreign Chrome
#     owns the profile: the slot is skipped (never kill it, never remove its lock). A dead owner's
#     Singleton* files are stale and are removed;
#   * slot 0 only waits for the lock (PW_PROFILE_SLOT0_WAIT_S, default 7 seconds): a /mcp reconnect's old
#     proxy keeps its lock for up to its 5 s teardown grace, and a reconnect must land back on the
#     persistent profile rather than an empty one. Slots 1+ never wait;
#   * no flock binary, a filesystem that cannot lock, or all 32 slots busy: a unique $base-$$ directory,
#     with a stderr note. Never blocks, never kills.
#
# Sourced-script hygiene: `return`, never `exit`; no `set -e`/`set -u` (they would leak into the launch
# shell); every helper and variable carries the _pwslot_ prefix and is unset before returning; fd 9 is
# opened in the surviving shell, never inside $(...).
# Test seam: PW_PROFILE_SLOT0_WAIT_S shortens the slot-0 wait; it changes timing only.

_pwslot_base="$HOME/.cache/playwright-mcp-profile"
_pwslot_max=32
_pwslot_wait0="${PW_PROFILE_SLOT0_WAIT_S:-7}"
_pwslot_fallback="$_pwslot_base-$$"
prof=""

_pwslot_note() { printf 'playwright-mcp-profile-slot: %s\n' "$1" >&2; }

# _pwslot_claim <dir> <wait-seconds> -> 0 claimed (fd 9 holds the lease) | 1 busy | 2 no lease can be taken here
_pwslot_claim() {
  # shellcheck disable=SC2174  # the mode is wanted on the slot directory only: the profile holds cookies
  mkdir -p -m 700 "$1" 2>/dev/null || return 2
  ( : >> "$1/.pwslot.lock" ) 2>/dev/null || return 2
  exec 9>> "$1/.pwslot.lock" || return 2
  _pwslot_wait="$2"
  flock -E 75 -w "$_pwslot_wait" 9
  _pwslot_rc=$?
  if [ "$_pwslot_rc" -eq 75 ]; then
    exec 9>&-
    return 1
  elif [ "$_pwslot_rc" -ne 0 ]; then
    exec 9>&-
    return 2
  fi
  if [ -L "$1/SingletonLock" ]; then
    _pwslot_target=$(readlink "$1/SingletonLock" 2>/dev/null)
    _pwslot_pid=${_pwslot_target##*-}
    case "$_pwslot_pid" in
      '' | *[!0-9]*) _pwslot_pid=0 ;;
    esac
    if ps -p "$_pwslot_pid" >/dev/null 2>&1; then
      exec 9>&-
      return 1
    fi
  fi
  rm -f "$1"/Singleton* 2>/dev/null
  return 0
}

if command -v flock >/dev/null 2>&1; then
  _pwslot_i=0
  while [ "$_pwslot_i" -lt "$_pwslot_max" ]; do
    if [ "$_pwslot_i" -eq 0 ]; then
      _pwslot_dir=$_pwslot_base
      _pwslot_w=$_pwslot_wait0
    else
      _pwslot_dir=$_pwslot_base-$_pwslot_i
      _pwslot_w=0
    fi
    _pwslot_claim "$_pwslot_dir" "$_pwslot_w"
    _pwslot_st=$?
    if [ "$_pwslot_st" -eq 0 ]; then
      prof=$_pwslot_dir
      break
    fi
    if [ "$_pwslot_st" -eq 2 ]; then
      break
    fi
    _pwslot_i=$((_pwslot_i + 1))
  done
fi

if [ -z "$prof" ]; then
  prof=$_pwslot_fallback
  _pwslot_note "no slot lease was available (no flock, no lock support, or all $_pwslot_max slots busy); using the unique profile $prof"
fi

unset -f _pwslot_claim _pwslot_note
for _pwslot_v in $(compgen -v _pwslot_); do unset "$_pwslot_v"; done
unset _pwslot_v
return 0

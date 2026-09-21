#!/usr/bin/env bash
#
# git-data cutover — a READ-ONLY PROOF until #8211 (epic #5274 / ADR-068 / ADR-220).
#
# WHAT THIS SCRIPT DOES TODAY. It proves, without changing anything on any host, that the
# reviewer-gated cutover job can reach root on the git-data host and that the store is in the
# state a future cutover would start from:
#   1. access_gate (ADR-220): web-1 answers, `ssh -W` through web-1 reaches git-data's sshd,
#      and root on git-data accepts the root key. Any non-ok verdict exits 3.
#   2. three store probes, each fail-closed, each through gd_capture:
#        refuse_if_unmounted        `findmnt -no SOURCE $OLD_ROOT` must name a /dev/ device
#        refuse_if_cut_over         ...and that device must not be $LUKS_MAPPER
#        refuse_if_store_not_empty  $OLD_REPOS must be a directory on that SAME source
#                                   (`findmnt -T`) holding zero `*.git` entries
#      A refusal exits 5 with a fixed verdict word. A read that could not be completed
#      (transport, timeout, oversized or multi-line answer) is `probe_failed rc=<n>`, never
#      a store-state verdict.
#   3. the fence probe (#8101), refuse_if_fence_not_intact: the pre-receive fence the bootstrap
#      plants is a real root:git 750 hooks directory under a root-owned, non-writable parent,
#      holding a real root:root 755 pre-receive the git user can run; the installed transport
#      wrapper pins pushes to it and the system core.hooksPath names it; and it sits on the
#      accepted store device. It checks the fence's SHAPE, not which hook is installed.
# Exit 0 means: access ok, store mounted on a plaintext device, not cut over, empty, and a push
# would run a root-owned pre-receive of the planted shape.
#
# WHAT IT NO LONGER DOES. The rsync / freeze / repoint / flag-flip / rollback / wipe body was
# deleted (git history keeps it). Its freeze and reload called systemd units that do not
# exist on either host, and a second run after a repoint could rsync a store onto itself.
# The real modes are rebuilt on real mechanisms in #8211. The rebuilt copy must carry hooks in
# both passes and re-run the fence probe against the fresh root, expecting the mapper, before
# any flag flip (#8101, carried by #8211). Until then, a caller that still
# asks for one (DRY_RUN other than 1, ROLLBACK or CONFIRM_WIPE other than 0) is refused with
# `verdict=real_cutover_unreconciled` (exit 5) BEFORE any remote call. Defaults: DRY_RUN=1,
# ROLLBACK=0, CONFIRM_WIPE=0 (unset or empty takes the default).
#
# NO DOPPLER. The flag read moved to its own workflow step (git-data-flag-precheck.sh) so the
# `prd` read token never reaches the process that handles host bytes. This script reads no
# secret store and receives no Doppler token.
#
# ACCESS PATH (ADR-220, #6680). The bridge exports WEB_HOST_SSH (root on web-1). git-data
# (10.0.1.20) has no ingress of its own: it is reached through web-1 as an `ssh -W`
# direct-tcpip channel, authenticating end to end, so no key and no agent socket lands on
# web-1. The workflow supplies GIT_DATA_SSH as `ssh -F <ssh_config>`, whose git-data block
# carries the root key and the literal ProxyCommand through web-1. There are no `ssh`
# fallbacks: an unset invocation fails closed instead of dialing a bare `ssh`.
#
# CAPTURED VALUES (P8). Host-chosen bytes are unauthenticated while host keys are unverified
# (#7226): a compromised web-1 could answer "mounted, empty". gd_capture therefore bounds
# every remote read (30 s, 4096 bytes), accepts a value only when it matches an anchored
# pattern in full, and never prints the value. This evidence is still not authentication.
#
# Exit codes: 0 clear; 1 internal error (die: the access gate's mktemp failed); 3 access gate;
# 5 refusal (real mode, store probe, fence probe); 78 xtrace refusal.
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

log()  { echo "[git-data-cutover] $*"; }
step() { echo; echo "[git-data-cutover] ===== $* ====="; }
die()  { echo "[git-data-cutover] FATAL: $*" >&2; exit 1; }

# --- Configuration (all overridable by the workflow; documented defaults) -----
GIT_DATA_HOST="${GIT_DATA_HOST:-10.0.1.20}"
OLD_ROOT="${OLD_ROOT:-/mnt/git-data}"                 # the plaintext store every wrapper hardcodes
LUKS_MAPPER="${LUKS_MAPPER:-/dev/mapper/git-data}"    # the LUKS device-mapper node a cutover mounts
REPO_SUBDIR="${REPO_SUBDIR:-repositories}"
OLD_REPOS="${OLD_ROOT}/${REPO_SUBDIR}"
WEB_HOSTS="${WEB_HOSTS:-10.0.1.10}"   # web-1 only: the read-only proof needs one jump host, not every web host

# --- Roster + invocations: parsed ONCE, used by the gate AND every later call ---
# One parse (`read -ra`: first line only, no glob expansion) so the addresses and argv the
# access gate proves are byte-for-byte the ones the store probes later dial. A value that
# is multi-line or not dotted-numeric is recorded, never dialed: an address starting with
# `-` would become an ssh option. Not an exit here — the access gate reports it as a verdict.
WEB_HOST_LIST=()
ROSTER_ERR_ROLE=""    # "" when valid; otherwise the role whose input is malformed
ROSTER_ERR_VERDICT=""
resolve_roster() {
  local h
  case "${WEB_HOSTS}${GIT_DATA_HOST}${WEB_HOST_SSH:-}${GIT_DATA_SSH:-}" in
    *$'\n'*) ROSTER_ERR_ROLE=web; ROSTER_ERR_VERDICT=invalid_multiline_input; return 0 ;;
  esac
  read -ra WEB_HOST_LIST <<< "$WEB_HOSTS"
  for h in "${WEB_HOST_LIST[@]}"; do
    if ! [[ "$h" =~ ^[0-9.]+$ ]]; then
      WEB_HOST_LIST=(); ROSTER_ERR_ROLE=web; ROSTER_ERR_VERDICT=invalid_host; return 0
    fi
  done
  if ! [[ "$GIT_DATA_HOST" =~ ^[0-9.]+$ ]]; then
    ROSTER_ERR_ROLE=git-data-jump; ROSTER_ERR_VERDICT=invalid_host
  fi
}

# --- Temp state (read by the EXIT trap) ---------------------------------------
ACCESS_TMP=""       # probe capture dir of the access gate; removed on every exit
CAPTURE_TMP=""      # stderr capture dir of gd_capture; removed on every exit
GD_CAPTURED=""      # the last value gd_capture ACCEPTED; never printed

# The trap only drops temp captures: nothing on any host is ever changed, so nothing is
# ever recovered.
cleanup() {
  local rc=$?
  trap - EXIT
  _access_tmp_drop || true
  _capture_tmp_drop || true
  exit "$rc"
}
trap cleanup EXIT

# ============================================================================
# refuse_real_modes — a real cutover, rollback or wipe cannot be requested (#8211)
# ============================================================================
# One arm per variable, so dropping one is a visible edit. Runs FIRST in main(): the refusal
# must leave an empty remote timeline. Prints variable NAMES, never their values.
refuse_real_modes() {
  local bad=""
  [ "${DRY_RUN:-1}" = 1 ] || bad="${bad} DRY_RUN"
  [ "${ROLLBACK:-0}" = 0 ] || bad="${bad} ROLLBACK"
  [ "${CONFIRM_WIPE:-0}" = 0 ] || bad="${bad} CONFIRM_WIPE"
  [ -n "$bad" ] || return 0
  log "REFUSE verdict=real_cutover_unreconciled vars=${bad# }"
  echo "::error title=git-data-cutover::verdict=real_cutover_unreconciled"
  log "remedy: this script is a read-only proof. The real cutover, rollback and wipe are rebuilt on real mechanisms in #8211; dispatch without DRY_RUN/ROLLBACK/CONFIRM_WIPE."
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf -- '- REFUSE verdict=real_cutover_unreconciled\n' >> "$GITHUB_STEP_SUMMARY" || true
  fi
  exit 5
}

# ============================================================================
# gd_capture — one bounded, pattern-validated remote read on git-data (D-7)
# ============================================================================
# gd_capture <anchored-regex> <remote-cmd>: runs the command over GIT_DATA_SSH with a 30 s
# bound, refuses more than 4096 bytes of stdout, takes ssh's own rc (PIPESTATUS[0], not the
# pipeline's), strips ONE trailing newline, and accepts the value only when it matches the
# pattern in full. A multi-line value never matches. On success GD_CAPTURED holds the value;
# on failure it is empty and the return is ssh's rc, or 96 on a mismatch. The value is never
# printed; a failed read's stderr goes out capped and filtered through _access_stderr.
_capture_tmp_drop() {
  [ -n "$CAPTURE_TMP" ] || return 0
  rm -f "$CAPTURE_TMP/capture.err"
  rmdir "$CAPTURE_TMP" || return 1
  CAPTURE_TMP=""
}
gd_capture() {
  local pat="$1" cmd="$2" rc=0 val=""
  local -a inv
  GD_CAPTURED=""
  read -ra inv <<< "${GIT_DATA_SSH:-}"
  [ "${#inv[@]}" -gt 0 ] || return 97
  if [ -z "$CAPTURE_TMP" ]; then CAPTURE_TMP="$(mktemp -d)" || return 95; fi
  : > "$CAPTURE_TMP/capture.err" || return 95
  # One byte past the cap is read so an oversized answer is refused, never truncated into a
  # value that happens to match. The trailing '.' keeps $(...) from eating newlines.
  val="$(timeout 30 "${inv[@]}" -o BatchMode=yes -o ConnectTimeout=20 "$GIT_DATA_HOST" "$cmd" </dev/null 2>"$CAPTURE_TMP/capture.err" | head -c 4097
    st=("${PIPESTATUS[@]}"); printf '.'; exit "${st[0]}")" || rc=$?
  val="${val%.}"
  if [ "$rc" -ne 0 ]; then
    _access_stderr "$CAPTURE_TMP/capture.err"
    return "$rc"
  fi
  [ "${#val}" -le 4096 ] || return 96
  val="${val%$'\n'}"
  case "$val" in
    *$'\n'*) return 96 ;;
  esac
  if ! [[ "$val" =~ $pat ]]; then
    _access_stderr "$CAPTURE_TMP/capture.err"
    return 96
  fi
  GD_CAPTURED="$val"
}

# ============================================================================
# access_gate — every host reachable and authorized BEFORE any store probe (ADR-220)
# ============================================================================
# Three probes, strictly ordered; each runs only after the previous one read ok:
#   web            every roster member runs `true` over WEB_HOST_SSH.
#   git-data-jump  `ssh -W <git-data>:22 <first roster member>` must return an `SSH-2.0-`
#                  line FIRST: web-1's sshd forwards and something answers as an sshd, with
#                  NO git-data credential (liveness, not authenticity — #7226). The verdict
#                  keys on that line, never the pipeline rc, which is ssh's own exit status.
#                  stdin is /dev/null: its EOF makes the remote close right after the banner;
#                  with stdin held open the probe waits out its timeout.
#   git-data-auth  root login over GIT_DATA_SSH; unset -> git_data_root_key_absent (#8189).
# Non-ok exits 3 from THIS body. Keep the call a plain statement: inside $(...) or a
# pipeline its `exit 3` would only leave a subshell and the store probes would run anyway.
# Probe bytes are chosen by the edge or web-1 while host keys are unverified (#7226), and the
# runner parses workflow commands on stdout AND stderr. So every probe writes to a file, the
# -W line is only compared, and a failed probe's stderr is printed capped, printable-ASCII,
# behind a fixed prefix, inside a ::stop-commands:: span keyed on a per-run random token.
# A failure's reason= is a fixed word chosen by grep over that file, never probe bytes.
# ssh keeps the FIRST value of a repeated -o, so the appended options can add, never override.
_access_emit() { # <role> <host> <verdict> [rc] [reason]
  local detail="role=$1 host=$2 verdict=$3${4:+ rc=$4}${5:+ reason=$5}"
  log "ACCESS ${detail}"
  if [ "$3" = ok ]; then
    echo "::notice title=git-data-cutover access::role=$1 verdict=ok"
  else
    echo "::error title=git-data-cutover access::role=$1 verdict=$3${4:+ rc=$4}${5:+ reason=$5}"
  fi
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf -- '- ACCESS %s\n' "$detail" >> "$GITHUB_STEP_SUMMARY" || true
  fi
}
_access_reason() { # <rc> <captured-stderr-file>
  if [ "$1" = 124 ]; then echo timeout
  elif grep -qF 'administratively prohibited' "$2"; then echo forward_refused
  elif grep -qF 'Connection refused' "$2"; then echo connect_refused
  elif grep -qF 'No route to host' "$2"; then echo no_route
  elif grep -qF 'Permission denied' "$2"; then echo auth_refused
  else echo unknown
  fi
}
_access_fail() { # <role> <host> <rc> <captured-stderr-file> — emit, dump, stop
  _access_emit "$1" "$2" failed "$3" "$(_access_reason "$3" "$4")"
  _access_stderr "$4"
  exit 3
}
_access_stderr() { # <captured-stderr-file>
  [ -s "$1" ] || return 0
  local tok l
  tok="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
  echo "::stop-commands::${tok}"
  head -c 8192 "$1" | LC_ALL=C tr -cd '\12\40-\176' | while IFS= read -r l || [ -n "$l" ]; do
    printf '[git-data-cutover] probe-stderr: %s\n' "$l"
  done
  echo "::${tok}::"
}
# Removes ONLY the gate's three named captures, then the directory itself: the EXIT trap reads
# a global it did not bind, so nothing here may recurse into whatever that global holds.
_access_tmp_drop() {
  [ -n "$ACCESS_TMP" ] || return 0
  rm -f "$ACCESS_TMP/web.err" "$ACCESS_TMP/jump.err" "$ACCESS_TMP/auth.err"
  rmdir "$ACCESS_TMP" || return 1
  ACCESS_TMP=""
}
access_gate() {
  step "access gate (ADR-220): web -> git-data-jump -> git-data-auth, before any store probe"
  local h rc first
  local -a inv gdinv
  if [ -n "$ROSTER_ERR_ROLE" ]; then _access_emit "$ROSTER_ERR_ROLE" "<invalid>" "$ROSTER_ERR_VERDICT"; exit 3; fi
  read -ra inv <<< "${WEB_HOST_SSH:-}"
  if [ "${#inv[@]}" -eq 0 ]; then _access_emit web "-" web_host_ssh_unset; exit 3; fi
  if [ "${#WEB_HOST_LIST[@]}" -eq 0 ]; then _access_emit web "-" web_roster_empty; exit 3; fi
  ACCESS_TMP="$(mktemp -d)" || die "access gate: mktemp failed"

  for h in "${WEB_HOST_LIST[@]}"; do
    rc=0
    timeout 30 "${inv[@]}" -o BatchMode=yes -o ConnectTimeout=20 "$h" true \
      </dev/null >/dev/null 2>"$ACCESS_TMP/web.err" || rc=$?
    [ "$rc" -eq 0 ] || _access_fail web "$h" "$rc" "$ACCESS_TMP/web.err"
    _access_emit web "$h" ok
  done

  rc=0
  first="$(timeout 25 "${inv[@]}" -o BatchMode=yes -o ConnectTimeout=20 -W "${GIT_DATA_HOST}:22" "${WEB_HOST_LIST[0]}" \
    </dev/null 2>"$ACCESS_TMP/jump.err" | head -n 1)" || rc=$?
  first="${first%$'\r'}"
  case "$first" in
    SSH-2.0-*) _access_emit git-data-jump "$GIT_DATA_HOST" ok ;;
    *) _access_fail git-data-jump "$GIT_DATA_HOST" "$rc" "$ACCESS_TMP/jump.err" ;;
  esac

  read -ra gdinv <<< "${GIT_DATA_SSH:-}"
  if [ "${#gdinv[@]}" -eq 0 ]; then
    _access_emit git-data-auth "$GIT_DATA_HOST" git_data_root_key_absent
    log "remedy: no root credential reached this step — dispatch apply-git-data-root-key.yml (it mints the key and publishes its read token), then re-dispatch (ADR-220)."
    exit 3
  fi
  rc=0
  timeout 30 "${gdinv[@]}" -o BatchMode=yes -o ConnectTimeout=20 "$GIT_DATA_HOST" true \
    </dev/null >/dev/null 2>"$ACCESS_TMP/auth.err" || rc=$?
  [ "$rc" -eq 0 ] || _access_fail git-data-auth "$GIT_DATA_HOST" "$rc" "$ACCESS_TMP/auth.err"
  _access_emit git-data-auth "$GIT_DATA_HOST" ok
  _access_tmp_drop
}

# ============================================================================
# Store probes (D-5) — each fails closed with a fixed verdict word, exit 5
# ============================================================================
_store_emit() { # <probe> <verdict> [rc] [reason]
  local detail="probe=$1 verdict=$2${3:+ rc=$3}${4:+ reason=$4}"
  log "STORE ${detail}"
  if [ "$2" = ok ]; then
    echo "::notice title=git-data-cutover store::probe=$1 verdict=ok"
  else
    echo "::error title=git-data-cutover store::${detail}"
  fi
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf -- '- STORE %s\n' "$detail" >> "$GITHUB_STEP_SUMMARY" || true
  fi
}
_store_refuse() { # <probe> <verdict> [rc] [reason] — emit, stop
  _store_emit "$@"
  exit 5
}

# The capture pattern admits any one-line findmnt SOURCE shape (device, tmpfs, bind `[..]`,
# host:/export, or empty), so gd_capture's 96 means only "the answer could not be read as one
# line" and is reported with the transport failures. The device test is a separate local match.
#   rc 0 + a /dev/ source   ok
#   rc 0 + any other answer old_store_unmounted             (a non-device source, or none)
#   rc 1                    old_store_unmounted rc=1        (findmnt's own "no such mount")
#   any other rc            probe_failed rc=<n>             (124 timeout, 255 ssh, 141 SIGPIPE,
#                                                            96 unreadable answer, 95/97 local)
STORE_SOURCE=""
refuse_if_unmounted() {
  step "store probe: $OLD_ROOT is mounted on a device"
  local rc=0 q
  printf -v q '%q' "$OLD_ROOT"
  gd_capture '^[][A-Za-z0-9/_.:@+=-]*$' "findmnt -no SOURCE $q" || rc=$?
  case "$rc" in
    0) ;;
    1) _store_refuse store-mounted old_store_unmounted "$rc" ;;
    *) _store_refuse store-mounted probe_failed "$rc" ;;
  esac
  [[ "$GD_CAPTURED" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || _store_refuse store-mounted old_store_unmounted
  STORE_SOURCE="$GD_CAPTURED"
  _store_emit store-mounted ok
}

refuse_if_cut_over() {
  step "store probe: $OLD_ROOT is not already the LUKS mapper"
  [ -n "$STORE_SOURCE" ] || _store_refuse store-not-cut-over probe_failed
  [ "$STORE_SOURCE" != "$LUKS_MAPPER" ] || _store_refuse store-not-cut-over already_cut_over
  _store_emit store-not-cut-over ok
}

# One remote command whose only output is the count, run in ONE ssh session so the source it
# checks is the source it counts on. Every abnormal shape is a probe error (remote exit code),
# never a count of 0:
#   3  $OLD_REPOS is a dangling symlink, or exists but is not a directory
#   7  $OLD_REPOS is missing: git-data-bootstrap.sh creates it on every boot, so a mounted
#      root without it is not an empty store
#   5  `findmnt -T` could not resolve the source $OLD_REPOS lives on
#   6  that source differs from the one refuse_if_unmounted accepted (another volume
#      underneath, or a remount between the two ssh sessions)
#   4  find failed
# `find -H` follows a symlinked $OLD_REPOS itself, never the entries under it.
refuse_if_store_not_empty() {
  step "store probe: $OLD_REPOS holds no repositories"
  local rc=0 q qs
  [[ "$STORE_SOURCE" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || _store_refuse store-empty probe_failed
  printf -v q '%q' "$OLD_REPOS"
  printf -v qs '%q' "$STORE_SOURCE"
  gd_capture '^[0-9]+$' "d=$q; src=$qs; if [ -L \"\$d\" ] && [ ! -e \"\$d\" ]; then exit 3; fi; if [ ! -e \"\$d\" ]; then exit 7; fi; [ -d \"\$d\" ] || exit 3; s=\$(findmnt -no SOURCE -T \"\$d\") || exit 5; [ \"\$s\" = \"\$src\" ] || exit 6; n=\$(find -H \"\$d\" -mindepth 1 -maxdepth 1 -name '*.git' -printf .) || exit 4; echo \"\${#n}\"" || rc=$?
  [ "$rc" -eq 0 ] || _store_refuse store-empty probe_failed "$rc"
  [[ "$GD_CAPTURED" =~ ^0+$ ]] || _store_refuse store-empty store_not_empty
  _store_emit store-empty ok
}

# The fence probe (#8101). git-data-bootstrap.sh plants the pre-receive fence (CAS lease fence,
# freeze-sentinel denial, namespace check). A push reaches it through the transport wrapper, which
# pins `core.hooksPath` on git's command line, and git runs the hook AS THE git USER. So the probe
# reads what a push actually depends on, in ONE ssh session, and exits with the first failure, in
# this order:
#   10  the hooks dir is absent, or is a symlink            reason=hooks_dir_absent
#   12  pre-receive is absent, a symlink, not a regular
#       file, or not executable                             reason=hook_absent
#   16  an instrument failed (a stat)                       probe_failed rc=16
#   11  the hooks dir is not root:git 750                   reason=hooks_dir_owner
#   13  pre-receive is not root:root 755                    reason=hook_owner
#   19  the hooks dir's parent is not root-owned, or is
#       group/other-writable (git could swap the dir)       reason=hooks_parent_writable
#   17  the git user cannot read and execute pre-receive
#       (group membership, an ACL, a denied traversal)      reason=hook_not_runnable_by_git
#   16  git config exited above 1                           probe_failed rc=16
#   14  the system core.hooksPath (includes resolved) does
#       not name the SERVING hooks path; unset is git's 1   reason=hooks_path_mismatch
#   18  the installed transport wrapper does not carry the
#       command-line pin to the serving hooks path          reason=transport_pin_mismatch
#    5  findmnt -T could not resolve a fence path's source  probe_failed rc=5
#   15  the hooks dir or pre-receive is on another source   reason=hooks_wrong_source
# Any other rc is gd_capture's own, reported probe_failed. SHAPE, NOT CONTENT: a planted
# placeholder hook passes; the content comparison belongs to the rebuilt copy (#8211). The
# answer is unauthenticated while #7226 is open, like every other store probe.
# Arguments (the #8211 reuse on the fresh root): the root probed (default OLD_ROOT), the source
# it must sit on (default STORE_SOURCE), and the hooks path a push is pinned to (default the
# serving OLD_ROOT/hooks, which does not move when a fresh root is probed before the repoint).
# A PASSED empty argument is refused, never defaulted: an empty FRESH_ROOT must not quietly
# probe the serving store. Arguments are validated before anything is printed or dialed.
TRANSPORT_WRAPPER="${TRANSPORT_WRAPPER:-/usr/local/bin/git-data-transport-wrapper.sh}"
refuse_if_fence_not_intact() {
  local root="${1-$OLD_ROOT}" src="${2-$STORE_SOURCE}" serving="${3-$OLD_ROOT/hooks}"
  local rc=0 reason="" cmd pin_hd pin_ex qh qs qsp qw qhd qex
  local -a c
  [[ "$root" =~ ^/[A-Za-z0-9/_.-]+$ ]] || _store_refuse fence-shape probe_failed "" arg_root
  [[ "$src" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || _store_refuse fence-shape probe_failed "" arg_source
  [[ "$serving" =~ ^/[A-Za-z0-9/_.-]+$ ]] || _store_refuse fence-shape probe_failed "" arg_serving
  [[ "$TRANSPORT_WRAPPER" =~ ^/[A-Za-z0-9/_.-]+$ ]] || _store_refuse fence-shape probe_failed "" arg_wrapper
  step "fence probe: $root/hooks holds the pre-receive fence, and a push would run it"
  # The two lines of git-data-transport-wrapper.sh that decide which hooks a push runs. The
  # suite's P2 row pins both against the wrapper itself.
  pin_hd="HOOKS_DIR=\"\${GIT_DATA_HOOKS_DIR:-$serving}\""
  pin_ex='exec git -c "core.hooksPath=${HOOKS_DIR}" "${verb#git-}" "$repo_real"'
  printf -v qh '%q' "$root/hooks"
  printf -v qs '%q' "$src"
  printf -v qsp '%q' "$serving"
  printf -v qw '%q' "$TRANSPORT_WRAPPER"
  printf -v qhd '%q' "$pin_hd"
  printf -v qex '%q' "$pin_ex"
  c=(
    "h=$qh; p=\"\$h/pre-receive\"; src=$qs; sp=$qsp; w=$qw"
    '[ -L "$h" ] && exit 10'
    '[ -d "$h" ] || exit 10'
    '[ -L "$p" ] && exit 12'
    '[ -f "$p" ] && [ -x "$p" ] || exit 12'
    "oh=\$(stat -c '%U:%G %a' \"\$h\") || exit 16"
    "op=\$(stat -c '%U:%G %a' \"\$p\") || exit 16"
    '[ "$oh" = "root:git 750" ] || exit 11'
    '[ "$op" = "root:root 755" ] || exit 13'
    "pp=\$(stat -c '%U %a' \"\${h%/*}\") || exit 16"
    'case "$pp" in "root "[0-7][0145][0145]|"root "[0-7][0-7][0145][0145]) ;; *) exit 19 ;; esac'
    'runuser -u git -- test -r "$p" && runuser -u git -- test -x "$p" || exit 17'
    'v=$(env -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM git config --system --includes --get core.hooksPath); g=$?'
    '[ "$g" -le 1 ] || exit 16'
    '[ "$v" = "$sp" ] || exit 14'
    "grep -qxF -- $qhd \"\$w\" && grep -qxF -- $qex \"\$w\" || exit 18"
    's=$(findmnt -no SOURCE -T "$h") || exit 5; [ "$s" = "$src" ] || exit 15'
    's=$(findmnt -no SOURCE -T "$p") || exit 5; [ "$s" = "$src" ] || exit 15'
    'echo ok'
  )
  printf -v cmd '%s; ' "${c[@]}"
  gd_capture '^ok$' "${cmd%; }" || rc=$?
  case "$rc" in
    0) ;;
    10) reason=hooks_dir_absent ;;
    11) reason=hooks_dir_owner ;;
    12) reason=hook_absent ;;
    13) reason=hook_owner ;;
    14) reason=hooks_path_mismatch ;;
    15) reason=hooks_wrong_source ;;
    17) reason=hook_not_runnable_by_git ;;
    18) reason=transport_pin_mismatch ;;
    19) reason=hooks_parent_writable ;;
    *) _store_refuse fence-shape probe_failed "$rc" ;;
  esac
  [ -z "$reason" ] || _store_refuse fence-shape fence_not_intact "" "$reason"
  _store_emit fence-shape ok
}

# ============================================================================
# Main
# ============================================================================
main() {
  refuse_real_modes
  resolve_roster
  log "starting git-data read-only proof (access gate, three store probes, then the fence probe; no host is changed)"
  access_gate
  refuse_if_unmounted
  refuse_if_cut_over
  refuse_if_store_not_empty
  refuse_if_fence_not_intact
  log "read-only proof clear: access ok, store mounted, not cut over, empty, fence in place for pushes"
  echo "::notice title=git-data-cutover store::verdict=clear"
}

main "$@"

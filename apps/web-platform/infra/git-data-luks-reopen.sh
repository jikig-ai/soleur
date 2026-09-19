#!/bin/bash
# (#8210) Reopen the git-data LUKS mapper on EVERY boot.
#
# WHY THIS EXISTS. The birth heredoc (cloud-init runcmd, STAGE=luks_open) runs ONCE per
# instance and the fstab line it appends is `nofail`, so every later boot waited on a mapper
# nothing opened, timed out, and continued with the encrypted store absent and no signal.
# ADR-115 recorded that as a normative blocker; this script is the reboot-safe equivalent of
# the crypttab/keyscript it named. ADR-198 forbids baking the passphrase, so the key arrives
# at boot through `doppler run --only-secrets GIT_DATA_LUKS_KEY --no-fallback` on the unit's
# ExecStart (git-data-luks-reopen.service), never from the root disk.
#
# SHAPE. Straight-line, bash (dash has no pipefail), `set -euo pipefail`, NO traps and NO
# fatal emits: reporting belongs to the OnFailure= reporter unit, which reads the phase file
# this script maintains. Every external command is called by BARE name so a scratch PATH can
# intercept it (git-data-luks-reopen.test.sh). It NEVER formats, never runs mkfs, and never
# calls mount(8): under PrivateTmp=yes the unit has its own mount namespace, so the mount is
# delegated to PID 1 via the fstab-generated .mount unit (measured on systemd 255: a mount(8)
# inside the unit is invisible to the host; a PID-1 mount propagates back in).
#
# PHASE TABLE (the tag the reporter emits as action=<phase> when this script dies there):
#   config          GIT_DATA_LUKS_DEV / GIT_DATA_DOPPLER_CONFIG present and well-shaped
#   key             GIT_DATA_LUKS_KEY injected (never an unencrypted fallback)
#   device          the pinned by-id device answers blockdev within DEVICE_WAIT seconds
#   header          cryptsetup isLuks rc 0 (any other rc refuses; rc is not a blankness verdict, #7240)
#   open            luksOpen if the mapper is closed (ACTION=reopened) else noop
#   identity        the mapper's backing device is the pin (a stale pin after a volume swap must not pass)
#   target          exactly one fstab entry names the mapper (cutover-agnostic: #8211 repoints it)
#   mount           PID-1 mount via `systemctl start <target>.mount` if not mounted (ACTION=mounted)
#   identity-mount  findmnt SOURCE of the target is the mapper (mountedness is not identity)
#   emit            the success row's emitter is structurally sound (rc 0/1 pass; 2/126/127 refuse)
# Success: ACTION=reopened|mounted emits ONE info row at stage luks_reopen_ok (deliberately absent
# from every Sentry rule — git_data_boot_fatal has no level condition); ACTION=noop is silent.
#
# TEST SEAMS. RUNDIR and DEVICE_WAIT are env-overridable so the suite can run this against a
# scratch dir with a 1 s device fixture. Production sets neither (the suite REDs on a unit that
# does). No literal of the form "doppler run" followed by "--project soleur" may appear in this
# file: git-data-luks.test.sh's config-scope census is not line-anchored.
set -euo pipefail
# (#7797) xtrace would print the Doppler-injected passphrase; refuse before anything reads it.
case "$-" in
  *x*)
    if [ -n "${GIT_DATA_LUKS_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

RUNDIR="${GIT_DATA_REOPEN_RUNDIR:-/run/git-data-luks-reopen}"
DEVICE_WAIT="${GIT_DATA_REOPEN_DEVICE_WAIT:-30}"
# THE SEAM IS AN OPERAND, SO IT IS ASSERTED BEFORE ANYTHING INTERPOLATES IT. Every write below
# is `"$RUNDIR/<name>"`, which for an EMPTY or relative RUNDIR resolves to `/action` or to a
# path under the CWD — a root-filesystem write, as root, on a host whose whole job is holding
# user source. The default is absolute, but a default is not a guarantee: the seam exists so a
# test can redirect it, and the same lever is what a mistake or an injected environment would
# pull. `readonly` afterwards so nothing below can reintroduce the degenerate case.
# (Shape mirrors the repo's canonical assert_fixture_dir; caught by plugins/soleur/test/
# fixture-relative-assert.test.sh, whose P1b rule is exactly "an operand that is neither
# provably absolute nor guarded".)
case "$RUNDIR" in
  "")            printf '[FATAL] GIT_DATA_REOPEN_RUNDIR is EMPTY; refusing to write to /\n' >&2; exit 2 ;;
  */../*|*/..)   printf '[FATAL] run dir %s contains ..; refusing\n' "$RUNDIR" >&2; exit 2 ;;
  /|//|/.)       printf '[FATAL] run dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
  /proc/*|/sys/*|/dev/*) printf '[FATAL] run dir %s is a synthetic-fs path; refusing\n' "$RUNDIR" >&2; exit 2 ;;
  /*)            : ;;
  *)             printf '[FATAL] run dir %s is RELATIVE; refusing\n' "$RUNDIR" >&2; exit 2 ;;
esac
readonly RUNDIR
case "$DEVICE_WAIT" in
  ''|*[!0-9]*) printf '[FATAL] device wait %s is not a positive integer; refusing\n' "$DEVICE_WAIT" >&2; exit 2 ;;
esac
readonly DEVICE_WAIT
MAPPER_NAME=git-data
MAPPER="/dev/mapper/$MAPPER_NAME"
UNIT=git-data-luks-reopen.service
LOG="$RUNDIR/log"

# `${VAR:?}` AT EVERY USE, not only the case-guard above. Two reasons, and the second is why it
# is not redundant: an empty operand here writes to `/` as root, and the P1b scanner
# (plugins/soleur/test/lib/fixture-scan.py) reads `readonly` as a re-binding, so a guard above it
# does not cover a use below it. The parameter expansion aborts at the use site regardless.
mkdir -p "${RUNDIR:?run dir unset}"
: > "${LOG:?log path unset}"
# Written BEFORE each phase runs, so the tag names the phase that was executing when the
# script died — including on SIGTERM, which runs no trap.
phase() { printf 'action=%s\n' "$1" > "${RUNDIR:?}/action"; }
# To the log (what the reporter ships) AND stderr (the journal — the only trace left when both
# of the reporter's arms are down).
die() { printf '%s\n' "$1" >> "${LOG:?}"; printf '%s\n' "$1" >&2; exit 1; }
ACTION=noop

phase config
[[ "${GIT_DATA_LUKS_DEV:-}" =~ ^/dev/disk/by-id/scsi-0HC_Volume_[0-9]+$ ]] \
  || die "GIT_DATA_LUKS_DEV is unset or not a by-id volume path"
[[ "${GIT_DATA_DOPPLER_CONFIG:-}" =~ ^[a-z0-9_]+$ ]] \
  || die "GIT_DATA_DOPPLER_CONFIG is unset or not a config name"
DEV="$GIT_DATA_LUKS_DEV"

phase key
[ -n "${GIT_DATA_LUKS_KEY:-}" ] || die "GIT_DATA_LUKS_KEY is empty: the passphrase was not injected"

phase device
_i=0
while :; do
  _sz=$(blockdev --getsize64 "$DEV" 2>>"$LOG" || true)
  if [[ "$_sz" =~ ^[0-9]+$ ]] && [ "$_sz" -gt 0 ]; then break; fi
  _i=$((_i + 1))
  [ "$_i" -lt "$DEVICE_WAIT" ] || die "device $DEV absent after ${DEVICE_WAIT}s"
  sleep 1
done

phase header
_rc=0
cryptsetup isLuks "$DEV" 2>>"$LOG" || _rc=$?
[ "$_rc" -eq 0 ] || die "cryptsetup isLuks $DEV rc=$_rc: refusing to open a device that is not a LUKS header"

phase open
_st=0
_status=$(cryptsetup status "$MAPPER_NAME" 2>>"$LOG") || _st=$?
if [ "$_st" -eq 0 ]; then
  :
elif [ "$_st" -eq 4 ]; then
  printf '%s' "$GIT_DATA_LUKS_KEY" | cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME" 2>>"$LOG" \
    || die "cryptsetup luksOpen failed (wrong passphrase after a mis-rotation, or a damaged header)"
  ACTION=reopened
  _status=$(cryptsetup status "$MAPPER_NAME" 2>>"$LOG") || die "mapper not active after luksOpen"
else
  die "cryptsetup status $MAPPER_NAME rc=$_st"
fi

phase identity
_backing=$(printf '%s\n' "$_status" | awk '/^[[:space:]]*device:/{print $2; exit}')
[ -n "$_backing" ] || die "cryptsetup status reports no backing device"
# Each realpath captured and REQUIRED non-empty before the comparison: `$(...)` inside `[` is
# not errexit-checked, so two failing realpaths (a volume detached between the device and
# identity phases) compared "" to "" and PASSED (review).
_rb=$(realpath "$_backing" 2>>"$LOG") || die "realpath $_backing failed: the backing device vanished between phases"
_rd=$(realpath "$DEV" 2>>"$LOG") || die "realpath $DEV failed: the pinned device vanished between phases"
[ -n "$_rb" ] && [ -n "$_rd" ] || die "realpath returned an empty path for the backing device or the pin"
[ "$_rb" = "$_rd" ] \
  || die "mapper $MAPPER is backed by $_backing, not the pinned $DEV"

phase target
# findmnt exits 1 on no match, so the `|| true` is what lets the count below decide.
_targets=$(findmnt --fstab -n -S "$MAPPER" -o TARGET 2>>"$LOG" || true)
[ "$(printf '%s\n' "$_targets" | grep -c .)" -eq 1 ] \
  || die "fstab names $MAPPER $(printf '%s\n' "$_targets" | grep -c .) times, expected exactly one"
TARGET="$_targets"
# CUTOVER-AGNOSTIC MEANS TWO NAMES, NOT ANY NAME. TARGET is read out of /etc/fstab and then
# handed to PID 1 as a unit to start, so without this the decrypted store follows whatever a
# garbled append or a bad #8211 rewrite put in that field. Both legal states are permitted —
# /mnt/git-data-luks today, /mnt/git-data after the cutover — and anything else is reported as
# action=target rather than mounted somewhere nobody is looking.
case "$TARGET" in
  /mnt/git-data|/mnt/git-data-luks) : ;;
  *) die "fstab points $MAPPER at '$TARGET', which is neither /mnt/git-data nor /mnt/git-data-luks" ;;
esac

phase mount
if ! mountpoint -q "$TARGET"; then
  _munit=$(systemd-escape -p --suffix=mount "$TARGET")
  systemctl daemon-reload 2>>"$LOG" || true
  if ! systemctl start "$_munit" 2>>"$LOG"; then
    journalctl -u "$_munit" -n 20 --no-pager -o cat >>"${LOG:?}" 2>&1 || true
    die "systemctl start $_munit failed"
  fi
  [ "$ACTION" = reopened ] || ACTION=mounted
fi

phase identity-mount
_src=$(findmnt -n -o SOURCE "$TARGET" 2>>"$LOG" || true)
[ "$_src" = "$MAPPER" ] || die "$TARGET is mounted from '${_src:-nothing}', not $MAPPER"

# THE SUCCESS EMIT IS BEST-EFFORT FOR A TRANSIENT, AND LOUD FOR A STRUCTURAL FAULT. Everything
# above has already succeeded — the mapper is open and the store is mounted from it — so the
# emitter's rc=1 (its "transient: the POST failed" arm; a DNS or Sentry blip seconds after
# network-online) must not fail the UNIT. Under plain `set -e` it did: the script died with the
# phase file still reading `identity-mount`, the restart ladder re-ran it into the silent noop
# branch (so the reopen was never evidenced and the rung-2 reboot probe read TRANSIENT), and
# an exhausted ladder shipped a FALSE `action=identity-mount` fatal — whose runbook row points
# at the ADR-068 backup/rebuild path — for a healthy host. But an emitter that CANNOT RUN
# (rc 126/127: absent, not executable) or that reports its own structural fault (rc=2) is a
# payload defect that would make every LATER failure on this host silent too, and that one is
# reported, under its own phase, so the tag names what actually broke.
phase emit
if [ "$ACTION" != noop ]; then
  _restarts=$(systemctl show --value -p NRestarts "$UNIT" 2>/dev/null || echo unknown)
  _erc=0
  git-data-emit "git-data LUKS mapper reopened at boot" luks_reopen_ok info "" \
    "action=$ACTION" "target=$TARGET" "restarts=${_restarts:-unknown}" || _erc=$?
  # The emitter's contract: 0 delivered, 1 transient (a POST failed), 2 structural (no curl /
  # no DSN); 126/127 are the shell's "not executable" / "not found". Only the first two are
  # tolerated. The refusal exits 3, NOT 1: the unit's RestartPreventExitStatus=3 makes that
  # attempt terminal, because a retry would find the store open, take the silent noop branch
  # and erase the fault (review). It is reported by the reporter, which uses the SAME emitter —
  # so action=emit is dark by construction off-host; what an agent sees is the unit `failed`
  # with ExecMainStatus=3, the boolean luks_reopen_unit=no at birth, and the ABSENCE of a
  # luks_reopen_ok row after a known reboot. The runbook's emit row says so.
  case "$_erc" in
    0|1) : ;;
    *) printf '%s\n' "git-data-emit rc=$_erc after a successful reopen: a structural emitter fault, not a transient POST failure — every later failure on this host would be silent" >> "${LOG:?}"; exit 3 ;;
  esac
fi
# Both files go on success so a later same-boot failure inside `doppler run` cannot ship a
# stale phase tag through the reporter.
rm -f "$RUNDIR/action" "$LOG"

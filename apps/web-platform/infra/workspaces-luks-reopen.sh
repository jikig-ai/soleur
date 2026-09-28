#!/bin/bash
# (#9123) Reopen the workspaces LUKS mapper on EVERY boot of web-1.
#
# WHY THIS EXISTS. web-1's /mnt/data is the sole copy of every user's checked-out
# source. The 2026-07-23 cutover made /dev/mapper/workspaces the live source of
# /mnt/data, but nothing unlocked it at boot: no crypttab line, no key-fetch unit,
# and the fstab entry still named the literal glob written on first boot. The
# Terraform-owned installer (terraform_data.workspaces_boot_unlock_install in
# workspaces-luks.tf) delivers this script, its units, the crypttab declaration,
# the fstab repair and the ADR-119 §(e) mount gate atomically. ADR-115's
# reopen-is-the-crypttab-equivalent acceptance and ADR-198's never-bake rule both
# apply: the key arrives at boot through `doppler secrets get WORKSPACES_LUKS_KEY
# --plain --config "$WORKSPACES_DOPPLER_CONFIG"` — the R9-pinned form, NEVER
# `doppler run` or `doppler secrets download` on that config (branch inheritance
# would drag the ~116 prd root secrets into env — the CWE-522 hole the dedicated
# config exists to close; workspaces-luks.tf).
#
# SHAPE. Straight-line, bash (dash has no pipefail), `set -euo pipefail`, NO traps
# and NO failure emits: reporting belongs to the OnFailure= reporter unit
# (workspaces-luks-reopen-failure.service), which reads the phase file this
# script maintains and emits via workspaces_luks_emit — the SOLE PAGING OP
# (feature=workspaces-luks, op=workspaces-luks-drift; the sentry issue alert pages
# on count > 0 regardless of level). So a success path NEVER calls that emitter:
# a healthy reboot would page every time. Success is a `logger -t
# workspaces-luks-reopen` journald line (Vector ships it to Better Stack under
# SYSLOG_IDENTIFIER=workspaces-luks-reopen) plus the unit's converge state.
# Every external command is called by BARE name so a scratch PATH can intercept
# it (workspaces-boot-unlock.test.sh). It NEVER formats, never runs mkfs, and
# never calls mount(8): under PrivateTmp=yes the unit has its own mount
# namespace, so the mount is delegated to PID 1 via the fstab-generated
# mnt-data.mount unit (measured on systemd 255: a mount(8) inside the unit is
# invisible to the host; a PID-1 mount propagates back in).
#
# PHASE TABLE (the tag the reporter emits as action=<phase> when this script dies
# there):
#   config          WORKSPACES_LUKS_DEV / WORKSPACES_DOPPLER_CONFIG present and
#                   well-shaped (both read from /etc/default/workspaces-luks-boot)
#   key             `doppler secrets get` returned a non-empty WORKSPACES_LUKS_KEY
#   device          the pinned by-id device answers blockdev within DEVICE_WAIT seconds
#   header          cryptsetup isLuks rc 0 (any other rc refuses; rc is not a
#                   blankness verdict, #7240)
#   open            luksOpen if the mapper is closed (ACTION=reopened) else noop
#   identity        the mapper's backing device is the pin (a stale pin after a
#                   volume swap must not pass)
#   target          exactly one fstab entry names the mapper, and it is /mnt/data
#   mount           PID-1 mount via `systemctl start mnt-data.mount` if not
#                   mounted (ACTION=mounted)
#   identity-mount  findmnt SOURCE of the target is the mapper (mountedness is
#                   not identity)
#   emit            the reporter's emit channel is structurally sound and the
#                   success row is journaled (reopened/mounted only; noop silent)
# Success: ACTION=reopened|mounted logs ONE journald line; ACTION=noop is silent.
# Neither arm reaches workspaces_luks_emit — failure-only is the whole emit
# contract (AC9).
#
# TEST SEAMS. RUNDIR and DEVICE_WAIT are env-overridable so the suite can run this
# against a scratch dir with a 1 s device fixture. Production sets neither (the
# suite REDs on a unit that does).
set -euo pipefail
# (#7797) xtrace would print the Doppler-fetched passphrase at the key/open
# phases. UNCONDITIONAL, mirroring luks-monitor.sh — NOT git-data-luks-reopen.sh's
# conditional "refuse only when GIT_DATA_LUKS_KEY is already in env" form: the key
# here is fetched mid-script, never injected, so a conditional check would always
# pass and -x would log the secret.
case "$-" in
  *x*)
    printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2
    exit 78
    ;;
esac

RUNDIR="${WORKSPACES_REOPEN_RUNDIR:-/run/workspaces-luks-reopen}"
DEVICE_WAIT="${WORKSPACES_REOPEN_DEVICE_WAIT:-30}"
# THE SEAM IS AN OPERAND, SO IT IS ASSERTED BEFORE ANYTHING INTERPOLATES IT. Every
# write below is `"$RUNDIR/<name>"`, which for an EMPTY or relative RUNDIR
# resolves to `/action` or to a path under the CWD — a root-filesystem write, as
# root, on a host whose whole job is holding user source. The default is
# absolute, but a default is not a guarantee: the seam exists so a test can
# redirect it, and the same lever is what a mistake or an injected environment
# would pull. `readonly` afterwards so nothing below can reintroduce the
# degenerate case. (Shape mirrors the repo's canonical assert_fixture_dir; caught
# by plugins/soleur/test/fixture-relative-assert.test.sh, whose P1b rule is
# exactly "an operand that is neither provably absolute nor guarded".)
case "$RUNDIR" in
  "")            printf '[FATAL] WORKSPACES_REOPEN_RUNDIR is EMPTY; refusing to write to /\n' >&2; exit 2 ;;
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
MAPPER_NAME=workspaces
MAPPER="/dev/mapper/$MAPPER_NAME"
UNIT=workspaces-luks-reopen.service
LOG="$RUNDIR/log"

# `${VAR:?}` AT EVERY USE, not only the case-guard above. Two reasons, and the
# second is why it is not redundant: an empty operand here writes to `/` as root,
# and the P1b scanner (plugins/soleur/test/lib/fixture-scan.py) reads `readonly`
# as a re-binding, so a guard above it does not cover a use below it. The
# parameter expansion aborts at the use site regardless.
mkdir -p "${RUNDIR:?run dir unset}"
: > "${LOG:?log path unset}"
# Written BEFORE each phase runs, so the tag names the phase that was executing
# when the script died — including on SIGTERM, which runs no trap.
phase() { printf 'action=%s\n' "$1" > "${RUNDIR:?}/action"; }
# To the log (what the reporter ships) AND stderr (the journal — the only trace
# left when both of the reporter's arms are down).
die() { printf '%s\n' "$1" >> "${LOG:?}"; printf '%s\n' "$1" >&2; exit 1; }
ACTION=noop

phase config
[[ "${WORKSPACES_LUKS_DEV:-}" =~ ^/dev/disk/by-id/scsi-0HC_Volume_[0-9]+$ ]] \
  || die "WORKSPACES_LUKS_DEV is unset or not a by-id volume path"
[[ "${WORKSPACES_DOPPLER_CONFIG:-}" =~ ^[a-z0-9_]+$ ]] \
  || die "WORKSPACES_DOPPLER_CONFIG is unset or not a config name"
DEV="$WORKSPACES_LUKS_DEV"

phase key
# THE R9-PINNED FORM, and the only line in this script that may name it:
# `doppler secrets get <NAME> --plain --config <scoped>` fetches ONE secret;
# `doppler run`/`doppler secrets download` on this config would resolve the whole
# inherited root set into env or disk (CWE-522). `--plain` writes no on-disk
# fallback cache under $DOPPLER_CONFIG_DIR. Empty means the fetch failed or the
# token lost scope — either way the ladder retries, then the reporter pages
# action=key.
KEY="$(doppler secrets get WORKSPACES_LUKS_KEY --plain --config "$WORKSPACES_DOPPLER_CONFIG" 2>>"$LOG" || true)"
[ -n "$KEY" ] || die "WORKSPACES_LUKS_KEY is empty: doppler secrets get failed or the secret is unset"

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
  printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME" 2>>"$LOG" \
    || die "cryptsetup luksOpen failed (wrong passphrase after a mis-rotation, or a damaged header)"
  ACTION=reopened
  _status=$(cryptsetup status "$MAPPER_NAME" 2>>"$LOG") || die "mapper not active after luksOpen"
else
  die "cryptsetup status $MAPPER_NAME rc=$_st"
fi
unset KEY

phase identity
_backing=$(printf '%s\n' "$_status" | awk '/^[[:space:]]*device:/{print $2; exit}')
[ -n "$_backing" ] || die "cryptsetup status reports no backing device"
# Each realpath captured and REQUIRED non-empty before the comparison: `$(...)`
# inside `[` is not errexit-checked, so two failing realpaths (a volume detached
# between the device and identity phases) compared "" to "" and PASSED (review).
_rb=$(realpath "$_backing" 2>>"$LOG") || die "realpath $_backing failed: the backing device vanished between phases"
_rd=$(realpath "$DEV" 2>>"$LOG") || die "realpath $DEV failed: the pinned device vanished between phases"
[ -n "$_rb" ] && [ -n "$_rd" ] || die "realpath returned an empty path for the backing device or the pin"
[ "$_rb" = "$_rd" ] \
  || die "mapper $MAPPER is backed by $_backing, not the pinned $DEV"

phase target
# findmnt exits 1 on no match, so the `|| true` is what lets the count below
# decide. ONE NAME, NOT ANY NAME: TARGET is read out of /etc/fstab and then
# handed to PID 1 as a unit to start, so without this the decrypted store follows
# whatever a garbled append put in that field. The mapper's canonical target on
# web-1 is /mnt/data; any other name is refused as action=target rather than
# mounted somewhere nobody is looking.
_targets=$(findmnt --fstab -n -S "$MAPPER" -o TARGET 2>>"$LOG" || true)
[ "$(printf '%s\n' "$_targets" | grep -c .)" -eq 1 ] \
  || die "fstab names $MAPPER $(printf '%s\n' "$_targets" | grep -c .) times, expected exactly one"
TARGET="$_targets"
case "$TARGET" in
  /mnt/data) : ;;
  *) die "fstab points $MAPPER at '$TARGET', not /mnt/data" ;;
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

# THE SUCCESS PATH IS JOURNALD-ONLY, AND THAT IS LOAD-BEARING. Everything above
# has already succeeded — the mapper is open and /mnt/data is mounted from it —
# so the evidence row is `logger -t workspaces-luks-reopen`, NEVER
# workspaces_luks_emit: that emitter hardcodes op=workspaces-luks-drift, the sole
# paging op, and its Sentry issue alert pages on count > 0 regardless of level —
# a success emit would page on every healthy reboot. The emit file's PRESENCE is
# still asserted here, on the success path, because on the failure path it is the
# thing that would be broken: workspaces-luks-reopen-failure.service sources
# /usr/local/bin/workspaces-luks-emit.sh to emit via workspaces_luks_emit. An
# absent/unreadable helper makes EVERY later failure on this host silent — a
# structural fault, so it refuses with exit 3, NOT 1:
# RestartPreventExitStatus=3 makes that attempt terminal, because a retry would
# find the store open, take the silent noop branch and erase the fault. It is
# reported by the reporter as action=emit; off-host the emit itself is dark by
# construction — what an agent sees is the unit failed with ExecMainStatus=3.
phase emit
if [ "$ACTION" != noop ]; then
  # Sibling-first resolution, the luks-monitor.sh EMIT shape: production finds
  # /usr/local/bin/workspaces-luks-emit.sh, the suite's scratch copy finds its
  # own fixture next to the script under test.
  EMIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workspaces-luks-emit.sh"
  [ -f "$EMIT" ] || EMIT="/usr/local/bin/workspaces-luks-emit.sh"
  [ -r "$EMIT" ] \
    || { printf '%s\n' "workspaces-luks-emit.sh is absent or unreadable: the OnFailure reporter cannot page — every later failure on this host would be silent" >> "${LOG:?}"; exit 3; }
  _restarts=$(systemctl show --value -p NRestarts "$UNIT" 2>/dev/null || echo unknown)
  logger -t workspaces-luks-reopen -- "workspaces LUKS mapper reopened at boot action=$ACTION target=$TARGET restarts=${_restarts:-unknown}" || true
fi
# Both files go on success so a later same-boot failure cannot ship a stale
# phase tag through the reporter.
rm -f "$RUNDIR/action" "$LOG"

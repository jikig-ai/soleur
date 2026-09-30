#!/usr/bin/env bash
#
# Behavioral suite for workspaces-cutover.sh :: CONFIRM_WIPE / wipe_plaintext() (#6604 runbook step 7,
# ADR-119 §(f)) — the mode that zeroes web-1's retained plaintext /workspaces volume.
#
# THE ONE PROPERTY THAT MATTERS: `blkdiscard -z` runs on exactly one device, and that device is the
# pinned plaintext volume — never the device backing /dev/mapper/workspaces, which holds the ONLY copy
# of every user's workspace. Every row below is a row of the plan's Guard Contract (Guards 1, 2, 3 and
# 5; the workflow guards 4 and 6 live in the workflow suites). Each RED row names its exact reason slug.
#
# HARNESS. Counters, reporters, the floor and the file-direct predicates come from
# workspaces-luks-harness.sh. The RUNNER is this file's own `run_wipe`, not the harness's run_case,
# because the seam is different in kind: run_case stubs the freeze/rollback world (mount, docker,
# lsof, the dead-man model); this mode touches a disjoint set of binaries (blkdiscard, dd, cmp,
# udevadm, blockdev, lsblk, systemd-run, aws) and needs three properties run_case has no notion of:
#   1. PATH TRIPWIRES. Recording executables for blkdiscard, dd, doppler and aws that `exit 64` sit
#      FIRST on PATH. The function stubs shadow them, so a call that escapes a stub (the stub was
#      deleted, or the SUT reached the binary by path) fails LOUDLY instead of starting the real
#      /usr/bin/blkdiscard against a real device, or `read_key` fetching the real prod passphrase.
#   2. A CLOSED WORLD. After the script is sourced, PATH is narrowed to the tripwires plus an
#      allowlist of pure text/file utilities, and `command_not_found_handle` records `UNSTUBBED <cmd>`.
#      Every case asserts none appeared: that is the census "every command wipe_plaintext invokes has
#      a stub", measured rather than listed.
#   3. STUB FIDELITY. The stubs whitelist the real flags and record `STUB_UNKNOWN_FLAG` on anything
#      else (learning 2026-09-25-gh-stub-must-mirror-real-cli-flags). cryptsetup --test-passphrase
#      compares stdin BYTE-FOR-BYTE (a trailing newline is a different passphrase); luksUUID answers per
#      path; blkid answers TYPE and LABEL separately, with real exit codes, and goes blank once the
#      zero has run; systemctl answers per exact unit name; list-dependencies prints the unit first and
#      dependents indented (measured locally 2026-09-28, systemd 258: `dev-mapper-x.device` then
#      `  home.mount`); cmp prints its first difference on STDOUT, as the real one does.
#
# The device-path SEAM: W1 requires the literal `/dev/disk/by-id/scsi-0HC_Volume_<id>`, and `[ -b ]` is
# a builtin, so no fixture could otherwise reach W6. The script resolves the by-id path through
# `_wipe_dev_path`, which this suite overrides to hand back a REAL block device on the host (never
# written: every consumer of it is stubbed). The seam takes no environment input — a census row pins
# that, so production cannot be pointed elsewhere by an .env line.
#
# HARNESS RULE (inherited): never pipe into an assertion predicate. Every verdict greps a FILE or a
# herestring.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUTOVER="$SCRIPT_DIR/workspaces-cutover.sh"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WORKFLOW="$REPO/.github/workflows/workspaces-luks-cutover.yml"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# shellcheck source=apps/web-platform/infra/workspaces-luks-harness.sh
. "$SCRIPT_DIR/workspaces-luks-harness.sh"
harness_selftest workspaces-luks-wipe.test.sh

PIN=105149570
BYID="/dev/disk/by-id/scsi-0HC_Volume_${PIN}"
SIZE=21474836480
UUID_LIVE="u-live-1"
DM='SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman'
WROW='SOLEUR_WORKSPACES_LUKS_WIPE feature=workspaces-luks op=workspaces-luks-wipe'

TGT_BLK="$(harness_blockdev)" || { printf 'INSTRUMENT FAIL - no block device on this host; the W6 identity rows cannot be reached\n'; exit 2; }
LUKS_BLK="$(harness_blockdev_other "$TGT_BLK")" || { printf 'INSTRUMENT FAIL - only one block device on this host; target and LUKS backing must be DISTINCT real devices\n'; exit 2; }
TGT_REAL="$(readlink -f -- "$TGT_BLK")"
TGT_KNAME="$(basename "$TGT_REAL")"
# T10 — the stubs cover COMMANDS, not shell redirections: a `> "$real"` in the SUT (or in a mutant of it)
# would reach the real device handed through the seam. So the suite refuses to run with write access to
# either device — root, or a `disk` group member — rather than trusting the closed world alone.
if [ "$(id -u)" = 0 ] || [ -w "$TGT_BLK" ] || [ -w "$LUKS_BLK" ]; then
  printf 'INSTRUMENT FAIL - this suite hands REAL block devices (%s, %s) to the SUT and must not be able to write them: run it as an unprivileged user outside the disk group\n' "$TGT_BLK" "$LUKS_BLK"
  exit 2
fi

# --- the stub world, sourced INSIDE each case after the script (a file, so no quoting contortions) ---
# Every path below hangs off ONE absolute mktemp root. The harness owns the EXIT trap (this suite must
# not REPLACE it, #6713), so its trap FUNCTION is extended to remove this root too.
WIPE_SCRATCH="$(mktemp -d -t wl-wipe.XXXXXXXX)" || { printf 'INSTRUMENT FAIL - mktemp -d failed\n'; exit 2; }
eval "_wl_harness_cleanup_scratch() $(declare -f cleanup_scratch | tail -n +2)"
cleanup_scratch() { rm -rf "$WIPE_SCRATCH"; _wl_harness_cleanup_scratch; }
WIPE_STUBS="$WIPE_SCRATCH/wipe-stubs.sh"
cat > "$WIPE_STUBS" <<'STUBS'
# shellcheck shell=bash
rec() { printf '%s\n' "$*" >> "$CALLS"; }
unk() { printf 'STUB_UNKNOWN_FLAG %s\n' "$*" >> "$CALLS"; return 64; }
command_not_found_handle() { printf 'UNSTUBBED %s\n' "$1" >> "$CALLS"; return 127; }
TGT_REAL="$(readlink -f -- "$TGT_BLK")"
TGT_KNAME="$(basename "$TGT_REAL")"
W_BACKING_DEV="${W_BACKING-$LUKS_BLK}"
LUKS_REAL="$(readlink -f -- "$W_BACKING_DEV" 2>/dev/null)"
W_TARGET_UNITS="${W_TARGET_UNITS-dev-${TGT_KNAME}.device dev-disk-by\\x2did-scsi\\x2d0HC_Volume_105149570.device}"
zeroed() { [ -f "$W_CASE_DIR/zeroed" ] && [ "${W_SIG_SURVIVES:-0}" != 1 ]; }
in_target_units() { local u; for u in $W_TARGET_UNITS; do [ "$u" = "$1" ] && return 0; done; return 1; }
# devkind <path> — which device a probe NAMED: tgt (the pinned target), luks (the mapper's backing
# device) or other. Every device-probing stub keys its answer on this (T1): a probe pointed at the
# wrong device gets the WRONG device's answer, or an `unk` that fails the case — never the target's.
devkind() {
  local r; r="$(readlink -f -- "${1:-}" 2>/dev/null)"
  if [ -n "$r" ] && [ "$r" = "$TGT_REAL" ]; then printf tgt
  elif [ -n "$r" ] && [ "$r" = "$LUKS_REAL" ]; then printf luks
  else printf other; fi
}

# THE SEAMS. Production returns its argument / the real roots; here a real block device (or an absent
# path), a per-case fake sysfs and a per-case fake cgroup root.
_wipe_dev_path() {
  rec "SEAM _wipe_dev_path $*"
  if [ "${W_DEV_ABSENT:-0}" = 1 ]; then printf '%s' "$W_CASE_DIR/no-such-dev"; return 0; fi
  if [ "${W_DEV_VIA_RELLINK:-0}" = 1 ]; then printf '%s' "$W_CASE_DIR/dev/disk/by-id/scsi-0HC_Volume_105149570"; return 0; fi
  printf '%s' "$TGT_BLK"
}
_wipe_sysfs_block() { printf '%s' "$W_CASE_DIR/sysfs"; }
_wipe_cgroup_root() { printf '%s' "$W_CASE_DIR/cgroup"; }

command() {
  if [ "${1:-}" = -v ] && [ -n "${W_TOOL_ABSENT:-}" ] && [ "${2:-}" = "$W_TOOL_ABSENT" ]; then return 1; fi
  builtin command "$@"
}
die()        { echo "DIE: $*"; exit 1; }
# emit_drift mirrors production's shape: its only terminal output happens inside a SUBSHELL (the real
# workspaces_luks_emit runs in `( ... ) || true`), so a dead stdout cannot kill the caller here either.
emit_drift() { rec "EMIT_DRIFT $1"; rec "EMIT_DRIFT_LEVEL $1 ${2:-fatal}"; ( echo "EMIT_DRIFT: $1" ) 2>/dev/null || true; }
logger()     { rec "logger $*"; printf '%s\n' "$*" >> "$MARKER_LOG"; }
hostname()   { echo test-host; }
sleep()      { rec "sleep $*"; return 0; }
docker()     { rec "docker $*"; return 0; }
mount()      { rec "mount $*"; return 0; }
umount()     { rec "umount $*"; return 0; }
apt-get()    { rec "apt-get $*"; return 1; }
curl()       { rec "curl $*"; return 1; }
shred()      { rec "shred $*"; builtin command rm -f -- "${@: -1}"; }

blkdiscard() {
  rec "blkdiscard $*"
  local a
  for a in "$@"; do case "$a" in -z|-v|--version|/*) ;; *) unk blkdiscard "$a"; return 64 ;; esac; done
  if [ "${1:-}" = --version ]; then printf 'blkdiscard from util-linux %s\n' "${W_BLKD_VER:-2.39.3}"; return 0; fi
  [ "$(devkind "${@: -1}")" = tgt ] || { unk blkdiscard "device ${*: -1}"; return 64; }
  [ -t 0 ] && rec "BLKDISCARD_STDIN_IS_A_TTY"
  if [ "${W_BLKDISCARD_RC:-0}" = 0 ]; then : > "$W_CASE_DIR/zeroed"; fi
  return "${W_BLKDISCARD_RC:-0}"
}
# pgrep: ONLY `pgrep -x blkdiscard` is legal (T1/H13: a mistyped pattern can never match the orphan).
pgrep() { rec "pgrep $*"; [ "$*" = "-x blkdiscard" ] || { unk pgrep "$*"; return 64; }; return "${W_PGREP_RC:-1}"; }
findmnt() {
  rec "findmnt $*"
  local a prev="" sdev=""
  for a in "$@"; do
    [ "$prev" = -S ] && sdev="$a"
    case "$a" in -n|-o|-r|-S|-no|-rn|SOURCE|TARGET|OPTIONS|/*) ;; -*) unk findmnt "$a"; return 64 ;; esac
    prev="$a"
  done
  if [ -n "$sdev" ]; then
    case "$(devkind "$sdev")" in
      tgt) if [ -n "${W_TGT_MNT:-}" ]; then printf '%s\n' "$W_TGT_MNT"; return 0; fi; return 1 ;;
      luks) return 1 ;;   # the backing device itself is never mounted: the MAPPER is (production-faithful)
      *) unk findmnt "-S $sdev"; return 64 ;;
    esac
  fi
  case " $* " in
    *"$WORKSPACES_MOUNT"*) printf '%s\n' "${W_MOUNT_SRC-/dev/mapper/workspaces}"; return 0 ;;
  esac
  return 1
}
cryptsetup() {
  rec "cryptsetup $*"
  local got want
  case "${1:-}" in
    status) printf '/dev/mapper/%s is active.\n  type:    LUKS2\n  device:  %s\n' "${2:-}" "$W_BACKING_DEV"; return 0 ;;
    luksUUID)
      if [ "${2:-}" = "$W_BACKING_DEV" ]; then [ -n "${W_LIVE_UUID-u-live-1}" ] || return 1; printf '%s\n' "${W_LIVE_UUID-u-live-1}"; return 0; fi
      case "${2:-}" in *wipe-header-download*) [ -n "${W_DL_UUID-u-live-1}" ] || return 1; printf '%s\n' "${W_DL_UUID-u-live-1}"; return 0 ;; esac
      return 1 ;;
    luksOpen)
      if [ "${2:-}" != --test-passphrase ] || [ "${3:-}" != --key-file ] || [ "${4:-}" != - ]; then unk cryptsetup "luksOpen ${2:-} ${3:-} ${4:-}"; return 64; fi
      got="$(cat; printf x)"; got="${got%x}"        # BYTE-EXACT: a trailing newline is kept
      case "${5:-}" in
        *wipe-header-download*) want="${W_HDR_KEY_EXPECT-k3y-synth}" ;;
        "$W_BACKING_DEV")       want="${W_KEY_EXPECT-k3y-synth}" ;;
        *) return 1 ;;
      esac
      [ "$got" = "$want" ] && return 0
      return 2 ;;
    luksHeaderBackup)
      [ "${3:-}" = --header-backup-file ] || { unk cryptsetup "luksHeaderBackup ${3:-}"; return 64; }
      [ -e "${4:-}" ] && return 1                   # the real one refuses an existing file
      [ "${W_HDRBK_RC:-0}" = 0 ] || return "${W_HDRBK_RC}"
      printf '%s' "${W_FRESH_CONTENT-HDR-v1}" > "$4"; return 0 ;;
    *) unk cryptsetup "${1:-}"; return 64 ;;
  esac
}
doppler() {
  rec "doppler $*"
  case "$*" in
    "secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks") printf '%s' "${W_KEY-k3y-synth}" ;;
    "secrets get WORKSPACES_HEADER_BUCKET --plain --config prd_workspaces_luks") printf '%s' "${W_BUCKET-wl-header-bkt}" ;;
    "secrets get WORKSPACES_HEADER_R2_ACCESS_KEY_ID --plain --config prd_workspaces_luks") printf synth-kid ;;
    "secrets get WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY --plain --config prd_workspaces_luks") printf synth-sec ;;
    "secrets get WORKSPACES_HEADER_R2_ENDPOINT --plain --config prd_workspaces_luks") printf https://r2.invalid ;;
    *) unk doppler "$*"; return 64 ;;
  esac
}
aws() {   # only a GET is legal in this mode: s3api get-object --bucket B --key K --endpoint-url E OUTFILE
  rec "aws $*"
  [ "${1:-} ${2:-}" = "s3api get-object" ] || { unk aws "${1:-} ${2:-}"; return 64; }
  [ "${3:-}" = --bucket ] && [ "${5:-}" = --key ] && [ "${7:-}" = --endpoint-url ] || { unk aws "$*"; return 64; }
  # W_HDR_ERR — what the real aws-cli prints on STDERR for a failed GetObject (it never prints the
  # body): the SUT classifies it and must never echo it.
  if [ "${W_HDR_ABSENT:-0}" = 1 ]; then
    printf '%s\n' "${W_HDR_ERR-An error occurred (NoSuchKey) when calling the GetObject operation: The specified key does not exist.}" >&2
    return "${W_HDR_RC:-254}"
  fi
  printf '%s' "${W_DL_CONTENT-HDR-v1}" > "$9"; return 0
}
stat() {
  rec "stat $*"
  local p
  if [ "${1:-}" = -Lc ] && [ "${2:-}" = '%t:%T' ]; then
    p="$(readlink -f -- "${3:-}")"
    if [ "$p" = "$TGT_REAL" ]; then
      # W_TGT_MAJMIN_2: the answer from the SECOND stat of the target (H7: when the backing path equals
      # the target's, only the PATH compare can refuse — the major:minor compare then sees two values).
      if [ -n "${W_TGT_MAJMIN_2:-}" ] && [ -f "$W_CASE_DIR/stat.tgt.1" ]; then printf '%s\n' "$W_TGT_MAJMIN_2"; return 0; fi
      : > "$W_CASE_DIR/stat.tgt.1"
      printf '%s\n' "${W_TGT_MAJMIN-8:32}"; return 0
    fi
    if [ "$p" = "$LUKS_REAL" ]; then printf '%s\n' "${W_BACKING_MAJMIN-8:16}"; return 0; fi
    return 1
  fi
  builtin command stat "$@"
}
blockdev() {
  rec "blockdev $*"
  case "${1:-}:$(devkind "${2:-}")" in
    --getsize64:tgt) printf '%s\n' "${W_SIZE-21474836480}" ;;
    --getsize64:luks) printf '%s\n' 21474836480 ;;   # both volumes ARE var.volume_size (production-faithful)
    --flushbufs:tgt) ;;
    *) unk blockdev "$*"; return 64 ;;
  esac
}
udevadm() {
  rec "udevadm $*"
  [ "${1:-}" = info ] || { unk udevadm "${1:-}"; return 64; }
  local n="${3#--name=}" k s
  k="$(devkind "$n")"
  case "${2:-}:$k" in
    --query=property:tgt)
      s="${W_SERIAL-0HC_Volume_105149570}"
      # W_SERIAL_AFTER_W6: the serial the target reports on every property read AFTER the first (W6),
      # i.e. at the W10 re-check — a different volume took the kernel name in between.
      if [ -n "${W_SERIAL_AFTER_W6:-}" ] && [ -f "$W_CASE_DIR/udev.prop.1" ]; then s="$W_SERIAL_AFTER_W6"; fi
      : > "$W_CASE_DIR/udev.prop.1"
      printf 'DEVNAME=%s\nID_SERIAL=%s\nID_SCSI_SERIAL=%s\n' "$TGT_REAL" "$s" "$s" ;;
    --query=property:luks) printf 'DEVNAME=%s\nID_SERIAL=0HC_Volume_106443278\n' "$LUKS_REAL" ;;
    --query=path:tgt) printf '/devices/virtual/wipe-test/block/%s\n' "$TGT_KNAME" ;;
    *) unk udevadm "$*"; return 64 ;;
  esac
}
blkid() {
  rec "blkid $*"
  if [ "${1:-}" != -p ] || [ "${2:-}" != -s ] || [ "${4:-}" != -o ] || [ "${5:-}" != value ]; then unk blkid "$*"; return 64; fi
  case "$(devkind "${6:-}"):${3:-}" in
    luks:TYPE) printf 'crypto_LUKS\n'; return 0 ;;
    luks:LABEL) return 2 ;;
    tgt:*) ;;
    *) unk blkid "$*"; return 64 ;;
  esac
  if zeroed; then return 2; fi
  case "${3:-}" in
    TYPE)
      [ -n "${W_BLKID_RC:-}" ] && return "$W_BLKID_RC"
      [ -n "${W_TYPE-ext4}" ] || return 2
      printf '%s\n' "${W_TYPE-ext4}"; return 0 ;;
    LABEL)
      # An UNLABELLED ext4 prints nothing with rc 0 (measured, util-linux 2.42.3): web-1's retained
      # plaintext carries no label (no artifact ever wrote one), so that is the default here.
      [ -n "${W_LABEL-}" ] || return 0
      printf '%s\n' "$W_LABEL"; return 0 ;;
    *) unk blkid "-s ${3:-}"; return 64 ;;
  esac
}
lsblk() {
  rec "lsblk $*"
  [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-}" = "-D -b -n -o DISC-GRAN,DISC-MAX" ] && [ "$(devkind "${6:-}")" = tgt ] || { unk lsblk "$*"; return 64; }
  # W_RETARGET_LINK: between W6 and W10 (lsblk runs at W8) the kernel name the by-id link resolves
  # through is taken over by ANOTHER device (hot-remove + reattach).
  if [ "${W_RETARGET_LINK:-0}" = 1 ]; then ln -sfn "$LUKS_REAL" "$W_CASE_DIR/dev/sdc"; fi
  printf '%s %s\n' 4096 1073741824
}
dumpe2fs() {
  rec "dumpe2fs $*"
  [ "${1:-}" = -h ] && [ "$(devkind "${2:-}")" = tgt ] || { unk dumpe2fs "$*"; return 64; }
  printf 'Filesystem volume name:   <none>\nLast mount time:          %s\nLast write time:          %s\n' \
    "${W_LAST_MOUNT-Thu Jul 23 09:30:00 2026}" "${W_LAST_WRITE-Thu Jul 23 09:40:30 2026}"
}
# debugfs — the READ-ONLY listing of the unmounted plaintext's /workspaces. The real one exits 0 even
# when it cannot open the device or find the path (measured, e2fsprogs 1.47.4), so the SUT must key on
# the listing's own `.`/`..` entries, which W_DEBUGFS_FAIL=1 withholds.
debugfs() {
  rec "debugfs $*"
  [ "${1:-} ${2:-}" = "-R ls -p /workspaces" ] && [ "$(devkind "${3:-}")" = tgt ] || { unk debugfs "$*"; return 64; }
  if [ "${W_DEBUGFS_FAIL:-0}" = 1 ]; then printf 'debugfs 1.47.4 (6-Mar-2025)\n/workspaces: File not found by ext2_lookup\n' >&2; return 0; fi
  local n=20 w
  printf '/%s/040755/0/0/.//\n/2/040755/0/0/..//\n' 13
  for w in ${W_PLAIN_WS-ws-a ws-b}; do n=$((n + 1)); printf '/%s/040755/0/0/%s//\n' "$n" "$w"; done
  printf '\n'
}
systemd-escape() {
  rec "systemd-escape $*"
  [ "${1:-} ${2:-}" = "--path --suffix=mount" ] || { unk systemd-escape "$*"; return 64; }
  printf 'mnt-data.mount\n'
}
# systemd-run --scope models what systemd does with IO*BandwidthMax: it writes io.max in the SCOPE's
# cgroup, for the major:minor of the device the property names, in bytes — a plain number verbatim, a
# K/M/G suffix in base 1000 (`150M` = 150000000, measured by loopback LW8 on a real kernel). The SUT's
# in-scope gate then reads that file FOR REAL (the gate text runs in a child bash). W_IOMAX_ABSENT=1 is
# the measured failure: the io controller is not enabled on the path, systemd logs a warning, the scope
# starts anyway, and io.max does not exist. W_IOMAX_LINE overrides the line verbatim.
systemd-run() {
  rec "systemd-run $*"
  local r=max w=max dv="" cg dir
  while [ $# -gt 0 ]; do
    case "$1" in
      --scope|--quiet) shift ;;
      -p)
        case "$2" in
          IOReadBandwidthMax=*)  dv="${2#IOReadBandwidthMax=}"; r="${dv##* }" ;;
          IOWriteBandwidthMax=*) dv="${2#IOWriteBandwidthMax=}"; w="${dv##* }" ;;
          *) unk systemd-run "-p $2"; return 64 ;;
        esac
        shift 2 ;;
      -*) unk systemd-run "$1"; return 64 ;;
      *) break ;;
    esac
  done
  dv="${dv%% *}"
  _w_sd_bytes() { case "$1" in *K) echo $(( ${1%K} * 1000 )) ;; *M) echo $(( ${1%M} * 1000000 )) ;; *G) echo $(( ${1%G} * 1000000000 )) ;; *) echo "$1" ;; esac; }
  [ "$r" = max ] || r="$(_w_sd_bytes "$r")"
  [ "$w" = max ] || w="$(_w_sd_bytes "$w")"
  cg="$(sed -n 's/^0:://p' /proc/self/cgroup)"
  dir="$W_CASE_DIR/cgroup$cg"; mkdir -p "$dir"; rm -f "$dir/io.max"
  if [ "${W_IOMAX_ABSENT:-0}" != 1 ] && ! { [ "${W_IOMAX_ABSENT_AT_ZERO:-0}" = 1 ] && [[ " $* " == *" blkdiscard "* ]]; }; then
    if [ -n "${W_IOMAX_LINE:-}" ]; then printf '%s\n' "$W_IOMAX_LINE" > "$dir/io.max"
    elif [ "$(devkind "$dv")" = tgt ]; then printf '%s rbps=%s wbps=%s riops=max wiops=max\n' "${W_DEVNUM-8:32}" "$r" "$w" > "$dir/io.max"
    else printf '9:99 rbps=%s wbps=%s riops=max wiops=max\n' "$r" "$w" > "$dir/io.max"; fi
  fi
  "$@"
}
dd() {
  rec "dd $*"
  local a count="" src=""
  for a in "$@"; do
    case "$a" in if=*) src="${a#if=}" ;; iflag=direct|status=none|bs=*) ;; count=*) count="${a#count=}" ;; *) unk dd "$a"; return 64 ;; esac
  done
  case "$(devkind "$src")" in
    tgt) ;;
    luks) if [ "$count" = 1 ]; then printf 'LUKS\272\276'; head -c 4090 /dev/zero; return 0; fi ;;
    *) unk dd "if=$src"; return 64 ;;
  esac
  if [ "$count" = 1 ]; then
    if zeroed || [ "${W_MAGIC:-1}" != 1 ]; then head -c 4096 /dev/zero
    else head -c 1080 /dev/zero; printf '\123\357'; head -c 3014 /dev/zero; fi
    return 0
  fi
  head -c 8192 /dev/zero
  return "${W_DD_RC:-0}"
}
cmp() {
  rec "cmp $*"
  local rc
  if [ "${1:-}" = -n ]; then
    builtin command cat > /dev/null
    if [ -n "${W_CMP_RC:-}" ]; then rc="$W_CMP_RC"; elif zeroed; then rc=0; else rc=1; fi
    [ "$rc" = 1 ] && printf -- '- /dev/zero differ: byte 1048577, line 1\n'
    return "$rc"
  fi
  [ "${1:-}" = -s ] || { unk cmp "${1:-}"; return 64; }
  builtin command cmp "$@"
}
systemctl() {
  rec "systemctl $*"
  local a u prop="" val=0 prev="" unit="" v rev=0
  case "${1:-}" in
    list-units)
      for a in "$@"; do case "$a" in list-units|--all|--type=device|--plain|--no-legend|--no-pager) ;; *) unk systemctl "$a"; return 64 ;; esac; done
      for u in $W_TARGET_UNITS dev-other.device; do printf '%s loaded active plugged Volume\n' "$u"; done
      return 0 ;;
    list-dependencies)
      # The shape systemd 258/261 prints (measured): the unit on line 1, each dependent on its own
      # indented line — the FIRST dependent is line 2. Without --reverse a device unit lists only itself,
      # so a call missing it is an `unk` (T2/H5), never a quiet empty answer.
      for a in "$@"; do case "$a" in --reverse) rev=1 ;; list-dependencies|--plain|--no-pager|--) ;; -*) unk systemctl "$a"; return 64 ;; *) unit="$a" ;; esac; done
      [ "$rev" = 1 ] || { unk systemctl "list-dependencies without --reverse"; return 64; }
      printf '%s\n' "$unit"
      if [ -n "${W_REVDEP:-}" ]; then for v in $W_REVDEP; do printf '  %s\n' "$v"; done; fi
      if [ -n "${W_REVDEP_AFTER_ZERO:-}" ] && [ -f "$W_CASE_DIR/zeroed" ]; then for v in $W_REVDEP_AFTER_ZERO; do printf '  %s\n' "$v"; done; fi
      return 0 ;;
    show)
      shift
      for a in "$@"; do
        if [ "$prev" = -p ]; then prop="$a"; prev=""; continue; fi
        case "$a" in -p) prev=-p ;; --value) val=1 ;; --) ;; -*) unk systemctl "$a"; return 64 ;; *) unit="$a" ;; esac
      done
      case "$unit#$prop" in
        workspaces-luks-deadman.timer#ActiveState)   v="${W_DM_TIMER_ACTIVE-inactive}" ;;
        workspaces-luks-deadman.service#ActiveState) v="${W_DM_SVC_ACTIVE-inactive}" ;;
        workspaces-luks-deadman.service#Job)         v="${W_DM_SVC_JOB-}" ;;
        workspaces-luks-deadman.timer#Job)           v="${W_DM_TIMER_JOB-}" ;;
        workspaces-luks-deadman.*)                   v="" ;;
        mnt-data.mount#BindsTo,Requires,What)
          printf '%s\n' "${W_MNT_BINDS-BindsTo=
Requires=-.mount system.slice dev-mapper-workspaces.device
What=/dev/mapper/workspaces}"; return 0 ;;
        *#SysFSPath) if in_target_units "$unit"; then v="/sys/devices/virtual/wipe-test/block/$TGT_KNAME"; else v="/sys/devices/other/block/zz"; fi ;;
        *#LoadState) if [ "$unit" = "${W_UNLOADED_UNIT:-}" ]; then v=not-found; else v=loaded; fi ;;
        *#ActiveState) if [ "$unit" = "${W_INACTIVE_UNIT:-}" ]; then v=inactive; else v=active; fi ;;
        *) v="" ;;
      esac
      if [ "$val" = 1 ]; then printf '%s\n' "$v"; else printf '%s=%s\n' "$prop" "$v"; fi
      return 0 ;;
    is-active) return 1 ;;
    stop|reset-failed) return 0 ;;
    *) unk systemctl "${1:-}"; return 64 ;;
  esac
}
# The in-scope io.max gate runs in a CHILD bash (the real gate text), so the stubs it runs — the zero
# and the read-back dd — and everything they call must reach that child. Exported, never re-defined.
export TGT_REAL LUKS_REAL
export -f rec unk command_not_found_handle devkind zeroed blkdiscard dd
STUBS

# --- PATH tripwires + the allowlist -------------------------------------------------------------
TRIP_DIR="$WIPE_SCRATCH/trip"; ALLOW_DIR="$WIPE_SCRATCH/allow"
mkdir -p "$TRIP_DIR" "$ALLOW_DIR"
for t in blkdiscard dd doppler aws; do
  printf '#!/usr/bin/env bash\nprintf "TRIPWIRE %%s %%s\\n" %s "$*" >> "${CALLS:-/dev/null}"\nexit 64\n' "$t" > "$TRIP_DIR/$t"
  chmod +x "$TRIP_DIR/$t"
done
for b in tr sed cut head tail grep awk cat od date mktemp basename dirname readlink sort uniq wc mkdir rm chmod sha256sum stat cmp ls env touch bash ln; do
  p="$(command -v "$b" 2>/dev/null)" || { printf 'INSTRUMENT FAIL - allowlist binary %s not found\n' "$b"; exit 2; }
  ln -sf "$p" "$ALLOW_DIR/$b"
done

# run_wipe <invocation> [VAR=value ...]
#   SEED_STATE='K=V;K=V'  written to the state file BEFORE the run (default: CANARY_OK=1:u-live-1 plus
#                         PLAINTEXT_DEV=$TGT_BLK, the plaintext mount source the cutover recorded — W6
#                         binds the first-wipe target to it). A SEED_STATE replaces BOTH lines.
#   W_HOLDERS='dm-3'      holder entries under the target's sysfs holders/ dir.
#   UNSET_DRY_RUN=1       run with DRY_RUN absent from the environment (the script default applies).
#   SEED_HDRS=1           pre-create the two fixed W5 header paths (as a mid-W5 abort would leave them).
#   W_LIVE_WS='a b'       workspace dirs on the LIVE mount (default `ws-a ws-b`, the plaintext listing's
#                         default too, so the happy path reads plaintext_only=0).
#   PRE_INV='<shell>'     eval'd after the stubs and BEFORE the invocation (a per-case override of a
#                         script function, e.g. an unwritable persist_state).
# Sets CASE_RC, CASE_OUT, CALLS, MARKER_LOG, STATE.
run_wipe() {
  local invocation="$1"; shift
  CASE_N=$((CASE_N + 1))
  local d="$WIPE_SCRATCH/case-$CASE_N" k h seeded=0 unset_dry=0 live="ws-a ws-b"
  CALLS="$d/calls"; MARKER_LOG="$d/marker"; STATE="$d/state"
  mkdir -p "$STATE" "$d/mnt/workspaces" "$d/staging" "$d/sysfs/$TGT_KNAME/holders" "$d/sysfs/$TGT_KNAME/queue" "$d/dev/disk/by-id"
  : > "$CALLS"; : > "$MARKER_LOG"
  printf '33554432\n' > "$d/sysfs/$TGT_KNAME/queue/write_zeroes_max_bytes"
  printf '[mq-deadline] none\n' > "$d/sysfs/$TGT_KNAME/queue/scheduler"
  printf '8:32\n' > "$d/sysfs/$TGT_KNAME/dev"
  ln -s "$TGT_REAL" "$d/dev/sdc"
  ln -s ../../sdc "$d/dev/disk/by-id/scsi-0HC_Volume_${PIN}"
  local -a envs=()
  for k in "$@"; do
    case "$k" in
      SEED_STATE=*) seeded=1; [ -n "${k#SEED_STATE=}" ] && printf '%s\n' "${k#SEED_STATE=}" | tr ';' '\n' > "$STATE/state" ;;
      W_HOLDERS=*) for h in ${k#W_HOLDERS=}; do mkdir -p "$d/sysfs/$TGT_KNAME/holders/$h"; done ;;
      UNSET_DRY_RUN=1) unset_dry=1 ;;
      SEED_HDRS=1) printf 'hdr' > "$STATE/wipe-header-download.img"; printf 'hdr' > "$STATE/wipe-header-fresh.img" ;;
      W_LIVE_WS=*) live="${k#W_LIVE_WS=}" ;;
      *) envs+=("$k") ;;
    esac
  done
  [ "$seeded" = 1 ] || printf 'CANARY_OK=1:%s\nPLAINTEXT_DEV=%s\n' "$UUID_LIVE" "$TGT_BLK" > "$STATE/state"
  for h in $live; do mkdir -p "$d/mnt/workspaces/$h"; done
  local -a pre=(env)
  [ "$unset_dry" = 1 ] && pre+=(-u DRY_RUN)
  local -a base=(CUTOVER="$CUTOVER" WIPE_STUBS="$WIPE_STUBS" CALLS="$CALLS" MARKER_LOG="$MARKER_LOG"
    W_CASE_DIR="$d" TRIP_DIR="$TRIP_DIR" ALLOW_DIR="$ALLOW_DIR" TGT_BLK="$TGT_BLK" LUKS_BLK="$LUKS_BLK"
    INVOCATION="$invocation" MAIN_PREFIX="${MAIN_PREFIX:-}" RB_TEXT="${RB_TEXT:-}" PRE_INV="${PRE_INV:-}"
    WORKSPACES_STATE_DIR="$STATE" WORKSPACES_MOUNT="$d/mnt" WORKSPACES_STAGING="$d/staging"
    CONFIRM_WIPE=1 ROLLBACK=0 CLEAN_STRAY=0 TZ=UTC
    WORKSPACES_PLAINTEXT_VOLUME_ID="$PIN" WORKSPACES_PLAINTEXT_DEV="$BYID"
    WORKSPACES_PLAINTEXT_SIZE_BYTES="$SIZE" WORKSPACES_LUKS_DEV="$LUKS_BLK")
  [ "$unset_dry" = 1 ] || base+=(DRY_RUN=0)
  CASE_OUT="$(
    "${pre[@]}" "${base[@]}" "${envs[@]}" bash -c '
      source "$CUTOVER"
      source "$WIPE_STUBS"
      PATH="$TRIP_DIR:$ALLOW_DIR"
      eval "$PRE_INV"
      eval "$INVOCATION"
    ' 2>&1
  )"
  CASE_RC=$?
}

# --- predicates (file-direct or herestring; never a pipe into a verdict) --------------------------
nounk()  { ! grep -qE '^(STUB_UNKNOWN_FLAG|UNSTUBBED|TRIPWIRE) ' "$CALLS"; }
unkdump() { grep -E '^(STUB_UNKNOWN_FLAG|UNSTUBBED|TRIPWIRE) ' "$CALLS" | tr '\n' '|' | cut -c1-200; }
zero_calls() { grep -cE '^blkdiscard (-z|-v|/)' "$CALLS" || true; }
row_line() {  # <result> -> first CASE_OUT line number of a WIPE row with that result (empty if none)
  awk -v p="^$WROW result=$1 " '$0 ~ p { print NR; exit }' <<<"$CASE_OUT"
}
wrow() {  # <result> <arm> -> the full row, empty if absent
  awk -v p="^$WROW result=$1 arm=$2 volume_id=" '$0 ~ p { print; exit }' <<<"$CASE_OUT"
}
nrows() { grep -c "^$WROW result=$1 " <<<"$CASE_OUT" || true; }
state_has() { grep -qE "^$1=" "$STATE/state" 2>/dev/null; }
hdrs_gone() { [ ! -e "$STATE/wipe-header-download.img" ] && [ ! -e "$STATE/wipe-header-fresh.img" ]; }
# refused_ok <slug> — the exact refusal contract: non-zero, exactly one refused row naming THIS slug,
# printed BEFORE the die, the same slug on the Sentry channel, and a clean stub world.
refused_ok() {
  local slug="$1" rl dl
  died || return 1
  rl="$(awk -v p="^$WROW result=refused arm=[a-z_]+ volume_id=[^ ]* reason=${slug}( |\$)" '$0 ~ p { print NR; exit }' <<<"$CASE_OUT")"
  dl="$(awk '/^DIE: / { print NR; exit }' <<<"$CASE_OUT")"
  [ -n "$rl" ] && [ -n "$dl" ] && [ "$rl" -lt "$dl" ] || return 1
  [ "$(nrows refused)" -eq 1 ] || return 1
  has "^EMIT_DRIFT ${slug}\$" || return 1
  nounk
}
# refusal <label> <slug> [run_wipe args...] — one RED row: the named refusal, and NO zeroing.
refusal() {
  local label="$1" slug="$2"; shift 2
  run_wipe 'wipe_plaintext; echo WIPE_RETURNED' "$@"
  if refused_ok "$slug" && [ "$(zero_calls)" -eq 0 ] && ! outF WIPE_RETURNED; then
    ok "$label → refused reason=$slug before any zeroing"
  else
    no "$label → expected reason=$slug, no blkdiscard (rc=$CASE_RC zero=$(zero_calls) unk=[$(unkdump)]) $(grep -E 'result=refused|^DIE' <<<"$CASE_OUT" | tr '\n' '|' | cut -c1-260)"
  fi
}

# ============================================================================
# H1 — INSTRUMENT: the recorder, the tripwire and the closed world must work, or every verdict below is
# meaningless. Reports through printf + exit 2, never through no().
# ============================================================================
run_wipe 'blkdiscard -z /dev/h1-probe; unset -f blkdiscard; blkdiscard -z /dev/h1-escaped; echo "trip_rc=$?"; no_such_binary_h1; echo "cnf_rc=$?"'
if ! hasF 'blkdiscard -z /dev/h1-probe' || ! has '^TRIPWIRE blkdiscard -z /dev/h1-escaped$' || ! outF 'trip_rc=64' \
  || ! has '^UNSTUBBED no_such_binary_h1$' || ! outF 'cnf_rc=127'; then
  printf 'INSTRUMENT FAIL - H1: recorder/tripwire/closed-world broken (rc=%s) calls=[%s] out=[%s]\n' "$CASE_RC" "$(tr '\n' '|' < "$CALLS" | cut -c1-200)" "${CASE_OUT:0:200}"
  exit 2
fi
ok "H1 instrument: the recorder records, an escaped blkdiscard hits the PATH tripwire (rc 64), an unstubbed command is recorded"
# T8 — the verdict-owning predicates prove themselves on synthetic evidence (a known-positive and a
# known-negative each), or every refusal row below would be only as strong as a neutered helper.
t8_fail=""
T8D="$WIPE_SCRATCH/t8"; mkdir -p "$T8D/state"
CALLS="$T8D/calls"; STATE="$T8D/state"
printf 'blkid -p -s TYPE -o value /dev/x\n' > "$CALLS"; nounk || t8_fail="$t8_fail nounk-clean"
for bad in 'STUB_UNKNOWN_FLAG blkid -q' 'UNSTUBBED wipefs' 'TRIPWIRE blkdiscard -z /dev/x'; do
  printf '%s\n' "$bad" >> "$CALLS"; nounk && t8_fail="$t8_fail nounk-missed[$bad]"
  printf 'blkid -p\n' > "$CALLS"
done
: > "$STATE/wipe-header-download.img"; hdrs_gone && t8_fail="$t8_fail hdrs_gone-missed-download"
rm -f "$STATE/wipe-header-download.img"; : > "$STATE/wipe-header-fresh.img"; hdrs_gone && t8_fail="$t8_fail hdrs_gone-missed-fresh"
rm -f "$STATE/wipe-header-fresh.img"; hdrs_gone || t8_fail="$t8_fail hdrs_gone-clean"
t8_refusal() {  # <slug in row> <slug in drift> <die after row: 1|0> <rows>
  CASE_RC=1; printf 'EMIT_DRIFT %s\n' "$2" > "$CALLS"
  local r="$WROW result=refused arm=first_wipe volume_id=105149570 reason=$1" out="" i
  for ((i = 0; i < $4; i++)); do out="$out$r"$'\n'; done
  if [ "$3" = 1 ]; then CASE_OUT="${out}DIE: x"; else CASE_OUT="DIE: x"$'\n'"$out"; fi
}
t8_refusal wipe_a wipe_a 1 1; refused_ok wipe_a || t8_fail="$t8_fail refused_ok-positive"
t8_refusal wipe_a wipe_a 1 1; refused_ok wipe_b && t8_fail="$t8_fail refused_ok-wrong-slug"
t8_refusal wipe_a wipe_a 0 1; refused_ok wipe_a && t8_fail="$t8_fail refused_ok-row-after-die"
t8_refusal wipe_a wipe_a 1 2; refused_ok wipe_a && t8_fail="$t8_fail refused_ok-two-rows"
t8_refusal wipe_a wipe_other 1 1; refused_ok wipe_a && t8_fail="$t8_fail refused_ok-drift-slug"
t8_refusal wipe_a wipe_a 1 1; CASE_RC=0; refused_ok wipe_a && t8_fail="$t8_fail refused_ok-rc0"
if [ -n "$t8_fail" ]; then
  printf 'INSTRUMENT FAIL - T8: a verdict predicate is neutered:%s\n' "$t8_fail"
  exit 2
fi
ok "T8 instrument: nounk, hdrs_gone and refused_ok each accept their known-positive and reject their known-negatives (wrong slug, row after DIE, two rows, wrong drift slug, rc 0)"

# ============================================================================
# Happy paths
# ============================================================================
# P1 — the real first wipe: exactly one zeroing of the resolved target, capped, then the read-back,
# then the success row; nothing escapes the stub world; aws is never installed.
run_wipe 'wipe_plaintext; echo WIPE_RETURNED'
P1_ROW="$(wrow wiped first_wipe)"
b_ln="$(row_line begun)"; r_ln="$(row_line readback_start)"; w_ln="$(row_line wiped)"
if ran && outF WIPE_RETURNED && [ -n "$P1_ROW" ] && [ "$(zero_calls)" -eq 1 ] \
  && hasF "blkdiscard -z -v $TGT_REAL" && nounk && nhas '^(apt-get|curl) ' \
  && [ -n "$b_ln" ] && [ -n "$r_ln" ] && [ -n "$w_ln" ] && [ "$b_ln" -lt "$r_ln" ] && [ "$r_ln" -lt "$w_ln" ] \
  && state_has PLAINTEXT_WIPE_BEGUN && state_has PLAINTEXT_WIPED && nhas '^BLKDISCARD_STDIN_IS_A_TTY$'; then
  ok "P1 first wipe: one blkdiscard -z -v on the resolved target, begun < readback_start < wiped, both markers persisted, aws never installed"
else
  no "P1 first wipe did not complete cleanly (rc=$CASE_RC zero=$(zero_calls) unk=[$(unkdump)]) ${CASE_OUT:0:300}"
fi
# scoped <prefix> <suffix> — a recorded systemd-run line that STARTS with the scope properties and ENDS with
# the gate arguments + the command (the gate text itself sits between them).
scoped() { awk -v p="$1" -v q="$2" 'index($0, p) == 1 && substr($0, length($0) - length(q) + 1) == q { f = 1 } END { exit !f }' "$CALLS"; }
P1_CG="$WIPE_SCRATCH/case-$CASE_N/cgroup"
scoped "systemd-run --scope --quiet -p IOWriteBandwidthMax=$TGT_REAL 150000000 -p IOReadBandwidthMax=$TGT_REAL 150000000 bash -c " \
  " wipe-io-gate $P1_CG 8:32 150000000 150000000 blkdiscard -z -v $TGT_REAL" \
  && ok "P1b the zero runs inside a scope capped at 150M read AND write on the target, behind the in-scope io.max gate (rbps=wbps=150000000 for the target's MAJ:MIN)" \
  || no "P1b the zero is not wrapped in the gated io.max scope: $(grep -E '^systemd-run .*blkdiscard' "$CALLS" | head -1 | cut -c1-200)"
scoped "systemd-run --scope --quiet -p IOReadBandwidthMax=$TGT_REAL 150000000 bash -c " \
  " wipe-io-gate $P1_CG 8:32 150000000 - dd if=$TGT_REAL iflag=direct bs=4M status=none" \
  && hasF "cmp -n $SIZE - /dev/zero" \
  && ok "P1c the read-back is a capped (gated, read cap) O_DIRECT full-device read compared by cmp -n <size> against /dev/zero" \
  || no "P1c the read-back shape drifted (gate / direct IO / cap / cmp -n size): $(grep -E '^(systemd-run .*dd|cmp -n)' "$CALLS" | tr '\n' '|' | cut -c1-240)"
# P1f (T1) — every identity probe names the RESOLVED TARGET, never another device. The device-keyed
# stubs answer the backing device with the backing device's facts (same size, not mounted), so these
# pins are what kill a probe re-pointed at it.
p1f_missing=""
for pin in "findmnt -rn -S $TGT_REAL -o TARGET" "blockdev --getsize64 $TGT_REAL" "udevadm info --query=property --name=$TGT_REAL" \
  "blkid -p -s LABEL -o value $TGT_REAL" "dd if=$TGT_REAL iflag=direct bs=4096 count=1 status=none" "dumpe2fs -h $TGT_REAL" \
  "debugfs -R ls -p /workspaces $TGT_REAL" "blkid -p -s TYPE -o value $TGT_REAL" "pgrep -x blkdiscard" "lsblk -D -b -n -o DISC-GRAN,DISC-MAX $TGT_REAL"; do
  hasF "$pin" || p1f_missing="$p1f_missing [$pin]"
done
[ "$(grep -cxF "udevadm info --query=property --name=$TGT_REAL" "$CALLS")" -eq 2 ] || p1f_missing="$p1f_missing [udevadm property x2: W6 + the W10 re-check]"
[ -z "$p1f_missing" ] && ok "P1f each identity/evidence probe names the resolved target (findmnt -S, blockdev, udevadm x2, blkid LABEL/TYPE, the magic dd, dumpe2fs, debugfs, lsblk) and pgrep names blkdiscard exactly" \
  || no "P1f probe arguments drifted, missing:$p1f_missing"
grep -qE -- "^cmp .*(-l|-b)" "$CALLS" \
  && no "P1d cmp was run with -l/-b — it would print device bytes (user content) into the log" \
  || ok "P1d cmp never runs with -l/-b (no device bytes can reach a log)"
# The success row, parsed by the WORKFLOW's own regex (read from the file, so the two cannot drift).
WF_ROW_RE="$(sed -n "s/^[[:space:]]*ROW_RE='\(.*\)'[[:space:]]*$/\1/p" "$WORKFLOW" 2>/dev/null | head -1)"
if [ -n "$WF_ROW_RE" ] && [ -n "$P1_ROW" ] && [[ "$P1_ROW" =~ $WF_ROW_RE ]] && [ "${BASH_REMATCH[2]:-}" = "$PIN" ]; then
  ok "P1e the wiped row matches the wipe job's success-row regex exactly, and its volume_id capture is the pin"
else
  no "P1e the wiped row does not satisfy the workflow parser (re=[${WF_ROW_RE:0:80}] row=[${P1_ROW:0:200}])"
fi

# P2 — the rehearsal (DRY_RUN=1): every precondition, no zero, no marker, and the row carries the fields
# W3–W9 measured (a rehearsal that stopped at W2 must not read as green — Guard 2 row 6).
run_wipe 'wipe_plaintext; echo WIPE_RETURNED' DRY_RUN=1
P2_ROW="$(wrow rehearsal_ok first_wipe)"
p2_fields=1; p2_missing=""
for f in "uuid=$UUID_LIVE" "hdr_sha256=" "hdr_bytes=" "label=none plaintext_dev=$TGT_BLK " "dependents=0" "holders=0" "device_units=2" \
  "discard_gran=4096" "write_zeroes_max=33554432" "scheduler=mq-deadline" "magic=53ef" "size=$SIZE" \
  "io_max=8:32_rbps=150000000_wbps=150000000_riops=max_wiops=max" "plaintext_only=0"; do
  [[ "$P2_ROW" == *" $f"* ]] || { p2_fields=0; p2_missing="$p2_missing $f"; }
done
if ran && [ -n "$P2_ROW" ] && [ "$p2_fields" = 1 ] && [ "$(zero_calls)" -eq 0 ] && nounk \
  && ! state_has PLAINTEXT_WIPE_BEGUN && ! state_has PLAINTEXT_WIPED && hdrs_gone \
  && [ "$(nrows begun)" -eq 0 ] && [ "$(nrows wiped)" -eq 0 ]; then
  ok "P2 rehearsal: one rehearsal_ok arm=first_wipe row carrying the W3–W9 fields; no blkdiscard, no PLAINTEXT_* marker, both header copies shredded"
else
  no "P2 rehearsal wrong (rc=$CASE_RC zero=$(zero_calls) missing=[$p2_missing] unk=[$(unkdump)]) ${CASE_OUT:0:200}"
fi
# P2b — Guard 2 H1: the same with DRY_RUN absent from the environment (the script default, 1).
run_wipe 'wipe_plaintext; echo WIPE_RETURNED' UNSET_DRY_RUN=1
[ -n "$(wrow rehearsal_ok first_wipe)" ] && [ "$(zero_calls)" -eq 0 ] && ran \
  && ok "P2b DRY_RUN unset takes the rehearsal default — no zero" \
  || no "P2b DRY_RUN unset did not rehearse (rc=$CASE_RC zero=$(zero_calls))"
# P2c — the dumpe2fs provenance times ride a SEPARATE evidence row, never the success/rehearsal row.
grep -qE '^SOLEUR_WORKSPACES_LUKS_WIPE_EVIDENCE feature=workspaces-luks op=workspaces-luks-wipe-evidence volume_id=105149570 field=last_write detail=' <<<"$CASE_OUT" \
  && ! grep -qE "^$WROW .*Thu Jul" <<<"$CASE_OUT" \
  && ok "P2c dumpe2fs last-write time is recorded on the evidence row, not the parsed row" \
  || no "P2c the provenance evidence row is missing or free text leaked into a parsed row"

# P3 — re_zero: an interrupted zero (BEGUN set, superblock already cleared) resumes; W9 does not run.
run_wipe 'wipe_plaintext; echo WIPE_RETURNED' "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_WIPE_BEGUN=$PIN:1759000000" W_TYPE=
if ran && [ -n "$(wrow wiped re_zero)" ] && [ "$(zero_calls)" -eq 1 ] && nhas '^dd .*count=1' && nhas '^blkid .* LABEL ' \
  && nhas '^(dumpe2fs|debugfs) ' && nounk; then
  ok "P3 re_zero: BEGUN + blank superblock re-zeroes without the positive control or the label check"
else
  no "P3 re_zero wrong (rc=$CASE_RC zero=$(zero_calls) unk=[$(unkdump)]) ${CASE_OUT:0:240}"
fi
run_wipe 'wipe_plaintext' "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_WIPE_BEGUN=$PIN:1759000000" W_BLKID_RC=8
[ -n "$(wrow wiped re_zero)" ] && ran \
  && ok "P3b re_zero accepts an ambivalent probe (blkid rc 8) once BEGUN names this id" \
  || no "P3b ambivalent + BEGUN did not re-zero (rc=$CASE_RC) ${CASE_OUT:0:200}"
run_wipe 'wipe_plaintext' "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_WIPED=$PIN:1759000000"
[ -n "$(wrow wiped re_zero)" ] && ran && [ "$(zero_calls)" -eq 1 ] \
  && ok "P3c a volume already WIPED but still attached (delete failed before detach) re-zeroes idempotently" \
  || no "P3c WIPED-but-attached did not re-zero (rc=$CASE_RC) ${CASE_OUT:0:200}"

# P4 — detached: the device is gone and PLAINTEXT_WIPED names this id — nothing is written.
run_wipe 'wipe_plaintext; echo WIPE_RETURNED' "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_WIPED=$PIN:1759000000" W_DEV_ABSENT=1
if ran && [ -n "$(wrow already_wiped_detached detached)" ] && [ "$(zero_calls)" -eq 0 ] && nhas '^(cryptsetup|aws) ' && nounk; then
  ok "P4 detached: an absent device with PLAINTEXT_WIPED for this id reports already_wiped_detached and touches nothing"
else
  no "P4 detached arm wrong (rc=$CASE_RC unk=[$(unkdump)]) ${CASE_OUT:0:240}"
fi
run_wipe 'wipe_plaintext' "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_WIPED=$PIN:1759000000" W_DEV_ABSENT=1 DRY_RUN=1
[ -n "$(wrow rehearsal_ok detached)" ] && ran \
  && ok "P4b a rehearsal of the detached arm reports rehearsal_ok arm=detached" \
  || no "P4b detached rehearsal wrong (rc=$CASE_RC) ${CASE_OUT:0:200}"

# H2 (Guard 1) — a valid target whose by-id link is a RELATIVE symlink to ../../sdc resolves and wipes.
run_wipe 'wipe_plaintext' W_DEV_VIA_RELLINK=1
[ -n "$(wrow wiped first_wipe)" ] && ran && hasF "blkdiscard -z -v $TGT_REAL" \
  && ok "H2 a relative by-id symlink (../../sdc) resolves to the real node, which is what is zeroed" \
  || no "H2 relative-symlink target not handled (rc=$CASE_RC) ${CASE_OUT:0:240}"

# ============================================================================
# Stage 1 — environment
# ============================================================================
refusal "W0 util-linux 2.35 (no O_EXCL guarantee)" wipe_tool_missing W_BLKD_VER=2.35.2
run_wipe 'wipe_plaintext' DRY_RUN=1 W_BLKD_VER=2.36.1
[ -n "$(wrow rehearsal_ok first_wipe)" ] && ok "W0 util-linux 2.36 passes" || no "W0 util-linux 2.36 refused (rc=$CASE_RC) ${CASE_OUT:0:160}"
run_wipe 'wipe_plaintext' DRY_RUN=1 W_BLKD_VER=3.0
[ -n "$(wrow rehearsal_ok first_wipe)" ] && ok "W0 util-linux 3.0 passes (major.minor compare, not minor alone)" || no "W0 util-linux 3.0 refused (rc=$CASE_RC) ${CASE_OUT:0:160}"
refusal "W0 a blkdiscard already running (orphaned zero)" wipe_in_progress W_PGREP_RC=0
refusal "W0 pgrep itself errors (rc 2) — cannot prove none running" wipe_tool_missing W_PGREP_RC=2
refusal "W0 aws absent" wipe_tool_missing W_TOOL_ABSENT=aws
nhas '^(apt-get|curl) ' && ok "W0 an absent aws is refused, never installed (ensure_aws is not called on prod web-1)" \
  || no "W0 the wipe tried to install aws on the host"
refusal "W0 systemd-run absent" wipe_tool_missing W_TOOL_ABSENT=systemd-run
refusal "W1 (Guard 1 #6) a glob device path" wipe_input_invalid "WORKSPACES_PLAINTEXT_DEV=/dev/disk/by-id/scsi-0HC_Volume_*"
refusal "W1 (Guard 1 #6) a by-id path for a different id than the pin" wipe_input_invalid WORKSPACES_PLAINTEXT_DEV=/dev/disk/by-id/scsi-0HC_Volume_106443278
refusal "W1 a non-numeric volume id" wipe_input_invalid "WORKSPACES_PLAINTEXT_VOLUME_ID=1 2"
refusal "W1 a non-numeric size" wipe_input_invalid WORKSPACES_PLAINTEXT_SIZE_BYTES=20G
refusal "W1 the plaintext path equals the LUKS path" wipe_input_invalid "WORKSPACES_LUKS_DEV=$BYID"
# W1 (struct R-DRY) — the rehearsal gate is an exact `= "1"`, so the mode flags are validated to {0,1}
# first: every other spelling would otherwise take the DESTRUCTIVE arm.
refusal "W1 DRY_RUN=true (not 0/1) never reaches the zero" wipe_input_invalid DRY_RUN=true
refusal "W1 DRY_RUN=' 1' (not 0/1) never reaches the zero" wipe_input_invalid "DRY_RUN= 1"
refusal "W1 CONFIRM_WIPE=yes (not 0/1)" wipe_input_invalid CONFIRM_WIPE=yes
refusal "W2 /mnt/data is not the LUKS mapper" wipe_live_mount_not_mapper W_MOUNT_SRC=/dev/sdz9

# ============================================================================
# Stage 2 — the arm table
# ============================================================================
refusal "S2 a marker naming a different volume" wipe_marker_other_volume "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_WIPE_BEGUN=999:1"
refusal "S2 device absent without PLAINTEXT_WIPED" wipe_target_absent_unexplained W_DEV_ABSENT=1
refusal "S2 blank device with no markers" wipe_target_blank_unexplained W_TYPE=
refusal "S2 ambivalent probe with no markers" wipe_target_blank_unexplained W_BLKID_RC=8
refusal "S2 (Guard 1 #3) a crypto_LUKS signature on the target" wipe_target_not_ext4 W_TYPE=crypto_LUKS
refusal "S2 (Guard 1 #9b) re_zero arm with a crypto_LUKS signature" wipe_target_not_ext4 "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_WIPE_BEGUN=$PIN:1" W_TYPE=crypto_LUKS
refusal "S2 an xfs signature with no markers" wipe_target_not_ext4 W_TYPE=xfs
refusal "S2 blkid usage error (rc 4) with a marker" wipe_blkid_probe_failed "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_WIPE_BEGUN=$PIN:1" W_BLKID_RC=4

# ============================================================================
# Stage 3 — W3..W12
# ============================================================================
refusal "W3 no persisted CANARY_OK" wipe_canary_ok_absent SEED_STATE=
refusal "W3 CANARY_OK uuid differs from the live header" wipe_header_uuid_mismatch "SEED_STATE=CANARY_OK=1:u-other"
refusal "W3 the mapper is backed by a device other than WORKSPACES_LUKS_DEV" wipe_mapper_not_luks_volume W_BACKING=/dev/sdz7
refusal "W4 the escrowed passphrase does not open the live header" wipe_escrow_passphrase_mismatch W_KEY_EXPECT=other-key
refusal "W4 the escrowed passphrase is unreadable" wipe_escrow_passphrase_mismatch W_KEY=
# W4 fidelity — a key delivered WITH a trailing newline is a different passphrase (the luks-monitor
# `printf '%s'` form is load-bearing). The stub compares byte-for-byte, so this row fails if the SUT
# ever pipes `echo "$key"` or `<<<"$key"`.
run_wipe 'wipe_plaintext' DRY_RUN=1 "W_KEY_EXPECT=k3y-synth
"
refused_ok wipe_escrow_passphrase_mismatch \
  && ok "W4 fidelity: the stub rejects a newline-terminated key, so the SUT's printf '%s' form is what makes the happy path pass" \
  || no "W4 fidelity row did not refuse a newline-bearing expected key (rc=$CASE_RC)"
refusal "W5 the off-host header object is absent" wipe_header_backup_absent W_HDR_ABSENT=1
hdrs_gone && ok "W5 absent: no header copy left on the root disk" || no "W5 absent: a header copy survived"
refusal "W5 the downloaded header's UUID differs" wipe_header_backup_mismatch W_DL_UUID=u-other
hdrs_gone && ok "W5 uuid mismatch: both header copies shredded on the refusal" || no "W5 uuid mismatch: a header copy survived the refusal"
refusal "W5 the escrowed passphrase does not open the downloaded header" wipe_header_backup_mismatch W_HDR_KEY_EXPECT=other-key
hdrs_gone && ok "W5 keyslot mismatch: both header copies shredded" || no "W5 keyslot mismatch: a header copy survived"
refusal "W5 the fresh luksHeaderBackup differs from the escrowed object (stale backup)" wipe_header_backup_stale W_FRESH_CONTENT=HDR-v2
hdrs_gone && has '^shred -u .*wipe-header-download' && has '^shred -u .*wipe-header-fresh' \
  && ok "W5 stale: both header copies shred -u'd (not merely unlinked)" || no "W5 stale: header copies not shredded"
refusal "W5 the fresh luksHeaderBackup itself fails" wipe_header_backup_stale W_HDRBK_RC=1
hdrs_gone && ok "W5 backup failure: no header copy left behind" || no "W5 backup failure: a header copy survived"
# W5 — a refusal raised inside a REUSED helper (load_escrow_creds dies on its own) surfaces as the
# cleanup() outcome row, mode=wipe — not as a WIPE row.
run_wipe 'trap cleanup EXIT; wipe_plaintext' W_BUCKET=
if died && [ "$(nrows refused)" -eq 0 ] && markerF "$DM result=cutover_aborted outcome=wipe_aborted mode=wipe" \
  && has '^EMIT_DRIFT header_bucket_unreadable$' && nounk; then
  ok "W5 a helper that dies on its own (load_escrow_creds) records outcome=wipe_aborted mode=wipe via cleanup()"
else
  no "W5 reused-helper refusal mis-recorded (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|') ${CASE_OUT:0:160}"
fi
# cleanup() sweeps the two fixed header paths on ANY wipe abort (belt to the explicit shreds).
run_wipe '[ -e "$STATE_DIR/wipe-header-download.img" ] && [ -e "$STATE_DIR/wipe-header-fresh.img" ] && echo HDRS_SEEDED; trap cleanup EXIT; die "synthetic abort mid-W5"' SEED_HDRS=1
died && outF HDRS_SEEDED && hdrs_gone && markerF "outcome=wipe_aborted mode=wipe" \
  && ok "W5 cleanup() sweeps both fixed header paths on a wipe abort" \
  || no "W5 cleanup() left a header copy on the root disk (rc=$CASE_RC)"

refusal "W6 (Guard 1 #1) the mapper's backing device IS the target" wipe_target_is_mapper_backing "W_BACKING=$TGT_BLK" "WORKSPACES_LUKS_DEV=$TGT_BLK"
refusal "W6 (Guard 1 #2) same major:minor through a different path" wipe_target_is_mapper_backing W_BACKING_MAJMIN=8:32
# H7 (T9) — the PATH compare on its own: the backing path IS the target's, but the second stat of it
# answers a different major:minor, so only the path compare can refuse (its row carries target=/backing=,
# the major:minor compare's carries target_majmin=/backing_majmin=).
refusal "W6 (Guard 1 #1, path compare alone) the backing path IS the target, major:minor reads differ" wipe_target_is_mapper_backing \
  "W_BACKING=$TGT_BLK" "WORKSPACES_LUKS_DEV=$TGT_BLK" W_TGT_MAJMIN_2=8:99
h7_row="$(awk -v p="^$WROW result=refused " '$0 ~ p { print; exit }' <<<"$CASE_OUT")"
[[ "$h7_row" == *" backing=$TGT_REAL"* && "$h7_row" != *"backing_majmin="* ]] \
  && ok "H7 the path compare refused by itself (row carries backing=<path>, not backing_majmin=)" \
  || no "H7 the refusal did not come from the path compare (row=[${h7_row:0:200}])"
refusal "W6 (Guard 1 #4) a holder under /sys/class/block/<k>/holders" wipe_target_held W_HOLDERS=dm-7
refusal "W6 the target is mounted somewhere (findmnt -S)" wipe_target_mounted W_TGT_MNT=/mnt/stray
refusal "W6 (Guard 1 #5) size off by one GiB" wipe_target_size_mismatch W_SIZE=22548578304
refusal "W6 (Guard 1 #9c) ID_SERIAL does not name HC_Volume_<id>" wipe_target_serial_mismatch W_SERIAL=0HC_Volume_106443278
refusal "W6 ID_SERIAL naming a LONGER id that merely starts with the pin" wipe_target_serial_mismatch W_SERIAL=0HC_Volume_1051495701
# --- G1 (Guard 1, #6604 fix-forward) — W6 binds the first-wipe target to the plaintext mount source the
# cutover RECORDED (PLAINTEXT_DEV, the last line wins), never to a filesystem label: no artifact ever
# labelled web-1's retained plaintext, and the 2026-09-30 rehearsal refused label=none on exactly that
# premise. The label is observed EVIDENCE on the row, never a gate.
LUKS_REAL_T="$(readlink -f -- "$LUKS_BLK")"
# A NON-CANONICAL /dev alias of the target (G1-P2): a real udev symlink when the host has one
# (/dev/block/<MAJ:MIN>), else a `/./` path — both resolve to the target only through readlink -f.
G1_ALIAS="/dev/block/$(tr -d '[:space:]' < "/sys/class/block/$TGT_KNAME/dev" 2>/dev/null)"
if [ ! -L "$G1_ALIAS" ] || [ "$(readlink -f -- "$G1_ALIAS")" != "$TGT_REAL" ]; then G1_ALIAS="/dev/./$TGT_KNAME"; fi
[ "$(readlink -f -- "$G1_ALIAS")" = "$TGT_REAL" ] && [ "$G1_ALIAS" != "$TGT_REAL" ] \
  || { printf 'INSTRUMENT FAIL - no non-canonical /dev alias of %s (got %s)\n' "$TGT_REAL" "$G1_ALIAS"; exit 2; }
g1_rehearsed() {  # <label> <expected exact fragment of the rehearsal_ok row>
  local r; r="$(wrow rehearsal_ok first_wipe)"
  if ran && [ -n "$r" ] && [[ "$r " == *" $2 "* ]] && [ "$(zero_calls)" -eq 0 ] && nounk && [ "$(nrows refused)" -eq 0 ]; then
    ok "$1"
  else
    no "$1 (rc=$CASE_RC want=[$2] row=[${r:0:260}]) $(grep -E 'result=refused|^DIE' <<<"$CASE_OUT" | tr '\n' '|' | cut -c1-260)"
  fi
}
g1_refused() {  # <label> <expected recorded=> <expected recorded_real=> [run_wipe args...]
  local label="$1" rec_want="$2" real_want="$3" r; shift 3
  # W_LABEL=workspaces_plain: every refusal row carries the label the retired gate wanted, so a label gate
  # re-introduced anywhere cannot be what makes these refuse (F-10).
  run_wipe 'wipe_plaintext; echo WIPE_RETURNED' DRY_RUN=1 W_LABEL=workspaces_plain "$@"
  r="$(awk -v p="^$WROW result=refused arm=first_wipe " '$0 ~ p { print; exit }' <<<"$CASE_OUT")"
  if refused_ok wipe_target_not_recorded_plaintext && [ "$(zero_calls)" -eq 0 ] && ! outF WIPE_RETURNED \
    && ! state_has PLAINTEXT_WIPE_BEGUN && hdrs_gone \
    && [[ "$r " == *" target=$TGT_REAL recorded=$rec_want recorded_real=$real_want "* ]]; then
    ok "$label → refused wipe_target_not_recorded_plaintext (target=/recorded=/recorded_real= evidence, no BEGUN, headers shredded)"
  else
    no "$label → want wipe_target_not_recorded_plaintext recorded=$rec_want recorded_real=$real_want (rc=$CASE_RC unk=[$(unkdump)]) row=[${r:0:300}] $(grep -E '^DIE' <<<"$CASE_OUT" | cut -c1-200)"
  fi
}
# G1-P1 — the PRODUCTION reproduction: an UNLABELLED ext4 (W_LABEL= explicit) whose device is the recorded
# plaintext reaches rehearsal_ok, carrying label=none as evidence next to the record it was bound to.
run_wipe 'wipe_plaintext; echo WIPE_RETURNED' DRY_RUN=1 W_LABEL=
g1_rehearsed "G1-P1 an unlabelled plaintext (the web-1 shape) bound to its recorded PLAINTEXT_DEV rehearses: label=none plaintext_dev=<record>" \
  "label=none plaintext_dev=$TGT_BLK"
# G1-P2 (must-PASS, non-canonical) — the record is an ALIAS of the target: the bind compares resolved paths.
run_wipe 'wipe_plaintext; echo WIPE_RETURNED' DRY_RUN=1 "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_DEV=$G1_ALIAS"
g1_rehearsed "G1-P2 a record that is a non-canonical alias of the target ($G1_ALIAS) still binds (readlink -f on both sides)" \
  "plaintext_dev=$G1_ALIAS"
# G1-H2 (must-PASS) — the label is evidence only: a DIFFERENT label with a matching record rehearses.
run_wipe 'wipe_plaintext; echo WIPE_RETURNED' DRY_RUN=1 W_LABEL=other
g1_rehearsed "G1-H2 a first-wipe target labelled 'other' with a matching record rehearses — the label is evidence, never a gate" \
  "label=other plaintext_dev=$TGT_BLK"
g1_refused "G1-R1 no PLAINTEXT_DEV recorded" none none "SEED_STATE=CANARY_OK=1:$UUID_LIVE"
g1_refused "G1-R2 the record names ANOTHER device (kernel-name drift onto the LUKS backing; the serial still passes)" \
  "$LUKS_BLK" "$LUKS_REAL_T" "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_DEV=$LUKS_BLK"
g1_refused "G1-R3 the LAST record wins (target first, then the LUKS backing)" \
  "$LUKS_BLK" "$LUKS_REAL_T" "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_DEV=$TGT_BLK;PLAINTEXT_DEV=$LUKS_BLK"
g1_refused "G1-R4 an option-shaped record (-o)" -o none "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_DEV=-o"
# G1-R5 — the validator is load-bearing at W6, not only the compare: a record that RESOLVES to the target
# but is not a canonical-charset /dev path (`//`) is refused, never bound.
G1_SLASH="${TGT_REAL/#\/dev\//\/dev\/\/}"
g1_refused "G1-R5 a record with '//' that resolves to the target is refused by the validator" \
  "$G1_SLASH" none "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_DEV=$G1_SLASH"
# G1-R6 — the `..` clause on its own: a record that climbs out and back (`/dev/../dev/<kname>`) RESOLVES
# to the target, so only the validator refuses it.
G1_DOTDOT="${TGT_REAL/#\/dev\//\/dev\/..\/dev\/}"
g1_refused "G1-R6 a record with '..' that resolves to the target is refused by the validator" \
  "$G1_DOTDOT" none "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_DEV=$G1_DOTDOT"
# G1-R7 — the charset clause on its own: `recorded_real=` is computed only for a VALID record, so a `;`
# record reads recorded_real=none only while the charset clause stands.
# (SEED_STATE splits on `;`, so the record is appended by PRE_INV; the last line wins.)
g1_refused "G1-R7 a record carrying ';' is refused, and never resolved (recorded_real=none)" \
  "$TGT_REAL;x" none "PRE_INV=persist_state PLAINTEXT_DEV '$TGT_REAL;x'"
# G1-H3 — the resume arm is NOT bound (the marker and the serial bind it): a WRONG record re-zeroes.
run_wipe 'wipe_plaintext; echo WIPE_RETURNED' "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_WIPE_BEGUN=$PIN:1759000000;PLAINTEXT_DEV=$LUKS_BLK" W_TYPE=
[ -n "$(wrow wiped re_zero)" ] && ran && [ "$(zero_calls)" -eq 1 ] && hasF "blkdiscard -z -v $TGT_REAL" && nounk \
  && ok "G1-H3 re_zero with a WRONG record still resumes (the binding is first_wipe-only)" \
  || no "G1-H3 re_zero was stranded by the record binding (rc=$CASE_RC) $(grep -E 'result=refused|^DIE' <<<"$CASE_OUT" | tr '\n' '|' | cut -c1-240)"
# G1-W (writer -> reader) — the ONE writer of the record W6 binds to is the cutover's rollback-rehearsal
# step: it persists `findmnt -no SOURCE $MOUNT` (the plaintext's mount source, pre-repoint). Run the
# REAL block (extracted, not copied) in the harness world with no seeded record: the LAST state line must
# be that mount source, and read_state (W6's reader) must return it.
REH_TEXT="$(awk '/^step "rollback rehearsal/{f=1} f{print} f && /^fi$/{exit}' "$CUTOVER")"
if [ -z "$REH_TEXT" ] || ! grep -qF 'persist_state PLAINTEXT_DEV' <<<"$REH_TEXT"; then
  no "G1-W INSTRUMENT: the rollback-rehearsal block (the PLAINTEXT_DEV writer) could not be extracted"
else
  run_case "$CUTOVER" 'DRY_RUN=0; eval "$REH_TEXT"; echo "READ=$(read_state PLAINTEXT_DEV)"' 'persist_state read_state' \
    REH_TEXT="$REH_TEXT" PLAINTEXT_DEV_UNSEEDED=1 FINDMNT_MOUNT_SRC=/dev/sdzX MKDIR_RC=0
  if ran && [ "$(tail -n1 "$STATE/state" 2>/dev/null)" = "PLAINTEXT_DEV=/dev/sdzX" ] && outF "READ=/dev/sdzX" \
    && [ "$(grep -c '^PLAINTEXT_DEV=' "$STATE/state" 2>/dev/null)" -eq 1 ]; then
    ok "G1-W the rollback-rehearsal step persists the plaintext mount source as the LAST PLAINTEXT_DEV line, and read_state returns it"
  else
    no "G1-W the writer did not record the mount source (rc=$CASE_RC last=[$(tail -n1 "$STATE/state" 2>/dev/null)]) ${CASE_OUT:0:200}"
  fi
fi
refusal "W6 (Guard 1 #9) re_zero arm with the target made the mapper's backing device" wipe_target_is_mapper_backing \
  "SEED_STATE=CANARY_OK=1:$UUID_LIVE;PLAINTEXT_WIPE_BEGUN=$PIN:1" W_TYPE= "W_BACKING=$TGT_BLK" "WORKSPACES_LUKS_DEV=$TGT_BLK"
refusal "W6b (Guard 1 #8) a .mount unit in a target device unit's reverse dependencies" wipe_target_has_dependents W_REVDEP=mnt-data.mount
refusal "W6b a .swap dependent" wipe_target_has_dependents W_REVDEP=dev-sdc.swap
refusal "W6b a .service dependent" wipe_target_has_dependents "W_REVDEP=systemd-fsck@dev-sdc.service"
refusal "W6b (Guard 1 #8) an unloaded device unit" wipe_target_has_dependents "W_UNLOADED_UNIT=dev-$TGT_KNAME.device"
refusal "W6b a matched device unit that is not active (a ghost unit reads loaded — measured)" wipe_target_has_dependents "W_INACTIVE_UNIT=dev-$TGT_KNAME.device"
refusal "W6b no device unit maps to the target (cannot prove no dependents)" wipe_target_has_dependents W_TARGET_UNITS=
refusal "W6b mnt-data.mount binds one of the target's device units" wipe_target_has_dependents "W_MNT_BINDS=BindsTo=dev-$TGT_KNAME.device
Requires=
What=/dev/disk/by-id/scsi-0HC_Volume_*"
# W10 (struct R-TOCTOU) — the identity is re-asserted at the act: the kernel name W6 measured must still
# be what the by-id link resolves to, and must still carry the pin's serial.
refusal "W10 the by-id link resolves to ANOTHER device at the act (hot-remove + reattach after W6)" wipe_target_changed \
  W_DEV_VIA_RELLINK=1 W_RETARGET_LINK=1
refusal "W10 the target reports another volume's serial at the act" wipe_target_changed W_SERIAL_AFTER_W6=0HC_Volume_106443278
nhas '^blkdiscard (-z|-v|/)' && ! state_has PLAINTEXT_WIPE_BEGUN \
  && ok "W10 a changed target refuses BEFORE BEGUN is persisted (a re-dispatch re-measures from first_wipe)" \
  || no "W10 the changed-target refusal came after BEGUN or the zero"
# W6b again after the zero (struct R-W6B): a dependent that appeared since the first W6b refuses the
# success row, so the API detach never runs.
run_wipe 'wipe_plaintext' W_REVDEP_AFTER_ZERO=mnt-data.mount
if refused_ok wipe_target_has_dependents && [ "$(zero_calls)" -eq 1 ] && [ "$(nrows wiped)" -eq 0 ] && ! state_has PLAINTEXT_WIPED; then
  ok "W12b W6b re-runs after the zero: a dependent that appeared since refuses the success row (no API detach), WIPED not persisted"
else
  no "W12b a post-zero dependent did not block the success row (rc=$CASE_RC wiped=$(nrows wiped)) ${CASE_OUT:0:200}"
fi
# W9 provenance (data F5) — a first wipe refuses a plaintext written after the 2026-07-23 freeze.
refusal "W9 the plaintext's Last write time is after the cutover froze it" wipe_plaintext_written_after_cutover "W_LAST_WRITE=Fri Jul 24 08:00:00 2026"
refusal "W9 the plaintext's Last write time is unparseable" wipe_plaintext_written_after_cutover "W_LAST_WRITE=never"
run_wipe 'wipe_plaintext' DRY_RUN=1 "W_LAST_WRITE=Thu Jul 23 09:44:59 2026"
[ -n "$(wrow rehearsal_ok first_wipe)" ] && ok "W9 H1 a Last write time one second before the freeze constant passes" \
  || no "W9 H1 a pre-freeze Last write time was refused (rc=$CASE_RC) ${CASE_OUT:0:200}"
fz_iso="$(sed -n 's/^WIPE_PLAINTEXT_FROZEN_AT="\(.*\)"$/\1/p' "$CUTOVER")"
fz_lit="$(sed -n "s/^_wipe_frozen_at_epoch() { printf '%s' \([0-9]*\); }$/\1/p" "$CUTOVER")"
[ -n "$fz_iso" ] && [ -n "$fz_lit" ] && [ "$(date -u -d "$fz_iso" +%s)" = "$fz_lit" ] && [ "$fz_iso" = 2026-07-23T09:45:00Z ] \
  && ok "W9 the frozen-at literal ($fz_lit) is exactly WIPE_PLAINTEXT_FROZEN_AT ($fz_iso), the 2026-07-23 cutover's host-step end plus skew" \
  || no "W9 the frozen-at constant and its epoch literal disagree (iso=[$fz_iso] lit=[$fz_lit])"
# W9 completeness EVIDENCE (data F2) — never a refusal.
run_wipe 'wipe_plaintext' DRY_RUN=1 W_LIVE_WS=ws-a
p9_row="$(wrow rehearsal_ok first_wipe)"
if [ -n "$p9_row" ] && [[ "$p9_row" == *" plaintext_only=1"* ]] \
  && grep -qE '^SOLEUR_WORKSPACES_LUKS_WIPE_EVIDENCE .* field=plaintext_only_name detail=ws-b$' <<<"$CASE_OUT" \
  && ! grep -qE 'field=plaintext_only_name detail=ws-a$' <<<"$CASE_OUT" && nounk; then
  ok "W9 a workspace on the unmounted plaintext but not on the live mount is EVIDENCE: plaintext_only=1 on the row, its name on an evidence row, no refusal"
else
  no "W9 plaintext-only evidence wrong (rc=$CASE_RC row=[${p9_row:0:160}]) $(grep -F EVIDENCE <<<"$CASE_OUT" | tr '\n' '|' | cut -c1-200)"
fi
run_wipe 'wipe_plaintext' DRY_RUN=1 W_DEBUGFS_FAIL=1
[[ "$(wrow rehearsal_ok first_wipe)" == *" plaintext_only=unknown"* ]] \
  && ok "W9 a debugfs that cannot list /workspaces (it exits 0 regardless) reads plaintext_only=unknown, never 0" \
  || no "W9 a failed listing did not read unknown: $(wrow rehearsal_ok first_wipe | cut -c1-200)"
# W5 (obs P3-5) — a failed header download carries aws_rc and a CLASS, never aws's stderr text.
W5_SECRET='AKIASYNTHLEAKCANARY'
run_wipe 'wipe_plaintext' W_HDR_ABSENT=1 W_HDR_RC=254 "W_HDR_ERR=An error occurred (AccessDenied) when calling the GetObject operation: Access Denied for $W5_SECRET"
w5_row="$(awk -v p="^$WROW result=refused " '$0 ~ p { print; exit }' <<<"$CASE_OUT")"
if refused_ok wipe_header_backup_absent && [[ "$w5_row" == *" aws_rc=254"* && "$w5_row" == *" class=access_denied"* ]] \
  && ! grep -qF "$W5_SECRET" <<<"$CASE_OUT" && ! grep -qF "$W5_SECRET" "$MARKER_LOG"; then
  ok "W5 a 403 on the header GET is classed access_denied with aws_rc, and aws's stderr (which can carry a key id) reaches no log"
else
  no "W5 403 classification wrong or stderr leaked (row=[${w5_row:0:200}])"
fi
run_wipe 'wipe_plaintext' W_HDR_ABSENT=1
[[ "$(awk -v p="^$WROW result=refused " '$0 ~ p { print; exit }' <<<"$CASE_OUT")" == *" class=not_found"* ]] \
  && ok "W5 a missing object is classed not_found (the one class whose remedy is re-escrow)" || no "W5 NoSuchKey not classed not_found"
run_wipe 'wipe_plaintext' W_HDR_ABSENT=1 W_HDR_RC=255 "W_HDR_ERR=Could not connect to the endpoint URL: https://r2.invalid/"
[[ "$(awk -v p="^$WROW result=refused " '$0 ~ p { print; exit }' <<<"$CASE_OUT")" == *" class=network"* ]] \
  && ok "W5 a connection failure is classed network" || no "W5 a connection failure not classed network"
refusal "W7 the dead-man timer is active" wipe_deadman_armed W_DM_TIMER_ACTIVE=active
refusal "W7 a dead-man fire is activating" wipe_deadman_armed W_DM_SVC_ACTIVE=activating
refusal "W7 a dead-man start job is queued" wipe_deadman_armed W_DM_SVC_JOB=4242
# W8 (impact F1 / quality F1) — the cap is proven IN FORCE by reading the scope's own io.max; systemd-run's
# rc proves nothing (it starts an uncapped scope when io.max cannot apply — measured, systemd 261).
refusal "W8 io.max absent in the scope (io controller not enabled: systemd starts the scope uncapped, rc 0)" wipe_io_cap_unavailable W_IOMAX_ABSENT=1
refusal "W8 io.max carries the cap for ANOTHER device (wrong MAJ:MIN)" wipe_io_cap_unavailable "W_IOMAX_LINE=9:99 rbps=150000000 wbps=150000000 riops=max wiops=max"
refusal "W8 io.max carries the read cap but no write cap" wipe_io_cap_unavailable "W_IOMAX_LINE=8:32 rbps=150000000 wbps=max riops=max wiops=max"
refusal "W8 io.max carries the write cap but no read cap" wipe_io_cap_unavailable "W_IOMAX_LINE=8:32 rbps=max wbps=150000000 riops=max wiops=max"
refusal "W8 io.max carries a different rate (15M, not 150M)" wipe_io_cap_unavailable "W_IOMAX_LINE=8:32 rbps=15728640 wbps=15728640 riops=max wiops=max"
refusal "W8 io.max carries 150 MiB (157286400), the base-1024 reading systemd never writes" wipe_io_cap_unavailable "W_IOMAX_LINE=8:32 rbps=157286400 wbps=157286400 riops=max wiops=max"
refusal "W8 the target's MAJ:MIN is unreadable from sysfs" wipe_io_cap_unavailable PRE_INV='rm -f "$W_CASE_DIR/sysfs/$TGT_KNAME/dev"'
run_wipe 'wipe_plaintext' W_IOMAX_ABSENT=1
w8_row="$(awk -v p="^$WROW result=refused " '$0 ~ p { print; exit }' <<<"$CASE_OUT")"
[[ "$w8_row" == *" io_max=absent"* && "$w8_row" == *" gate_rc=97"* ]] && ! state_has PLAINTEXT_WIPE_BEGUN && nhas '^systemd-run .*blkdiscard' \
  && ok "W8 the refusal row carries io_max=absent gate_rc=97, and nothing (not even BEGUN) was written" \
  || no "W8 refusal row lacks the measured io.max (row=[${w8_row:0:200}])"
# The zero's OWN scope is gated too: the cap proven at W8 but absent when the zero's scope starts (the
# environment changed) refuses wipe_io_cap_unavailable with nothing zeroed — never wipe_blkdiscard_failed.
refusal "W10 the zero's own scope lacks io.max (cap gone after W8): the gate stops blkdiscard" wipe_io_cap_unavailable W_IOMAX_ABSENT_AT_ZERO=1
state_has PLAINTEXT_WIPE_BEGUN && ! grep -q '^blkdiscard -z' "$CALLS" \
  && ok "W10 the gated zero never started blkdiscard; BEGUN is persisted, so the next dispatch resumes on re_zero" \
  || no "W10 the zero-scope gate refusal ran blkdiscard or lost BEGUN"
refusal "W9 (Guard 3 #6) first-wipe positive control sees no ext4 magic" wipe_positive_control_failed W_MAGIC=0

# W10 — the zero itself fails: refused, BEGUN persisted (the next dispatch takes re_zero), no wiped row.
run_wipe 'wipe_plaintext' W_BLKDISCARD_RC=1
w10_row="$(awk -v p="^$WROW result=refused " '$0 ~ p { print; exit }' <<<"$CASE_OUT")"
if refused_ok wipe_blkdiscard_failed && state_has PLAINTEXT_WIPE_BEGUN && ! state_has PLAINTEXT_WIPED && [ "$(nrows wiped)" -eq 0 ] \
  && [[ "$w10_row" == *" rc=1"* ]]; then
  ok "W10 a failed blkdiscard refuses wipe_blkdiscard_failed carrying rc=1, with BEGUN persisted and no wiped row"
else
  no "W10 failed blkdiscard mis-handled (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# W10/W12 — the markers are the precondition of Guard 5 (the permanent ROLLBACK lockout) and of the
# re_zero resume, so an unwritable state file refuses BEFORE the zero (BEGUN) and BEFORE the success row
# (WIPED). Each is proven by a failing write AND by a write that "succeeds" but does not land (the
# read-back decides, not persist_state's rc).
refusal "W10 (Guard 5) PLAINTEXT_WIPE_BEGUN cannot be written (root disk full / read-only)" wipe_marker_write_failed \
  PRE_INV='persist_state() { return 1; }'
refusal "W10 (Guard 5) PLAINTEXT_WIPE_BEGUN 'written' but not readable back" wipe_marker_write_failed \
  PRE_INV='persist_state() { return 0; }'
run_wipe 'eval "_orig_persist() $(declare -f persist_state | tail -n +2)"; persist_state() { [ "$1" = PLAINTEXT_WIPED ] && return 1; _orig_persist "$@"; }; wipe_plaintext'
if refused_ok wipe_marker_write_failed && [ "$(zero_calls)" -eq 1 ] && state_has PLAINTEXT_WIPE_BEGUN && ! state_has PLAINTEXT_WIPED \
  && [ "$(nrows wiped)" -eq 0 ]; then
  ok "W12 (Guard 5) PLAINTEXT_WIPED cannot be persisted after a verified zero → refused, NO wiped row (so no API delete), BEGUN still locks ROLLBACK out"
else
  no "W12 an unpersisted WIPED marker still produced a success row (rc=$CASE_RC wiped=$(nrows wiped)) ${CASE_OUT:0:240}"
fi
# W11 — cmp decides; dd's rc never classifies (Guard 3 #3/#4/#5).
run_wipe 'wipe_plaintext' W_CMP_RC=1 W_DD_RC=141
w11_row="$(awk -v p="^$WROW result=refused " '$0 ~ p { print; exit }' <<<"$CASE_OUT")"
if refused_ok wipe_readback_failed && [[ "$w11_row" == *" cmp_rc=1"* ]] && [[ "$w11_row" == *" dd_rc=141"* ]] \
  && ! state_has PLAINTEXT_WIPED && [ "$(nrows wiped)" -eq 0 ] \
  && grep -qE '^SOLEUR_WORKSPACES_LUKS_WIPE_EVIDENCE .* field=cmp detail=- /dev/zero differ: byte 1048577, line 1' <<<"$CASE_OUT"; then
  ok "W11 (Guard 3 #3) cmp 1 + dd 141 (EPIPE): readback_failed carrying cmp_rc=1 dd_rc=141, the scrubbed cmp line on the evidence row, no wiped marker"
else
  no "W11 cmp1/dd141 mis-classified (rc=$CASE_RC) row=[${w11_row:0:200}] ${CASE_OUT:0:200}"
fi
run_wipe 'wipe_plaintext' W_CMP_RC=0 W_DD_RC=1
refused_ok wipe_readback_failed && ! state_has PLAINTEXT_WIPED \
  && ok "W11 (Guard 3 #4) cmp 0 but dd 1 is still a refusal (a short read is not proof)" \
  || no "W11 cmp0/dd1 accepted (rc=$CASE_RC) ${CASE_OUT:0:200}"
run_wipe 'wipe_plaintext' W_CMP_RC=2
refused_ok wipe_readback_failed && ok "W11 cmp rc 2 (trouble) is a refusal" || no "W11 cmp rc 2 accepted (rc=$CASE_RC)"
# W12 runs after the zero by construction, so it is asserted with refused_ok directly (refusal() also
# asserts "no blkdiscard", which holds only for the pre-W10 slugs).
run_wipe 'wipe_plaintext' W_SIG_SURVIVES=1 W_CMP_RC=0
refused_ok wipe_signature_survived && ! state_has PLAINTEXT_WIPED \
  && ok "W12 a surviving signature refuses and never persists PLAINTEXT_WIPED" \
  || no "W12 surviving signature accepted (rc=$CASE_RC) ${CASE_OUT:0:200}"

# obs P2-1 — after an SSH drop the run's stdout is a DEAD pipe, and in the main body SIGPIPE keeps its
# default disposition: the first echo kills the process. The refusal must already be off-host by then —
# the Sentry slug and the luks-monitor row are written BEFORE the echo. Driven through a pipe whose only
# reader has already exited (race-free: the reader is waited for before the first write).
run_wipe 'exec 1> >(true); wait $!; exec 2>&1; _wipe_refuse wipe_blkdiscard_failed "dead-pipe probe" "rc=1"; exit 0'
if [ "$CASE_RC" -ne 0 ] && has '^EMIT_DRIFT wipe_blkdiscard_failed$' && markerF "result=refused arm=none volume_id=105149570 reason=wipe_blkdiscard_failed"; then
  ok "OBS1 a refusal into a DEAD stdout (the process dies on SIGPIPE) still reached Sentry AND the luks-monitor tag first"
else
  no "OBS1 a dead-pipe refusal lost its off-host signal (rc=$CASE_RC drift=$(grep -c '^EMIT_DRIFT wipe_blkdiscard_failed' "$CALLS") marker=$(grep -c reason=wipe_blkdiscard_failed "$MARKER_LOG"))"
fi
run_wipe 'emit_wipe rehearsal_ok first_wipe "Bad-Key=1"; echo EMITTED'
died && ! outF EMITTED && ok "F7 emit_wipe dies on a malformed row key instead of silently dropping the field" \
  || no "F7 emit_wipe accepted or silently dropped a malformed key (rc=$CASE_RC)"

# ============================================================================
# The mode block, dispatched through the REAL main-body prefix (Guard 1 #12, Guard 2 #2)
# ============================================================================
MAIN_PREFIX="$(awk '/^trap cleanup EXIT$/{f=1} /^step "L3 gates/{exit} f{print}' "$CUTOVER")"
export MAIN_PREFIX
if [ -z "$MAIN_PREFIX" ] || ! grep -qE '^assert_mode_exclusive$' <<<"$MAIN_PREFIX" || ! bash -n <<<"$MAIN_PREFIX" 2>/dev/null; then
  no "M0 the main-body prefix (trap .. L3) could not be extracted — treat M1-M4 as UN-RUN"
fi
run_wipe 'eval "$MAIN_PREFIX"; echo FELL_THROUGH_TO_L3'
if ran && [ -n "$(wrow wiped first_wipe)" ] && ! outF FELL_THROUGH_TO_L3 && ! markerF 'result=cutover_aborted' && nounk; then
  ok "M1 (Guard 1 #12) CONFIRM_WIPE=1 dispatched through the real main body reaches wipe_plaintext and exits green via RUN_COMPLETE (never the L3 cutover)"
else
  no "M1 CONFIRM_WIPE=1 did not dispatch to the wipe (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
run_wipe 'eval "$MAIN_PREFIX"; echo FELL_THROUGH_TO_L3' DRY_RUN=1
if ran && [ -n "$(wrow rehearsal_ok first_wipe)" ] && [ "$(zero_calls)" -eq 0 ] && ! outF FELL_THROUGH_TO_L3; then
  ok "M2 (Guard 2 #2) a DRY_RUN=1 dispatch through the real mode block rehearses — the block never forces DRY_RUN=0"
else
  no "M2 the mode block zeroed or fell through on DRY_RUN=1 (rc=$CASE_RC zero=$(zero_calls))"
fi
run_wipe 'eval "$MAIN_PREFIX"' W_CMP_RC=1
if died && markerF "$DM result=cutover_aborted outcome=wipe_aborted mode=wipe begun=1" && nhas '^umount ' && nhas '^docker (start|stop) ' \
  && nhas '^mount ' && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ] && has '^EMIT_DRIFT wipe_aborted$'; then
  ok "M3 (Guard 5 #3) an aborted wipe (die at W11) records outcome=wipe_aborted mode=wipe begun=1, PAGES wipe_aborted (obs P2-2), and never rolls back or starts the app"
else
  no "M3 an aborted wipe mis-recorded or touched the live mount (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|') calls=[$(grep -E '^(umount|mount|docker) ' "$CALLS" | tr '\n' '|')]"
fi
run_wipe 'eval "$MAIN_PREFIX"' DRY_RUN=1 W_MOUNT_SRC=/dev/sdz9
markerF "$DM result=cutover_aborted outcome=dry_run mode=wipe" && nhas '^EMIT_DRIFT wipe_aborted$' \
  && has '^EMIT_DRIFT_LEVEL wipe_live_mount_not_mapper warning$' \
  && ok "M4 a refused rehearsal reads outcome=dry_run mode=wipe, pages its slug at level warning (obs P3-7) and never pages wipe_aborted" \
  || no "M4 a refused rehearsal mis-recorded: $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
# M3b — a REAL wipe aborted BEFORE the zero pages wipe_aborted WITHOUT begun=1 (the volume is untouched).
run_wipe 'eval "$MAIN_PREFIX"' W_BUCKET=
markerF "$DM result=cutover_aborted outcome=wipe_aborted mode=wipe" && ! markerF 'begun=1' && has '^EMIT_DRIFT wipe_aborted$' \
  && has '^EMIT_DRIFT_LEVEL header_bucket_unreadable fatal$' \
  && ok "M3b a real wipe aborted before the zero pages wipe_aborted (fatal) with no begun=1" \
  || no "M3b pre-zero abort mis-recorded: $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
run_wipe 'eval "$MAIN_PREFIX"' ROLLBACK=1
if died && has '^EMIT_DRIFT clean_stray_mode_conflict$' && [ "$(zero_calls)" -eq 0 ]; then
  ok "M5 CONFIRM_WIPE=1 with ROLLBACK=1 is refused by the counted mode exclusion before either block"
else
  no "M5 wipe+rollback not refused (rc=$CASE_RC) ${CASE_OUT:0:200}"
fi

# --- static rows over the mode block and the function ----------------------------------------------
WIPE_BLOCK="$(awk '/^if \[ "\$CONFIRM_WIPE" = "1" \]; then$/{f=1} f{print} f && /^fi$/{exit}' "$CUTOVER")"
WIPE_FN="$(awk '/^wipe_plaintext\(\) \{$/{f=1} f{print} f && /^\}$/{exit}' "$CUTOVER")"
if [ -n "$WIPE_BLOCK" ] && grep -qE '^[[:space:]]*wipe_plaintext$' <<<"$WIPE_BLOCK" \
  && ! grep -qE '(^|[;&|[:space:]])(DRY_RUN|CANARY_OK|FREEZE_HELD|FLIP_DONE|DEADMAN_ARMED)=' <<<"$(sed -E 's/"[^"]*"//g; s/^[[:space:]]*#.*$//' <<<"$WIPE_BLOCK
$WIPE_FN")"; then
  ok "S1 (Guard 2 #2) neither the mode block nor wipe_plaintext assigns DRY_RUN or a cleanup() rollback global (CANARY_OK/FREEZE_HELD/FLIP_DONE/DEADMAN_ARMED)"
else
  no "S1 the mode block/function assigns DRY_RUN or a rollback global, or could not be extracted"
fi
ame_ln="$(grep -n '^assert_mode_exclusive$' "$CUTOVER" | head -1 | cut -d: -f1)"
wb_ln="$(grep -n '^if \[ "\$CONFIRM_WIPE" = "1" \]; then$' "$CUTOVER" | head -1 | cut -d: -f1)"
cs_ln="$(grep -n '^if \[ "\$CLEAN_STRAY" = "1" \]; then$' "$CUTOVER" | head -1 | cut -d: -f1)"
l3_ln="$(grep -n '^step "L3 gates' "$CUTOVER" | head -1 | cut -d: -f1)"
[ -n "$ame_ln" ] && [ -n "$wb_ln" ] && [ -n "$cs_ln" ] && [ -n "$l3_ln" ] && [ "$ame_ln" -lt "$wb_ln" ] && [ "$cs_ln" -lt "$wb_ln" ] && [ "$wb_ln" -lt "$l3_ln" ] \
  && ok "S2 the wipe block sits after assert_mode_exclusive and CLEAN_STRAY and before the L3 gates" \
  || no "S2 mode-block placement wrong (exclusive=$ame_ln clean_stray=$cs_ln wipe=$wb_ln l3=$l3_ln)"
# Guard 1 #10/#11 — exactly one zeroing call site, and never -f/--force.
BODY_NC="$(grep -vE '^[[:space:]]*#' "$CUTOVER")"
# S3 (struct R-CENSUS) counts EVERY blkdiscard invocation, in any flag spelling (`--zeroout`, `-v -z`, a
# bare discard): comments and quoted text are stripped, then every remaining `blkdiscard` word is an
# invocation unless it is one of the three non-invocations (the W0 tool list, `--version`, `pgrep -x`).
zero_sites() {
  sed -E 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g' <<<"$1" \
    | grep -oE '(^|[^A-Za-z0-9_-])blkdiscard([[:space:]]+[^[:space:];|&)]+)?' \
    | grep -vE 'blkdiscard[[:space:]]+(--version|systemd-run)$' | grep -vcE '^-x blkdiscard' || true
}
n_zero_sites="$(zero_sites "$(grep -vE 'pgrep -x blkdiscard' <<<"$BODY_NC")")"
n_ctl="$(zero_sites "$(grep -vE 'pgrep -x blkdiscard' <<<"$BODY_NC")
  blkdiscard --zeroout \"\$x\"")"
[ "$n_zero_sites" -eq 1 ] && [ "$n_ctl" -eq 2 ] && ok "S3 (Guard 1 #10) exactly one blkdiscard invocation in the script, any flag spelling (control: a planted --zeroout counts 2)" \
  || no "S3 blkdiscard invocation sites = $n_zero_sites (want exactly 1; control=$n_ctl, want 2)"
# H6 (T9) — the zero's stdin is /dev/null on the line itself (blkdiscard prompts on a TTY; the stub's
# TTY clause cannot fire under a non-TTY harness, so the literal is pinned).
grep -qE 'blkdiscard -z -v "\$real" </dev/null$' <<<"$WIPE_FN" \
  && ok "H6 the zero's line ends with </dev/null (no confirmation prompt can ever block or answer it)" \
  || no "H6 the zero is not fed </dev/null on its own line"
if grep -qE 'blkdiscard([^#]*[[:space:]])(-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)' <<<"$BODY_NC"; then
  no "S4 (Guard 1 #11) blkdiscard is invoked with -f/--force somewhere — O_EXCL would be disabled"
else
  ok "S4 (Guard 1 #11) no blkdiscard invocation carries -f/--force (O_EXCL stays on)"
fi
# The seams are not settable from the environment (an .env line could otherwise repoint the zero, or the
# blkid a root dead-man fire execs). A one-line seam ends on its own line; a multi-line one at `^}$`. The
# only variables a seam may read are its argument and its declared local `b`.
SEAM_RE='^(_wipe_dev_path|_wipe_sysfs_block|_wipe_cgroup_root|_wipe_frozen_at_epoch|_plaintext_blkid_bin|_plaintext_dev_type)\(\) '
seam_env="$(awk -v re="$SEAM_RE" '$0 ~ re {f=1} f{print} f && (/^\}$/ || /\(\) \{.*\}$/){f=0}' "$CUTOVER" | grep -vE '^[[:space:]]*#' | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' | grep -vE '^\$\{?b$' || true)"
seam_n="$(grep -cE "$SEAM_RE" "$CUTOVER" || true)"
[ "$seam_n" -eq 6 ] && [ -z "$seam_env" ] \
  && ok "S5 the device, sysfs, cgroup, frozen-at, blkid-path and plaintext-type seams read no variable but their own argument (not env-settable)" \
  || no "S5 a seam reads an environment variable or is missing (defs=$seam_n want 6, vars=[$seam_env])"
# F6 — the REAL probe functions (never the harness seams): only the blkid PATH seam is replaced, by a
# stub that records its argv and exits with a chosen rc. The rc is kept (rc 0 → the TYPE, or `none` when
# empty; rc 2 → `none`; anything else → `blkid_error_<rc>`), the argv is exactly `-p -s TYPE -o value
# <dev>`, a missing blkid reads `blkid_absent`, and a node that is not a block device reads `absent`
# (both through _plaintext_dev_type and through the composed _plaintext_record_status).
F6_BLKID="$WIPE_SCRATCH/f6-blkid"; F6_ARGV="$WIPE_SCRATCH/f6-argv"
cat > "$F6_BLKID" <<'F6_STUB'
#!/bin/sh
printf '%s\n' "$*" > "$F6_ARGV"
[ -z "$F6_OUT" ] || printf '%s\n' "$F6_OUT"
exit "$F6_RC"
F6_STUB
chmod +x "$F6_BLKID"
f6() {  # <fn> <arg> <stub stdout> <stub rc> [bin override: '' = the stub, - = none]
  : > "$F6_ARGV"
  env -u PLAINTEXT_DEV_FSTYPE F6_ARGV="$F6_ARGV" F6_OUT="$3" F6_RC="$4" F6_BIN="${5:-$F6_BLKID}" F6_FN="$1" F6_ARG="$2" \
    bash -c 'source "$1" >/dev/null 2>&1
      _plaintext_blkid_bin() { [ "$F6_BIN" = - ] || printf "%s" "$F6_BIN"; }
      "$F6_FN" "$F6_ARG"' _ "$CUTOVER" 2>/dev/null
}
f6_bad=""
for f6c in "ext4|0|ext4" "|2|none" "|0|none" "|4|blkid_error_4" "crypto_LUKS|0|crypto_LUKS" "|8|blkid_error_8"; do
  IFS='|' read -r f6_out f6_rc f6_want <<<"$f6c"
  f6_got="$(f6 _plaintext_blkid_type /dev/sdz9 "$f6_out" "$f6_rc")"
  [ "$f6_got" = "$f6_want" ] && [ "$(cat "$F6_ARGV")" = "-p -s TYPE -o value /dev/sdz9" ] \
    || f6_bad="$f6_bad [out=${f6_out:-empty} rc=$f6_rc got=$f6_got want=$f6_want argv=$(cat "$F6_ARGV")]"
done
f6_got="$(f6 _plaintext_blkid_type /dev/sdz9 ext4 0 -)"; [ "$f6_got" = blkid_absent ] || f6_bad="$f6_bad [no-bin got=$f6_got]"
f6_file="$WIPE_SCRATCH/f6-regular"; : > "$f6_file"
for f6a in /dev/null "$f6_file" /dev/sdz_no_such_node; do
  f6_got="$(f6 _plaintext_dev_type "$f6a" ext4 0)"; [ "$f6_got" = absent ] && [ ! -s "$F6_ARGV" ] || f6_bad="$f6_bad [dev_type $f6a got=$f6_got]"
done
f6_got="$(f6 _plaintext_record_status /dev/null ext4 0)"; [ "$f6_got" = absent ] || f6_bad="$f6_bad [status /dev/null got=$f6_got]"
f6_got="$(f6 _plaintext_record_status '/dev/sdz9;x' ext4 0)"; [ "$f6_got" = invalid ] || f6_bad="$f6_bad [status invalid got=$f6_got]"
[ -z "$f6_bad" ] \
  && ok "F6 the real blkid probe keeps the rc (TYPE / none / blkid_error_<rc> / blkid_absent) with argv '-p -s TYPE -o value <dev>', and a non-block node reads absent without running blkid" \
  || no "F6 the real probe mapping is wrong:$f6_bad"
# F7 — the real _plaintext_blkid_bin in a clean shell with a FAKE blkid first on PATH: it must answer a
# fixed root-owned path, never the PATH hit (the fire bakes this path into an unattended root command).
F7_DIR="$WIPE_SCRATCH/f7-path"; mkdir -p "$F7_DIR"; printf '#!/bin/sh\nexit 0\n' > "$F7_DIR/blkid"; chmod +x "$F7_DIR/blkid"
f7_got="$(env PATH="$F7_DIR:$PATH" bash -c 'source "$1" >/dev/null 2>&1; blkid() { :; }; _plaintext_blkid_bin' _ "$CUTOVER" 2>/dev/null)"
[[ "$f7_got" =~ ^(/usr/sbin|/sbin|/usr/bin|/bin)/blkid$ ]] \
  && ok "F7 _plaintext_blkid_bin answers a fixed root-owned path ($f7_got), not a PATH-first fake or a shell function" \
  || no "F7 _plaintext_blkid_bin answered [$f7_got] (want one of /usr/sbin|/sbin|/usr/bin|/bin + /blkid; this host has: $(ls /usr/sbin/blkid /sbin/blkid /usr/bin/blkid /bin/blkid 2>/dev/null | tr '\n' ' '))"
# F11 — the main body records the plaintext mount source BEFORE it arms the dead-man (the arm refuses
# without a record, and the fire bakes it).
f11_rec="$(grep -n 'persist_state PLAINTEXT_DEV' "$CUTOVER" | head -1 | cut -d: -f1)"; f11_arm="$(grep -n '^arm_dead_man$' "$CUTOVER" | head -1 | cut -d: -f1)"
[ -n "$f11_rec" ] && [ -n "$f11_arm" ] && [ "$f11_rec" -lt "$f11_arm" ] \
  && ok "F11 the main body persists PLAINTEXT_DEV (line $f11_rec) before it arms the dead-man (line $f11_arm)" \
  || no "F11 PLAINTEXT_DEV is not persisted before the main-body arm (record line=${f11_rec:-none} arm line=${f11_arm:-none})"
# arm_dead_man reachability — the plan asked whether any dispatch can still reach arm_dead_man on a
# post-cutover host. It cannot: the main body runs prepare_staging_target (which refuses
# staging_already_cutover when $MOUNT is the mapper) BEFORE arm_dead_man, and the wipe needs
# $MOUNT == mapper (W2). So the refusal was dropped; this row pins the premise it rests on.
MAIN_BODY="$(awk '/^trap cleanup EXIT$/{f=1} f{print}' "$CUTOVER")"
pst_ln="$(grep -nE '^prepare_staging_target$' <<<"$MAIN_BODY" | head -1 | cut -d: -f1)"
adm_ln="$(grep -nE '^arm_dead_man$' <<<"$MAIN_BODY" | head -1 | cut -d: -f1)"
[ -n "$pst_ln" ] && [ -n "$adm_ln" ] && [ "$pst_ln" -lt "$adm_ln" ] && grep -qF 'emit_drift staging_already_cutover' "$CUTOVER" \
  && ok "S6 arm_dead_man is unreachable on a cut-over host: prepare_staging_target (already_cutover refusal) runs first" \
  || no "S6 arm_dead_man may be reachable post-cutover (prepare=$pst_ln arm=$adm_ln) — add the plaintext-wiped refusal there"
# Observability discoverability probe (plan §Observability): the row prefix is built in ONE place.
disc_n="$(grep -c -e 'SOLEUR_WORKSPACES_LUKS_WIPE feature=workspaces-luks' "$CUTOVER" || true)"
[ "$disc_n" -eq 1 ] && ok "S7 the WIPE row prefix exists exactly once (emit_wipe is the single builder)" \
  || no "S7 WIPE row prefix count=$disc_n (want 1)"

# --- reason-slug census: every refusal the function raises has a RED row in THIS file ---------------
SLUGS="$(grep -oE '_wipe_refuse[[:space:]]+wipe_[a-z0-9_]+' "$CUTOVER" | awk '{print $2}' | sort -u)"
slug_n="$(grep -c . <<<"$SLUGS" || true)"
missing_rows=""
while IFS= read -r s; do
  [ -n "$s" ] || continue
  grep -qE "^(refusal \"[^\"]*\"|[[:space:]]*refused_ok|refused_ok) ${s}([[:space:]]|\$)|refused_ok ${s} " "$SELF" || missing_rows="$missing_rows $s"
done <<<"$SLUGS"
[ "$slug_n" -ge 25 ] && [ -z "$missing_rows" ] \
  && ok "C1 reason census: all $slug_n wipe refusal slugs have an asserting RED row in this suite" \
  || no "C1 reason census: $slug_n slugs, missing rows for [$missing_rows] (floor 25)"
# ...and the runbook's verdict table names every one of them (the operator's only no-SSH triage path).
RUNBOOK="$REPO/knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md"
rb_missing=""
while IFS= read -r s; do [ -n "$s" ] || continue; grep -qF "\`$s\`" "$RUNBOOK" 2>/dev/null || rb_missing="$rb_missing $s"; done <<<"$SLUGS"
[ "$slug_n" -ge 25 ] && [ -z "$rb_missing" ] \
  && ok "C2 the runbook step-7 verdict table names every refusal slug" \
  || no "C2 runbook verdict table missing [$rb_missing]"
# ...and every token the plan's Observability section names exists in the script. The plan is archived
# after ship (timestamp prefix), so it is FOUND by name under plans/, never by a fixed path.
PLAN="$(find "$REPO/knowledge-base/project/plans" -name '*feat-workspaces-plaintext-volume-wipe-plan.md' 2>/dev/null | head -1)"
if [ -z "$PLAN" ]; then
  no "C3 the plan file could not be found under knowledge-base/project/plans — the observability token census did not run"
else
  OBS="$(awk '/^## Observability$/{f=1; next} /^## /{f=0} f' "$PLAN")"
  toks="$( { grep -oE '(reason|arm|result|outcome)=[a-z_|]+' <<<"$OBS" | cut -d= -f2 | tr '|' '\n'; grep -oE '\bwipe_[a-z0-9_]+' <<<"$OBS"; } | grep -E '^[a-z0-9_]+$' | sort -u)"
  tok_missing=""
  while IFS= read -r t; do [ -n "$t" ] || continue; grep -qE "(^|[^a-z_])${t}([^a-z_]|\$)" "$CUTOVER" || tok_missing="$tok_missing $t"; done <<<"$toks"
  [ -n "$toks" ] && [ -z "$tok_missing" ] \
    && ok "C3 every result/arm/reason/outcome token in the plan's Observability section exists in the script" \
    || no "C3 plan observability tokens absent from the script: [$tok_missing]"
fi

# ============================================================================
# Guard 5 — nothing remounts a wiped volume (ROLLBACK refusal), via the harness's rollback world
# ============================================================================
RB_TEXT="$(awk '/^if \[ "\$ROLLBACK" = "1" \]; then$/{f=1} f{print} f && /^fi$/{exit}' "$CUTOVER")"
T_MAPPER="$(env -u WORKSPACES_MAPPER_NAME bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "$MAPPER"' _ "$CUTOVER")"
G5_ACT="inngest-server.service webhook.service inngest-redis.service"
g5_case() {  # <seed lines> [env...]
  local seed="$1"; shift
  run_case "$CUTOVER" "$seed trap cleanup EXIT; eval \"\$RB_TEXT\"" 'rollback cleanup assert_rollback_not_post_cutover' \
    ROLLBACK=1 RB_TEXT="$RB_TEXT" ACTIVE_UNITS="$G5_ACT" CRYPTSETUP_DEV=/dev/sdz7 "$@"
}
g5_refused() {  # [drift slug] [outcome] — default: the marker refusal (a wipe began)
  local slug="${1:-rollback_refused_plaintext_wiped}" oc="${2:-refused_plaintext_wiped}"
  died && has "^EMIT_DRIFT ${slug}\$" \
    && markerF "$DM result=cutover_aborted outcome=${oc} mode=rollback" \
    && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ] \
    && nhas '^umount[[:space:]]' && nhas '^docker stop' && nhas '^cryptsetup close'
}
g5_case "persist_state PLAINTEXT_WIPE_BEGUN '$PIN:1';" FINDMNT_MOUNT_SRC=/dev/sdz9 ROLLBACK_ACK_LUKS_WRITES=1
g5_refused && ok "G5 #1/#2 a BEGUN-only state refuses ROLLBACK=1 even with ROLLBACK_ACK_LUKS_WRITES=1 — before any umount/close/stop" \
  || no "G5 BEGUN-only ROLLBACK not refused (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|') ${CASE_OUT:0:200}"
g5_case "persist_state PLAINTEXT_WIPED '$PIN:1'; persist_state CANARY_OK 1:u-live-1;" FINDMNT_MOUNT_SRC="$T_MAPPER" CRYPTSETUP_UUID=u-live-1
g5_refused && outF "rollback_ack_luks_writes does not override this" && outF "a plaintext wipe began" \
  && grep -qE "outcome=refused_plaintext_wiped mode=rollback why=marker\$" "$MARKER_LOG" && ! markerF 'recorded=' \
  && ok "G5 a WIPED completed cutover refuses ROLLBACK=1 as refused_plaintext_wiped (why=marker, no recorded= fields: the marker arm never probed the record) FIRST, never as post_cutover (#4: never a false pre_freeze)" \
  || no "G5 WIPED ROLLBACK not refused (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case ":;" FINDMNT_MOUNT_SRC=/dev/sdz9 CRYPTSETUP_UUID=u-live-1
ran && has '^umount[[:space:]]' && nhas '^EMIT_DRIFT rollback_refused_plaintext_wiped$' \
  && ok "G5 H1 a ROLLBACK with no wipe markers behaves exactly as before (runs, not refused)" \
  || no "G5 H1 an unmarked ROLLBACK was refused or failed (rc=$CASE_RC) ${CASE_OUT:0:200}"
# G5b — the PHYSICAL check, independent of the wipe markers: /mnt/data on the mapper and the RECORDED
# plaintext device (PLAINTEXT_DEV, the device rollback() remounts) not an intact ext4 means there is no
# copy to remount, ack or not. Device-based: nothing here depends on a /dev/disk/by-label link. Each
# refusal must say WHICH (why=) and what the record read (recorded=/recorded_status=), in the run log and
# on the off-host outcome row, under its OWN slug (rollback_refused_plaintext_record_gone): no marker
# exists, so this is never a wipe — the sentence says so.
g5b_refused() {  # <recorded> <recorded_status>
  g5_refused rollback_refused_plaintext_record_gone refused_plaintext_record_gone && outF "(plaintext_dev_gone)" \
    && outF "recorded_status=$2" && outF "NOT a wipe" && nhas '^EMIT_DRIFT rollback_refused_plaintext_wiped$' \
    && markerF "$DM result=cutover_aborted outcome=refused_plaintext_record_gone mode=rollback why=plaintext_dev_gone recorded=$1 recorded_status=$2"
}
G5B_ENV=(FINDMNT_MOUNT_SRC="$T_MAPPER" CRYPTSETUP_UUID=u-live-1 ROLLBACK_ACK_LUKS_WRITES=1)
g5_case ":;" "${G5B_ENV[@]}" PLAINTEXT_DEV_FSTYPE=
g5b_refused /dev/sdz9 none && ok "G5b-R1 mapper mounted + the recorded plaintext reads no filesystem signature → refused before any umount, why=plaintext_dev_gone recorded_status=none" \
  || no "G5b-R1 a zeroed recorded plaintext did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|') ${CASE_OUT:0:240}"
g5_case ":;" "${G5B_ENV[@]}" PLAINTEXT_DEV_FSTYPE=crypto_LUKS
g5b_refused /dev/sdz9 crypto_LUKS && ok "G5b-D the record names a crypto_LUKS device (a stale record, drift) → refused, recorded_status=crypto_LUKS tells drift from a wipe" \
  || no "G5b-D a drifted record did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case ":;" "${G5B_ENV[@]}" BLKID_ABSENT=1
g5b_refused /dev/sdz9 blkid_absent && ok "G5b-B no blkid at a fixed path (cannot tell) → refused, recorded_status=blkid_absent (the one name for it)" \
  || no "G5b-B an unreadable type did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case ":;" "${G5B_ENV[@]}" PLAINTEXT_DEV_UNSEEDED=1
g5b_refused none invalid && ok "G5b-U no PLAINTEXT_DEV recorded (a lost state file) → refused, recorded=none recorded_status=invalid (fail-closed)" \
  || no "G5b-U an unrecorded plaintext did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case "persist_state PLAINTEXT_DEV $T_MAPPER;" "${G5B_ENV[@]}"
g5b_refused "$T_MAPPER" is_mapper && ok "G5b-M the record IS the mapper (reads ext4, but it is the live copy) → refused, recorded_status=is_mapper" \
  || no "G5b-M a record naming the mapper did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
# G5b-M2 — an ALIAS of the mapper (a `/./` spelling; readlink -f resolves it) is the live copy too.
G5_MAP_ALIAS="${T_MAPPER%/*}/./${T_MAPPER##*/}"
g5_case "persist_state PLAINTEXT_DEV $G5_MAP_ALIAS;" "${G5B_ENV[@]}"
g5b_refused "$G5_MAP_ALIAS" is_mapper && ok "G5b-M2 a record that is an ALIAS of the mapper ($G5_MAP_ALIAS) → refused, recorded_status=is_mapper" \
  || no "G5b-M2 a mapper-alias record did not refuse as is_mapper (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
# G5b-A — the recorded node is not a block device (a vanished kernel name after a reboot): absent, never
# conflated with a zeroed device (none).
g5_case ":;" "${G5B_ENV[@]}" PLAINTEXT_DEV_FSTYPE=absent
g5b_refused /dev/sdz9 absent && ok "G5b-A the recorded node is not a block device → refused, recorded_status=absent (drift or detach, not zeroed)" \
  || no "G5b-A an absent recorded node did not refuse as absent (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case "persist_state PLAINTEXT_DEV -o;" "${G5B_ENV[@]}"
g5b_refused -o invalid && ! hasF "SEAM _plaintext_dev_type -o" \
  && ok "G5b-V an option-shaped record (-o, the seam says ext4) → refused by the validator, never probed" \
  || no "G5b-V an option-shaped record did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
# G5b-V2/V3 — the validator's charset and `..` clauses, each on its own (the seam says ext4, so only the
# validator can refuse these): a `;` inside a /dev path, and a /dev path that climbs out with `..`.
for g5v in '/dev/sdz9;logger' '/dev/../tmp/x'; do
  g5_case "persist_state PLAINTEXT_DEV '$g5v';" "${G5B_ENV[@]}"
  g5b_refused "$g5v" invalid && ! hasF "SEAM _plaintext_dev_type $g5v" \
    && ok "G5b-V an unsafe record ($g5v) → refused by the validator (recorded_status=invalid), never probed" \
    || no "G5b-V an unsafe record ($g5v) did not refuse as invalid (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
done
# G5b-F8 — the physical witness needs BOTH conjuncts: with $MOUNT on the plaintext (pre-flip) a record that
# reads no filesystem is NOT "gone" (the mount gate), and the same record with the mapper mounted is.
for g5m in "/dev/sdz9:1:" "$T_MAPPER:0:plaintext_dev_gone"; do
  IFS=: read -r g5m_src g5m_rc g5m_why <<<"$g5m"
  run_case "$CUTOVER" '_plaintext_gone; echo "GONE_RC=$? WHY=$PLAINTEXT_GONE_WHY"' '_plaintext_gone' FINDMNT_MOUNT_SRC="$g5m_src" PLAINTEXT_DEV_FSTYPE=
  grep -qxF "GONE_RC=$g5m_rc WHY=$g5m_why" <<<"$CASE_OUT" \
    && ok "G5b-F8 _plaintext_gone with the mount on ${g5m_src} and an empty recorded fs → rc=$g5m_rc why=[${g5m_why}]" \
    || no "G5b-F8 _plaintext_gone mount conjunct wrong for ${g5m_src} (want rc=$g5m_rc why=[${g5m_why}]) ${CASE_OUT:0:200}"
done
# G5b-H1 — the pre-wipe web-1 shape: mapper mounted, the recorded plaintext intact → the acknowledged
# rollback runs, it probed the RECORDED device (not an empty or other key), and remounts that device.
g5_case ":;" "${G5B_ENV[@]}" DEADMAN_LOADED=timer FINDMNT_MOUNT_SRC_AFTER_DEADMAN_STOP=/dev/sdz9
ran && has '^umount[[:space:]]' && nhas '^EMIT_DRIFT rollback_refused_plaintext_wiped$' \
  && hasF "SEAM _plaintext_dev_type /dev/sdz9" && has '^mount /dev/sdz9[[:space:]]' \
  && ok "G5b-H1 mapper mounted + the recorded plaintext intact (pre-wipe) + ack → the rollback runs, probing and remounting the recorded device" \
  || no "G5b-H1 a pre-wipe acknowledged rollback was refused or probed the wrong key (rc=$CASE_RC seam=[$(grep -F 'SEAM _plaintext_dev_type' "$CALLS" | tr '\n' '|')]) ${CASE_OUT:0:200}"

# G5c — the check lives IN rollback(), so every caller is covered, not only ROLLBACK mode: here the
# cleanup() freeze arm (FREEZE_HELD / FLIP_DONE set, CANARY_OK not) on a post-wipe host.
g5_cleanup() {  # <seed> [env...]
  local seed="$1"; shift
  run_case "$CUTOVER" "$seed DRY_RUN=0; trap cleanup EXIT; die 'synthetic abort mid-freeze'" 'rollback cleanup' \
    ACTIVE_UNITS="$G5_ACT" CRYPTSETUP_DEV=/dev/sdz7 FINDMNT_MOUNT_SRC="$T_MAPPER" "$@"
}
g5c_refused() {  # [drift slug] [outcome]
  local slug="${1:-rollback_refused_plaintext_wiped}" oc="${2:-refused_plaintext_wiped}"
  died && has "^EMIT_DRIFT ${slug}\$" \
    && markerF "$DM result=cutover_aborted outcome=${oc}" \
    && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ] \
    && nhas '^umount[[:space:]]' && nhas '^docker stop' && nhas '^cryptsetup close' && nhas '^mount[[:space:]]'
}
g5_cleanup "persist_state PLAINTEXT_WIPED '$PIN:1'; FREEZE_HELD=1;"
g5c_refused && grep -qE "outcome=refused_plaintext_wiped why=marker\$" "$MARKER_LOG" \
  && ok "G5c cleanup()'s freeze arm on a WIPED host refuses inside rollback(): no umount/close/stop/mount, outcome=refused_plaintext_wiped why=marker" \
  || no "G5c the cleanup() freeze arm rolled back over a wiped plaintext (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|') calls=[$(grep -E '^(umount|mount|docker|cryptsetup) ' "$CALLS" | tr '\n' '|')]"
g5_cleanup "FLIP_DONE=1;" PLAINTEXT_DEV_FSTYPE=
g5c_refused rollback_refused_plaintext_record_gone refused_plaintext_record_gone \
  && markerF "outcome=refused_plaintext_record_gone why=plaintext_dev_gone recorded=/dev/sdz9 recorded_status=none" \
  && ok "G5c the cleanup() flip arm with NO marker but the recorded plaintext unreadable (physical) refuses inside rollback() as refused_plaintext_record_gone, the outcome row carrying why=/recorded=/recorded_status=" \
  || no "G5c the markerless physical case rolled back (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_cleanup "FLIP_DONE=1;"
died && has '^umount[[:space:]]' && nhas '^EMIT_DRIFT rollback_refused_plaintext_wiped$' && has '^mount /dev/sdz9[[:space:]]' \
  && ok "G5c H1 the pre-wipe flip arm (recorded plaintext intact, no marker) still rolls back, remounting the recorded device" \
  || no "G5c H1 the pre-wipe cleanup rollback was refused (rc=$CASE_RC) ${CASE_OUT:0:200}"

# G5d — the dead-man FIRE string is self-contained (it runs after this script is gone), so it cannot
# call rollback(): it carries its OWN copy of the same check, evaluated by /bin/sh at fire time before
# any stop/umount/close. EXECUTED here against recording stubs (not grepped). g5d_arm re-arms per record
# (the record and the blkid path are BAKED at arm time), rebinding both the fire and its state file.
G5D_BIN="$WIPE_SCRATCH/g5d-bin"; mkdir -p "$G5D_BIN"
# One recording stub, copied per name (a quoted heredoc, so the stub's own `>>` is never read as a
# redirect of this suite by the fixture-relative-assert scanner).
cat > "$G5D_BIN/logger" <<'G5D_STUB'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >> "$G5D_LOG"
G5D_STUB
for b in umount mount cryptsetup docker systemctl; do cp "$G5D_BIN/logger" "$G5D_BIN/$b"; done
# findmnt answers ONLY `-no SOURCE <the baked mount>`; blkid ONLY `-p -s TYPE -o value <the expected
# device>` (anything else logs *-unexpected and exits 64, so a fire probing the wrong device is seen).
cat > "$G5D_BIN/findmnt" <<'G5D_STUB'
#!/bin/sh
[ "$*" = "-no SOURCE $G5D_MNT" ] || { printf 'findmnt-unexpected %s\n' "$*" >> "$G5D_LOG"; exit 64; }
printf '%s\n' "$G5D_SRC"
G5D_STUB
cat > "$G5D_BIN/blkid" <<'G5D_STUB'
#!/bin/sh
printf 'blkid %s\n' "$*" >> "$G5D_LOG"
[ "$*" = "-p -s TYPE -o value $G5D_EXPECT_DEV" ] || { printf 'blkid-unexpected %s\n' "$*" >> "$G5D_LOG"; exit 64; }
[ -n "$G5D_TYPE" ] || exit 2
printf '%s\n' "$G5D_TYPE"
G5D_STUB
chmod +x "$G5D_BIN"/*
g5d_arm() {  # <record> [env...]
  local r="$1"; shift
  run_case "$CUTOVER" "persist_state PLAINTEXT_DEV '$r'; DRY_RUN=0 arm_dead_man" 'arm_dead_man' BLKID_BIN_PATH="$G5D_BIN/blkid" "$@"
  G5D_STATE="$STATE/state"; G5D_MNT="$MNT"
  G5D_FIRE="$(awk '/^systemd-run / { sub(/^.* \/bin\/sh -c /, ""); print; exit }' "$CALLS")"
}
g5d_fire() {  # <mount source> <state line or empty> <blkid TYPE or empty>
  G5D_LOG="$WIPE_SCRATCH/g5d.log"; : > "$G5D_LOG"
  : > "$G5D_STATE"; [ -z "$2" ] || printf '%s\n' "$2" > "$G5D_STATE"
  env PATH="$G5D_BIN:/usr/bin:/bin" G5D_LOG="$G5D_LOG" G5D_SRC="$1" G5D_MNT="$G5D_MNT" G5D_TYPE="${3:-}" \
    G5D_EXPECT_DEV="$TGT_BLK" sh -c "$G5D_FIRE" >/dev/null 2>&1
}
g5d_log() { tr '\n' '|' < "$G5D_LOG" | cut -c1-300; }
g5d_arm "$TGT_BLK"
if [ -z "$G5D_FIRE" ] || ! sh -n -c "$G5D_FIRE" 2>/dev/null; then
  no "G5d INSTRUMENT: the fire string was not captured or is not valid /bin/sh (every fire row below would be vacuous) — ${G5D_FIRE:0:160}"
else
  # The behavioural rows below run whatever the fire contains, so a fire that lost its physical test
  # (or the whole guard) goes RED on the row that exercises it, not only here.
  grep -qF "$G5D_BIN/blkid -p -s TYPE -o value $TGT_BLK" <<<"$G5D_FIRE" \
    && ok "G5d the captured fire string parses under sh -n and bakes the fixed-path blkid against the recorded device" \
    || no "G5d the fire does not bake the arm-time blkid path against the recorded device — ${G5D_FIRE:0:200}"
  g5d_fire /dev/sdz9 "PLAINTEXT_WIPE_BEGUN=$PIN:1" ext4
  grep -qF 'reason=refused_plaintext_wiped why=marker' "$G5D_LOG" && ! grep -qE '^(umount|cryptsetup|mount) ' "$G5D_LOG" && ! grep -qE '^docker stop' "$G5D_LOG" \
    && ok "G5d-R1 a dead-man FIRE on a host whose state names a wipe refuses (why=marker) before any stop/umount/close" \
    || no "G5d-R1 the fire string tore down the mount on a wiped host: $(g5d_log)"
  g5d_fire "$T_MAPPER" "" ""
  grep -qF "reason=refused_plaintext_record_gone why=plaintext_dev_gone recorded=$TGT_BLK recorded_status=none" "$G5D_LOG" \
    && ! grep -qE '^(umount|cryptsetup|mount) ' "$G5D_LOG" && ! grep -qE '^docker stop' "$G5D_LOG" && ! grep -qF -- '-unexpected' "$G5D_LOG" \
    && ok "G5d-R2 a FIRE with no marker, the mapper mounted and the recorded plaintext zeroed refuses (reason=refused_plaintext_record_gone recorded_status=none)" \
    || no "G5d-R2 the markerless physical fire tore down the mount: $(g5d_log)"
  g5d_fire "$T_MAPPER" "" crypto_LUKS
  grep -qF "reason=refused_plaintext_record_gone why=plaintext_dev_gone recorded=$TGT_BLK recorded_status=crypto_LUKS" "$G5D_LOG" && ! grep -qE '^(umount|cryptsetup|mount) ' "$G5D_LOG" \
    && ok "G5d-D a FIRE whose recorded device now reads crypto_LUKS (drift) refuses and says so" \
    || no "G5d-D a drifted-record fire tore down the mount: $(g5d_log)"
  g5d_fire "$T_MAPPER" "" ext4
  grep -qE "^mount $TGT_BLK $G5D_MNT\$" "$G5D_LOG" && grep -qF "result=ok reason=plaintext_remounted mount_source=$TGT_BLK" "$G5D_LOG" \
    && grep -qxF "blkid -p -s TYPE -o value $TGT_BLK" "$G5D_LOG" && ! grep -qF -- '-unexpected' "$G5D_LOG" && ! grep -qF refused_plaintext "$G5D_LOG" \
    && ok "G5d-H2 the pre-wipe web-1 shape (mapper mounted, recorded plaintext intact ext4) RESTORES: mount <record> <mnt>, result=ok mount_source=<record>, blkid probed the record" \
    || no "G5d-H2 the intact-record fire did not restore the recorded device: $(g5d_log)"
  g5d_fire /dev/sdz9 "" ext4
  grep -qE '^umount ' "$G5D_LOG" && ! grep -qF 'reason=refused_plaintext_wiped' "$G5D_LOG" && grep -qE "^mount $TGT_BLK " "$G5D_LOG" \
    && ok "G5d-H1 a FIRE mid-freeze (plaintext still mounted, no marker) runs its restore exactly as before" \
    || no "G5d-H1 the pre-wipe fire was refused: $(g5d_log)"
  # G5d-F8 — the fire's physical witness is gated on the mapper being mounted: mid-freeze (plaintext still
  # mounted) a record that reads NO filesystem still restores — the mount conjunct, not the type alone.
  g5d_fire /dev/sdz9 "" ""
  grep -qE "^mount $TGT_BLK $G5D_MNT\$" "$G5D_LOG" && ! grep -qF refused_plaintext "$G5D_LOG" \
    && ok "G5d-F8 a FIRE with the plaintext still mounted restores even when the record reads no filesystem (the mapper conjunct)" \
    || no "G5d-F8 the fire refused (or did not mount) with the plaintext still mounted: $(g5d_log)"
  # G5d-S — the fire carries a SUBSET of _plaintext_record_status (marker; mapper mounted AND recorded not
  # ext4); validity, -b and not-the-mapper are proven at arm time. Pin the ext4 clause literally.
  grep -qF "= ${T_MAPPER} ] && [ \"\$t\" != ext4 ]" <<<"$G5D_FIRE" \
    && ok "G5d-S the fire's physical witness is exactly (mapper mounted AND recorded TYPE != ext4)" \
    || no "G5d-S the fire's ext4 clause changed — ${G5D_FIRE:0:300}"
fi

# ============================================================================
echo
echo "workspaces-luks-wipe.test.sh: $pass passed, $fail failed"
# PASS FLOOR at the measured count (harness_floor exits through printf, never through no()).
WIPE_MIN_PASS=173
harness_floor workspaces-luks-wipe.test.sh "$WIPE_MIN_PASS"
[ "$fail" -eq 0 ]

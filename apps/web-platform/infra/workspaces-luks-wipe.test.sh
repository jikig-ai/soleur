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

# --- the stub world, sourced INSIDE each case after the script (a file, so no quoting contortions) ---
WIPE_STUBS="$RUN_SCRATCH/wipe-stubs.sh"
cat > "$WIPE_STUBS" <<'STUBS'
# shellcheck shell=bash
rec() { printf '%s\n' "$*" >> "$CALLS"; }
unk() { printf 'STUB_UNKNOWN_FLAG %s\n' "$*" >> "$CALLS"; return 64; }
command_not_found_handle() { printf 'UNSTUBBED %s\n' "$1" >> "$CALLS"; return 127; }
TGT_REAL="$(readlink -f -- "$TGT_BLK")"
TGT_KNAME="$(basename "$TGT_REAL")"
W_BACKING_DEV="${W_BACKING-$LUKS_BLK}"
W_TARGET_UNITS="${W_TARGET_UNITS-dev-${TGT_KNAME}.device dev-disk-by\\x2did-scsi\\x2d0HC_Volume_105149570.device}"
zeroed() { [ -f "$W_CASE_DIR/zeroed" ] && [ "${W_SIG_SURVIVES:-0}" != 1 ]; }
in_target_units() { local u; for u in $W_TARGET_UNITS; do [ "$u" = "$1" ] && return 0; done; return 1; }

# THE SEAM. Production returns its argument; here it returns a real block device (or an absent path).
_wipe_dev_path() {
  rec "SEAM _wipe_dev_path $*"
  if [ "${W_DEV_ABSENT:-0}" = 1 ]; then printf '%s' "$W_CASE_DIR/no-such-dev"; return 0; fi
  if [ "${W_DEV_VIA_RELLINK:-0}" = 1 ]; then printf '%s' "$W_CASE_DIR/dev/disk/by-id/scsi-0HC_Volume_105149570"; return 0; fi
  printf '%s' "$TGT_BLK"
}
_wipe_sysfs_block() { printf '%s' "$W_CASE_DIR/sysfs"; }

command() {
  if [ "${1:-}" = -v ] && [ -n "${W_TOOL_ABSENT:-}" ] && [ "${2:-}" = "$W_TOOL_ABSENT" ]; then return 1; fi
  builtin command "$@"
}
die()        { echo "DIE: $*"; exit 1; }
emit_drift() { rec "EMIT_DRIFT $1"; echo "EMIT_DRIFT: $1"; }
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
  [ -t 0 ] && rec "BLKDISCARD_STDIN_IS_A_TTY"
  if [ "${W_BLKDISCARD_RC:-0}" = 0 ]; then : > "$W_CASE_DIR/zeroed"; fi
  return "${W_BLKDISCARD_RC:-0}"
}
pgrep() { rec "pgrep $*"; [ "${1:-}" = -x ] || { unk pgrep "${1:-}"; return 64; }; return "${W_PGREP_RC:-1}"; }
findmnt() {
  rec "findmnt $*"
  local a
  for a in "$@"; do case "$a" in -n|-o|-r|-S|-no|-rn|SOURCE|TARGET|OPTIONS|/*) ;; -*) unk findmnt "$a"; return 64 ;; esac; done
  case " $* " in
    *" -S "*) if [ -n "${W_TGT_MNT:-}" ]; then printf '%s\n' "$W_TGT_MNT"; return 0; fi; return 1 ;;
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
aws() {
  rec "aws $*"
  [ "${1:-} ${2:-}" = "s3 cp" ] || { unk aws "${1:-} ${2:-}"; return 64; }
  case "${3:-}" in s3://*) ;; *) unk aws "upload-direction ${3:-}"; return 64 ;; esac
  [ "${5:-}" = --endpoint-url ] || { unk aws "${5:-}"; return 64; }
  [ "${W_HDR_ABSENT:-0}" = 1 ] && return 1
  printf '%s' "${W_DL_CONTENT-HDR-v1}" > "$4"; return 0
}
stat() {
  rec "stat $*"
  local p
  if [ "${1:-}" = -Lc ] && [ "${2:-}" = '%t:%T' ]; then
    p="$(readlink -f -- "${3:-}")"
    if [ "$p" = "$TGT_REAL" ]; then printf '%s\n' "${W_TGT_MAJMIN-8:32}"; return 0; fi
    if [ "$p" = "$(readlink -f -- "$W_BACKING_DEV")" ]; then printf '%s\n' "${W_BACKING_MAJMIN-8:16}"; return 0; fi
    return 1
  fi
  builtin command stat "$@"
}
blockdev() {
  rec "blockdev $*"
  case "${1:-}" in
    --getsize64) printf '%s\n' "${W_SIZE-21474836480}" ;;
    --flushbufs) ;;
    *) unk blockdev "${1:-}"; return 64 ;;
  esac
}
udevadm() {
  rec "udevadm $*"
  [ "${1:-}" = info ] || { unk udevadm "${1:-}"; return 64; }
  case "${2:-}" in
    --query=property) printf 'DEVNAME=%s\nID_SERIAL=%s\nID_SCSI_SERIAL=%s\n' "$TGT_REAL" "${W_SERIAL-0HC_Volume_105149570}" "${W_SERIAL-0HC_Volume_105149570}" ;;
    --query=path) printf '/devices/virtual/wipe-test/block/%s\n' "$TGT_KNAME" ;;
    *) unk udevadm "${2:-}"; return 64 ;;
  esac
}
blkid() {
  rec "blkid $*"
  if [ "${1:-}" != -p ] || [ "${2:-}" != -s ] || [ "${4:-}" != -o ] || [ "${5:-}" != value ]; then unk blkid "$*"; return 64; fi
  if zeroed; then return 2; fi
  case "${3:-}" in
    TYPE)
      [ -n "${W_BLKID_RC:-}" ] && return "$W_BLKID_RC"
      [ -n "${W_TYPE-ext4}" ] || return 2
      printf '%s\n' "${W_TYPE-ext4}"; return 0 ;;
    LABEL)
      [ -n "${W_LABEL-workspaces_plain}" ] || return 2
      printf '%s\n' "${W_LABEL-workspaces_plain}"; return 0 ;;
    *) unk blkid "-s ${3:-}"; return 64 ;;
  esac
}
lsblk() {
  rec "lsblk $*"
  [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-}" = "-D -b -n -o DISC-GRAN,DISC-MAX" ] || { unk lsblk "$*"; return 64; }
  printf '%s %s\n' 4096 1073741824
}
dumpe2fs() {
  rec "dumpe2fs $*"
  [ "${1:-}" = -h ] || { unk dumpe2fs "${1:-}"; return 64; }
  printf 'Filesystem volume name:   workspaces_plain\nLast mount time:          Thu Jul 23 10:00:00 2026\nLast write time:          Thu Jul 23 10:05:00 2026\n'
}
systemd-escape() {
  rec "systemd-escape $*"
  [ "${1:-} ${2:-}" = "--path --suffix=mount" ] || { unk systemd-escape "$*"; return 64; }
  printf 'mnt-data.mount\n'
}
systemd-run() {
  rec "systemd-run $*"
  while [ $# -gt 0 ]; do
    case "$1" in
      --scope|--quiet) shift ;;
      -p) shift 2 ;;
      -*) unk systemd-run "$1"; return 64 ;;
      *) break ;;
    esac
  done
  if [ "${1:-}" = true ]; then return "${W_SCOPE_PROBE_RC:-0}"; fi
  "$@"
}
dd() {
  rec "dd $*"
  local a count=""
  for a in "$@"; do
    case "$a" in if=*|iflag=direct|status=none|bs=*) ;; count=*) count="${a#count=}" ;; *) unk dd "$a"; return 64 ;; esac
  done
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
  local a u prop="" val=0 prev="" unit="" v
  case "${1:-}" in
    list-units)
      for a in "$@"; do case "$a" in list-units|--all|--type=device|--plain|--no-legend|--no-pager) ;; *) unk systemctl "$a"; return 64 ;; esac; done
      for u in $W_TARGET_UNITS dev-other.device; do printf '%s loaded active plugged Volume\n' "$u"; done
      return 0 ;;
    list-dependencies)
      for a in "$@"; do case "$a" in list-dependencies|--reverse|--plain|--no-pager|--) ;; -*) unk systemctl "$a"; return 64 ;; *) unit="$a" ;; esac; done
      printf '%s\n' "$unit"
      printf '  blockdev@%s.target\n' "${unit%.device}"
      if [ -n "${W_REVDEP:-}" ]; then for v in $W_REVDEP; do printf '  %s\n' "$v"; done; fi
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
STUBS

# --- PATH tripwires + the allowlist -------------------------------------------------------------
TRIP_DIR="$RUN_SCRATCH/trip"; ALLOW_DIR="$RUN_SCRATCH/allow"
mkdir -p "$TRIP_DIR" "$ALLOW_DIR"
for t in blkdiscard dd doppler aws; do
  printf '#!/usr/bin/env bash\nprintf "TRIPWIRE %%s %%s\\n" %s "$*" >> "${CALLS:-/dev/null}"\nexit 64\n' "$t" > "$TRIP_DIR/$t"
  chmod +x "$TRIP_DIR/$t"
done
for b in tr sed cut head tail grep awk cat od date mktemp basename dirname readlink sort uniq wc mkdir rm chmod sha256sum stat cmp ls env touch bash; do
  p="$(command -v "$b" 2>/dev/null)" || { printf 'INSTRUMENT FAIL - allowlist binary %s not found\n' "$b"; exit 2; }
  ln -sf "$p" "$ALLOW_DIR/$b"
done

# run_wipe <invocation> [VAR=value ...]
#   SEED_STATE='K=V;K=V'  written to the state file BEFORE the run (default: CANARY_OK=1:u-live-1).
#   W_HOLDERS='dm-3'      holder entries under the target's sysfs holders/ dir.
#   UNSET_DRY_RUN=1       run with DRY_RUN absent from the environment (the script default applies).
# Sets CASE_RC, CASE_OUT, CALLS, MARKER_LOG, STATE, WCASE.
run_wipe() {
  local invocation="$1"; shift
  CASE_N=$((CASE_N + 1))
  local d="$RUN_SCRATCH/wipe-$CASE_N" k h seeded=0 unset_dry=0
  WCASE="$d"; CALLS="$d/calls"; MARKER_LOG="$d/marker"; STATE="$d/state"
  mkdir -p "$STATE" "$d/mnt/workspaces" "$d/staging" "$d/sysfs/$TGT_KNAME/holders" "$d/sysfs/$TGT_KNAME/queue" "$d/dev/disk/by-id"
  : > "$CALLS"; : > "$MARKER_LOG"
  printf '33554432\n' > "$d/sysfs/$TGT_KNAME/queue/write_zeroes_max_bytes"
  printf '[mq-deadline] none\n' > "$d/sysfs/$TGT_KNAME/queue/scheduler"
  ln -s "$TGT_REAL" "$d/dev/sdc"
  ln -s ../../sdc "$d/dev/disk/by-id/scsi-0HC_Volume_${PIN}"
  local -a envs=()
  for k in "$@"; do
    case "$k" in
      SEED_STATE=*) seeded=1; [ -n "${k#SEED_STATE=}" ] && printf '%s\n' "${k#SEED_STATE=}" | tr ';' '\n' > "$STATE/state" ;;
      W_HOLDERS=*) for h in ${k#W_HOLDERS=}; do mkdir -p "$d/sysfs/$TGT_KNAME/holders/$h"; done ;;
      UNSET_DRY_RUN=1) unset_dry=1 ;;
      *) envs+=("$k") ;;
    esac
  done
  [ "$seeded" = 1 ] || printf 'CANARY_OK=1:%s\n' "$UUID_LIVE" > "$STATE/state"
  local -a pre=(env)
  [ "$unset_dry" = 1 ] && pre+=(-u DRY_RUN)
  local -a base=(CUTOVER="$CUTOVER" WIPE_STUBS="$WIPE_STUBS" CALLS="$CALLS" MARKER_LOG="$MARKER_LOG"
    W_CASE_DIR="$d" TRIP_DIR="$TRIP_DIR" ALLOW_DIR="$ALLOW_DIR" TGT_BLK="$TGT_BLK" LUKS_BLK="$LUKS_BLK"
    INVOCATION="$invocation" MAIN_PREFIX="${MAIN_PREFIX:-}" RB_TEXT="${RB_TEXT:-}"
    WORKSPACES_STATE_DIR="$STATE" WORKSPACES_MOUNT="$d/mnt" WORKSPACES_STAGING="$d/staging"
    CONFIRM_WIPE=1 ROLLBACK=0 CLEAN_STRAY=0
    WORKSPACES_PLAINTEXT_VOLUME_ID="$PIN" WORKSPACES_PLAINTEXT_DEV="$BYID"
    WORKSPACES_PLAINTEXT_SIZE_BYTES="$SIZE" WORKSPACES_LUKS_DEV="$LUKS_BLK")
  [ "$unset_dry" = 1 ] || base+=(DRY_RUN=0)
  CASE_OUT="$(
    "${pre[@]}" "${base[@]}" "${envs[@]}" bash -c '
      source "$CUTOVER"
      source "$WIPE_STUBS"
      PATH="$TRIP_DIR:$ALLOW_DIR"
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
hasF "systemd-run --scope --quiet -p IOWriteBandwidthMax=$TGT_REAL 150M -p IOReadBandwidthMax=$TGT_REAL 150M blkdiscard -z -v $TGT_REAL" \
  && ok "P1b the zero runs inside a systemd scope capped at 150M read AND write on the target (cgroup io.max, not ionice)" \
  || no "P1b the zero is not wrapped in the io.max-capped scope: $(grep -E '^systemd-run .*blkdiscard' "$CALLS" | head -1)"
hasF "systemd-run --scope --quiet -p IOReadBandwidthMax=$TGT_REAL 150M dd if=$TGT_REAL iflag=direct bs=4M status=none" \
  && hasF "cmp -n $SIZE - /dev/zero" \
  && ok "P1c the read-back is a capped O_DIRECT full-device read compared by cmp -n <size> against /dev/zero" \
  || no "P1c the read-back shape drifted (direct IO / cap / cmp -n size): $(grep -E '^(systemd-run .*dd|cmp -n)' "$CALLS" | tr '\n' '|')"
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
p2_fields=1
for f in "uuid=$UUID_LIVE" "hdr_sha256=" "hdr_bytes=" "label=workspaces_plain" "dependents=0" "holders=0" "device_units=2" \
  "discard_gran=4096" "write_zeroes_max=33554432" "scheduler=mq-deadline" "magic=53ef" "size=$SIZE"; do
  [[ "$P2_ROW" == *" $f"* ]] || p2_fields=0
done
if ran && [ -n "$P2_ROW" ] && [ "$p2_fields" = 1 ] && [ "$(zero_calls)" -eq 0 ] && nounk \
  && ! state_has PLAINTEXT_WIPE_BEGUN && ! state_has PLAINTEXT_WIPED && hdrs_gone \
  && [ "$(nrows begun)" -eq 0 ] && [ "$(nrows wiped)" -eq 0 ]; then
  ok "P2 rehearsal: one rehearsal_ok arm=first_wipe row carrying the W3–W9 fields; no blkdiscard, no PLAINTEXT_* marker, both header copies shredded"
else
  no "P2 rehearsal wrong (rc=$CASE_RC zero=$(zero_calls) fields=$p2_fields unk=[$(unkdump)]) row=[${P2_ROW:0:300}] ${CASE_OUT:0:200}"
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
if ran && [ -n "$(wrow wiped re_zero)" ] && [ "$(zero_calls)" -eq 1 ] && nhas '^dd .*count=1' && nhas '^blkid .* LABEL ' && nounk; then
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
run_wipe ': > "$STATE_DIR/wipe-header-download.img"; : > "$STATE_DIR/wipe-header-fresh.img"; trap cleanup EXIT; die "synthetic abort mid-W5"'
died && hdrs_gone && markerF "outcome=wipe_aborted mode=wipe" \
  && ok "W5 cleanup() sweeps both fixed header paths on a wipe abort" \
  || no "W5 cleanup() left a header copy on the root disk (rc=$CASE_RC)"

refusal "W6 (Guard 1 #1) the mapper's backing device IS the target" wipe_target_is_mapper_backing "W_BACKING=$TGT_BLK" "WORKSPACES_LUKS_DEV=$TGT_BLK"
refusal "W6 (Guard 1 #2) same major:minor through a different path" wipe_target_is_mapper_backing W_BACKING_MAJMIN=8:32
refusal "W6 (Guard 1 #4) a holder under /sys/class/block/<k>/holders" wipe_target_held W_HOLDERS=dm-7
refusal "W6 the target is mounted somewhere (findmnt -S)" wipe_target_mounted W_TGT_MNT=/mnt/stray
refusal "W6 (Guard 1 #5) size off by one GiB" wipe_target_size_mismatch W_SIZE=22548578304
refusal "W6 (Guard 1 #9c) ID_SERIAL does not name HC_Volume_<id>" wipe_target_serial_mismatch W_SERIAL=0HC_Volume_106443278
refusal "W6 ID_SERIAL naming a LONGER id that merely starts with the pin" wipe_target_serial_mismatch W_SERIAL=0HC_Volume_1051495701
refusal "W6 (Guard 1 #7) first-wipe label is not workspaces_plain" wipe_target_label_mismatch W_LABEL=other
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
refusal "W7 the dead-man timer is active" wipe_deadman_armed W_DM_TIMER_ACTIVE=active
refusal "W7 a dead-man fire is activating" wipe_deadman_armed W_DM_SVC_ACTIVE=activating
refusal "W7 a dead-man start job is queued" wipe_deadman_armed W_DM_SVC_JOB=4242
refusal "W8 the io.max cap cannot be applied (systemd-run scope probe fails)" wipe_io_cap_unavailable W_SCOPE_PROBE_RC=1
refusal "W9 (Guard 3 #6) first-wipe positive control sees no ext4 magic" wipe_positive_control_failed W_MAGIC=0

# W10 — the zero itself fails: refused, BEGUN persisted (the next dispatch takes re_zero), no wiped row.
run_wipe 'wipe_plaintext' W_BLKDISCARD_RC=1
if refused_ok wipe_blkdiscard_failed && state_has PLAINTEXT_WIPE_BEGUN && ! state_has PLAINTEXT_WIPED && [ "$(nrows wiped)" -eq 0 ]; then
  ok "W10 a failed blkdiscard refuses wipe_blkdiscard_failed with BEGUN persisted and no wiped row"
else
  no "W10 failed blkdiscard mis-handled (rc=$CASE_RC) ${CASE_OUT:0:240}"
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
if died && markerF "$DM result=cutover_aborted outcome=wipe_aborted mode=wipe" && nhas '^umount ' && nhas '^docker (start|stop) ' \
  && nhas '^mount ' && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ]; then
  ok "M3 (Guard 5 #3) an aborted wipe (die at W11) with CANARY_OK persisted records outcome=wipe_aborted mode=wipe and never rolls back or starts the app"
else
  no "M3 an aborted wipe mis-recorded or touched the live mount (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|') calls=[$(grep -E '^(umount|mount|docker) ' "$CALLS" | tr '\n' '|')]"
fi
run_wipe 'eval "$MAIN_PREFIX"' DRY_RUN=1 W_MOUNT_SRC=/dev/sdz9
markerF "$DM result=cutover_aborted outcome=dry_run mode=wipe" \
  && ok "M4 a refused rehearsal reads outcome=dry_run mode=wipe" \
  || no "M4 a refused rehearsal mis-recorded: $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
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
  && ! grep -qE '(^|[;[:space:]])(DRY_RUN|CANARY_OK|FREEZE_HELD|FLIP_DONE|DEADMAN_ARMED)=' <<<"$WIPE_BLOCK$WIPE_FN"; then
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
n_zero_sites="$(grep -cE '(^|[;&|[:space:]])blkdiscard[[:space:]]+-z' <<<"$BODY_NC" || true)"
[ "$n_zero_sites" -eq 1 ] && ok "S3 (Guard 1 #10) exactly one blkdiscard -z call site in the script" \
  || no "S3 blkdiscard -z call sites = $n_zero_sites (want exactly 1)"
if grep -qE 'blkdiscard([^#]*[[:space:]])(-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)' <<<"$BODY_NC"; then
  no "S4 (Guard 1 #11) blkdiscard is invoked with -f/--force somewhere — O_EXCL would be disabled"
else
  ok "S4 (Guard 1 #11) no blkdiscard invocation carries -f/--force (O_EXCL stays on)"
fi
# The seams are not settable from the environment (an .env line could otherwise repoint the zero).
seam_env="$(awk '/^_wipe_dev_path\(\)|^_wipe_sysfs_block\(\)/{f=1} f{print} f && /\}$/{f=0}' "$CUTOVER" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' | grep -vE '^\$\{?1$' || true)"
seam_n="$(grep -cE '^_wipe_dev_path\(\) |^_wipe_sysfs_block\(\) ' "$CUTOVER" || true)"
[ "$seam_n" -eq 2 ] && [ -z "$seam_env" ] \
  && ok "S5 the device and sysfs seams read no variable but their own argument (not env-settable)" \
  || no "S5 a seam reads an environment variable or is missing (defs=$seam_n vars=[$seam_env])"
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
SLUGS="$(grep -oE '_wipe_refuse[[:space:]]+wipe_[a-z_]+' "$CUTOVER" | awk '{print $2}' | sort -u)"
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
  toks="$( { grep -oE '(reason|arm|result|outcome)=[a-z_|]+' <<<"$OBS" | cut -d= -f2 | tr '|' '\n'; grep -oE '\bwipe_[a-z_]+' <<<"$OBS"; } | grep -E '^[a-z_]+$' | sort -u)"
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
g5_refused() {
  died && has '^EMIT_DRIFT rollback_refused_plaintext_wiped$' \
    && markerF "$DM result=cutover_aborted outcome=refused_plaintext_wiped mode=rollback" \
    && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ] \
    && nhas '^umount[[:space:]]' && nhas '^docker stop' && nhas '^cryptsetup close'
}
g5_case "persist_state PLAINTEXT_WIPE_BEGUN '$PIN:1';" FINDMNT_MOUNT_SRC=/dev/sdz9 ROLLBACK_ACK_LUKS_WRITES=1
g5_refused && ok "G5 #1/#2 a BEGUN-only state refuses ROLLBACK=1 even with ROLLBACK_ACK_LUKS_WRITES=1 — before any umount/close/stop" \
  || no "G5 BEGUN-only ROLLBACK not refused (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|') ${CASE_OUT:0:200}"
g5_case "persist_state PLAINTEXT_WIPED '$PIN:1';" FINDMNT_MOUNT_SRC="$T_MAPPER" CRYPTSETUP_UUID=u-live-1
g5_refused && ok "G5 a WIPED state refuses ROLLBACK=1 with the explicit row (#4: never a false pre_freeze)" \
  || no "G5 WIPED ROLLBACK not refused (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case ":;" FINDMNT_MOUNT_SRC=/dev/sdz9 CRYPTSETUP_UUID=u-live-1
ran && has '^umount[[:space:]]' && nhas '^EMIT_DRIFT rollback_refused_plaintext_wiped$' \
  && ok "G5 H1 a ROLLBACK with no wipe markers behaves exactly as before (runs, not refused)" \
  || no "G5 H1 an unmarked ROLLBACK was refused or failed (rc=$CASE_RC) ${CASE_OUT:0:200}"

# ============================================================================
echo
echo "workspaces-luks-wipe.test.sh: $pass passed, $fail failed"
# PASS FLOOR at the measured count (harness_floor exits through printf, never through no()).
WIPE_MIN_PASS=110
harness_floor workspaces-luks-wipe.test.sh "$WIPE_MIN_PASS"
[ "$fail" -eq 0 ]

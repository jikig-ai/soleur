#!/bin/bash
# (#6931) Guest-side FRESH-BOOT LUKS provisioner for the /workspaces data volume.
#
# WHY THIS EXISTS. A web host born from cloud-init (web-2 today; any future cattle host) used to
# mount the Hetzner volume as plaintext ext4 and was kept safe only by lb-weight-gate.sh refusing
# to pool it. web-1 reaches "LUKS at boot" because a Terraform SSH installer delivers the reopen
# units to the running pet; a fresh host never receives that installer. This script is baked into
# the image (soleur-host-bootstrap.sh installs it), called ONCE by cloud-init before anything
# writes under /mnt/data, and leaves the host with /mnt/data on /dev/mapper/workspaces plus the
# SAME crypttab / fstab / docker drop-in / reopen units web-1 has. Binding ruling: ADR-143 R3,
# superseded by the guest-side-LUKS ADR (knowledge-base/engineering/architecture/decisions/).
#
# THE ONE RULE. Nothing in this file may destroy data that exists. A destructive call
# (`cryptsetup luksFormat`, `mkfs`) is reachable ONLY through the two chokepoints _may_format()
# (device level) and _may_format_fs() (mapper level), and each is RE-RUN immediately before the
# destructive call it guards, not merely somewhere earlier — the device can change state between
# the discriminator and the call. The discriminator is `blkid -o value -s TYPE`: empty (rc 2) means
# raw, `crypto_LUKS` means open, ANYTHING else (including the `ext4` Hetzner pre-formats at create)
# is FATAL with zero write calls. The `isLuks` subcommand is NEVER used here: it reports rc 1 for a
# populated plaintext device, which reads as "not LUKS, safe to format" — the documented
# data-destroyer on a populated device (workspaces-luks.tf doctrine). The reopen script uses it
# read-only as a "refuse if not LUKS" header check, the opposite polarity, and stays.
#
# ARMS (each failure is a distinct exit code, one SOLEUR_WORKSPACES_LUKS_PROVISION row, and a
# soleur-boot-emit stage workspaces_luks_provision_<arm>):
#   config        10  both env files present, regular, root-owned, 0600, well-shaped
#   device        11  the by-id device answers blockdev within 300 s (attachment lags server boot)
#   discriminate  12  blkid rc 0|2 only; PTTYPE + wipefs corroborate a raw device
#   key           13  WORKSPACES_LUKS_KEY via the R9-pinned `doppler secrets get ... --plain`,
#                     retried ~5 min so a Doppler blip at first boot does not end in poweroff
#   format        14  luksFormat -> luksOpen -> mkfs, with a durable INTENT file so a crash
#                     between luksFormat and mkfs is recoverable instead of bricking every boot
#   open          15  luksOpen if closed; mkfs ONLY for a blank mapper WITH the intent file
#   wire          16  crypttab / fstab / docker drop-in / immutable covered inode / mount / units
#   mount         17  /mnt/data is not mounted from the mapper after wire
#   (escrow)          NON-fatal: header backup -> off-host bucket; failure records escrow=missing,
#                     pages, and is retried on every boot. The FENCE is the soak marker (a header
#                     with no off-host copy never earns it), not the boot path.
# 78 = refused under xtrace (the passphrase is handled here).
#
# THE KEY never touches argv, a file, or the environment of a child: it is held in a shell
# variable and piped on stdin. DOPPLER_TOKEN is read from /etc/default/luks-monitor (the
# fresh-host scoped token cloud-init writes) and handed to the single doppler child only.
#
# TEST SEAM. WORKSPACES_PROVISION_TEST_SEAM=1 + WORKSPACES_PROVISION_ROOT=<abs dir> prefix every
# FILE path so the suite can run against a scratch tree; every external command is called by BARE
# name so a scratch PATH can intercept it. Nothing in production sets the seam, and outside it the
# prefix is the empty string.
set -uo pipefail
case "$-" in
  *x*)
    printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2
    exit 78
    ;;
esac
umask 077
: "${HOME:=/root}"
export HOME

ROOT=""
if [ "${WORKSPACES_PROVISION_TEST_SEAM:-0}" = "1" ]; then
  ROOT="${WORKSPACES_PROVISION_ROOT:-}"
  case "$ROOT" in
    ""|/|//|/.|*/../*|*/..) printf '[FATAL] test-seam root %s is empty, the filesystem root or contains ..; refusing\n' "$ROOT" >&2; exit 2 ;;
    /*) : ;;
    *) printf '[FATAL] test-seam root %s is RELATIVE; refusing\n' "$ROOT" >&2; exit 2 ;;
  esac
fi
readonly ROOT

ENVFILE="${ROOT}/etc/default/workspaces-luks-boot"
TOKFILE="${ROOT}/etc/default/luks-monitor"
CRYPTTAB="${ROOT}/etc/crypttab"
FSTAB="${ROOT}/etc/fstab"
DROPIN_DIR="${ROOT}/etc/systemd/system/docker.service.d"
DROPIN="$DROPIN_DIR/10-workspaces-luks-mount.conf"
STATE_DIR="${ROOT}/var/lib/soleur"
INTENT="$STATE_DIR/workspaces-luks-formatting"
RUN_DIR="${ROOT}/run/soleur"
ARM_FILE="$RUN_DIR/workspaces-luks-arm"
DETAIL_DIR="${SOLEUR_STAGE_DETAIL_DIR:-${ROOT}/run/soleur-stage-detail.d}"
MNT_DIR="${ROOT}/mnt/data"

MAPPER_NAME=workspaces
MAPPER="/dev/mapper/$MAPPER_NAME"
MNT=/mnt/data
# The canonical lines. BYTE-IDENTICAL to local.workspaces_boot_unlock_* in workspaces-luks.tf, which
# the web-1 SSH installer writes: fresh-boot-parity.test.sh pins the equality, so the two delivery
# paths cannot drift while both exist. (The by-id path is appended per host at config time.)
FSTAB_LINE='/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2'
DROPIN_BODY='[Unit]
RequiresMountsFor=/mnt/data
After=workspaces-luks-reopen.service
'

ARM=none
ESCROW=none
KEY=""
TOKEN=""
HDR_DIR=""

cleanup() {
  unset KEY TOKEN
  [ -z "$HDR_DIR" ] || { shred -u "$HDR_DIR"/* 2>/dev/null || rm -f "$HDR_DIR"/* 2>/dev/null || true; rmdir "$HDR_DIR" 2>/dev/null || true; }
}
trap cleanup EXIT

row() { # <arm> <rc> [detail]
  local line="SOLEUR_WORKSPACES_LUKS_PROVISION arm=$1 rc=$2${3:+ $3}"
  logger -t workspaces-luks-provision -- "$line" 2>/dev/null || true
  printf '%s\n' "$line" >&2
}

# The reason text is non-secret by construction (fixed words + validated tokens); the emitter
# redacts credential shapes again regardless.
fatal() { # <arm> <exit-code> <reason>
  mkdir -p "$DETAIL_DIR" 2>/dev/null || true
  printf 'arm=%s %s' "$1" "$3" > "$DETAIL_DIR/workspaces_luks_provision_$1" 2>/dev/null || true
  row "$1" "$2" "reason=$3"
  soleur-boot-emit "workspaces_luks_provision_$1" fatal 2>/dev/null || true
  exit "$2"
}

# ── config ────────────────────────────────────────────────────────────────────────────────────
_secure_file() { # <path>: regular, not a symlink, owned by the running uid, mode 600
  [ ! -L "$1" ] && [ -f "$1" ] || return 1
  [ "$(stat -c '%u' "$1" 2>/dev/null)" = "$(id -u)" ] || return 1
  [ "$(stat -c '%a' "$1" 2>/dev/null)" = 600 ] || return 1
}
_one() { # <file> <KEY>: the value of the single KEY= line, or fail (0 or 2+ lines is ambiguity)
  local n v
  n=$(grep -c "^$2=" "$1" 2>/dev/null) || n=0
  [ "$n" = 1 ] || return 1
  v=$(sed -n "s/^$2=//p" "$1")
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

_secure_file "$ENVFILE" || fatal config 10 "boot env file absent, not a regular file, or not root 0600"
DEV=$(_one "$ENVFILE" WORKSPACES_LUKS_DEV) || fatal config 10 "WORKSPACES_LUKS_DEV missing or ambiguous"
CFG=$(_one "$ENVFILE" WORKSPACES_DOPPLER_CONFIG) || fatal config 10 "WORKSPACES_DOPPLER_CONFIG missing or ambiguous"
[[ "$DEV" =~ ^/dev/disk/by-id/scsi-0HC_Volume_[0-9]+$ ]] || fatal config 10 "device pin is not a by-id Hetzner volume path"
[ "$CFG" = prd_workspaces_luks ] || fatal config 10 "doppler config is not the dedicated prd_workspaces_luks"
_secure_file "$TOKFILE" || fatal config 10 "luks-monitor env file absent, not a regular file, or not root 0600"
TOKEN=$(_one "$TOKFILE" DOPPLER_TOKEN) || fatal config 10 "DOPPLER_TOKEN missing or ambiguous in the luks-monitor env file"
CRYPTTAB_LINE="$MAPPER_NAME $DEV none luks,noauto"
for _c in blkid wipefs lsblk findmnt mountpoint doppler mkfs.ext4 curl blockdev; do
  command -v "$_c" >/dev/null 2>&1 || fatal config 10 "required command $_c is absent"
done
if ! command -v cryptsetup >/dev/null 2>&1; then
  timeout 300 apt-get install -y -o DPkg::Lock::Timeout=300 cryptsetup-bin >/dev/null 2>&1 || true
  command -v cryptsetup >/dev/null 2>&1 || fatal config 10 "cryptsetup is absent and could not be installed"
fi
mkdir -p "$RUN_DIR" "$STATE_DIR" || fatal config 10 "cannot create the run/state directories"

# ── device ────────────────────────────────────────────────────────────────────────────────────
_i=0
while :; do
  _sz=$(blockdev --getsize64 "$DEV" 2>/dev/null || true)
  if [[ "$_sz" =~ ^[0-9]+$ ]] && [ "$_sz" -gt 0 ]; then break; fi
  _i=$((_i + 1))
  [ "$_i" -lt 300 ] || fatal device 11 "device absent after 300s"
  sleep 1
done
[ -z "$(findmnt -rn -S "$DEV" 2>/dev/null || true)" ] || fatal device 11 "the device is mounted directly; refusing"

# ── the two chokepoints ───────────────────────────────────────────────────────────────────────
# DEVICE LEVEL: true only when the device carries NOTHING — no TYPE (blkid rc 2), no partition
# table (a GPT disk reads an empty TYPE), no signature wipefs can see, no child device, no mount.
_may_format() {
  local rc t pt wf
  rc=0; t=$(blkid -o value -s TYPE "$DEV" 2>/dev/null) || rc=$?
  [ "$rc" = 2 ] && [ -z "$t" ] || return 1
  rc=0; pt=$(blkid -p -o value -s PTTYPE "$DEV" 2>/dev/null) || rc=$?
  [ "$rc" = 2 ] && [ -z "$pt" ] || return 1
  rc=0; wf=$(wipefs "$DEV" 2>/dev/null) || rc=$?
  [ "$rc" = 0 ] && [ -z "$wf" ] || return 1
  [ "$(lsblk -nr -o NAME "$DEV" 2>/dev/null | grep -c .)" = 1 ] || return 1
  [ -z "$(findmnt -rn -S "$DEV" 2>/dev/null || true)" ] || return 1
  return 0
}
# MAPPER LEVEL: true only for a blank, unmounted mapper.
_may_format_fs() {
  local rc t wf
  rc=0; t=$(blkid -o value -s TYPE "$MAPPER" 2>/dev/null) || rc=$?
  [ "$rc" = 2 ] && [ -z "$t" ] || return 1
  rc=0; wf=$(wipefs "$MAPPER" 2>/dev/null) || rc=$?
  [ "$rc" = 0 ] && [ -z "$wf" ] || return 1
  [ -z "$(findmnt -rn -S "$MAPPER" 2>/dev/null || true)" ] || return 1
  return 0
}

# ── discriminate ──────────────────────────────────────────────────────────────────────────────
_rc=0
TYPE=$(blkid -o value -s TYPE "$DEV" 2>/dev/null) || _rc=$?
case "$_rc" in 0|2) : ;; *) fatal discriminate 12 "blkid could not read the device (rc=$_rc)" ;; esac
case "$TYPE" in
  crypto_LUKS) MODE=open ;;
  "")
    [ "$_rc" = 2 ] || fatal discriminate 12 "blkid rc 0 with no TYPE is ambiguous"
    _may_format || fatal discriminate 12 "empty TYPE but the device carries a partition table, a signature, a child or a mount; refusing"
    MODE=format
    ;;
  *)
    # The value is sanitized before it is shipped: it is attacker-shaped bytes read off a disk.
    fatal discriminate 12 "the device carries a $(printf '%s' "$TYPE" | tr -cd 'A-Za-z0-9_' | cut -c1-24) signature; refusing to touch it"
    ;;
esac

# ── key ───────────────────────────────────────────────────────────────────────────────────────
# THE R9-PINNED FORM: `doppler secrets get <NAME> --plain --config <scoped>` fetches ONE secret;
# `doppler run` / `secrets download` on this config would resolve the ~116 inherited prd secrets
# (CWE-522). The token reaches the single child through its environment, never argv.
_dget() { # <NAME>: print the secret, empty on any failure
  DOPPLER_TOKEN="$TOKEN" DOPPLER_ENABLE_VERSION_CHECK=false doppler secrets get "$1" --plain --config "$CFG" 2>/dev/null || true
}
_get_key() {
  local n=0
  while [ "$n" -lt 20 ]; do
    KEY=$(_dget WORKSPACES_LUKS_KEY)
    [ -z "$KEY" ] || return 0
    n=$((n + 1))
    [ "$n" -ge 20 ] || sleep 15
  done
  fatal key 13 "WORKSPACES_LUKS_KEY unavailable after 20 attempts"
}

# ── format / open ─────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = format ]; then
  _get_key
  # Re-run immediately before the destructive call: the state may have changed since discriminate.
  _may_format || fatal format 14 "device state changed after discriminate; refusing luksFormat"
  # The durable INTENT precedes luksFormat and outlives it until mkfs completes. Without it a
  # crash between the two leaves a LUKS container with a blank mapper that the open arm must
  # treat as a damaged store — on every later boot.
  printf '%s %s\n' "$DEV" "$(date +%s)" > "$INTENT.tmp" || fatal format 14 "cannot write the format intent file"
  mv "$INTENT.tmp" "$INTENT" || fatal format 14 "cannot install the format intent file"
  sync
  printf '%s' "$KEY" | cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV" >/dev/null 2>&1 \
    || fatal format 14 "luksFormat failed"
  printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME" >/dev/null 2>&1 \
    || fatal format 14 "luksOpen after luksFormat failed"
  _may_format_fs || fatal format 14 "the new mapper is not blank; refusing mkfs"
  mkfs.ext4 -q "$MAPPER" >/dev/null 2>&1 || fatal format 14 "mkfs.ext4 failed"
  rm -f "$INTENT"
  ARM=formatted
else
  _st=0
  cryptsetup status "$MAPPER_NAME" >/dev/null 2>&1 || _st=$?
  case "$_st" in
    0) ARM=noop ;;
    4)
      _get_key
      printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME" >/dev/null 2>&1 \
        || fatal open 15 "luksOpen failed (wrong passphrase, or a damaged header)"
      ARM=opened
      ;;
    *) fatal open 15 "cryptsetup status rc=$_st" ;;
  esac
  # The mapper's backing device must be the pin: a stale pin after a volume swap must not pass.
  _bk=$(cryptsetup status "$MAPPER_NAME" 2>/dev/null | awk '/^[[:space:]]*device:/{print $2; exit}')
  [ -n "$_bk" ] || fatal open 15 "cryptsetup status reports no backing device"
  _rb=$(realpath -m "$_bk" 2>/dev/null) && _rd=$(realpath -m "$DEV" 2>/dev/null) && [ -n "$_rb" ] && [ "$_rb" = "$_rd" ] \
    || fatal open 15 "the mapper is not backed by the pinned device"
  _frc=0
  _fst=$(blkid -o value -s TYPE "$MAPPER" 2>/dev/null) || _frc=$?
  if [ "$_frc" = 2 ] && [ -z "$_fst" ]; then
    # A blank mapper is acceptable in exactly one situation: THIS provisioner started the format
    # and was interrupted before mkfs (the intent file proves it). Anything else is a damaged store.
    [ -f "$INTENT" ] || fatal open 15 "LUKS container with no filesystem and no format intent: damaged store; refusing mkfs"
    _may_format_fs || fatal open 15 "blank-mapper recovery refused: the mapper is not blank or is mounted"
    mkfs.ext4 -q "$MAPPER" >/dev/null 2>&1 || fatal open 15 "mkfs.ext4 failed during interrupted-birth recovery"
    rm -f "$INTENT"
    ARM=formatted
  elif [ "$_frc" = 0 ] && [ "$_fst" = ext4 ]; then
    rm -f "$INTENT"
  else
    fatal open 15 "the mapper carries an unexpected filesystem state (rc=$_frc)"
  fi
fi
unset KEY

# ── wire ──────────────────────────────────────────────────────────────────────────────────────
# crypttab: append the canonical line if the mapper has none; a foreign `workspaces` line is
# refused, never coexisted with (web-1's installer refuses it with exit 32 for the same reason).
[ ! -L "$CRYPTTAB" ] || fatal wire 16 "crypttab is a symlink"
[ -e "$CRYPTTAB" ] || : > "$CRYPTTAB"
if grep -q '^[[:space:]]*workspaces[[:space:]]' "$CRYPTTAB"; then
  [ "$(grep -c '^[[:space:]]*workspaces[[:space:]]' "$CRYPTTAB")" = 1 ] && grep -qxF "$CRYPTTAB_LINE" "$CRYPTTAB" \
    || fatal wire 16 "a foreign workspaces crypttab line exists; refusing to coexist"
else
  printf '%s\n' "$CRYPTTAB_LINE" >> "$CRYPTTAB" || fatal wire 16 "cannot append the crypttab line"
fi
# fstab: exactly ONE non-comment /mnt/data entry and it is the canonical mapper line. Anything else
# naming /mnt/data is commented in place (kept as evidence), never deleted.
[ ! -L "$FSTAB" ] || fatal wire 16 "fstab is a symlink"
[ -e "$FSTAB" ] || : > "$FSTAB"
_ft="$FSTAB.provision.tmp"
awk -v canon="$FSTAB_LINE" '
  { m = $2; sub(/\/+$/, "", m)
    if ($1 !~ /^#/ && m == "/mnt/data") {
      if ($0 == canon && !seen) { print; seen = 1 } else print "# provision-6931-superseded " $0
    } else print }
  END { if (!seen) print canon }' "$FSTAB" > "$_ft" || fatal wire 16 "fstab rewrite failed"
[ "$(awk '{ m=$2; sub(/\/+$/,"",m); if ($1 !~ /^#/ && m == "/mnt/data") n++ } END { print n+0 }' "$_ft")" = 1 ] \
  && grep -qxF "$FSTAB_LINE" "$_ft" || { rm -f "$_ft"; fatal wire 16 "the rewritten fstab does not hold exactly one canonical /mnt/data line"; }
mv "$_ft" "$FSTAB" || fatal wire 16 "cannot install the rewritten fstab"
# The covered root-disk inode is made immutable BEFORE anything is mounted on it, so that if the
# mapper is ever absent a container's implicit bind-mount mkdir is refused (an outage) instead of
# silently writing sole user data to the plaintext root disk (the #5274 data-stranding mode).
mkdir -p "$MNT_DIR" || fatal wire 16 "cannot create the mountpoint"
if ! mountpoint -q "$MNT" 2>/dev/null; then
  chattr +i "$MNT_DIR" || fatal wire 16 "chattr +i on the covered mountpoint failed"
  case "$(lsattr -d "$MNT_DIR" 2>/dev/null | awk '{print $1}')" in
    *i*) : ;;
    *) fatal wire 16 "lsattr does not show the immutable flag on the covered mountpoint" ;;
  esac
fi
mkdir -p "$DROPIN_DIR" || fatal wire 16 "cannot create the docker drop-in directory"
printf '%s' "$DROPIN_BODY" > "$DROPIN" || fatal wire 16 "cannot write the docker drop-in"
chmod 644 "$DROPIN"
systemctl daemon-reload 2>/dev/null || true
if ! mountpoint -q "$MNT" 2>/dev/null; then
  mount "$MNT" >/dev/null 2>&1 || fatal mount 17 "mount $MNT failed"
fi
[ "$(findmnt -n -o SOURCE "$MNT" 2>/dev/null)" = "$MAPPER" ] || fatal mount 17 "$MNT is not mounted from $MAPPER"
systemctl enable workspaces-luks-reopen.service workspaces-luks-reopen.timer >/dev/null 2>&1 \
  || row wire 0 "warn=reopen_units_not_enabled"
systemctl start --no-block workspaces-luks-reopen.timer >/dev/null 2>&1 || true
# The daily at-rest probe (standby profile: /etc/default/luks-monitor carries LUKS_MONITOR_PROFILE=standby).
# Enabled here, not by cloud-init, so the user_data pays zero bytes for it. The unit is deliberately NOT
# kicked: luks-monitor-install.test.sh Row 10 pins that exactly one line anywhere starts
# luks-monitor.service (rows with _SYSTEMD_UNIT=luks-monitor.service are what the host-timer-dark alert
# counts), so the first probe row arrives with the timer's first daily fire instead. Non-fatal: a probe
# fault pages on its own channel and must not hold an empty standby dark.
systemctl enable --now luks-monitor.timer >/dev/null 2>&1 || row wire 0 "warn=luks_monitor_timer_not_enabled"

# ── escrow (NON-fatal) ────────────────────────────────────────────────────────────────────────
# After BOTH the format and open arms and idempotent (check, then upload), so a crash between the
# format and the upload self-heals on the next boot. The transport is curl's SigV4 signer so no
# aws-cli install is needed on a fresh host; credentials go in via `--config -` on stdin, never
# argv. A failure here must NOT hold an empty standby dark: it records escrow=missing and pages.
_escrow() {
  local bucket kid sec ep uuid key sz sha code len
  bucket=$(_dget WORKSPACES_HEADER_BUCKET); kid=$(_dget WORKSPACES_HEADER_R2_ACCESS_KEY_ID)
  sec=$(_dget WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY); ep=$(_dget WORKSPACES_HEADER_R2_ENDPOINT)
  if [ -z "$bucket" ] || [ -z "$kid" ] || [ -z "$sec" ] || [ -z "$ep" ]; then ESCROW_WHY=creds; return 1; fi
  [[ "$bucket" =~ ^[a-z0-9][a-z0-9.-]*$ ]] && [[ "$ep" =~ ^https://[A-Za-z0-9.-]+$ ]] || { ESCROW_WHY=shape; return 1; }
  uuid=$(cryptsetup luksUUID "$DEV" 2>/dev/null) || uuid=""
  [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || { ESCROW_WHY=uuid; return 1; }
  HDR_DIR=$(mktemp -d "${ROOT}/run/soleur-lukshdr.XXXXXXXX") || { ESCROW_WHY=tmp; return 1; }
  cryptsetup luksHeaderBackup "$DEV" --header-backup-file "$HDR_DIR/hdr.img" >/dev/null 2>&1 || { ESCROW_WHY=backup; return 1; }
  sz=$(stat -c %s "$HDR_DIR/hdr.img" 2>/dev/null) || sz=0
  [ "$sz" -gt 0 ] || { ESCROW_WHY=backup; return 1; }
  sha=$(sha256sum "$HDR_DIR/hdr.img" | cut -d' ' -f1)
  key="workspaces-luks-header-${uuid}.img"
  _curl() { printf 'user = "%s:%s"\n' "$kid" "$sec" | curl --disable --noproxy '*' --config - --aws-sigv4 'aws:amz:auto:s3' -sS --max-time 120 "$@"; }
  # CHECK: an object of the right size already exists -> nothing to do.
  code=$(_curl -I -o /dev/null -D "$HDR_DIR/h" -w '%{http_code}' "$ep/$bucket/$key" 2>/dev/null) || code=000
  len=$(awk 'tolower($1)=="content-length:"{gsub("\r",""); print $2+0; exit}' "$HDR_DIR/h" 2>/dev/null)
  if [ "$code" = 200 ] && [ "${len:-0}" = "$sz" ]; then return 0; fi
  # UPLOAD, then read back.
  code=$(_curl -T "$HDR_DIR/hdr.img" -H "x-amz-content-sha256: $sha" -o /dev/null -w '%{http_code}' "$ep/$bucket/$key" 2>/dev/null) || code=000
  case "$code" in 2??) : ;; *) ESCROW_WHY=put; return 1 ;; esac
  code=$(_curl -I -o /dev/null -D "$HDR_DIR/h" -w '%{http_code}' "$ep/$bucket/$key" 2>/dev/null) || code=000
  len=$(awk 'tolower($1)=="content-length:"{gsub("\r",""); print $2+0; exit}' "$HDR_DIR/h" 2>/dev/null)
  [ "$code" = 200 ] && [ "${len:-0}" = "$sz" ] || { ESCROW_WHY=readback; return 1; }
  return 0
}
ESCROW_WHY=none
if _escrow; then
  ESCROW=ok
else
  ESCROW=missing
  mkdir -p "$DETAIL_DIR" 2>/dev/null || true
  printf 'arm=escrow reason=%s' "$ESCROW_WHY" > "$DETAIL_DIR/workspaces_luks_provision_escrow" 2>/dev/null || true
  row escrow 0 "reason=$ESCROW_WHY escrow=missing"
  soleur-boot-emit workspaces_luks_provision_escrow fatal 2>/dev/null || true
fi

# ── result ────────────────────────────────────────────────────────────────────────────────────
printf 'luks_arm=%s\nescrow=%s\n' "$ARM" "$ESCROW" > "$ARM_FILE" || row result 0 "warn=arm_file_unwritable"
row result 0 "luks_arm=$ARM escrow=$ESCROW"
exit 0

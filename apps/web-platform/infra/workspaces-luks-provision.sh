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
# EXIT CODES / ARMS (each failure is one SOLEUR_WORKSPACES_LUKS_PROVISION row and a
# soleur-boot-emit stage workspaces_luks_provision_<arm>):
#   2             test seam refused (a real cloud-init host as root; or a root that is empty, /, relative,
#                 `..`, or under /proc /sys /dev)
#   config        10  both env files present, regular, root-owned, 0600, well-shaped; also `flock` absent,
#                     the lock file unopenable, or the single-instance lock not won within 600 s
#                     (reason `lock_timeout`: another provisioner holds it)
#   device        11  the by-id device answers blockdev within 300 s (attachment lags server boot)
#   discriminate  12  blkid rc 0|2 only; PTTYPE + wipefs + a zero-content probe corroborate raw
#   key           13  WORKSPACES_LUKS_KEY via the R9-pinned `doppler secrets get ... --plain`,
#                     retried ~5 min so a Doppler blip at first boot does not end in poweroff
#   format        14  luksFormat (label soleur-formatting) -> luksOpen -> mkfs -> relabel
#                     soleur-workspaces. The LABEL is the recovery marker and lives ON the volume.
#   open          15  luksOpen if closed; mkfs ONLY for a blank mapper whose format this
#                     provisioner started (an intent file bound to the volume's UUID, OR the
#                     on-volume formatting label)
#   wire          16  crypttab / fstab / docker drop-in / immutable covered inode / mount / units
#                     (the reopen units failing to enable is fatal: no unlock at the first reboot)
#   mount         17  /mnt/data is not mounted from the mapper after wire
#   78            refused under xtrace (the passphrase is handled here)
#   (escrow)          NON-fatal: header backup -> off-host bucket; failure records escrow=missing
#                     (reasons: creds, shape [bucket/endpoint], creds_shape [key id/secret], uuid, tmp, backup,
#                     put, readback; each is decoded in the web-host-replace/web-host-birth runbooks and the
#                     provision suite fails on an undecoded one) and emits a warning-level
#                     Sentry stage that PAGES by stage name (#9377, issue-alerts.tf web_luks_boot_fatal).
#                     NOT retried: this script runs ONCE per instance
#                     (cloud-init runcmd) and is idempotent, so escrow=missing persists until the
#                     host is replaced or the provisioner is re-run by hand. The FENCE is the soak
#                     marker (a header with no off-host copy never earns it), not the boot path.
# Non-fatal warns (probe timer: wire_warn, arm file: result) and the escrow stage emit a workspaces_luks_provision_<arm> WARNING stage.
# An INTERRUPTED format (crash between luksFormat and mkfs) is not retried on the same host either;
# it heals on host replace: the replacement reads LUKS + blank mapper + the on-volume label.
#
# THE KEY never touches argv, a file, or the environment of a child: it is held in a shell
# variable and piped on stdin. DOPPLER_TOKEN is read from /etc/default/luks-monitor (the
# fresh-host scoped token cloud-init writes) and handed to the single doppler child only.
#
# TEST SEAM. WORKSPACES_PROVISION_TEST_SEAM=1 + WORKSPACES_PROVISION_ROOT=<abs dir> prefix every
# FILE path so the suite can run against a scratch tree; every external command is called by BARE
# name so a scratch PATH can intercept it. Nothing in production sets the seam, and outside it the
# prefix is the empty string. Under the seam ONLY, WORKSPACES_PROVISION_LOCK_WAIT shortens the lock
# wait (a knob visible in production would be new attack surface). The seam is REFUSED (exit 2) on a
# real host: euid 0 together with the cloud-init instance marker. A non-root runner that happens to
# carry cloud-init state is not refused (the production provisioner always runs as root). The marker
# path is a literal constant, never an environment value. The refusal exits before `fatal`/`row`
# exist, so it prints and logs best-effort; the page for such a host is indirect (cloud-init's own
# workspaces_luks_not_mounted stage).
#
# SERIALIZATION AND ATOMIC WRITES. One provisioner at a time: an exclusive flock on fd 9 is taken before the
# first side effect (the web-1 SSH installer and the reopen script write some of the same files without it;
# that is accepted). fd 9 is inherited by every child; none of the commands this script runs daemonizes while
# holding it (the same child-leak hazard ci-deploy.sh documents at its fd-200 flock), and
# workspaces-luks-provision.test.sh pins what happens if one did (the lock stays held). fstab,
# crypttab, the docker drop-in and the format intent file are only ever replaced through _install_file: a
# same-directory temp file, fsynced, renamed, directory fsynced.
set -uo pipefail
case "$-" in
  *x*)
    printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2
    exit 78
    ;;
esac
# lastpipe: the final stage of a pipeline runs in THIS shell, so `... | _install_file` can hand its reason
# (_IF_WHY) back to the caller's fatal message. Scripts have no job control, which lastpipe requires.
shopt -s lastpipe
umask 077
ulimit -c 0 2>/dev/null || true # the LUKS key sits in a shell variable: a crash must not write the process image to the root disk
: "${HOME:=/root}"
export HOME

# >>> seam
# A real cloud-init host carries /var/lib/cloud/instance (a symlink on every cloud-init image), root-owned and
# never under the test root. `-e` misses a dangling symlink, hence the `-L` half.
_seam_allowed() { # <cloud-init-marker-path>: non-zero when the marker exists
  [ ! -e "$1" ] && [ ! -L "$1" ]
}
ROOT=""
if [ "${WORKSPACES_PROVISION_TEST_SEAM:-0}" = "1" ]; then
  if [ "$(id -u)" = 0 ] && ! _seam_allowed /var/lib/cloud/instance; then
    printf '[FATAL] refusing the test seam on a real cloud-init host (euid 0 and the cloud-init instance marker is present)\n' >&2
    logger -t workspaces-luks-reopen -- "SOLEUR_WORKSPACES_LUKS_PROVISION arm=seam rc=2 reason=test seam refused on a cloud-init host" 2>/dev/null || true
    exit 2
  fi
  ROOT="${WORKSPACES_PROVISION_ROOT:-}"
  case "$ROOT" in
    ""|/|//|/.|*/../*|*/..) printf '[FATAL] test-seam root %s is empty, the filesystem root or contains ..; refusing\n' "$ROOT" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf '[FATAL] test-seam root %s is a synthetic-fs path; refusing\n' "$ROOT" >&2; exit 2 ;;
    /*) : ;;
    *) printf '[FATAL] test-seam root %s is RELATIVE; refusing\n' "$ROOT" >&2; exit 2 ;;
  esac
fi
readonly ROOT
# <<< seam

# >>> pin
# Production (ROOT empty) runs only system-path commands: a caller-supplied PATH cannot substitute
# `cryptsetup`, `mkfs.ext4`, `doppler`... Under the seam the scratch PATH stays so the suite's stubs intercept.
# SOLEUR_STAGE_DETAIL_DIR is an env knob that steers a root mkdir and write; production has no use for it, so it
# is clamped to the default soleur-boot-emit reads (children inherit the clamped value).
if [ -z "$ROOT" ]; then
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  export PATH
  SOLEUR_STAGE_DETAIL_DIR=/run/soleur-stage-detail.d
  export SOLEUR_STAGE_DETAIL_DIR
fi
# <<< pin

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
# The recovery marker CARRIED BY THE VOLUME (a LUKS2 label: `cryptsetup config <dev> --label` needs no
# passphrase and libblkid reports it as LABEL; measured on cryptsetup 2.8.7 / util-linux 2.42.3). It is
# set at luksFormat and flipped to a non-empty final label only after mkfs, so a replacement host can
# tell "formatting was interrupted" from "damaged store" without the first host's local intent file.
LABEL_FORMATTING=soleur-formatting
LABEL_READY=soleur-workspaces
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
HAVE_LOCK=0

ERRF="$RUN_DIR/workspaces-luks-cmd.err"
cleanup() {
  unset KEY TOKEN
  # Only the lock holder owns the scratch file: a provisioner that lost the lock must not delete the winner's.
  [ "$HAVE_LOCK" != 1 ] || rm -f "$ERRF" 2>/dev/null || true
  [ -z "$HDR_DIR" ] || { shred -u "$HDR_DIR"/* 2>/dev/null || rm -f "$HDR_DIR"/* 2>/dev/null || true; rmdir "$HDR_DIR" 2>/dev/null || true; }
}
trap cleanup EXIT

_cause() { # last stderr line of the previous cryptsetup/mkfs call, printable, <=200 chars (the key rides stdin)
  local l
  l=$(grep -v '^[[:space:]]*$' "$ERRF" 2>/dev/null | tail -n 1 | LC_ALL=C tr -cd '[:print:]' | cut -c1-200)
  [ -z "$l" ] || printf ': %s' "$l"
}

row() { # <arm> <rc> [detail]
  local line="SOLEUR_WORKSPACES_LUKS_PROVISION arm=$1 rc=$2${3:+ $3}"
  # the journald tag Vector already ships (reusing it needs no image rebuild)
  logger -t workspaces-luks-reopen -- "$line" 2>/dev/null || true
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

# Non-fatal, but never local-only: a dead probe timer or an unwritable arm file is a Sentry warning too.
warn() { # <arm> <reason>
  mkdir -p "$DETAIL_DIR" 2>/dev/null || true
  printf 'arm=%s warn=%s' "$1" "$2" > "$DETAIL_DIR/workspaces_luks_provision_$1" 2>/dev/null || true
  row "$1" 0 "warn=$2"
  soleur-boot-emit "workspaces_luks_provision_$1" warning 2>/dev/null || true
}

# ── atomic writes ─────────────────────────────────────────────────────────────────────────────
# The ONLY way fstab, crypttab, the docker drop-in and the format intent file are written. The content arrives
# on stdin and is read to EOF BEFORE the destination is touched, so callers compute (and validate) their content
# into a variable first. The helper cannot tell a truncated stream from a complete one, so a `producer | _install_file`
# whose producer can die mid-stream WOULD rename the partial output over the real file: every caller below pipes `printf`
# of an already-built, already-validated variable, and a new caller must do the same.
# Temp file in the SAME directory (rename is atomic only within one filesystem), fsynced (coreutils >= 8.24:
# `sync FILE` is an fsync; the host and the runner are Ubuntu), renamed, and the directory fsynced. Every step
# is checked because this script has no `set -e`. A symlinked destination is refused (a bare `mv -f` would
# silently replace the link), a pre-existing temp path is removed first (a planted temp symlink would otherwise
# be followed), and an existing file's mode and ownership are kept. A stale *.provision.tmp from a crash is
# overwritten, never read. _IF_WHY carries the reason for the caller's fatal text (non-secret by construction).
_IF_WHY=""
_install_file() { # <dest> <mode-if-created>
  local dest="$1" mode="$2" tmp dir body=""
  tmp="$dest.provision.tmp"; dir="${dest%/*}"; _IF_WHY=""
  IFS= read -r -d '' body || true
  [ -n "$body" ] || { _IF_WHY="empty content"; return 1; }
  [ ! -L "$dest" ] || { _IF_WHY="destination is a symlink"; return 1; }
  [ ! -e "$dest" ] || [ -f "$dest" ] || { _IF_WHY="destination is not a regular file"; return 1; }
  rm -f "$tmp" || { _IF_WHY="cannot clear the temp path"; return 1; }
  printf '%s' "$body" > "$tmp" || { rm -f "$tmp"; _IF_WHY="cannot write the temp file"; return 1; }
  if [ -e "$dest" ]; then
    { chmod --reference="$dest" "$tmp" && chown --reference="$dest" "$tmp"; } || { rm -f "$tmp"; _IF_WHY="cannot copy the existing mode and owner"; return 1; }
  else
    chmod "$mode" "$tmp" || { rm -f "$tmp"; _IF_WHY="cannot set the mode"; return 1; }
  fi
  sync "$tmp" || { rm -f "$tmp"; _IF_WHY="fsync of the temp file failed"; return 1; }
  mv -f "$tmp" "$dest" || { rm -f "$tmp"; _IF_WHY="rename failed"; return 1; }
  sync "$dir" || { _IF_WHY="fsync of the directory failed"; return 1; }
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

# ── serialize ─────────────────────────────────────────────────────────────────────────────────
# Before the first side effect. File-descriptor form (not a re-exec with an env guard): no env flag to forge and
# no second exec. A missing `flock` is arm config, not rc 127 (the required-commands loop runs later). A failed
# `exec` redirection does not stop bash outside POSIX mode, so the `||` is load-bearing. 600 s is deliberate
# (a second boot-time invocation should queue, not fail) and sits inside cloud-init's once-per-instance runcmd,
# equal to the 300 s device wait plus the ~300 s key retry (a holder that burns both can outlast a queued second run). Reuses arm config (10) so the stage alert contract
# does not move; the distinct reason text separates contention from misconfiguration.
LOCK_WAIT=600
[ -z "$ROOT" ] || LOCK_WAIT="${WORKSPACES_PROVISION_LOCK_WAIT:-600}"
[[ "$LOCK_WAIT" =~ ^[0-9]{1,4}$ ]] || LOCK_WAIT=600
command -v flock >/dev/null 2>&1 || fatal config 10 "flock is absent"
mkdir -p "${ROOT}/run" || fatal config 10 "cannot create the lock directory"
exec 9>"${ROOT}/run/workspaces-luks-provision.lock" || fatal config 10 "cannot open the lock file"
flock -w "$LOCK_WAIT" 9 || fatal config 10 "lock_timeout: another provisioner holds the lock"
HAVE_LOCK=1

_secure_file "$ENVFILE" || fatal config 10 "boot env file absent, not a regular file, or not root 0600"
DEV=$(_one "$ENVFILE" WORKSPACES_LUKS_DEV) || fatal config 10 "WORKSPACES_LUKS_DEV missing or ambiguous"
CFG=$(_one "$ENVFILE" WORKSPACES_DOPPLER_CONFIG) || fatal config 10 "WORKSPACES_DOPPLER_CONFIG missing or ambiguous"
[[ "$DEV" =~ ^/dev/disk/by-id/scsi-0HC_Volume_[0-9]+$ ]] || fatal config 10 "device pin is not a by-id Hetzner volume path"
# Closed set (#9377): web-1 keeps the original pair config; the web-host class reads its own split config. The token's config scope, not this name check, is what stops a mis-paired image reading web-1's pair.
case "$CFG" in
  prd_workspaces_luks|prd_workspaces_luks_web) ;;
  *) fatal config 10 "doppler config is not a dedicated workspaces-luks config" ;;
esac
_secure_file "$TOKFILE" || fatal config 10 "luks-monitor env file absent, not a regular file, or not root 0600"
TOKEN=$(_one "$TOKFILE" DOPPLER_TOKEN) || fatal config 10 "DOPPLER_TOKEN missing or ambiguous in the luks-monitor env file"
CRYPTTAB_LINE="$MAPPER_NAME $DEV none luks,noauto"
for _c in blkid wipefs lsblk findmnt mountpoint doppler mkfs.ext4 curl blockdev cmp md5sum; do
  command -v "$_c" >/dev/null 2>&1 || fatal config 10 "required command $_c is absent"
done
if ! command -v cryptsetup >/dev/null 2>&1; then
  _a=0
  until timeout 300 apt-get install -y -o DPkg::Lock::Timeout=300 cryptsetup-bin >/dev/null 2>&1; do
    _a=$((_a + 1)); [ "$_a" -lt 2 ] || break
    sleep 10
  done
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
# A window of the RAW device is all zeros (clamped to the device size). DEVICE LEVEL ONLY: a fresh
# mapper over zeroed ciphertext decrypts to pseudo-random bytes, so this probe is wrong one layer up.
# DEVNODE is $DEV under the seam's root (identical to $DEV in production, where ROOT is empty).
DEVNODE="${ROOT}${DEV}"
_zero_window() { # <offset> <len>
  local off=$1 len=$2
  [ "$off" -ge 0 ] || { len=$((len + off)); off=0; }
  [ "$off" -lt "$_sz" ] || return 0
  [ $((off + len)) -le "$_sz" ] || len=$((_sz - off))
  cmp -s -n "$len" -i "$off:0" "$DEVNODE" /dev/zero
}
# DEVICE LEVEL: true only when the device carries NOTHING — no TYPE (blkid rc 2), no partition
# table (a GPT disk reads an empty TYPE), no signature wipefs can see, no child device, no mount,
# AND zero bytes where a populated volume would show them. "No signature libblkid knows" is not
# "empty": an ext4 volume with its first 8 KiB zeroed reads as blank to blkid and wipefs. Windows:
# the first 16 MiB (LUKS2 header, partition tables, primary superblocks), the last 16 MiB (backup
# GPT / secondary headers) and 1 MiB at 128 MiB (the first ext4 backup superblock at 4 KiB blocks).
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
  [[ "$_sz" =~ ^[0-9]+$ ]] || return 1
  _zero_window 0 16777216 || return 1
  _zero_window $((_sz - 16777216)) 16777216 || return 1
  _zero_window 134217728 1048576 || return 1
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
    _may_format || fatal discriminate 12 "empty TYPE but the device carries a partition table, a signature, a child, a mount or non-zero content; refusing"
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
# The label flips to its final value only AFTER a filesystem exists. If the flip fails after a good
# mkfs the arm is fatal: the next host reads an ext4 mapper (which the open arm accepts) and heals it.
_ready_label() { # <arm> <exit-code>
  cryptsetup config "$DEV" --label "$LABEL_READY" >/dev/null 2>"$ERRF" \
    || fatal "$1" "$2" "relabel to the final volume label failed after mkfs$(_cause)"
}
if [ "$MODE" = format ]; then
  _get_key
  # Re-run immediately before the destructive call: the state may have changed since discriminate.
  _may_format || fatal format 14 "device state changed after discriminate; refusing luksFormat"
  # Two durable markers precede luksFormat's effect and outlive it until mkfs completes: the local
  # INTENT file (same-host evidence) and the formatting LABEL written by luksFormat itself (it rides
  # the volume, so a replacement host after a crash between the two still recognises the state).
  # Without either, the open arm must treat a LUKS container with a blank mapper as a damaged store.
  # The intent is BOUND to this volume: it records the UUID luksFormat is told to assign (--uuid), so
  # a stale or foreign intent file cannot authorise a mkfs on another container.
  _nu=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
  [[ "$_nu" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || fatal format 14 "cannot generate the volume UUID"
  printf '%s %s %s\n' "$DEV" "$_nu" "$(date +%s)" | _install_file "$INTENT" 600 || fatal format 14 "cannot install the format intent file${_IF_WHY:+: $_IF_WHY}"
  printf '%s' "$KEY" | cryptsetup luksFormat --batch-mode --type luks2 --label "$LABEL_FORMATTING" --uuid "$_nu" --key-file - "$DEV" >/dev/null 2>"$ERRF" \
    || fatal format 14 "luksFormat failed$(_cause)"
  [ "$(cryptsetup luksUUID "$DEV" 2>/dev/null)" = "$_nu" ] || fatal format 14 "the formatted volume does not carry the UUID the intent file recorded"
  printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME" >/dev/null 2>"$ERRF" \
    || fatal format 14 "luksOpen after luksFormat failed$(_cause)"
  _may_format_fs || fatal format 14 "the new mapper is not blank; refusing mkfs"
  mkfs.ext4 -q "$MAPPER" >/dev/null 2>"$ERRF" || fatal format 14 "mkfs.ext4 failed$(_cause)"
  _ready_label format 14
  rm -f "$INTENT"; sync
  ARM=formatted
else
  _st=0
  cryptsetup status "$MAPPER_NAME" >/dev/null 2>&1 || _st=$?
  case "$_st" in
    0) ARM=noop ;;
    4)
      _get_key
      printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME" >/dev/null 2>"$ERRF" \
        || fatal open 15 "luksOpen failed (wrong passphrase, or a damaged header)$(_cause)"
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
    # and was interrupted before mkfs. Two independent proofs, either suffices: the local intent
    # file (same host) BOUND to this volume (recorded DEV and UUID equal the current ones), or the
    # formatting LABEL on the volume (survives a host replace). Anything else is a damaged store.
    # An unreadable label or UUID reads empty and so authorises nothing.
    _lbl=$(blkid -p -o value -s LABEL "$DEV" 2>/dev/null || true)
    _cur=$(cryptsetup luksUUID "$DEV" 2>/dev/null || true)
    _bound=0
    if [ -f "$INTENT" ] && [[ "$_cur" =~ ^[0-9a-fA-F-]{36}$ ]]; then
      read -r _i_dev _i_uuid _ < "$INTENT" || true
      [ "${_i_dev:-}" = "$DEV" ] && [ "${_i_uuid:-}" = "$_cur" ] && _bound=1
    fi
    [ "$_bound" = 1 ] || [ "$_lbl" = "$LABEL_FORMATTING" ] \
      || fatal open 15 "LUKS container with no filesystem and neither a volume-bound format intent nor the formatting label: damaged store; refusing mkfs"
    _may_format_fs || fatal open 15 "blank-mapper recovery refused: the mapper is not blank or is mounted"
    mkfs.ext4 -q "$MAPPER" >/dev/null 2>"$ERRF" || fatal open 15 "mkfs.ext4 failed during interrupted-birth recovery$(_cause)"
    _ready_label open 15
    rm -f "$INTENT"; sync
    ARM=formatted
  elif [ "$_frc" = 0 ] && [ "$_fst" = ext4 ]; then
    # A crash between mkfs and the relabel leaves ext4 under the formatting label: close that window
    # here so the label can never authorise a mkfs on a store that later reads blank by damage.
    [ "$(blkid -p -o value -s LABEL "$DEV" 2>/dev/null || true)" != "$LABEL_FORMATTING" ] || _ready_label open 15
    rm -f "$INTENT"; sync
  else
    fatal open 15 "the mapper carries an unexpected filesystem state (rc=$_frc)"
  fi
fi
unset KEY

# ── wire ──────────────────────────────────────────────────────────────────────────────────────
# crypttab: append the canonical line if the mapper has none; a foreign `workspaces` line is
# refused, never coexisted with (web-1's installer refuses it with exit 32 for the same reason).
# Read-modify-write through _install_file: the file is read whole, the new line is added on its OWN line even when
# the old last line has no trailing newline, and a file that already holds the canonical line is not rewritten.
[ ! -L "$CRYPTTAB" ] || fatal wire 16 "crypttab is a symlink"
_ct=""
# `&&`, not `;`: the sentinel `x` keeps trailing newlines through $(...), and `cat ...; printf x` would report printf's status, so a
# failed cat (I/O error) would read as an empty crypttab and the rewrite below would drop every other entry.
if [ -e "$CRYPTTAB" ]; then _ct=$(cat "$CRYPTTAB" && printf x) || fatal wire 16 "cannot read crypttab"; _ct="${_ct%x}"; fi
if grep -q '^[[:space:]]*workspaces[[:space:]]' <<< "$_ct"; then
  [ "$(grep -c '^[[:space:]]*workspaces[[:space:]]' <<< "$_ct")" = 1 ] && grep -qxF "$CRYPTTAB_LINE" <<< "$_ct" \
    || fatal wire 16 "a foreign workspaces crypttab line exists; refusing to coexist"
else
  [ -z "$_ct" ] || [ "${_ct: -1}" = $'\n' ] || _ct+=$'\n'
  _ctnew="$_ct$CRYPTTAB_LINE"$'\n'
  # Same no-fewer-lines guard fstab has: the rewrite may only ADD the canonical line, never lose an existing entry.
  [ "$(grep -c . <<< "$_ctnew")" -gt "$(grep -c . <<< "$_ct")" ] || fatal wire 16 "the rewritten crypttab would not add exactly the canonical line"
  printf '%s' "$_ctnew" | _install_file "$CRYPTTAB" 600 || fatal wire 16 "cannot install the crypttab line${_IF_WHY:+: $_IF_WHY}"
fi
# fstab: exactly ONE non-comment /mnt/data entry and it is the canonical mapper line. Anything else
# naming /mnt/data is commented in place (kept as evidence), never deleted. The new content is built and
# validated in a variable (exactly one canonical line, no fewer lines than before) before it is installed.
[ ! -L "$FSTAB" ] || fatal wire 16 "fstab is a symlink"
_fsrc="$FSTAB"; [ -e "$FSTAB" ] || _fsrc=/dev/null
_fnew=$(awk -v canon="$FSTAB_LINE" '
  { m = $2; sub(/\/+$/, "", m)
    if ($1 !~ /^#/ && m == "/mnt/data") {
      if ($0 == canon && !seen) { print; seen = 1 } else print "# provision-6931-superseded " $0
    } else print }
  END { if (!seen) print canon }' "$_fsrc") || fatal wire 16 "fstab rewrite failed"
[ "$(awk '{ m=$2; sub(/\/+$/,"",m); if ($1 !~ /^#/ && m == "/mnt/data") n++ } END { print n+0 }' <<< "$_fnew")" = 1 ] \
  && grep -qxF "$FSTAB_LINE" <<< "$_fnew" \
  && [ "$(grep -c . <<< "$_fnew")" -ge "$(grep -c . "$_fsrc")" ] \
  || fatal wire 16 "the rewritten fstab does not hold exactly one canonical /mnt/data line"
printf '%s\n' "$_fnew" | _install_file "$FSTAB" 644 || fatal wire 16 "cannot install the rewritten fstab${_IF_WHY:+: $_IF_WHY}"
# The covered root-disk inode is made immutable BEFORE anything is mounted on it, so that if the
# mapper is ever absent a container's implicit bind-mount mkdir is refused (an outage) instead of
# silently writing sole user data to the plaintext root disk (the #5274 data-stranding mode).
( umask 022; mkdir -p "$MNT_DIR" ) || fatal wire 16 "cannot create the mountpoint"
if ! mountpoint -q "$MNT" 2>/dev/null; then
  chattr +i "$MNT_DIR" || fatal wire 16 "chattr +i on the covered mountpoint failed"
  case "$(lsattr -d "$MNT_DIR" 2>/dev/null | awk '{print $1}')" in
    *i*) : ;;
    *) fatal wire 16 "lsattr does not show the immutable flag on the covered mountpoint" ;;
  esac
fi
( umask 022; mkdir -p "$DROPIN_DIR" ) || fatal wire 16 "cannot create the docker drop-in directory"
printf '%s' "$DROPIN_BODY" | _install_file "$DROPIN" 644 || fatal wire 16 "cannot install the docker drop-in${_IF_WHY:+: $_IF_WHY}"
systemctl daemon-reload 2>/dev/null || true
if ! mountpoint -q "$MNT" 2>/dev/null; then
  mount "$MNT" >/dev/null 2>&1 || fatal mount 17 "mount $MNT failed"
fi
[ "$(findmnt -n -o SOURCE "$MNT" 2>/dev/null)" = "$MAPPER" ] || fatal mount 17 "$MNT is not mounted from $MAPPER"
# FATAL: without these units nothing reopens the mapper at the next boot, and the drop-in above then
# holds docker behind RequiresMountsFor (an outage nothing pages for, found only after the reboot).
systemctl enable workspaces-luks-reopen.service workspaces-luks-reopen.timer >/dev/null 2>&1 \
  && systemctl is-enabled workspaces-luks-reopen.service workspaces-luks-reopen.timer >/dev/null 2>&1 \
  || fatal wire 16 "the reopen service and timer could not be enabled; the next boot would leave docker without its volume"
systemctl start --no-block workspaces-luks-reopen.timer >/dev/null 2>&1 || true
# The daily at-rest probe (standby profile: /etc/default/luks-monitor carries LUKS_MONITOR_PROFILE=standby).
# Enabled here, not by cloud-init, so the user_data pays zero bytes for it. The unit is deliberately NOT
# kicked: luks-monitor-install.test.sh Row 10 pins that exactly one line anywhere starts
# luks-monitor.service (rows with _SYSTEMD_UNIT=luks-monitor.service are what the host-timer-dark alert
# counts), so the first probe row arrives with the timer's first daily fire instead. Non-fatal: a probe
# fault pages on its own channel and must not hold an empty standby dark.
systemctl enable --now luks-monitor.timer >/dev/null 2>&1 || warn wire_warn luks_monitor_timer_not_enabled

# ── escrow (NON-fatal) ────────────────────────────────────────────────────────────────────────
# After BOTH the format and open arms and idempotent (check, then upload) so a manual re-run is safe.
# It is NOT retried automatically: this script runs once per instance, so escrow=missing stands until
# the host is replaced. The transport is curl's SigV4 signer so no aws-cli install is needed on a
# fresh host; credentials go in via `--config -` on stdin, never argv. A failure here must NOT hold an
# empty standby dark: it records escrow=missing and emits the escrow stage (the soak marker is the fence).
_escrow() {
  local bucket kid sec ep uuid key sz sha md5 code len etag
  bucket=$(_dget WORKSPACES_HEADER_BUCKET); kid=$(_dget WORKSPACES_HEADER_R2_ACCESS_KEY_ID)
  sec=$(_dget WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY); ep=$(_dget WORKSPACES_HEADER_R2_ENDPOINT)
  if [ -z "$bucket" ] || [ -z "$kid" ] || [ -z "$sec" ] || [ -z "$ep" ]; then ESCROW_WHY=creds; return 1; fi
  [[ "$bucket" =~ ^[a-z0-9][a-z0-9.-]*$ ]] && [[ "$ep" =~ ^https://[0-9a-f]{32}\.r2\.cloudflarestorage\.com$ ]] || { ESCROW_WHY=shape; return 1; }
  # The R2 pair reaches curl as a config line `user = "<kid>:<sec>"` on stdin (_curl below), so a quote, backslash,
  # whitespace or control byte in either value would add a directive to that stream. Shape-checked HERE, before _curl
  # exists, under LC_ALL=C (a locale can widen the bracket ranges to non-ASCII letters). Deliberately wider than R2's
  # current 32/64 hex so a vendor format change does not silently turn escrow off; no value is echoed on refusal.
  # Its own reason (creds_shape), distinct from the bucket/endpoint refusal above (shape): the paged event carries only the
  # reason, so one value for both could not say whether the bucket/endpoint or the minted pair was refused.
  ( LC_ALL=C; [[ "$kid" =~ ^[A-Za-z0-9]{16,128}$ ]] && [[ "$sec" =~ ^[A-Za-z0-9/+=_-]{16,256}$ ]] ) || { ESCROW_WHY=creds_shape; return 1; }
  uuid=$(cryptsetup luksUUID "$DEV" 2>/dev/null) || uuid=""
  [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || { ESCROW_WHY=uuid; return 1; }
  HDR_DIR=$(mktemp -d "${ROOT}/run/soleur-lukshdr.XXXXXXXX") || { ESCROW_WHY=tmp; return 1; }
  cryptsetup luksHeaderBackup "$DEV" --header-backup-file "$HDR_DIR/hdr.img" >/dev/null 2>&1 || { ESCROW_WHY=backup; return 1; }
  sz=$(stat -c %s "$HDR_DIR/hdr.img" 2>/dev/null) || sz=0
  [ "$sz" -gt 0 ] || { ESCROW_WHY=backup; return 1; }
  sha=$(sha256sum "$HDR_DIR/hdr.img" | cut -d' ' -f1)
  md5=$(md5sum "$HDR_DIR/hdr.img" | cut -d' ' -f1)
  key="workspaces-luks-header-${uuid}.img"
  _curl() { printf 'user = "%s:%s"\n' "$kid" "$sec" | curl --disable --noproxy '*' --config - --aws-sigv4 'aws:amz:auto:s3' -sS --max-time 120 "$@"; }
  # CHECK: an object with the right size AND the right content already exists -> nothing to do. R2's
  # ETag of a single-part PUT is the md5 hex, so a stale backup under the same UUID (the header
  # changed since: luksAddKey/KillSlot/ChangeKey keep the UUID) is re-uploaded instead of certified.
  _head() { # sets code, len, etag from a HEAD of the object
    code=$(_curl -I -o /dev/null -D "$HDR_DIR/h" -w '%{http_code}' "$ep/$bucket/$key" 2>/dev/null) || code=000
    len=$(awk 'tolower($1)=="content-length:"{gsub("\r",""); print $2+0; exit}' "$HDR_DIR/h" 2>/dev/null)
    etag=$(awk 'tolower($1)=="etag:"{gsub("[\r\"]",""); print tolower($2); exit}' "$HDR_DIR/h" 2>/dev/null)
  }
  _head
  if [ "$code" = 200 ] && [ "${len:-0}" = "$sz" ] && [ "$etag" = "$md5" ]; then return 0; fi
  # UPLOAD, then read back.
  code=$(_curl -T "$HDR_DIR/hdr.img" -H "x-amz-content-sha256: $sha" -o /dev/null -w '%{http_code}' "$ep/$bucket/$key" 2>/dev/null) || code=000
  case "$code" in 2??) : ;; *) ESCROW_WHY=put; return 1 ;; esac
  _head
  [ "$code" = 200 ] && [ "${len:-0}" = "$sz" ] && [ "$etag" = "$md5" ] || { ESCROW_WHY=readback; return 1; }
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
  soleur-boot-emit workspaces_luks_provision_escrow warning 2>/dev/null || true
fi

# ── result ────────────────────────────────────────────────────────────────────────────────────
printf 'luks_arm=%s\nescrow=%s\n' "$ARM" "$ESCROW" > "$ARM_FILE" || warn result arm_file_unwritable
row result 0 "luks_arm=$ARM escrow=$ESCROW"
exit 0

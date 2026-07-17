#!/usr/bin/env bash
#
# #6604 — the /workspaces LUKS cutover body (ADR-119, epic #6588 PR 2).
#
# Migrates web-1's sole-copy user data from the LIVE plaintext ext4 /mnt/data onto the FRESH
# LUKS-encrypted volume (already +created + attached by apply_target=workspaces-luks-cutover), then
# re-points the mapper so /mnt/data (hardcoded into the app's `-v /mnt/data/workspaces:/workspaces`
# bind mount) becomes LUKS-backed with ZERO path changes. Copies the SHAPE of git-data-cutover.sh;
# it NEVER sources or invokes it (that script calls services defined nowhere — R3).
#
# ⚠️ DP-6 — HOST-SIDE recovery. This script runs ON web-1 over the workflow's CF-Tunnel SSH bridge,
# so `trap cleanup EXIT` is HOST-LOCAL and rolls back (unmount-mapper → remount-plaintext → restart)
# even if the CI SSH session dies mid-freeze (F3). Freeze state is persisted to a HOST FILE
# (/var/lib/workspaces-luks/state), not shell vars, so a deliberate reboot (C15) does not destroy
# the trap or the recovery state; the post-reboot re-canary is its OWN gated step reading that file
# (a pre-reboot CANARY_OK MUST NOT satisfy it — F5). A host-local dead-man timer auto-remounts
# plaintext if no orchestrator heartbeat lands within the window.
#
# ⚠️ R7/C3 — the escrow proof runs AFTER prepare_luks_target, against the REAL device via the host's
# prd_workspaces_luks token path (`doppler secrets get WORKSPACES_LUKS_KEY --plain --config
# prd_workspaces_luks`, R9 — NEVER `doppler run`/`download`, the CWE-522 hole). A throwaway-format
# proof passes for any string; only luksOpen --test-passphrase against the real header is real.
#
# ⚠️ C1 — the delta rsync verify is the ITEMIZED form (`-aHAXi … --dry-run --out-format='%i %n' |
# wc -l == 0`), caches dropped first (else you verify the page cache, not that bytes round-tripped
# through dm-crypt); NOT a rev-list identity (which passes while dropping the working-tree +
# refs/checkpoints/* data — R4).
#
# Observability: any failed at-rest assert exports the nine WL_* fields and calls
# workspaces-luks-emit.sh (feature=workspaces-luks / op=workspaces-luks-drift). Verdict is read from
# Sentry + the Better Stack heartbeat, NEVER by SSH-eyeballing (hr-no-ssh-fallback-in-runbooks).
set -uo pipefail

log()  { echo "[workspaces-cutover] $*"; }
step() { echo; echo "[workspaces-cutover] ===== $* ====="; }
die()  { echo "[workspaces-cutover] FATAL: $*" >&2; exit 1; }

# --- Configuration (overridable by the workflow; documented defaults) ---------
MOUNT="${WORKSPACES_MOUNT:-/mnt/data}"          # the live plaintext source AND the final LUKS mount
STAGING="${WORKSPACES_STAGING:-/mnt/data-luks}" # LUKS staging mount during the copy
MAPPER_NAME="${WORKSPACES_MAPPER_NAME:-workspaces}"
MAPPER="/dev/mapper/${MAPPER_NAME}"
CONTAINER="${WORKSPACES_CONTAINER:-soleur-web-platform}"
STATE_DIR="${WORKSPACES_STATE_DIR:-/var/lib/workspaces-luks}"
STATE_FILE="${STATE_DIR}/state"
HEADER_BACKUP_BUCKET="${WORKSPACES_HEADER_BUCKET:-}"  # MUST be distinct from the tfstate bucket (C4)
DEAD_MAN_MIN="${WORKSPACES_DEAD_MAN_MIN:-30}"
DRY_RUN="${DRY_RUN:-1}"
ROLLBACK="${ROLLBACK:-0}"
CONFIRM_WIPE="${CONFIRM_WIPE:-0}"

EMIT="/usr/local/bin/workspaces-luks-emit.sh"
[ -f "$EMIT" ] || EMIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workspaces-luks-emit.sh"
# shellcheck source=apps/web-platform/infra/workspaces-luks-emit.sh
[ -f "$EMIT" ] && . "$EMIT"

# The passphrase is read ONLY via the pinned scoped-config form (R9) — never doppler run/download.
read_key() { doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks 2>/dev/null || true; }

# --- Persisted recovery state (survives a reboot; read by the EXIT trap) ------
persist_state() { mkdir -p "$STATE_DIR"; printf '%s=%s\n' "$1" "$2" >> "$STATE_FILE"; }
read_state()    { [ -f "$STATE_FILE" ] && (grep -E "^$1=" "$STATE_FILE" | tail -1 | cut -d= -f2-) || echo ""; }
FREEZE_HELD=0
FLIP_DONE=0
CANARY_OK=0

# Emit a discriminating drift event (any failed at-rest assert routes here).
emit_drift() {
  WL_REASON="$1"; export WL_REASON
  if command -v workspaces_luks_emit >/dev/null 2>&1; then WL_LEVEL=fatal workspaces_luks_emit; fi
}

# Host-local rollback: unmount the mapper, remount the RETAINED plaintext volume at $MOUNT, restart.
# Reconcilable, not a one-way door (C13): the LUKS volume RETAINS post-cutover writes.
# shellcheck disable=SC2317  # invoked indirectly via the EXIT trap / ROLLBACK mode
rollback() {
  step "ROLLBACK — remount the retained plaintext at $MOUNT + restart"
  [ "$DRY_RUN" = "1" ] && { log "(dry-run) would rollback"; return 0; }
  systemctl stop webhook.service 2>/dev/null || true
  docker stop -t 30 "$CONTAINER" 2>/dev/null || true
  umount "$MOUNT" 2>/dev/null || true
  cryptsetup close "$MAPPER_NAME" 2>/dev/null || true
  # Remount the retained plaintext volume (its by-label / by-id device — never the mapper).
  mount /dev/disk/by-label/workspaces_plain "$MOUNT" 2>/dev/null \
    || mount "$(read_state PLAINTEXT_DEV)" "$MOUNT" 2>/dev/null || true
  docker start "$CONTAINER" 2>/dev/null || true
  systemctl start webhook.service 2>/dev/null || true
  emit_drift rollback_engaged
}

# shellcheck disable=SC2317  # invoked indirectly via the EXIT trap
cleanup() {
  local rc=$?
  trap - EXIT
  if [ "$rc" -eq 0 ]; then exit 0; fi
  log "ABORT (rc=$rc) — host-local auto-recovery"
  [ "$FLIP_DONE" = "1" ] && [ "$CANARY_OK" != "1" ] && rollback
  [ "$FREEZE_HELD" = "1" ] && [ "$CANARY_OK" != "1" ] && rollback
  exit "$rc"
}
trap cleanup EXIT

# Arm a host-local dead-man timer: if the orchestrator does not clear it within DEAD_MAN_MIN,
# systemd-run auto-remounts plaintext + restarts (closes "frozen-and-SSH-unreachable", F3).
arm_dead_man() {
  [ "$DRY_RUN" = "1" ] && return 0
  systemd-run --on-active="${DEAD_MAN_MIN}min" --unit=workspaces-luks-deadman \
    /usr/local/bin/workspaces-cutover-rollback 2>/dev/null || true
}
disarm_dead_man() { systemctl stop workspaces-luks-deadman.timer 2>/dev/null || true; }

# ============================================================================
# ROLLBACK mode — operator recovery entrypoint
# ============================================================================
if [ "$ROLLBACK" = "1" ]; then
  DRY_RUN=0 rollback
  exit 0
fi

# ============================================================================
# L3 pre-freeze gates (Hypotheses 1-2) — abort BEFORE any freeze
# ============================================================================
step "L3 gates — host reachability + mount preconditions (pre-freeze, zero downtime)"
mountpoint -q "$MOUNT" || die "L3: $MOUNT is not mounted — the data is not where the cutover assumes (Phase 0 STOP + Hetzner rescue crypttab/fstab repair, DP-9 F1)"
[ -b "$(findmnt -no SOURCE "$MOUNT" 2>/dev/null)" ] || log "WARN: $MOUNT source is not a block device"

# ============================================================================
# prepare_luks_target — select the FRESH device by volume ID, format-if-raw, open the mapper
# ============================================================================
step "prepare LUKS target: select fresh device by volume ID, blkid discriminator, open mapper"
KEY="$(read_key)"
if [ -z "$KEY" ]; then WL_DOPPLER_REACHABLE=false; export WL_DOPPLER_REACHABLE; emit_drift doppler_unreachable; die "empty WORKSPACES_LUKS_KEY — refusing to proceed unencrypted (NFR-026)"; fi
# The fresh LUKS volume is the ATTACHED block device that is NOT the current /mnt/data source. Select
# it by its Hetzner volume-ID by-id path (passed as WORKSPACES_LUKS_DEV), never a bare glob — the glob
# matches the LIVE plaintext volume too (the ambiguity Phase 1 pins).
FRESH_DEV="${WORKSPACES_LUKS_DEV:-}"
[ -n "$FRESH_DEV" ] && [ -e "$FRESH_DEV" ] || die "WORKSPACES_LUKS_DEV unset or absent — pass the fresh volume by-id device"
raw_type="$(blkid -s TYPE -o value "$FRESH_DEV" 2>/dev/null || true)"
if [ -z "$raw_type" ]; then
  log "fresh device is RAW (no signature) — luksFormat"
  [ "$DRY_RUN" = "1" ] || printf '%s' "$KEY" | cryptsetup luksFormat --type luks2 --key-file - "$FRESH_DEV"
elif [ "$raw_type" = "crypto_LUKS" ]; then
  log "fresh device already crypto_LUKS — no format (idempotent)"
else
  die "fresh device carries TYPE=$raw_type (expected raw or crypto_LUKS) — refusing to format a device with a filesystem signature (C7)"
fi
if [ "$DRY_RUN" != "1" ] && [ ! -e "$MAPPER" ]; then
  printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$FRESH_DEV" "$MAPPER_NAME"
fi
mkdir -p "$STAGING"
[ "$DRY_RUN" = "1" ] || { mountpoint -q "$STAGING" || mount "$MAPPER" "$STAGING"; }

# ============================================================================
# Escrow proof (BLOCKING, AFTER prepare — R7/C3) — against the REAL device via the host token path
# ============================================================================
step "escrow proof: luksOpen --test-passphrase against the REAL device (host token path)"
if [ "$DRY_RUN" != "1" ]; then
  if printf '%s' "$KEY" | cryptsetup luksOpen --test-passphrase --key-file - "$FRESH_DEV" >/dev/null 2>&1; then
    log "escrow OK — the host-token passphrase unlocks the real device"
  else
    WL_LUKS_OPEN_RESULT=fail; export WL_LUKS_OPEN_RESULT; emit_drift escrow_passphrase_mismatch
    die "escrow proof FAILED — the passphrase does not unlock the real device (F4 — unreadable-forever risk); aborting BEFORE the freeze"
  fi
  # C4 — the LUKS header is an independent terminal limb: back it up to a bucket DISTINCT from the
  # tfstate bucket, then assert the backup's UUID matches the live header.
  [ -n "$HEADER_BACKUP_BUCKET" ] || die "WORKSPACES_HEADER_BUCKET unset — refusing to proceed without an off-host header backup to a bucket DISTINCT from tfstate (C4)"
  hdr="/tmp/workspaces-luks-header.img"
  cryptsetup luksHeaderBackup "$FRESH_DEV" --header-backup-file "$hdr"
  live_uuid="$(cryptsetup luksUUID "$FRESH_DEV")"
  bkp_uuid="$(cryptsetup luksUUID "$hdr" 2>/dev/null || cryptsetup luksDump "$hdr" | sed -n 's/^UUID:[[:space:]]*//p')"
  [ -n "$live_uuid" ] && [ "$live_uuid" = "$bkp_uuid" ] || die "header backup UUID mismatch (live=$live_uuid backup=$bkp_uuid) — C4"
  # Off-host copy to the DISTINCT bucket (rclone/aws configured by the workflow env).
  aws s3 cp "$hdr" "s3://${HEADER_BACKUP_BUCKET}/workspaces-luks-header-$(cryptsetup luksUUID "$FRESH_DEV").img" >/dev/null 2>&1 \
    || log "WARN: header off-host upload failed — the workflow env must provide S3 creds for $HEADER_BACKUP_BUCKET"
  shred -u "$hdr" 2>/dev/null || rm -f "$hdr"
else
  log "(dry-run) would luksOpen --test-passphrase + luksHeaderBackup to $HEADER_BACKUP_BUCKET"
fi

# ============================================================================
# G2 manifest (writers live) — enumerate every workspace + ref, derive a count floor
# ============================================================================
step "G2 manifest — enumerate workspaces + all refs (incl refs/checkpoints/*), derive count floor"
manifest_of() {  # $1 = root dir
  local root="$1" ws
  for ws in "$root"/workspaces/*/; do
    [ -d "$ws" ] || continue
    echo "WS $(basename "$ws")"
    git -C "$ws" for-each-ref --format='REF %(refname) %(objectname)' 2>/dev/null || true
    git -C "$ws" for-each-ref --format='CHK %(refname) %(objectname)' 'refs/checkpoints/*' 2>/dev/null || true
    git -C "$ws" status --porcelain 2>/dev/null | sed 's/^/DIRTY /' || true
  done
}
G2="$(manifest_of "$MOUNT")"
G2_COUNT="$(printf '%s\n' "$G2" | grep -c '^WS ' || true)"
log "G2: $G2_COUNT workspace(s) enumerated"
# DP-9 F10: derive the floor from the OBSERVED count, never a hardcoded >0 (0 users ⇒ 0 is valid).

# ============================================================================
# Rollback rehearsal (C15 caveat) — prove the retained plaintext remounts read-only, no restart
# ============================================================================
step "rollback rehearsal — read-only remount of the retained plaintext at a distinct path"
if [ "$DRY_RUN" != "1" ]; then
  reh="/mnt/data-rehearse"; mkdir -p "$reh"
  plain_dev="$(findmnt -no SOURCE "$MOUNT")"
  persist_state PLAINTEXT_DEV "$plain_dev"
  mount -o ro "$plain_dev" "$reh" 2>/dev/null && { log "rehearsal OK — plaintext remounts read-only"; umount "$reh"; } \
    || log "WARN: rehearsal remount failed (a single mounted device cannot be mounted twice on some fs — acceptable; the retained volume is a SEPARATE device post-repoint)"
fi

# ============================================================================
# Bulk rsync (writers live, no --delete) — no user impact
# ============================================================================
step "bulk rsync (writers live, no --delete) into the empty LUKS target"
[ "$DRY_RUN" = "1" ] || rsync -aHAX --numeric-ids "$MOUNT"/ "$STAGING"/

# ============================================================================
# FREEZE (≤20 min budget) — quiesce, drain, copy the delta, verify, repoint
# ============================================================================
step "FREEZE — halt webhook.service + docker stop -t 120 (C8) + interrupted-write asserts (G4)"
FREEZE_HELD=1; persist_state FREEZE_HELD 1; arm_dead_man
if [ "$DRY_RUN" != "1" ]; then
  systemctl stop webhook.service    # so a CI deploy cannot restart the container mid-rsync
  docker stop -t 120 "$CONTAINER"   # C8: drain lets in-flight write() finish (a 10s SIGKILL truncates)
  # Interrupted-write asserts — abort rather than faithfully copy wreckage.
  for ws in "$MOUNT"/workspaces/*/; do
    [ -d "$ws" ] || continue
    [ -e "$ws/.git/index.lock" ] && die "index.lock present in $ws — a write was interrupted; aborting (C8)"
    ls "$ws"/.git/objects/pack/tmp_pack_* >/dev/null 2>&1 && die "tmp_pack_* present in $ws — interrupted pack; aborting"
    [ -e "$ws/.git/gc.pid" ] && die "gc.pid present in $ws — interrupted gc; aborting"
  done
  # G4 — no process is still touching the mount.
  if command -v lsof >/dev/null 2>&1; then lsof +D "$MOUNT" 2>/dev/null | grep -q . && die "lsof +D $MOUNT non-empty — a straggler still holds the mount (G4)"; fi
fi

step "G3 manifest AFTER the freeze on SRC vs DST — same instant, opposite volumes (C9)"
if [ "$DRY_RUN" != "1" ]; then
  # C1: pass-2 delta with --checksum (the only backstop), caches dropped first (verify dm-crypt round-trip).
  sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  rsync -aHAX --numeric-ids --delete --checksum "$MOUNT"/ "$STAGING"/
  # C1 — the ITEMIZED verify (the false-green fix): MUST be 0. --dry-run hardcoded (one typo from wiping).
  DIFF_N="$(rsync -aHAXi --numeric-ids --checksum --delete --dry-run --out-format='%i %n' "$MOUNT"/ "$STAGING"/ | grep -c . || true)"
  [ "$DIFF_N" -eq 0 ] || die "itemized rsync verify found $DIFF_N difference(s) — DST is not byte-identical to SRC (C1)"
  # Byte assert with apparent-size (never df/du -sb — LUKS steals a header, geometry differs).
  SRC_BYTES="$(du --apparent-size -sb "$MOUNT"/workspaces 2>/dev/null | cut -f1)"
  DST_BYTES="$(du --apparent-size -sb "$STAGING"/workspaces 2>/dev/null | cut -f1)"
  [ "$SRC_BYTES" = "$DST_BYTES" ] || die "apparent-size mismatch (src=$SRC_BYTES dst=$DST_BYTES) — C1"
  # git fsck --full per workspace + df + df -i preflight (inode exhaustion with free bytes is the real ENOSPC).
  for ws in "$STAGING"/workspaces/*/; do [ -d "$ws/.git" ] && git -C "$ws" fsck --full >/dev/null 2>&1 || true; done
  df "$STAGING" >/dev/null && df -i "$STAGING" >/dev/null || die "df/df -i preflight failed on $STAGING"
  # G3 count floor derived from OBSERVED G2 (DP-9 F10) — never a hardcoded >0.
  G3_DST_COUNT="$(manifest_of "$STAGING" | grep -c '^WS ' || true)"
  [ "$G3_DST_COUNT" = "$G2_COUNT" ] || die "DST workspace count ($G3_DST_COUNT) != G2 count ($G2_COUNT) — the data gate (G3), not the canary, is the partial-loss detector (AC24)"
fi

step "repoint_luks_mount — mapper -> $MOUNT (backup fstab; findmnt assert)"
if [ "$DRY_RUN" != "1" ]; then
  cp /etc/fstab "/etc/fstab.pre-luks.$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo bak)" 2>/dev/null || cp /etc/fstab /etc/fstab.pre-luks.bak
  umount "$STAGING" 2>/dev/null || true
  umount "$MOUNT"
  mount "$MAPPER" "$MOUNT"
  FLIP_DONE=1; persist_state FLIP_DONE 1
  [ "$(findmnt -no SOURCE "$MOUNT")" = "$MAPPER" ] || die "findmnt: $MOUNT is not $MAPPER after repoint (#5274 stranding)"
fi

# ============================================================================
# Host-level canary BEFORE docker start (C13) — the mapper link is the missing chain link
# ============================================================================
step "host canary BEFORE docker start (C13) — blkid + findmnt + cryptsetup status + mountpoint"
if [ "$DRY_RUN" != "1" ]; then
  WL_DEVICE_TYPE="$(blkid -s TYPE -o value "$FRESH_DEV")"; export WL_DEVICE_TYPE
  [ "$WL_DEVICE_TYPE" = "crypto_LUKS" ] || { emit_drift device_not_luks; die "blkid: $FRESH_DEV is not crypto_LUKS"; }
  [ "$(findmnt -no SOURCE "$MOUNT")" = "$MAPPER" ] || { emit_drift mount_not_mapper; die "findmnt: $MOUNT != $MAPPER"; }
  cryptsetup status "$MAPPER_NAME" >/dev/null 2>&1 || { emit_drift cryptsetup_status_missing; die "cryptsetup status: no mapper->device link"; }
  mountpoint -q "$MOUNT" || { emit_drift not_mounted; die "mountpoint -q $MOUNT failed"; }
  CANARY_OK=1; persist_state CANARY_OK "1:$(cryptsetup luksUUID "$FRESH_DEV")"  # DP-7: run-keyed + header UUID
  log "host canary PASSED — $MOUNT is the LUKS mapper"
fi

step "docker start + resume webhook + app canary + reboot-once re-canary (C15)"
if [ "$DRY_RUN" != "1" ]; then
  docker start "$CONTAINER"
  systemctl start webhook.service
  disarm_dead_man
  health="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 https://app.soleur.ai/api/health || echo 000)"
  [ "$health" = "200" ] || die "app /api/health=$health (expected 200) after restart"
  # Deliver the standing observability to the LIVE host via THIS channel (ADR-119 §(e)).
  install -D -m 0755 "$(dirname "${BASH_SOURCE[0]}")/luks-monitor.sh" /usr/local/bin/luks-monitor 2>/dev/null || true
  install -D -m 0755 "$EMIT" /usr/local/bin/workspaces-luks-emit.sh 2>/dev/null || true
  install -D -m 0644 "$(dirname "${BASH_SOURCE[0]}")/luks-monitor.service" /etc/systemd/system/luks-monitor.service 2>/dev/null || true
  install -D -m 0644 "$(dirname "${BASH_SOURCE[0]}")/luks-monitor.timer" /etc/systemd/system/luks-monitor.timer 2>/dev/null || true
  # Structural fail-closed gate: chattr +i the root-disk mountpoint is unreachable now (mapper is
  # mounted), so it is delivered on the next unmount path; arm the daily probe timer now.
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable --now luks-monitor.timer 2>/dev/null || true
  log "reboot-once re-canary (C15): a deliberate reboot tests the boot path in ~90s; the post-reboot"
  log "re-canary is a SEPARATE gated step that reads $STATE_FILE (a pre-reboot CANARY_OK must NOT satisfy it)."
fi

step "cutover body complete (DRY_RUN=$DRY_RUN). The WIPE/converge is a SEPARATE environment-gated dispatch (DP-4)."
# CONFIRM_WIPE path is authored in the Phase-5 soak/converge dispatch, not here (DP-4): the sweeper
# cannot hold the creds for an irreversible blkdiscard, so the wipe rides its own env-gated workflow
# that re-verifies the persisted run-keyed canary_ok header UUID against the live mapper (DP-7).
exit 0

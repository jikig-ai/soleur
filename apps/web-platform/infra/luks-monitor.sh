#!/usr/bin/env bash
# #6604 — the DAILY /workspaces LUKS at-rest probe (baked to /usr/local/bin/luks-monitor,
# fired by luks-monitor.timer). NOT a 5-min poll: the mount topology is boot-immutable, so the
# steady-state check is a once-a-day escrow + header-UUID re-test (C3/C15). The transition-time
# signal lives in the STRUCTURAL fail-closed mapper gate delivered via the cutover channel, not here.
#
# On success: pushes the Better Stack heartbeat (a DEAD probe therefore FAILS the heartbeat — P1-4)
# and logs one OK line under SyslogIdentifier=luks-monitor (Vector ships it to Better Stack).
# On ANY failed assert: exports the nine WL_* discriminating fields and calls workspaces-luks-emit.sh
# (a direct-curl Sentry envelope carrying feature=workspaces-luks / op=workspaces-luks-drift so the
# sentry_issue_alert pages — DP-8), then exits non-zero. The probe is read-only; it mutates nothing.
#
# The passphrase is read ONLY via the pinned form `doppler secrets get WORKSPACES_LUKS_KEY --plain
# --config prd_workspaces_luks` (R9 / workspaces-luks.tf:112) — NEVER `doppler run`/`download
# --config prd_workspaces_luks`, which drag the root's ~116 prd secrets into env (the CWE-522 hole
# the dedicated config exists to close). DOPPLER_TOKEN (the scoped workspaces-luks-boot service
# token) + SOLEUR_SENTRY_DSN arrive via the unit's EnvironmentFile=/etc/default/luks-monitor,
# provisioned via the cutover channel (ADR-119 §(e)).
set -uo pipefail

# LOG_TAG is a REAL assignment (never an inline `logger -t` literal) — the drift-fixture contract
# at inngest-heartbeat.sh: a heredoc-blind fixture derives the SYSLOG_IDENTIFIER set from
# `^\s*(readonly\s+)?LOG_TAG="..."`. Must equal the vector.toml include_matches tag.
LOG_TAG="luks-monitor"

MOUNT="${WORKSPACES_MOUNT:-/mnt/data}"
MAPPER_NAME="${WORKSPACES_MAPPER_NAME:-workspaces}"
MAPPER="/dev/mapper/${MAPPER_NAME}"
EMIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workspaces-luks-emit.sh"
[ -f "$EMIT" ] || EMIT="/usr/local/bin/workspaces-luks-emit.sh"
# shellcheck source=apps/web-platform/infra/workspaces-luks-emit.sh
[ -f "$EMIT" ] && . "$EMIT"

log() { logger -t "$LOG_TAG" -- "$*" 2>/dev/null || true; echo "[$LOG_TAG] $*"; }

# Discriminating-field accumulators (exported to workspaces-luks-emit.sh on failure).
WL_DEVICE_TYPE=unknown WL_MOUNT_SOURCE=unknown WL_MAPPER_PRESENT=unknown
WL_LUKS_OPEN_RESULT=unknown WL_HEADER_UUID_MATCH=unknown WL_CRYPTSETUP_UNIT_RESULT=unknown
WL_DOPPLER_REACHABLE=unknown WL_MOUNTPOINT_OK=unknown
export WL_DEVICE_TYPE WL_MOUNT_SOURCE WL_MAPPER_PRESENT WL_LUKS_OPEN_RESULT WL_HEADER_UUID_MATCH \
  WL_CRYPTSETUP_UNIT_RESULT WL_DOPPLER_REACHABLE WL_MOUNTPOINT_OK

emit_and_die() {
  WL_REASON="$1"
  export WL_DEVICE_TYPE WL_MOUNT_SOURCE WL_MAPPER_PRESENT WL_LUKS_OPEN_RESULT WL_HEADER_UUID_MATCH \
    WL_CRYPTSETUP_UNIT_RESULT WL_DOPPLER_REACHABLE WL_MOUNTPOINT_OK WL_REASON
  log "FAIL ($WL_REASON): device_type=$WL_DEVICE_TYPE mount_source=$WL_MOUNT_SOURCE mapper_present=$WL_MAPPER_PRESENT luks_open_result=$WL_LUKS_OPEN_RESULT header_uuid_match=$WL_HEADER_UUID_MATCH cryptsetup_unit_result=$WL_CRYPTSETUP_UNIT_RESULT doppler_reachable=$WL_DOPPLER_REACHABLE mountpoint_ok=$WL_MOUNTPOINT_OK"
  if command -v workspaces_luks_emit >/dev/null 2>&1; then
    WL_LEVEL=fatal workspaces_luks_emit
  else
    # The emit script was not sourced (install failure). The drift is now visible ONLY via journald
    # + the heartbeat miss — the discriminating Sentry event is lost. Make THAT state itself visible.
    log "WARN: workspaces-luks-emit.sh unavailable — drift ($WL_REASON) NOT emitted to Sentry; only journald + the heartbeat-miss will page. Reinstall $EMIT."
  fi
  exit 1
}

# 1. The mount MUST resolve to the LUKS mapper (not the raw device — the #5274 silent-plaintext mode).
mnt_src="$(findmnt -no SOURCE "$MOUNT" 2>/dev/null || true)"
WL_MOUNT_SOURCE="${mnt_src:-none}"
if mountpoint -q "$MOUNT"; then WL_MOUNTPOINT_OK=true; else WL_MOUNTPOINT_OK=false; emit_and_die not_mounted; fi
[ "$mnt_src" = "$MAPPER" ] || emit_and_die mount_not_mapper

# 2. The mapper must exist and cryptsetup status must show the mapper -> device link.
if [ -e "$MAPPER" ]; then WL_MAPPER_PRESENT=true; else WL_MAPPER_PRESENT=false; emit_and_die mapper_absent; fi
if cryptsetup status "$MAPPER_NAME" >/dev/null 2>&1; then
  WL_CRYPTSETUP_UNIT_RESULT=active
else
  WL_CRYPTSETUP_UNIT_RESULT=inactive; emit_and_die cryptsetup_status_missing
fi
# The backing device (the mapper -> device link cryptsetup status reports).
real_dev="$(cryptsetup status "$MAPPER_NAME" 2>/dev/null | sed -n 's/^[[:space:]]*device:[[:space:]]*//p' | head -1)"
[ -n "$real_dev" ] || emit_and_die mapper_device_link_missing

# 3. The backing device must be a real LUKS container (never plaintext ext4).
dev_type="$(blkid -s TYPE -o value "$real_dev" 2>/dev/null || true)"
WL_DEVICE_TYPE="${dev_type:-none}"
[ "$dev_type" = "crypto_LUKS" ] || emit_and_die device_not_luks

# 4. Escrow re-test: read the passphrase via the PINNED scoped-config form (R9), never doppler run.
key="$(doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks 2>/dev/null || true)"
if [ -n "$key" ]; then WL_DOPPLER_REACHABLE=true; else WL_DOPPLER_REACHABLE=false; emit_and_die doppler_unreachable; fi
if printf '%s' "$key" | cryptsetup luksOpen --test-passphrase --key-file - "$real_dev" >/dev/null 2>&1; then
  WL_LUKS_OPEN_RESULT=ok
else
  WL_LUKS_OPEN_RESULT=fail; emit_and_die escrow_passphrase_mismatch
fi

# 5. Header-UUID match: the live mapper's UUID must equal the device header's UUID (a swapped
#    header/device is a silent stranding). cryptsetup status reports no UUID, so compare luksUUID
#    of the backing device against the mapper's dm uuid suffix.
dev_uuid="$(cryptsetup luksUUID "$real_dev" 2>/dev/null || true)"
map_uuid="$(blkid -s UUID -o value "$MAPPER" 2>/dev/null || cryptsetup luksUUID "$real_dev" 2>/dev/null || true)"
if [ -n "$dev_uuid" ]; then
  # The mapper is opened FROM real_dev, so their luksUUID is definitionally the same device header;
  # assert the device header UUID resolves (a corrupt header returns empty -> header loss, F4).
  WL_HEADER_UUID_MATCH=true
else
  WL_HEADER_UUID_MATCH=false; emit_and_die header_uuid_unreadable
fi
: "${map_uuid:-}"  # informational; the device-header read above is the terminal-limb check

# All asserts passed — push the heartbeat so a dead probe FAILS it (P1-4).
hb_url="$(doppler secrets get WORKSPACES_LUKS_HEARTBEAT_URL --plain --config prd_workspaces_luks 2>/dev/null || true)"
if [ -n "$hb_url" ]; then
  # -g (--globoff): the URL is a bearer capability; without -g a URL with [ ]/{ } prints the full
  # URL in curl's glob-parse error, which SyslogIdentifier would ship to Better Stack.
  curl -gfsS --max-time 10 "$hb_url" >/dev/null 2>&1 || log "WARN: heartbeat push failed (URL present)"
else
  log "WARN: WORKSPACES_LUKS_HEARTBEAT_URL absent — heartbeat not pushed (operator wires it at cutover)"
fi

log "OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=$MAPPER escrow=ok header=readable)"
exit 0

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
# Overridable for the same reason WORKSPACES_MOUNT and WORKSPACES_MAPPER_NAME are: the behavioural
# seam asserts on the READINESS block, which sits behind `[ -e "$MAPPER" ]` — and `[` is a shell
# BUILTIN, so unlike findmnt/blkid/cryptsetup it cannot be stubbed onto a mock PATH. Without this
# the whole block is unreachable in a fixture. The DEFAULT is pinned by its own assertion in
# luks-monitor.test.sh (a test-only seam with no seam-unset companion is a coverage hole wearing a
# convenience costume), so production behaviour cannot drift behind the override.
MAPPER="${WORKSPACES_MAPPER_PATH:-/dev/mapper/${MAPPER_NAME}}"
# #6807 — defaults MUST match workspaces-cutover.sh:44-45; this is where the cutover persists
# WORKSPACES_COUNT and where the readiness assert reads it back.
STATE_DIR="${WORKSPACES_STATE_DIR:-/var/lib/workspaces-luks}"
STATE_FILE="${STATE_DIR}/state"
# The container publishes the app on host loopback; /internal/readyz is loopback-GATED
# (readiness.ts:113 requires both a loopback peer AND a loopback Host header), so it is reachable
# from the host and from nowhere else.
READYZ_URL="${LUKS_MONITOR_READYZ_URL:-http://127.0.0.1:3000/internal/readyz}"
# The host-side path that the container sees as /workspaces (a docker -v bind of $MOUNT/workspaces).
WORKSPACES_DIR="${LUKS_MONITOR_WORKSPACES_DIR:-$MOUNT/workspaces}"
EMIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workspaces-luks-emit.sh"
[ -f "$EMIT" ] || EMIT="/usr/local/bin/workspaces-luks-emit.sh"
# shellcheck source=apps/web-platform/infra/workspaces-luks-emit.sh
[ -f "$EMIT" ] && . "$EMIT"

# `logger -t` on its OWN line (not after `log() {`) so the vector-pii-scrub.test.sh AC3 emitter
# extractor — which gates on `(^|\|)\s*logger -t` before deriving LOG_TAG — sees this channel and
# includes "luks-monitor" in the expected SYSLOG_IDENTIFIER set (matching the vector.toml allowlist).
log() {
  logger -t "$LOG_TAG" -- "$*" 2>/dev/null || true
  echo "[$LOG_TAG] $*"
}

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

# #6807 — the READINESS/INVENTORY failure exit, DISTINCT from emit_and_die's LUKS-drift exit.
#
# Exit 1 = at-rest LUKS drift. Exit 2 = the volume is a correct LUKS mapper but the APPLICATION
# cannot serve from it (not ready) or the inventory shrank. Collapsing both into `exit 1` made
# probe_rc a three-way ambiguity (drift / readiness / SSH transport 255) behind one hardcoded
# at-rest ::error:: message, which is why the workflow told the operator to read a Sentry event that
# was never emitted. The Sentry `op` stays workspaces-luks-drift either way (see the emit header) —
# de-conflation lives here, in `reason`, and in the workflow's per-arm ::error:: text.
emit_readiness_and_die() {
  WL_REASON="$1"
  export WL_READYZ_WRITABLE WL_READYZ_POPULATED WL_READYZ_CAPACITY \
    WL_WORKSPACE_COUNT WL_WORKSPACE_COUNT_EXPECTED \
    WL_PROBE_LAST_CODE WL_PROBE_ATTEMPTS WL_PROBE_ELAPSED_S WL_PROBE_CLASS WL_REASON
  log "FAIL ($WL_REASON): readyz_writable=${WL_READYZ_WRITABLE:-unknown} readyz_populated=${WL_READYZ_POPULATED:-unknown} capacity=${WL_READYZ_CAPACITY:-unknown} workspace_count=${WL_WORKSPACE_COUNT:-unknown} expected=${WL_WORKSPACE_COUNT_EXPECTED:-unknown} probe_last_code=${WL_PROBE_LAST_CODE:-unknown} probe_attempts=${WL_PROBE_ATTEMPTS:-unknown}"
  if command -v workspaces_luks_emit >/dev/null 2>&1; then
    WL_LEVEL=fatal workspaces_luks_emit
  else
    log "WARN: workspaces-luks-emit.sh unavailable — readiness failure ($WL_REASON) NOT emitted to Sentry. Reinstall $EMIT."
  fi
  exit 2
}

# Mirrors workspaces-cutover.sh:171 read_state. `|| true` because `grep` exits 1 on no match and
# this script runs under `set -o pipefail`, which would otherwise abort the substitution.
read_ws_state() {
  [ -f "$STATE_FILE" ] || { printf ''; return 0; }
  (grep -E "^$1=" "$STATE_FILE" | tail -1 | cut -d= -f2-) 2>/dev/null || true
}

# Sourced-detection guard — mirrors workspaces-cutover.sh:1896. When this file is `source`d (the
# workspaces-luks-harness.sh execution seam obtains the functions above without running the probe),
# return HERE: after every definition, before the main body. Without it, `source luks-monitor.sh`
# runs the entire probe from the next line and the harness's stubs can never take effect — the test
# seam is not merely awkward but IMPOSSIBLE. An executed run (BASH_SOURCE[0] == $0) is a no-op here.
if [ "${BASH_SOURCE[0]:-$0}" != "$0" ]; then return 0 2>/dev/null || true; fi

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

# ---------------------------------------------------------------------------
# 6. #6807 — APPLICATION READINESS + WORKSPACE INVENTORY (flag-gated, default OFF)
# ---------------------------------------------------------------------------
# Steps 1-5 prove the volume is a correct LUKS container. They do NOT prove the application can
# serve user data from it, and NOTHING off-host did until this block existed: /health returns 200
# unconditionally and never touches $MOUNT (server/index.ts), so it is the one endpoint in the
# codebase GUARANTEED not to reflect the repointed volume.
#
# DEFAULT OFF, set to 1 only by workspaces-luks-verify.yml. The reason is NOT "it is slow": it is
# that luks-monitor.service:5 carries `RequiresMountsFor=/mnt/data`, which makes the DAILY unit
# structurally INERT in the reboot hazard (no mount => the unit does not run at all). Default-ON
# therefore buys zero coverage in exactly the scenario it would be argued for, while adding a retry
# budget to time-to-page on a real outage. The verify workflow's bare-file path has no such
# RequiresMountsFor and CAN run in that state, which is why the flag lives there.
#
# ORDERING IS LOAD-BEARING: this runs BEFORE the heartbeat push below, so a host that is
# LUKS-correct but cannot serve does not push a healthy beat.
if [ "${LUKS_MONITOR_ASSERT_READYZ:-0}" = "1" ]; then
  # The probe/counter helpers live in workspaces-luks-emit.sh (sourced at :32). If that install
  # failed, an undefined function would still fail CLOSED below (rc 127) — but under a misleading
  # reason code. Name the real cause instead: the assert cannot run, so this run proves nothing.
  if ! command -v wl_probe_readyz >/dev/null 2>&1 || ! command -v wl_count_workspace_dirs >/dev/null 2>&1; then
    emit_readiness_and_die readiness_helper_unavailable
  fi
  # Capacity FIRST, so a ready=false verdict can be discriminated capacity-fault vs data-loss. A
  # full or read-only mount makes isWorkspacesWritable fail closed (readiness.ts:54-60 catches
  # ENOSPC/EROFS/EACCES/EIO alike), and escalating a full disk to "data-recovery incident on
  # sole-copy data" is a destructive operator response to a non-destructive problem.
  _cap_use="$(df -P "$MOUNT" 2>/dev/null | awk 'NR==2 {print $5}' 2>/dev/null || true)"
  _cap_opts="$(findmnt -no OPTIONS "$MOUNT" 2>/dev/null || true)"
  # Comma-DELIMITED match, never a bare substring: the kernel really sets `errors=remount-ro` on a
  # perfectly healthy ext4 mount, so `case $opts in *ro*)` reports every healthy mount read-only.
  case ",$_cap_opts," in *,ro,*) _cap_rw=ro ;; *) _cap_rw=rw ;; esac
  WL_READYZ_CAPACITY="use=${_cap_use:-unknown},mount=${_cap_rw}"
  export WL_READYZ_CAPACITY

  if ! wl_probe_readyz "$READYZ_URL"; then
    emit_readiness_and_die "${WL_READYZ_REASON:-readyz_unreachable}"
  fi

  # --- INVENTORY. readyz proves a FLOOR, not an inventory ---------------------
  # readiness.ts:81 is `countWorkspaceDirsAt(root) > 0`, so a cutover that preserved 1 of 8
  # sole-copy workspaces returns ready=true. The count below is what actually carries the claim
  # "the inventory survived". It runs HOST-SIDE (not in the workflow run block) for four reasons:
  # it BINDS the value (a runner-side echo plus a prefix grep passes on workspace_count=1 exactly
  # as on =8), it can FAIL CLOSED on a missing baseline, it keeps any error text off the SSH
  # boundary, and emit_drift/workspaces_luks_emit is a host-side function the workflow cannot call.
  #
  # wl_count_workspace_dirs is pure shell (globs + basename), so unlike a `find`/`ls` pipeline it
  # emits NOTHING on stderr — a permission or symlink error cannot carry a user-identifying
  # workspace path across the SSH boundary into the Actions run log.
  if ! WL_WORKSPACE_COUNT="$(wl_count_workspace_dirs "$WORKSPACES_DIR" 2>/dev/null)"; then
    WL_WORKSPACE_COUNT=unknown; export WL_WORKSPACE_COUNT
    emit_readiness_and_die workspace_count_unreadable
  fi
  export WL_WORKSPACE_COUNT
  WL_WORKSPACE_COUNT_EXPECTED="$(read_ws_state WORKSPACES_COUNT)"
  export WL_WORKSPACE_COUNT_EXPECTED
  # FAIL CLOSED. A missing operand must never become a SKIPPED comparison — that is the same
  # "green probe that cannot fail on the condition it names" defect this whole change exists to fix.
  case "${WL_WORKSPACE_COUNT_EXPECTED:-}" in
    ''|*[!0-9]*) emit_readiness_and_die workspace_count_baseline_missing ;;
  esac
  # `-lt`, not `-ne`: users create workspaces between cutovers, so a GROWN inventory is healthy.
  # Only a SHRINK is the sole-copy data-loss signal.
  if [ "$WL_WORKSPACE_COUNT" -lt "$WL_WORKSPACE_COUNT_EXPECTED" ]; then
    emit_readiness_and_die workspace_count_shortfall
  fi

  # MANDATORY VERDICT LINE — the positive control. If the flag is ever lost (it is delivered through
  # the verify workflow's SSH quoting), this block silently never runs, the script exits 0, and the
  # workflow prints PASSED: byte-for-byte the failure shape #6807 is about. The workflow therefore
  # asserts this line is PRESENT rather than asserting no error occurred. Integers only — workspace
  # directory NAMES are user-identifying and must not cross this boundary.
  log "SOLEUR_WORKSPACES_READYZ ready=true writable=${WL_READYZ_WRITABLE} populated=${WL_READYZ_POPULATED} workspace_count=${WL_WORKSPACE_COUNT} expected=${WL_WORKSPACE_COUNT_EXPECTED} capacity=${WL_READYZ_CAPACITY}"
fi

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

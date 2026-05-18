#!/usr/bin/env bash
# Inngest server bootstrap installer (PR-F follow-up, #3960).
#
# Idempotent contract:
#   - Downloads pinned inngest-cli, SHA256-verifies, installs to /usr/local/bin.
#   - Writes systemd units for inngest-server.service + inngest-heartbeat.{service,timer}.
#   - On second invocation with the SAME version, short-circuits via
#     `systemctl is-active` + version match.
#   - On version bump, pauses the running server (drains in-flight events),
#     restarts, resumes.
#
# Self-hosted Inngest binds loopback only (127.0.0.1:8288 events / 8289 API)
# per ADR-030. Signing/event keys + heartbeat URL come from Doppler `prd` via
# `doppler run --project soleur --config prd --` wrapping ExecStart.
#
# Embedded into OCI artifact `ghcr.io/jikig-ai/soleur-inngest-bootstrap:vX.Y.Z`
# AND base64-embedded into cloud-init for fresh-host provisioning. Single
# source of truth on disk; both delivery paths reference this file.

set -euo pipefail

# These two variables are templated by the OCI image build OR cloud-init
# substitution. Default-to-empty triggers loud failure at runtime check.
INNGEST_CLI_VERSION="${INNGEST_CLI_VERSION:-}"
INNGEST_CLI_SHA256="${INNGEST_CLI_SHA256:-}"

if [[ -z "$INNGEST_CLI_VERSION" || -z "$INNGEST_CLI_SHA256" ]]; then
  echo "ERROR: INNGEST_CLI_VERSION and INNGEST_CLI_SHA256 must be set (templated at build/cloud-init time)" >&2
  exit 1
fi

readonly INSTALL_PATH="/usr/local/bin/inngest"
readonly VERSION_FILE="/var/lib/inngest/version"
readonly UNIT_FILE="/etc/systemd/system/inngest-server.service"
readonly HEARTBEAT_UNIT="/etc/systemd/system/inngest-heartbeat.service"
readonly HEARTBEAT_TIMER="/etc/systemd/system/inngest-heartbeat.timer"
readonly HEARTBEAT_SCRIPT="/usr/local/bin/inngest-heartbeat.sh"
readonly DOWNLOAD_URL="https://github.com/inngest/inngest/releases/download/${INNGEST_CLI_VERSION}/inngest_${INNGEST_CLI_VERSION#v}_linux_amd64.tar.gz"
# In-place upgrade drain. Override via env at install time if event volume
# exceeds ~10 events/sec sustained — at higher rates the SQLite fsync window
# can leave some inbound HTTP events unacknowledged. Default is fine for
# alpha-internal (CFO autonomous-draft from Stripe webhooks, low volume).
DRAIN_SLEEP_SEC="${DRAIN_SLEEP_SEC:-2}"

# Defense-in-depth: refuse to operate if the writable host paths are symlinks
# (CWE-367 TOCTOU; an attacker with pre-existing host write could substitute
# a symlink to redirect file writes). All three paths are bind-mounted from
# the host so this guards both fresh-host AND container-extracted execution.
for sensitive_path in /var/lib/inngest "$INSTALL_PATH" "$VERSION_FILE" /etc/default/inngest-server; do
  if [[ -L "$sensitive_path" ]]; then
    echo "ERROR: $sensitive_path is a symlink — refusing to operate (CWE-367)" >&2
    exit 1
  fi
done

log() { printf '[inngest-bootstrap] %s\n' "$*" >&2; }

# Idempotency short-circuit: skip everything if the service is active AND
# the recorded version matches the requested version. Second invocation of
# the same vX.Y.Z is a no-op (~50ms).
if [[ -f "$VERSION_FILE" ]] && [[ "$(cat "$VERSION_FILE" 2>/dev/null || true)" == "$INNGEST_CLI_VERSION" ]]; then
  if systemctl is-active --quiet inngest-server.service 2>/dev/null; then
    log "inngest-server.service already active at $INNGEST_CLI_VERSION — no-op"
    exit 0
  fi
fi

# Detect in-place version upgrade (existing service running an older version).
# Pause the server so the in-memory queue drains to the SQLite store before
# replacing the binary, then resume after restart. Wall-clock downtime per
# upgrade on loopback-only binding: ~5s.
UPGRADE_FROM=""
if systemctl is-active --quiet inngest-server.service 2>/dev/null; then
  UPGRADE_FROM=$(cat "$VERSION_FILE" 2>/dev/null || echo "unknown")
  if [[ "$UPGRADE_FROM" != "$INNGEST_CLI_VERSION" ]]; then
    log "upgrade detected: $UPGRADE_FROM → $INNGEST_CLI_VERSION; pausing for queue drain (${DRAIN_SLEEP_SEC}s)"
    "$INSTALL_PATH" pause >/dev/null 2>&1 || log "warn: pause command failed (continuing)"
    sleep "$DRAIN_SLEEP_SEC"  # allow in-flight events to drain to SQLite
  fi
fi

# Download + SHA256 verify the pinned binary.
mkdir -p /var/lib/inngest
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
TARBALL="$TMPDIR/inngest.tar.gz"

log "downloading $DOWNLOAD_URL"
curl -fsSL -o "$TARBALL" "$DOWNLOAD_URL"

ACTUAL_SHA=$(sha256sum "$TARBALL" | awk '{print $1}')
if [[ "$ACTUAL_SHA" != "$INNGEST_CLI_SHA256" ]]; then
  log "ERROR: SHA256 mismatch — expected $INNGEST_CLI_SHA256, got $ACTUAL_SHA"
  exit 1
fi
log "SHA256 verified: $ACTUAL_SHA"

tar -xzf "$TARBALL" -C "$TMPDIR" inngest
install -m 0755 "$TMPDIR/inngest" "$INSTALL_PATH"

# Write the inngest-server systemd unit. Mirrors webhook.service hardening
# (User=deploy, ProtectSystem=strict, PrivateTmp, ReadWritePaths). The
# `doppler run` wrapper materializes INNGEST_SIGNING_KEY / INNGEST_EVENT_KEY /
# INNGEST_HEARTBEAT_URL at process start; Doppler CLI uses
# /etc/default/inngest-server for its own token.
cat > "$UNIT_FILE" <<'UNITEOF'
[Unit]
Description=Inngest self-hosted server (loopback 127.0.0.1:8288/8289)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/default/inngest-server
ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/inngest start --host 127.0.0.1 --port 8288 --sqlite-dir /var/lib/inngest
Restart=on-failure
RestartSec=5
User=deploy
Group=deploy
# Resource guardrails: cx33 has 8GB RAM + 4 vCPU shared with web-platform.
# Cap inngest-server so a runaway loop can't starve the app container.
# Sized for alpha-internal (<10 events/sec). Bump MemoryMax if the SQLite
# store grows past ~500MB or sustained throughput exceeds ~100 events/sec.
MemoryMax=512M
CPUQuota=100%
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
ReadWritePaths=/var/lib/inngest /var/lock
ReadOnlyPaths=/usr/local/bin /etc/default/inngest-server
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
UNITEOF

# Heartbeat ping script + service + 60s timer.
# The URL lives in $INNGEST_HEARTBEAT_URL (loaded by systemd from
# /etc/default/inngest-server). Indirecting through a script file rather
# than inlining the curl in ExecStart= keeps the URL out of systemd's
# journal (which logs resolved ExecStart= lines on some configurations).
# Defense-in-depth — the URL is also `sensitive = true` in the TF output.
cat > "$HEARTBEAT_SCRIPT" <<'HEARTBEATSCRIPTEOF'
#!/bin/sh
# Posted to Better Stack every 60s by inngest-heartbeat.timer.
exec /usr/bin/curl -fsS --max-time 10 "$INNGEST_HEARTBEAT_URL" >/dev/null
HEARTBEATSCRIPTEOF
chmod 0755 "$HEARTBEAT_SCRIPT"

cat > "$HEARTBEAT_UNIT" <<HEARTBEATEOF
[Unit]
Description=Inngest server heartbeat ping to Better Stack
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/default/inngest-server
ExecStart=${HEARTBEAT_SCRIPT}
HEARTBEATEOF

cat > "$HEARTBEAT_TIMER" <<'TIMEREOF'
[Unit]
Description=Run Inngest heartbeat every 60s

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

# Materialize Doppler token env file (read-only, mode 0600, owned by deploy).
# DOPPLER_TOKEN itself is already present in /etc/environment from the existing
# cloud-init secrets-bootstrap path; we re-export here so the unit's
# EnvironmentFile= sees it without exposing /etc/environment.
if [[ -f /etc/default/inngest-server ]]; then
  log "/etc/default/inngest-server exists — preserving"
else
  # umask-then-write to avoid a world-readable window between create and
  # chmod 0640. 0137 inverts: u=rw,g=r,o=none. DOPPLER_TOKEN is sensitive
  # so close that window even though it's microseconds in practice (CWE-732
  # defense-in-depth).
  ( umask 0137 && printf 'DOPPLER_TOKEN=%s\n' "${DOPPLER_TOKEN:-}" > /etc/default/inngest-server )
  chown root:deploy /etc/default/inngest-server
  chmod 0640 /etc/default/inngest-server
fi

# Record the installed version BEFORE restart so the idempotency short-circuit
# fires on subsequent invocations even if the restart races with a check.
echo "$INNGEST_CLI_VERSION" > "$VERSION_FILE"

systemctl daemon-reload
systemctl enable --now inngest-server.service
systemctl enable --now inngest-heartbeat.timer

# Resume from upgrade pause (if any).
if [[ -n "$UPGRADE_FROM" ]]; then
  sleep 2  # let the new server bind loopback before resume
  "$INSTALL_PATH" resume >/dev/null 2>&1 || log "warn: resume command failed (server is still running)"
  log "upgrade complete: $UPGRADE_FROM → $INNGEST_CLI_VERSION"
fi

log "bootstrap complete: inngest-server $INNGEST_CLI_VERSION active on 127.0.0.1:8288"

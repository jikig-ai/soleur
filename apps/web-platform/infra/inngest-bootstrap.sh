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
# Self-hosted Inngest binds 0.0.0.0:8288 (events) + 8289 (connect-gateway).
# ADR-030's "loopback only" intent — keep Inngest unreachable from the public
# internet — is preserved via the host firewall (`apps/web-platform/infra/
# firewall.tf`), which only allows 22 (admin IPs), 80, and 443 (Cloudflare
# IPs) inbound. Port 8288 is implicitly closed externally. The 0.0.0.0 bind
# is REQUIRED so the bridge-networked `soleur-web-platform` Docker container
# can reach Inngest via `host.docker.internal` (= docker bridge gateway). The
# original 127.0.0.1 bind worked for systemd unit-local consumers but blocked
# the container's SDK from registering — surfaced 2026-05-19 via #4017.
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

# Idempotency short-circuit: when the server is already active AND the recorded
# version matches, skip the binary download/install + server unit write — but
# ALWAYS fall through to reconcile heartbeat units, env file, and daemon-reload.
# Without this, a bootstrap-script fix (e.g. PR #4123's doppler-run heartbeat
# wrap) stays masked indefinitely: the version match short-circuits before the
# unit writes, so the host runs the OLD unit shape even though the deployed
# image embeds the new script. Surfaced 2026-05-20 during the #4144 cascade —
# v1.0.1 image carried the heartbeat fix but every no-op redeploy skipped the
# unit reconcile, leaving inngest-heartbeat.service in `failed` with
# `curl: (3) URL rejected: Malformed input to a URL function`.
SKIP_BINARY_INSTALL=
if [[ -f "$VERSION_FILE" ]] && [[ "$(cat "$VERSION_FILE" 2>/dev/null || true)" == "$INNGEST_CLI_VERSION" ]]; then
  if systemctl is-active --quiet inngest-server.service 2>/dev/null; then
    log "inngest-server.service already active at $INNGEST_CLI_VERSION — skipping binary install, reconciling units"
    SKIP_BINARY_INSTALL=1
  fi
fi

if [[ -z "$SKIP_BINARY_INSTALL" ]]; then

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
# /var/lib/inngest is SQLite's writable dir; the unit runs as `deploy` so the
# directory MUST be owned by deploy:deploy or SQLite returns CANTOPEN(14).
# Surfaced 2026-05-19 via #4017 substrate audit (PR-1 cron-daily-triage missed
# all scheduled fires — root cause one of five).
mkdir -p /var/lib/inngest
chown deploy:deploy /var/lib/inngest
chmod 0750 /var/lib/inngest
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

fi  # end SKIP_BINARY_INSTALL guard — unit + heartbeat reconcile below always run

# Write the inngest-server systemd unit. RECONCILE-ALWAYS — deliberately
# OUTSIDE the SKIP_BINARY_INSTALL guard, matching the heartbeat-unit (and
# Vector-unit) precedent below. An ExecStart-only change (#4652:
# --poll-interval / --sdk-url) must land even on a same-CLI-version redeploy
# where SKIP_BINARY_INSTALL fires; leaving the write inside the guard would
# skip it and the host would keep the OLD ExecStart indefinitely (same masking
# class as the #4144 heartbeat-fix cascade). The binary download/install +
# upgrade-drain stay inside the guard above (no need to re-download on a
# no-op redeploy); only the unit write + the restart below are reconciled
# every bootstrap. Mirrors webhook.service hardening (User=deploy,
# ProtectSystem=strict, PrivateTmp, ReadWritePaths).
#
# Signing-key prefix strip: Terraform sets INNGEST_SIGNING_KEY to the SDK-
# format `signkey-prod-<64hex>`, but `inngest start --signing-key` requires
# the bare 64-hex (the CLI literally errors `signing-key must be hex string
# with even number of chars` on the prefixed form). Strip in-place via bash
# `${VAR#prefix}`. The SDK consumer (apps/web-platform container) still uses
# the full prefixed value — that's what the SDK helper expects per
# `node_modules/inngest/helpers/strings.js`. Both sides resolve to the same
# 32-byte HMAC seed; the prefix is purely a SDK-side string marker.
# Surfaced 2026-05-19 via #4017 substrate audit.
#
# --poll-interval 60 + --sdk-url: the server polls the co-located web-platform
# app serve route (loopback port 3000 per Dockerfile PORT=3000; /api/inngest is
# in PUBLIC_PATHS per the #4017 fix so the poll is not 307→/login) every 60s,
# re-syncing AND re-planning any dropped/de-planned function within one
# interval — without a restart. This is what lets the #4650 watchdog demote its
# restart-on-first-tick to a guarded backstop (#4652).
# #5159: re-planning via this poll REQUIRES the SDK to register the canonical
# PUBLIC serve URL (serveHost pinned in app/api/inngest/route.ts) — a
# 127.0.0.1-host registration is accepted (HTTP 200) but its crons are never
# planned. Without that pin, neither this poll nor the loopback re-register PUT
# re-plans crons after a restart (the 2026-06-11 cron-deplan incident).
# Durable backend (#5450): the ExecStart below adds --postgres-uri (dedicated
# Supabase project, Supavisor SESSION pooler :5432 — transaction pooler breaks
# inngest's sqlc prepared statements, verdict 0.5) + --redis-uri (self-hosted
# Redis, AOF on /mnt/data). Phase-0 spike (runbook § Durable backend) proved
# Postgres-ALONE loses armed future-ts reminders on a host re-provision; durable
# external Redis is what survives. Both secrets inject from Doppler prd via the
# `doppler run` wrapper (same $${...} pattern as the keys; avoids the #4116
# EnvironmentFile-empty trap). --sqlite-dir is kept but vestigial when
# --postgres-uri is set (verified); rollback = drop the two new flags in one
# revert step. --postgres-max-open-conns 25 bounds the pooler budget. Inngest
# FAILS CLOSED on an unreachable/empty backend (verdict 0.3) — so this ExecStart
# must not deploy until INNGEST_POSTGRES_URI + INNGEST_REDIS_PASSWORD are
# populated in Doppler prd (cutover ordering; verify_inngest_health hard-gates).
cat > "$UNIT_FILE" <<'UNITEOF'
[Unit]
Description=Inngest self-hosted server (loopback 127.0.0.1:8288/8289)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/default/inngest-server
ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/bin/bash -c '/usr/local/bin/inngest start --host 0.0.0.0 --port 8288 --sqlite-dir /var/lib/inngest --postgres-uri "$${INNGEST_POSTGRES_URI}" --redis-uri "redis://:$${INNGEST_REDIS_PASSWORD}@127.0.0.1:6379" --postgres-max-open-conns 25 --signing-key "$${INNGEST_SIGNING_KEY#signkey-prod-}" --event-key "$${INNGEST_EVENT_KEY}" --poll-interval 60 --sdk-url http://127.0.0.1:3000/api/inngest'
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
# The URL lives in $INNGEST_HEARTBEAT_URL — resolved at ExecStart time via
# `doppler run --project soleur --config prd` (same pattern as
# inngest-server.service above). The earlier shape relied on systemd's
# EnvironmentFile=/etc/default/inngest-server to provide the URL, but the
# substrate-fix in PR #4085 only writes DOPPLER_TOKEN / DOPPLER_CONFIG_DIR /
# DOPPLER_ENABLE_VERSION_CHECK into that file — INNGEST_HEARTBEAT_URL was
# silently empty and curl errored every 60s (#4116). Wrapping in `doppler run`
# collapses the env-injection class: Doppler prd is the single source of
# truth, no host-side materialization required.
#
# Indirecting through a script file rather than inlining the curl in
# ExecStart= keeps the URL out of systemd's journal (which logs resolved
# ExecStart= lines on some configurations). Defense-in-depth — the URL is
# also `sensitive = true` in the TF output.
cat > "$HEARTBEAT_SCRIPT" <<'HEARTBEATSCRIPTEOF'
#!/bin/sh
# Posted to Better Stack every 60s by inngest-heartbeat.timer.
exec /usr/bin/curl -fsS --max-time 10 "$INNGEST_HEARTBEAT_URL" >/dev/null
HEARTBEATSCRIPTEOF
chmod 0755 "$HEARTBEAT_SCRIPT"

# Resolve the doppler binary path at bootstrap time. cloud-init installs to
# /usr/local/bin/doppler (cloud-init.yml:289-290); inngest-server.service:137
# hardcodes /usr/bin/doppler. Interpolating `command -v` here avoids
# inheriting that latent path discrepancy in the heartbeat unit.
DOPPLER_BIN="$(command -v doppler 2>/dev/null || true)"
if [[ -z "$DOPPLER_BIN" ]]; then
  log "ERROR: doppler CLI not found on PATH — cloud-init must install /usr/local/bin/doppler before inngest-bootstrap"
  exit 1
fi

cat > "$HEARTBEAT_UNIT" <<HEARTBEATEOF
[Unit]
Description=Inngest server heartbeat ping to Better Stack
After=network-online.target

[Service]
Type=oneshot
User=deploy
Group=deploy
# Doppler CLI calls os.UserHomeDir() during init even when DOPPLER_CONFIG_DIR
# is set in the env file. Running as root with no HOME triggers
# "Doppler Error: \$HOME is not defined". User=deploy gets HOME=/home/deploy
# automatically, matching inngest-server.service's hardening pattern.
# Surfaced 2026-05-20 once #4204's reconcile gate exposed the new unit shape.
EnvironmentFile=/etc/default/inngest-server
ExecStart=${DOPPLER_BIN} run --project soleur --config prd -- ${HEARTBEAT_SCRIPT}
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

# Materialize Doppler token + CLI config dir env file. The unit's `User=deploy`
# combined with `ProtectHome=read-only` blocks Doppler CLI's default fallback
# dir (/home/deploy/.doppler/fallback) — must redirect via DOPPLER_CONFIG_DIR
# to a PrivateTmp-writable location.
#
# Token source-of-truth: reuse /etc/default/webhook-deploy's DOPPLER_TOKEN
# (provisioned at cloud-init for the webhook-deploy service). Originally this
# script assumed the env-injection path would have DOPPLER_TOKEN set in the
# caller env; in the GHA→webhook deploy path that's NOT the case, leaving the
# token empty and inngest in a crash loop with "Doppler Error: you must
# provide a token". Reading from webhook-deploy's env file collapses one
# more substrate gap. Surfaced 2026-05-19 via #4017.
if [[ -f /etc/default/inngest-server ]] && grep -q '^DOPPLER_TOKEN=dp\.' /etc/default/inngest-server; then
  log "/etc/default/inngest-server exists with valid token — preserving"
else
  # Pull token from the sibling webhook-deploy env file (same Doppler scope
  # — both run as `deploy` user against the `prd` config).
  if [[ ! -f /etc/default/webhook-deploy ]]; then
    log "ERROR: /etc/default/webhook-deploy not found — cannot source DOPPLER_TOKEN"
    exit 1
  fi
  TOKEN=$(grep -oP '(?<=^DOPPLER_TOKEN=)dp\.\S+' /etc/default/webhook-deploy | head -n1)
  if [[ -z "$TOKEN" ]]; then
    log "ERROR: webhook-deploy env file has no DOPPLER_TOKEN — aborting"
    exit 1
  fi
  # umask-then-write to avoid a world-readable window between create and
  # chmod 0640. 0137 inverts: u=rw,g=r,o=none. DOPPLER_TOKEN is sensitive
  # so close that window even though it's microseconds in practice (CWE-732
  # defense-in-depth).
  ( umask 0137 && cat > /etc/default/inngest-server <<DOPPLEREOF
DOPPLER_TOKEN=$TOKEN
DOPPLER_CONFIG_DIR=/tmp/.doppler
DOPPLER_ENABLE_VERSION_CHECK=false
DOPPLEREOF
  )
  chown root:deploy /etc/default/inngest-server
  chmod 0640 /etc/default/inngest-server
fi

# Durable Redis (#5450) — install + start the queue store BEFORE the
# inngest-server restart below, because the new ExecStart fails closed when
# --redis-uri is unreachable (Phase-0 verdict 0.3). Assets are staged to /tmp by
# the OCI image entrypoint (mirrors /tmp/vector.toml). The unit's
# EnvironmentFile=/etc/default/inngest-server now exists (written just above), so
# Redis can start with its Doppler-injected password on fresh AND existing hosts.
# Skip gracefully if the assets are absent (a pre-#5450 image on a not-yet-
# migrated host) — verify_inngest_health is the hard durability gate.
if [[ -f /tmp/inngest-redis.conf && -f /tmp/inngest-redis.service && -x /tmp/inngest-redis-bootstrap.sh ]]; then
  log "installing durable Redis assets (#5450)"
  mkdir -p /etc/redis
  install -m 0644 /tmp/inngest-redis.conf /etc/redis/inngest-redis.conf
  install -m 0644 /tmp/inngest-redis.service /etc/systemd/system/inngest-redis.service
  install -m 0755 /tmp/inngest-redis-bootstrap.sh /usr/local/bin/inngest-redis-bootstrap.sh
  if /usr/local/bin/inngest-redis-bootstrap.sh; then
    log "durable Redis ready"
  else
    log "warn: inngest-redis-bootstrap.sh failed — inngest-server will fail closed if Redis is required; verify_inngest_health will catch it"
  fi
else
  log "durable Redis assets not staged at /tmp/inngest-redis.* — skipping (pre-#5450 image?)"
fi

# Record the installed version BEFORE restart so the idempotency short-circuit
# fires on subsequent invocations even if the restart races with a check.
echo "$INNGEST_CLI_VERSION" > "$VERSION_FILE"

systemctl daemon-reload
# `enable --now` is a no-op when the unit is already running; a new ExecStart
# (e.g. #4652's --poll-interval / --sdk-url) would never be picked up by an
# already-running inngest-server process. Replace with explicit enable +
# restart so each deploy reloads the unit — mirroring the vector.service fix
# below (this file, "enable vector.service" + "restart vector.service") and
# the same root cause documented there. Combined with the reconcile-always
# unit write above, an ExecStart-only change is now deploy-reliable even on a
# same-CLI-version redeploy (SKIP_BINARY_INSTALL path). The upgrade-drain
# pause above runs before the binary replace; this restart subsumes the start
# and the resume below runs after.
systemctl enable inngest-server.service 2>/dev/null || true
systemctl restart inngest-server.service
systemctl enable --now inngest-heartbeat.timer
# Force one heartbeat tick now so a unit-shape change (e.g. ExecStart) takes
# effect immediately rather than waiting up to 60s for the next timer fire.
# Oneshot in `failed` state: restart re-runs ExecStart with the new unit.
systemctl restart inngest-heartbeat.service || log "warn: heartbeat oneshot non-zero (timer will retry in 60s)"

# Resume from upgrade pause (if any).
if [[ -n "${UPGRADE_FROM:-}" ]]; then
  sleep 2  # let the new server bind loopback before resume
  "$INSTALL_PATH" resume >/dev/null 2>&1 || log "warn: resume command failed (server is still running)"
  log "upgrade complete: $UPGRADE_FROM → $INNGEST_CLI_VERSION"
fi

log "bootstrap complete: inngest-server $INNGEST_CLI_VERSION active on 127.0.0.1:8288"

# ----------------------------------------------------------------------
# Vector observability shipper — ships journald + host_metrics to Better
# Stack Logs via Vector's native `better_stack_logs` sink (#4273 pivot
# from the original Sentry envelope target). ci-deploy.sh still captures
# stderr at the sudo boundary into /tmp/inngest-bootstrap-stderr.log so
# any future failure surfaces via the deploy-status endpoint without
# needing SSH (permanent diagnostic kept post-pivot).
# envelope endpoint. Same Doppler-injected envs as inngest-heartbeat
# (SENTRY_INGEST_DOMAIN / SENTRY_PROJECT_ID / SENTRY_PUBLIC_KEY); no new
# secrets minted.
#
# Idempotency: matches the inngest path — version file at
# `/var/lib/vector/version`, sha256-verify on download, skip-install when
# version matches.
# ----------------------------------------------------------------------

VECTOR_CLI_VERSION="${VECTOR_CLI_VERSION:-}"
VECTOR_CLI_SHA256="${VECTOR_CLI_SHA256:-}"

if [[ -z "$VECTOR_CLI_VERSION" || -z "$VECTOR_CLI_SHA256" ]]; then
  log "warn: VECTOR_CLI_VERSION + VECTOR_CLI_SHA256 unset — skipping Vector install (observability shipper deferred until next bootstrap)"
else
  readonly VECTOR_INSTALL_PATH="/usr/local/bin/vector"
  readonly VECTOR_VERSION_FILE="/var/lib/vector/version"
  readonly VECTOR_CONFIG_DIR="/etc/vector"
  readonly VECTOR_CONFIG="$VECTOR_CONFIG_DIR/vector.toml"
  readonly VECTOR_UNIT="/etc/systemd/system/vector.service"
  readonly VECTOR_DOWNLOAD_URL="https://packages.timber.io/vector/${VECTOR_CLI_VERSION}/vector-${VECTOR_CLI_VERSION}-x86_64-unknown-linux-musl.tar.gz"

  install_vector_binary() {
    local current=""
    [[ -f "$VECTOR_VERSION_FILE" ]] && current="$(cat "$VECTOR_VERSION_FILE")"
    if [[ "$current" == "$VECTOR_CLI_VERSION" && -x "$VECTOR_INSTALL_PATH" ]]; then
      log "vector $VECTOR_CLI_VERSION already installed; skipping download"
      return 0
    fi
    log "downloading vector $VECTOR_CLI_VERSION"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    curl -fsSL --max-time 120 -o "$tmp/vector.tar.gz" "$VECTOR_DOWNLOAD_URL"
    local actual_sha
    actual_sha="$(sha256sum "$tmp/vector.tar.gz" | awk '{print $1}')"
    if [[ "$actual_sha" != "$VECTOR_CLI_SHA256" ]]; then
      log "error: vector sha256 mismatch: expected $VECTOR_CLI_SHA256 actual $actual_sha"
      return 1
    fi
    tar -xzf "$tmp/vector.tar.gz" -C "$tmp"
    install -m 0755 "$tmp"/vector-x86_64-unknown-linux-musl/bin/vector "$VECTOR_INSTALL_PATH"
    mkdir -p "$(dirname "$VECTOR_VERSION_FILE")"
    echo "$VECTOR_CLI_VERSION" > "$VECTOR_VERSION_FILE"
  }

  install_vector_binary || { log "warn: vector install failed; skipping rest of observability bootstrap"; }

  if [[ -x "$VECTOR_INSTALL_PATH" ]]; then
    # The config file content is templated by the OCI build (same delivery
    # as the systemd-unit heredoc above). The bootstrap script's caller
    # is responsible for ensuring vector.toml exists at /tmp/vector.toml
    # before invocation; if missing, we skip the rest gracefully.
    if [[ -f /tmp/vector.toml ]]; then
      mkdir -p "$VECTOR_CONFIG_DIR" /var/lib/vector
      install -m 0644 /tmp/vector.toml "$VECTOR_CONFIG"
      chown -R deploy:deploy /var/lib/vector
      # Log the sha256 of the installed config so cat-deploy-state's
      # journal tail proves what content actually reached disk. Bitten
      # 2026-05-21 by the stale `/tmp/vector.toml` reuse path; the hash
      # comparison surfaces drift between the OCI-bundled config and
      # what vector.service is actually reading.
      log "vector config installed: sha256=$(sha256sum "$VECTOR_CONFIG" | awk '{print $1}')"
    fi

    if [[ -f "$VECTOR_CONFIG" ]]; then
      cat > "$VECTOR_UNIT" <<'VECTOREOF'
[Unit]
Description=Vector observability shipper (journald + host_metrics -> Better Stack Logs)
After=network-online.target inngest-server.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/default/inngest-server
# Vector needs Doppler-injected BETTERSTACK_LOGS_TOKEN (and any other
# secrets the config references). doppler run resolves them at
# ExecStart time.
ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/vector --config /etc/vector/vector.toml
Restart=on-failure
RestartSec=10
User=deploy
Group=deploy
SupplementaryGroups=systemd-journal
MemoryMax=256M
CPUQuota=50%
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
ReadWritePaths=/var/lib/vector
ReadOnlyPaths=/etc/vector
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
VECTOREOF

      systemctl daemon-reload
      # `enable --now` is a no-op when the unit is already running; the
      # new config would never be picked up by an already-running vector
      # process. Replace with explicit enable + restart so each deploy
      # gives Vector a clean reload (it reads /etc/vector/vector.toml
      # only at start, not on SIGHUP without explicit reload mapping).
      # Surfaced 2026-05-21: v1.1.7 deploy reported "active" but kept
      # running the v1.1.6 Sentry-sink config.
      systemctl enable vector.service 2>/dev/null || true
      systemctl restart vector.service || log "warn: vector.service failed to (re)start; check journalctl -u vector.service"
      log "vector observability shipper restarted"
    else
      log "warn: $VECTOR_CONFIG missing — vector installed but not started"
    fi
  fi
fi

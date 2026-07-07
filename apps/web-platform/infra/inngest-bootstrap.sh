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
# #6178: the co-located web host is amd64; the dedicated inngest host (cax11) is
# ARM64. Default amd64 PRESERVES the web-host behavior (cross-consumer edit —
# hr-type-widening-cross-consumer-grep); the dedicated host's cloud-init passes
# INNGEST_CLI_ARCH=arm64 AND an arch-matching INNGEST_CLI_SHA256 (the arm64 tarball
# SHA — the amd64 image-baked SHA would fail the verify below on an arm64 download).
INNGEST_CLI_ARCH="${INNGEST_CLI_ARCH:-amd64}"
# #6178 cross-consumer templating (defaults PRESERVE the co-located web-host behavior;
# the dedicated inngest host overrides both). SDK_URL: the app serve URL inngest syncs +
# invokes (Phase-0.2 spike: route-once → a single stable URL; the dedicated host points
# at the active web backend's private interface). DOPPLER_PROJECT: the dedicated host's
# boot token is scoped to the ISOLATED `soleur-inngest` project (AC3), so its ExecStart
# `doppler run` must target that project, not `soleur`.
SDK_URL="${SDK_URL:-http://127.0.0.1:3000/api/inngest}"
# EXPORTED so the inngest-redis-bootstrap.sh subprocess (which renders the redis
# unit's @@DOPPLER_PROJECT@@) inherits it. Default `soleur` preserves the web host.
export DOPPLER_PROJECT="${DOPPLER_PROJECT:-soleur}"

if [[ -z "$INNGEST_CLI_VERSION" || -z "$INNGEST_CLI_SHA256" ]]; then
  echo "ERROR: INNGEST_CLI_VERSION and INNGEST_CLI_SHA256 must be set (templated at build/cloud-init time)" >&2
  exit 1
fi
case "$INNGEST_CLI_ARCH" in
  amd64 | arm64) ;;
  *) echo "ERROR: INNGEST_CLI_ARCH must be amd64 or arm64 (got '$INNGEST_CLI_ARCH')" >&2; exit 1 ;;
esac

readonly INSTALL_PATH="/usr/local/bin/inngest"
readonly VERSION_FILE="/var/lib/inngest/version"
readonly UNIT_FILE="/etc/systemd/system/inngest-server.service"
readonly HEARTBEAT_UNIT="/etc/systemd/system/inngest-heartbeat.service"
readonly HEARTBEAT_TIMER="/etc/systemd/system/inngest-heartbeat.timer"
readonly HEARTBEAT_SCRIPT="/usr/local/bin/inngest-heartbeat.sh"
readonly DOWNLOAD_URL="https://github.com/inngest/inngest/releases/download/${INNGEST_CLI_VERSION}/inngest_${INNGEST_CLI_VERSION#v}_linux_${INNGEST_CLI_ARCH}.tar.gz"
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
ExecStart=${DOPPLER_BIN} run --project ${DOPPLER_PROJECT} --config prd -- ${HEARTBEAT_SCRIPT}
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

# Durable Redis (#5450, #5547 Gap 2) — install + start the queue store and
# capture REDIS_READY BEFORE writing the inngest-server unit below, so the
# ExecStart can be branched: write the durable form (env-delivered URIs +
# --postgres-max-open-conns sentinel since #5560) ONLY when Redis is verifiably
# active, else a SQLite-only fail-safe that keeps
# inngest-server AVAILABLE instead of crash-looping on 127.0.0.1:6379 (the ~3.5h
# #5542 outage). Assets are staged to /tmp by the OCI image entrypoint (fresh-host
# cloud-init) OR by ci-deploy.sh's `case "inngest")` docker-cp (existing-host
# deploy — #5547 Gap 1). The unit's EnvironmentFile=/etc/default/inngest-server
# now exists (written just above), so Redis can start with its Doppler-injected
# password on fresh AND existing hosts.
REDIS_READY=0
if [[ -f /tmp/inngest-redis.conf && -f /tmp/inngest-redis.service && -x /tmp/inngest-redis-bootstrap.sh ]]; then
  log "installing durable Redis (#5450)"
  # Only the bootstrap SCRIPT lands here (/usr/local/bin is webhook-namespace
  # writable); the script installs the conf onto /mnt/data and the unit into
  # /etc/systemd/system itself (the conf canNOT go to /etc/redis — read-only in
  # the deploy namespace; see inngest-redis-bootstrap.sh header).
  install -m 0755 /tmp/inngest-redis-bootstrap.sh /usr/local/bin/inngest-redis-bootstrap.sh
  # REDIS_READY is driven by the bootstrap EXIT CODE alone: inngest-redis-bootstrap.sh
  # step 6 self-asserts `systemctl is-active --quiet` and exits non-zero otherwise,
  # so exit-0 ⟹ the unit is active — a second is-active re-check here would be
  # redundant (#5547, code-simplicity finding).
  if /usr/local/bin/inngest-redis-bootstrap.sh; then
    REDIS_READY=1
    log "durable Redis ready"
  else
    log "warn: INNGEST_DURABLE_DEGRADED — inngest-redis-bootstrap.sh failed; falling back to the SQLite-only ExecStart so inngest-server stays available (durability degraded; verify_inngest_health emits the no-SSH advisory). #5547 Gap 2"
  fi
else
  log "warn: INNGEST_DURABLE_DEGRADED — durable Redis assets not staged at /tmp/inngest-redis.* (pre-#5450 image or undelivered assets); falling back to the SQLite-only ExecStart. #5547 Gap 1/2"
fi

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
# Durable backend (#5450): the durable backend uses a dedicated Supabase project
# (Supavisor SESSION pooler :5432 — transaction pooler breaks inngest's sqlc
# prepared statements, verdict 0.5) + self-hosted Redis (AOF on /mnt/data).
# Phase-0 spike (runbook § Durable backend) proved Postgres-ALONE loses armed
# future-ts reminders on a host re-provision; durable external Redis is what survives.
#
# Secrets delivery (#5560): inngest reads INNGEST_POSTGRES_URI, INNGEST_REDIS_URI,
# INNGEST_SIGNING_KEY, and INNGEST_EVENT_KEY from the ENVIRONMENT (self-hosting
# docs). We rely on that — NO secret is passed on the `inngest start` argv, because
# argv is world-readable via /proc/<pid>/cmdline (mode 0444); the inherited env is
# owner-only (/proc/<pid>/environ, mode 0400). The `doppler run --config prd`
# wrapper injects INNGEST_POSTGRES_URI / INNGEST_SIGNING_KEY / INNGEST_EVENT_KEY by
# name; INNGEST_REDIS_URI is constructed in @@BACKEND_ENV@@ from INNGEST_REDIS_PASSWORD
# (Doppler holds only the password). The signing key is re-exported with the
# `signkey-prod-` prefix stripped (the self-hosted server wants the bare hex; the
# SDK side keeps the prefixed form in its own scope). This avoids the #4116
# EnvironmentFile-empty trap (env stays inside the doppler-run scope, not a file).
#
# --postgres-max-open-conns 10 stays UNDER the dedicated project's session-mode
# pooler pool_size (15) so inngest cannot self-exhaust the pool — #5558: 25 > 15 →
# EMAXCONNSESSION. It is ALSO the NON-SECRET durable-detection sentinel (see the
# @@BACKEND_FLAGS@@ note below + ci-deploy.sh / inngest-inventory.sh / wiped-volume-verify).
# ⚠ DETECTION SENTINEL — NEVER move --postgres-max-open-conns into the SHARED prefix
# (where --sqlite-dir lives): it MUST appear in argv iff durable. Promoting it to the
# shared prefix would make it present in BOTH branches → every parser misclassifies the
# SQLite-only fail-safe as durable, and inngest-wiped-volume-verify would permit a wipe
# of real SQLite state. The drift-guard catches a RENAME, not a prefix-promotion (#5560).
# Inngest FAILS CLOSED on an unreachable/empty backend (verdict 0.3) —
# #5547 Gap 2: rather than configure the durable backend unconditionally (which
# crash-loops when Redis is unprovisioned), the ExecStart below carries literal
# @@BACKEND_ENV@@ + @@BACKEND_FLAGS@@ sentinels substituted (just after the heredoc)
# with the durable fragments ONLY when REDIS_READY=1 (Redis verifiably active), else
# the fail-safe form (unset INNGEST_POSTGRES_URI + empty flags) → a SQLite-only
# ExecStart that keeps inngest-server available.
# --sqlite-dir stays in the shared prefix (load-bearing in the SQLite form,
# vestigial-but-harmless in the durable form).
cat > "$UNIT_FILE" <<'UNITEOF'
[Unit]
Description=Inngest self-hosted server (loopback 127.0.0.1:8288/8289)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/default/inngest-server
ExecStart=/usr/bin/doppler run --project @@DOPPLER_PROJECT@@ --config prd -- /usr/bin/bash -c 'export INNGEST_SIGNING_KEY="$${INNGEST_SIGNING_KEY#signkey-prod-}"; @@BACKEND_ENV@@exec /usr/local/bin/inngest start --host 0.0.0.0 --port 8288 --sqlite-dir /var/lib/inngest @@BACKEND_FLAGS@@ --poll-interval 60 --sdk-url @@SDK_URL@@'
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

# #5547 Gap 2 + #5560: substitute the @@BACKEND_ENV@@ + @@BACKEND_FLAGS@@ sentinels
# based on Redis readiness. Secrets are delivered via the ENVIRONMENT (BACKEND_ENV),
# never argv (#5560) — BACKEND_FLAGS carries only the NON-SECRET --postgres-max-open-conns
# durable-detection sentinel.
#   REDIS_READY=1 → durable: export INNGEST_REDIS_URI (from the password) so inngest
#                   reads it from env; INNGEST_POSTGRES_URI is left in the doppler env
#                   for inngest to read; argv carries --postgres-max-open-conns (sentinel).
#   REDIS_READY=0 → SQLite-only fail-safe: `unset INNGEST_POSTGRES_URI` so inngest does
#                   NOT pick it up from the doppler env and connect to Postgres (it is a
#                   prd Doppler secret present in BOTH branches' scope — the unset is
#                   LOAD-BEARING, #5560); empty flags; inngest stays available on SQLite
#                   rather than crash-looping. verify_inngest_health then SKIPs the durable
#                   gate (sentinel absent) and a rollback deploy succeeds.
# --sqlite-dir stays in the SHARED prefix above (load-bearing in the SQLite form,
# vestigial-but-harmless in the durable form). Use bash parameter expansion (NOT sed):
# the fragments contain `/`, `&`, and the literal `$${...}` Doppler token, all of which
# sed's replacement string would mangle. The fragments are single-quoted so `$${...}`
# stays literal until systemd unescapes $$→$ and the doppler-wrapped bash -c expands the
# injected env (same $${...} contract as before). The `exec` in the ExecStart keeps
# inngest as the unit's main PID (Type=simple signal/drain/`inngest pause` semantics).
if [[ "$REDIS_READY" == "1" ]]; then
  BACKEND_ENV='export INNGEST_REDIS_URI="redis://:$${INNGEST_REDIS_PASSWORD}@127.0.0.1:6379"; '
  BACKEND_FLAGS='--postgres-max-open-conns 10'
  log "inngest-server ExecStart: durable backend (env-delivered URIs; --postgres-max-open-conns sentinel)"
else
  BACKEND_ENV='unset INNGEST_POSTGRES_URI; '
  BACKEND_FLAGS=''
  log "inngest-server ExecStart: SQLite-only fail-safe (INNGEST_DURABLE_DEGRADED — Redis not ready)"
fi
unit_content="$(cat "$UNIT_FILE")"
unit_content="${unit_content//@@BACKEND_ENV@@/$BACKEND_ENV}"
unit_content="${unit_content//@@BACKEND_FLAGS@@/$BACKEND_FLAGS}"
# #6178: same bash-parameter-expansion mechanism (NOT sed — SDK_URL contains `/`).
unit_content="${unit_content//@@SDK_URL@@/$SDK_URL}"
unit_content="${unit_content//@@DOPPLER_PROJECT@@/$DOPPLER_PROJECT}"
printf '%s\n' "$unit_content" > "$UNIT_FILE"

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
# The sink reads BETTERSTACK_LOGS_TOKEN, Doppler-injected at ExecStart via
# `doppler run --project @@DOPPLER_PROJECT@@ --config prd`. On the dedicated
# arm64 host that token lives in the isolated soleur-inngest project (#6197).
#
# Idempotency: matches the inngest path — version file at
# `/var/lib/vector/version`, sha256-verify on download, skip-install when
# version matches.
# ----------------------------------------------------------------------

VECTOR_CLI_VERSION="${VECTOR_CLI_VERSION:-}"
VECTOR_CLI_SHA256="${VECTOR_CLI_SHA256:-}"
# arm64 support (#6197): mirror the INNGEST_CLI_ARCH pattern (:37/:53-56). Default amd64
# PRESERVES the co-located web host (cross-consumer edit — hr-type-widening-cross-consumer-grep).
# Vector's release triple names arm64 as `aarch64` (NOT `arm64`, ≠ the Inngest CLI's
# `linux_arm64`), so the map below translates arm64→aarch64 for Vector specifically.
VECTOR_CLI_ARCH="${VECTOR_CLI_ARCH:-amd64}"
case "$VECTOR_CLI_ARCH" in
  amd64) vec_triple="x86_64-unknown-linux-musl" ;;
  arm64) vec_triple="aarch64-unknown-linux-musl" ;;
  *) echo "ERROR: VECTOR_CLI_ARCH must be amd64 or arm64 (got '$VECTOR_CLI_ARCH')" >&2; exit 1 ;;
esac

if [[ -z "$VECTOR_CLI_VERSION" || -z "$VECTOR_CLI_SHA256" ]]; then
  log "warn: VECTOR_CLI_VERSION + VECTOR_CLI_SHA256 unset — skipping Vector install (observability shipper deferred until next bootstrap)"
else
  readonly VECTOR_INSTALL_PATH="/usr/local/bin/vector"
  readonly VECTOR_VERSION_FILE="/var/lib/vector/version"
  readonly VECTOR_CONFIG_DIR="/etc/vector"
  readonly VECTOR_CONFIG="$VECTOR_CONFIG_DIR/vector.toml"
  readonly VECTOR_UNIT="/etc/systemd/system/vector.service"
  readonly VECTOR_DOWNLOAD_URL="https://packages.timber.io/vector/${VECTOR_CLI_VERSION}/vector-${VECTOR_CLI_VERSION}-${vec_triple}.tar.gz"

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
    install -m 0755 "$tmp"/vector-${vec_triple}/bin/vector "$VECTOR_INSTALL_PATH"
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
ExecStart=/usr/bin/doppler run --project @@DOPPLER_PROJECT@@ --config prd -- /usr/local/bin/vector --config /etc/vector/vector.toml
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
      # #6178: render the @@DOPPLER_PROJECT@@ sentinel (same bash-param-expansion as the
      # server/redis units; default `soleur` preserves the web host). Load-bearing for the
      # deferred arm64-Vector follow-up: without this, when the dedicated host later sets
      # VECTOR_CLI_*, this unit would run `doppler run --project soleur` under the scoped
      # soleur-inngest token → FAIL (or force a token-widen that defeats AC3 isolation).
      vector_unit_content="$(cat "$VECTOR_UNIT")"
      vector_unit_content="${vector_unit_content//@@DOPPLER_PROJECT@@/$DOPPLER_PROJECT}"
      printf '%s\n' "$vector_unit_content" > "$VECTOR_UNIT"

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

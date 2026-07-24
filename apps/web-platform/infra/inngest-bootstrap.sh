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
# #6178: the co-located web host is amd64; the dedicated inngest host is DUAL-ARCH.
# Default amd64 PRESERVES the web-host behavior (cross-consumer edit —
# hr-type-widening-cross-consumer-grep); the dedicated host's cloud-init passes
# INNGEST_CLI_ARCH (arm64 on a cax* type, amd64 otherwise) AND an arch-matching
# INNGEST_CLI_SHA256 (the wrong-arch image-baked SHA would fail the verify below).
INNGEST_CLI_ARCH="${INNGEST_CLI_ARCH:-amd64}"
# #6178 cross-consumer templating (defaults PRESERVE the co-located web-host behavior;
# the dedicated inngest host overrides both). SDK_URL: the app serve URL inngest syncs +
# invokes (Phase-0.2 spike: route-once → a single stable URL; the dedicated host points
# at the active web backend's private interface). DOPPLER_PROJECT selects the ISOLATED
# `soleur-inngest` project (AC3) on the dedicated host vs `soleur` on the co-located web host.
# Since #6555 the units no longer pass `--project`; DOPPLER_PROJECT is delivered to them via
# EnvironmentFile=/etc/default/inngest-server (written by cloud-init-inngest.yml's env-file
# pre-create / the bootstrap heredoc + the in-place augment below). This shell var still GATES
# which arms render (heartbeat dark arm, flip units, DEDICATED_FLIP) below.
SDK_URL="${SDK_URL:-http://127.0.0.1:3000/api/inngest}"
# EXPORTED so child bootstrap subprocesses inherit it. Default `soleur` preserves the web host.
# SOLEUR-DEBT: the `${DOPPLER_PROJECT:-soleur}` render-time default renders the WRONG (web) arm on the dedicated host if cloud-init's inline `env DOPPLER_PROJECT=soleur-inngest` ever fails to reach here, and the #6555 fail-closed backstop below is a PRESENCE check not a VALUE check so a wrong-but-present `soleur` passes it; when a dedicated-host in-place re-bootstrap path is ever added (the dedicated host is force-replace-only today) fail-close the default AND assert the value == soleur-inngest when the host carries the soleur-inngest Doppler token.
# Detector for a wrong render (indirect — the field reports arm-render, not project identity):
# cat-deploy-state.sh's `inngest_heartbeat_dark_arm` field (#6536), read no-SSH over
# /hooks/deploy-status. #6555 removed the RUNTIME `--project` surface (units resolve the project
# from the env-file) but NOT this render-time default. Ref #6555.
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
# #6556 Part 2: OnFailure target for inngest-heartbeat.service — a push-less, queryable-only
# oneshot that emits an ERR-priority `inngest-heartbeat` line when the heartbeat unit fails.
readonly HEARTBEAT_FAILURE_LOG_UNIT="/etc/systemd/system/inngest-heartbeat-failure-log.service"
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
# `doppler run --config prd` (the project comes from DOPPLER_PROJECT in the
# EnvironmentFile below, #6555; same pattern as inngest-server.service above).
# The earlier shape relied on systemd's
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
#
# LOG_TAG is a REAL assignment, never an inline tag literal in the logger call: the drift
# fixture at test/infra/vector-pii-scrub.test.sh:392-404 derives the expected
# SYSLOG_IDENTIFIER set from `^\s*(readonly\s+)?LOG_TAG="..."` across infra/*.sh. Its
# `logger -t` probe is heredoc-blind, so a literal would pull THIS file into the fixture's
# loop and yield NO tag -- hard-failing that fixture's exact-set equality.
LOG_TAG="inngest-heartbeat"
#
# --- #6617b: dark-arm rate limiter ---------------------------------------------------------
# Reachable ONLY from the dark arm rendered below (the live co-located host's render deletes
# that arm entirely, so on that host this function is defined and never called). It exists as a
# function rather than inline in the sed replacement because the replacement is a single
# `s|...|...|` expression with \n escapes -- readable logic does not survive in there.
#
# WHY rate-limit rather than emit once: the dark arm fires every 60s and each fire ships a row
# through Source 4 (no PRIORITY filter) -- ~1,440 rows/day of an unchanging message, against a
# ~25k/day quota. But "emit once per boot" or "emit only on transition" would make a DEAD
# pusher and a healthy deliberately-dark one produce the identical observation: nothing. That
# is the #6617 failure exactly, and ADR-117 names it -- a monitor that "goes silent exactly
# when someone ships a probe". Hourly keeps the positive control at ~1.7% of the row cost.
#
# FAILS OPEN, deliberately: if the stamp cannot be read or written (RuntimeDirectory missing,
# disk full) this returns 0 and the marker still ships. The degraded mode is then today's row
# volume -- loud and visible -- rather than a silently disarmed liveness signal. Quota is
# recoverable; a blind host is what this whole change exists to end.
#
# That guarantee needed one more case to actually hold. A FUTURE-DATED stamp is not a read or
# write failure, so none of the guards below caught it, and it failed CLOSED: boot before NTP
# writes `now+skew`; timesyncd then steps the clock BACK; `_now - _last` goes NEGATIVE, never
# reaches `>= _interval`, and the marker is suppressed for the whole skew duration. On a host
# whose liveness signal IS this marker, a clock correction would read as a dead pusher --
# ADR-117's "goes silent exactly when someone ships a probe", reintroduced through the stamp.
# `_last` is now clamped to `_now`, so a future stamp reads as "never emitted" and emits.
dark_arm_emit_due() {
  # Override exists for the test harness, which must supply a writable stamp path; production
  # takes the default, which inngest-heartbeat.service provisions via RuntimeDirectory=.
  _stamp="${INNGEST_HEARTBEAT_DARK_STAMP:-/run/inngest-heartbeat/dark.stamp}"
  _interval=${INNGEST_HEARTBEAT_DARK_INTERVAL:-3600}
  _now="$(date +%s 2>/dev/null || true)"
  # No usable clock -> emit. Never let a broken read suppress the marker.
  case "$_now" in '' | *[!0-9]*) return 0 ;; esac
  _last="$(cat "$_stamp" 2>/dev/null || true)"
  # A truncated/garbage stamp reads as "never emitted", not as "emitted just now".
  case "$_last" in '' | *[!0-9]*) _last=0 ;; esac
  # A stamp in the FUTURE (boot-before-NTP wrote now+skew, then timesyncd stepped back) reads
  # as "never emitted" too. Without this the subtraction goes negative and suppresses the
  # marker for the entire skew -- the one path where this function failed CLOSED.
  [ "$_last" -le "$_now" ] || _last=0
  [ "$(( _now - _last ))" -ge "$_interval" ] || return 1
  printf '%s' "$_now" > "$_stamp" 2>/dev/null || true
  return 0
}
#
# @@DARK_ARM@@ -- substituted at RENDER time by inngest-bootstrap.sh (see the render block
# just below): the skip branch on the dedicated host, EMPTY on the co-located web host.
#
# An absent INNGEST_HEARTBEAT_URL is NOT a curl no-op. `curl -fsS --max-time 10 ""` exits 2
# ("option : blank argument where content is expected" -- measured, #6536); unset behaves
# identically. That is why this oneshot failed every 60s for 3 days (3,724 fires) on the dark
# host, and why inngest-host.tf's old "curl no-ops" claim was false. Same class as #4116.
#
# The dark host legitimately has NO url: inngest-host.tf:137-151 keeps one unambiguous pusher
# per monitor and provisions the URL out-of-band only AT cutover (op=arm). So skipping is
# correct THERE and only there. The co-located web host is TODAY'S live pusher and gets no
# arm at all -- an absent URL there is always a real fault and must stay loud.
@@DARK_ARM@@
# -g (--globoff): the URL is a BEARER capability. Without -g, a URL containing [ ] or
# { } makes curl print the FULL URL in its glob-parse error (`curl: (3) bad range in URL
# position N:` followed by the URL) — measured, curl 8.18 — which FR4's SyslogIdentifier
# now ships straight to Better Stack. -g disables globbing (we never glob) and the echo
# with it. Belt to cat-deploy-state.sh's braces: neither alone is sufficient.
exec /usr/bin/curl -gfsS --max-time 10 "$INNGEST_HEARTBEAT_URL" >/dev/null
HEARTBEATSCRIPTEOF
chmod 0755 "$HEARTBEAT_SCRIPT"

# @@DARK_ARM@@ render begin (#6536)
# Host identity is resolved into DIFFERENT ARTIFACTS at render time, never shipped into the
# script for a runtime `if`. This is the house pattern already used twice in this file:
# `sed -i 's|@@HOST_NAME@@|...|'` on the Vector config below, and @@FLIP_GUARD_EXECSTARTPRE@@
# on inngest-server.service above ("ON THE DEDICATED HOST ONLY (empty on the co-located web
# host)"). The consequence is the point: the LIVE co-located pusher's script has NO exit-0
# branch to reach, so masking a real fault there is structurally unreachable, not merely gated.
#
# Deliberately NO INNGEST_CUTOVER_FLIP case: url-presence is sufficient (op=arm writes the URL
# at G4 BEFORE flip=armed at G5), and an 8-state FSM that ADR-100 owns -- and
# inngest-cutover-flip.sh implements once -- must not be copied a third time into a 20-line
# liveness probe. A fail-closed `*)` arm would reintroduce this very bug: a future #6178 state
# would land in it, exit 1 on a dark host, and restore the 60s storm.
#
# The heredoc above MUST stay QUOTED. The tempting way to render this sentinel is to unquote
# it so the shell expands at bootstrap -- that would ALSO expand $INNGEST_HEARTBEAT_URL into
# /usr/local/bin/inngest-heartbeat.sh, a 0755 WORLD-READABLE file, writing the bearer
# capability to disk in plaintext and defeating the script-indirection control at :156-159.
# AC3's canary asserts the script's runtime OUTPUT, not the file's CONTENTS, so AC3 would
# pass while the secret sat on disk. `sed -i` on the quoted heredoc is the only safe render.
# Both seds anchor on the STANDALONE sentinel line (^...$). An unanchored `s|@@DARK_ARM@@|`
# also rewrites the sentinel's own mention inside the comment above, corrupting the script --
# caught by the sh -n leg of the render test.
if [[ "$DOPPLER_PROJECT" == "soleur-inngest" ]]; then
  # #6617b: the logger call is now gated on dark_arm_emit_due (hourly), NOT on any state
  # transition -- see that function. `exit 0` stays OUTSIDE the gate: the storm fix from #6536
  # is that an absent URL must never reach curl, and that is independent of whether this
  # particular fire is the one that logs.
  sed -i 's|^@@DARK_ARM@@$|if [ -z "$INNGEST_HEARTBEAT_URL" ]; then\n  if dark_arm_emit_due; then\n    logger -t "$LOG_TAG" "url_present=no — no heartbeat URL provisioned; skipping ping (hourly rate-limited, #6617b)"\n  fi\n  exit 0\nfi|' "$HEARTBEAT_SCRIPT"
  log "inngest-heartbeat: dark arm RENDERED (DOPPLER_PROJECT=$DOPPLER_PROJECT) — an absent URL skips the ping and logs why, hourly"
else
  sed -i '/^@@DARK_ARM@@$/d' "$HEARTBEAT_SCRIPT"
  log "inngest-heartbeat: dark arm OMITTED (DOPPLER_PROJECT=$DOPPLER_PROJECT) — live pusher; an absent URL stays loud (curl rc=2)"
fi
# @@DARK_ARM@@ render end

# Resolve the doppler binary path at bootstrap time. cloud-init installs to
# /usr/local/bin/doppler (the `chmod +x /usr/local/bin/doppler` step in
# cloud-init.yml); inngest-server.service:137 hardcodes /usr/bin/doppler.
# Interpolating `command -v` here avoids inheriting that latent path
# discrepancy in the heartbeat unit.
DOPPLER_BIN="$(command -v doppler 2>/dev/null || true)"
if [[ -z "$DOPPLER_BIN" ]]; then
  log "ERROR: doppler CLI not found on PATH — cloud-init must install /usr/local/bin/doppler before inngest-bootstrap"
  exit 1
fi

cat > "$HEARTBEAT_UNIT" <<HEARTBEATEOF
[Unit]
Description=Inngest server heartbeat ping to Better Stack
After=network-online.target
# #6556 Part 2: on failure, fire a push-less oneshot that emits an ERR-priority
# `inngest-heartbeat` line so a unit failure is READABLE off-box (no SSH). Before this, a
# heartbeat failure surfaced only as the un-shippable SYSLOG_IDENTIFIER=systemd "Failed to
# start" journal row (the #6551 signature); now it also ships on the inngest-heartbeat channel.
OnFailure=inngest-heartbeat-failure-log.service

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
# #6536 ROUND 2 — this line is why the unit failed, and its absence is what 3,724 fires were.
# MEASURED on the fresh host (the FIRST thing the SyslogIdentifier= channel below ever
# shipped): `Doppler Error: open /tmp/.doppler/.doppler.yaml.XXXX: permission denied`.
#
# The env file above sets DOPPLER_CONFIG_DIR=/tmp/.doppler for EVERY doppler-wrapped unit.
# That path is only safe under PrivateTmp: cloud-init-inngest.yml's boot isolation
# self-check runs `doppler secrets` as ROOT (with HOME=/root and the same
# DOPPLER_CONFIG_DIR, cloud-init-inngest.yml:212/226/289), so /tmp/.doppler exists
# ROOT-OWNED from first boot. A unit with a PRIVATE /tmp never sees it and the CLI
# recreates it as `deploy`; this unit shared the host /tmp and could not write there, so
# `doppler run` died BEFORE exec -- the ping script never ran at all. Both siblings
# (inngest-server, vector) already set this; the heartbeat was the lone omission, which is
# exactly why they work and it did not.
#
# The #6536 plan REFUTED this hypothesis (H3) on reasoning: "they use different /tmps and
# cannot collide" + "nothing mkdirs /tmp/.doppler; the CLI creates it lazily as deploy".
# Both halves are false. The collision is not heartbeat-vs-sibling, it is
# heartbeat-vs-ROOT's-boot-self-check; and the CLI creates it lazily as ROOT, before this
# unit's first fire. It also explains the onset the plan could not attribute (13:00:38Z =
# the host's boot, not a deploy): this unit has failed since its very first fire.
# Do NOT remove without moving DOPPLER_CONFIG_DIR off the shared /tmp.
PrivateTmp=true
# #6617b: the dark arm's hourly rate limiter keeps its last-emit stamp at
# /run/inngest-heartbeat/dark.stamp. This unit runs User=deploy and /run is root-owned 0755,
# so deploy cannot create anything there directly -- without RuntimeDirectory= the stamp write
# fails on every fire, the limiter never engages, and the quota fix is a silent no-op.
# PrivateTmp=true above does NOT cover /run, so this is the right mechanism (and /tmp is
# already spoken for by the DOPPLER_CONFIG_DIR collision documented above).
# RuntimeDirectoryPreserve=yes is equally load-bearing: this is a Type=oneshot, so systemd
# tears the directory down the moment ExecStart returns -- taking the stamp with it and
# restoring the 60s storm this rate limit removes.
RuntimeDirectory=inngest-heartbeat
RuntimeDirectoryPreserve=yes
# #6536: WITHOUT this, systemd derives SYSLOG_IDENTIFIER from the ExecStart basename ->
# "doppler", which matches ZERO vector.toml sources. The unit's own stderr (doppler's AND
# curl's) then never leaves the host: the issue's _SYSTEMD_UNIT='inngest-heartbeat.service'
# query returned zero rows for exactly this reason -- not a Better Stack retention gap.
# Retagging onto the "inngest-heartbeat" channel (vector.toml Source 4, which carries NO
# PRIORITY filter and so admits this unit's PRIORITY-6 output) is what makes the
# "no row at all + unit failed" signature readable off-box, with no SSH.
# This line is what made the PrivateTmp defect above diagnosable in 2 minutes, off-box,
# after 3 days of a blind 60s storm. It earned its keep before the fix it shipped with did.
SyslogIdentifier=inngest-heartbeat
ExecStart=${DOPPLER_BIN} run --config prd -- ${HEARTBEAT_SCRIPT}
HEARTBEATEOF

# #6556 Part 2 — the OnFailure target for inngest-heartbeat.service. Non-templated (ONE
# consumer, so no `@`/%i template — cf. cron-egress-alarm@ which earns its template from two
# consumers) and rendered as a bootstrap heredoc like every other inngest unit (no standalone
# tracked file, no server.tf delivery entry, no separate pinning test). Quoted delimiter — the
# body is fully literal (no shell expansion). Loaded by the daemon-reload below; NOT enabled
# (systemd triggers it via the heartbeat unit's OnFailure=, not a [Install] wants).
cat > "$HEARTBEAT_FAILURE_LOG_UNIT" <<'FAILLOGEOF'
[Unit]
Description=Log an ERR-priority marker when inngest-heartbeat.service fails (#6556)
# QUERYABLE, NOT ALARMING. This oneshot emits a single ERR line on the inngest-heartbeat
# Vector -> Better Stack channel (vector.toml Source 4) so a heartbeat-unit failure is readable
# off-box with NO SSH — it turns the failure systemd otherwise emits as the un-shippable
# SYSLOG_IDENTIFIER=systemd "Failed to start" row (the #6551 signature) into a shippable
# inngest-heartbeat line.
#
# It deliberately does NOT push to any monitor. One-unambiguous-pusher-per-monitor
# (inngest-host.tf:137-171): the LIVE co-located pusher's alarm IS the Better Stack heartbeat
# MONITOR (missing pings redden it in ~90s); the dark host has no monitor push by design.
# POST-CUTOVER this stays correct — once the dedicated host BECOMES the live pusher, the
# monitor's missing-pings alarm covers it and this log line remains the diagnostic. Do NOT
# "complete" this unit by adding a monitor push.

[Service]
Type=oneshot
# Reuse the existing Source 4 tag (vector.toml) — no new allowlist entry, no fresh quota decision.
SyslogIdentifier=inngest-heartbeat
# Bare `logger`, NO `doppler run` wrapper: this unit emits only a fixed marker and needs no
# secrets. A `doppler run --project …` wrapper would hardcode a project (WRONG on the
# soleur-inngest host) and re-introduce the exact project-resolution surface #6555 removes.
ExecStart=/usr/bin/logger -t inngest-heartbeat -p err "inngest-heartbeat.service entered failed state (OnFailure) — the 60s ping failed; see the preceding inngest-heartbeat lines for the underlying ping error (#6556)"
FAILLOGEOF

# AccuracySec=1s added by #6537. systemd's default is 1 MINUTE, so this timer fires anywhere in
# [elapse, elapse+60s] — an interval of 60s+delta, structurally bounded at 120s, against
# inngest_prd's 60s period + 30s grace (a 90s deadline). Measured A/B on this exact unit shape:
# unset drifted 60.0s / 62.0s / 72.6s / 66.5s; AccuracySec=1s held 61.0s +/- 16ms. This monitor is
# live and up today on margin, not by design — systemd's coalescing offset derives from the BOOT
# ID, so today's greenness is evidence about this boot only and is re-rolled by every host
# replace. Takes effect on the next inngest-host-replace; harmless until then.
# (Persistent=true below is a no-op for a monotonic timer — it only applies to OnCalendar — but is
# left as-is: removing it is unrelated to this fix.)
cat > "$HEARTBEAT_TIMER" <<'TIMEREOF'
[Unit]
Description=Run Inngest heartbeat every 60s

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=1s
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

# --- #6617a (A4): POSITIVE liveness marker for inngest-server -------------------------
# The dedicated host is deny-all-public with no SSH: the ONLY evidence that inngest-server
# is actually serving is what it ships off-box. Every existing signal is an ABSENCE signal
# (no heartbeat push, no journal line), and #6617 is the lesson that absence is not
# evidence — a dead probe and a healthy quiet host are the same row count: zero.
#
# TWO properties are load-bearing, and each one is a defect this repo has already paid for:
#
# 1. EMITTED UNCONDITIONALLY, BEFORE ANY CLASSIFICATION (ADR-117 / #6537). There is no `if`
#    in front of the `logger` call below and there must never be one. The tempting shape —
#    "only log when something is wrong" — is precisely what ADR-117 describes as a monitor
#    that "goes silent exactly when someone ships a probe": it deletes the positive control,
#    after which silence means either health or death and nothing can tell them apart.
#
# 2. DISCRIMINATING FIELDS, IN ONE EVENT. A boolean/OK-vs-not marker reproduces #6617 one
#    layer up: you would learn the probe ran and still not know WHY the server was down.
#    The fields are gathered first and shipped in a SINGLE logger call so one row is
#    self-sufficient — no correlating across rows that Better Stack may interleave or drop:
#      http_code    — including the literal 000 (curl could not connect at all), which is
#                     the single most diagnostic value here and the one a naive
#                     `curl -f && logger` shape silently discards
#      vector_active/redis_active — is the SHIPPER dead, or the SERVER? #6536 burned 3 days
#                     on exactly this ambiguity
#      uptime_s     — discriminates "never came up after boot" from "died later"
#      boot_id      — ties rows to one boot; a host replace re-rolls it, so it is how you
#                     tell a fresh host's first probe from the previous host's last one
#      image_ref    — WHICH bootstrap image produced this host (CF-3: vector.toml and this
#                     very script are OCI-baked, so "the fix is on main" never implied "the
#                     fix is on the host"; #6539 measured two releases that carried none of
#                     the fix they were dispatched for)
#
# Runs as root but wraps NO doppler: it needs no secrets (a bare `logger` + `curl` to
# loopback), so it inherits neither the $HOME-is-not-defined trap nor the
# DOPPLER_CONFIG_DIR/PrivateTmp collision that cost #6536 three days. If a future edit adds
# `doppler run` here, it MUST also set Environment=HOME=/root.
readonly PROBE_SCRIPT="/usr/local/bin/inngest-server-probe.sh"
readonly PROBE_UNIT="/etc/systemd/system/inngest-server-probe.service"
readonly PROBE_TIMER="/etc/systemd/system/inngest-server-probe.timer"

# Quoted delimiter: the body is fully literal. Unquoting it would expand $http_code et al at
# BOOTSTRAP time (yielding an empty-field marker that always reads healthy) and would break
# curl's `%{http_code}` writeout — the same quoted-heredoc discipline as the heartbeat script.
cat > "$PROBE_SCRIPT" <<'PROBESCRIPTEOF'
#!/bin/sh
# Positive liveness marker for inngest-server (#6617a). Fired by inngest-server-probe.timer.
#
# LOG_TAG is a REAL assignment, never an inline literal in the logger call — same drift-fixture
# contract as inngest-heartbeat.sh. The matching Source 4 allowlist entry is in vector.toml;
# journald-config.test.sh asserts BOTH sides, because Source 4 is exact-value equality and a
# one-sided change is a silent no-op.
LOG_TAG="inngest-server-probe"

# --- gather (never branch on the results before the emit below) ---
# `|| true` on every capture: this probe must ALWAYS reach its logger call. A non-zero curl
# under a future `set -e`, or a missing systemctl, must degrade a FIELD, never the event.
http_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8288/health 2>/dev/null || true)"
# curl writes 000 for "no HTTP response at all" but prints nothing when it cannot even start;
# normalize both to the literal 000 so "could not connect" is a VALUE, not an empty field that
# reads as missing data.
[ -n "$http_code" ] || http_code=000
vector_active="$(systemctl is-active vector.service 2>/dev/null || true)"
redis_active="$(systemctl is-active inngest-redis.service 2>/dev/null || true)"
server_active="$(systemctl is-active inngest-server.service 2>/dev/null || true)"
[ -n "$vector_active" ] || vector_active=unknown
[ -n "$redis_active" ] || redis_active=unknown
[ -n "$server_active" ] || server_active=unknown
uptime_s="$(cut -d. -f1 /proc/uptime 2>/dev/null || true)"
[ -n "$uptime_s" ] || uptime_s=unknown
boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
[ -n "$boot_id" ] || boot_id=unknown
# Written by cloud-init-inngest.yml immediately after the OCI pull, from the SAME digest-pinned
# $IREF the bootstrap was extracted from. Absent on the co-located web host (whose IREF is
# reassigned at runtime by the zot arm) -> `unknown`, which is honest rather than wrong.
#
# Named image_REF, not image_sha: cloud-init-inngest.yml writes INNGEST_BOOTSTRAP_IMAGE=$IREF,
# and $IREF is the FULL reference -- `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.24@sha256:
# 6cdaa63...` -- not a bare digest. A Better Stack consumer keying on `image_sha=sha256:` would
# match nothing forever, which is the silent-gap class this probe exists to close. The full ref
# is also the MORE useful value (registry + tag + digest in one field); only the name was wrong.
image_ref="$(sed -n 's/^INNGEST_BOOTSTRAP_IMAGE=//p' /etc/default/soleur-inngest-image 2>/dev/null | head -1 || true)"
[ -n "$image_ref" ] || image_ref=unknown

# --- emit: unconditional, one event, all fields. NO `if` may precede this line. ---
logger -t "$LOG_TAG" "SOLEUR_INNGEST_SERVER_PROBE http_code=$http_code server_active=$server_active vector_active=$vector_active redis_active=$redis_active uptime_s=$uptime_s boot_id=$boot_id image_ref=$image_ref"

# --- second channel, AFTER the unconditional emit above (ADR-117 unaffected) ---
# vector_active is the ONE field whose only off-box path is Vector itself: this marker reaches
# Better Stack via journald -> Vector Source 4. So `vector_active=inactive` is unobservable by
# construction -- exactly when the field carries information, the shipper that would carry it
# is the thing that is down, and the row never leaves the host. The result is indistinguishable
# from a dead host, which is the ambiguity #6536 burned three days on.
#
# inngest-boot-phone-home.sh is a direct curl to the Better Stack HTTP ingest (see
# cloud-init-inngest.yml), independent of Vector entirely, and it lands in the SAME source
# table. Firing it only on the non-active branch keeps the steady-state row cost at zero.
#
# This `if` is placed AFTER the emit and gates only the SECOND channel -- ADR-117 forbids
# branching BEFORE the unconditional emit, not after it. Fail-open: the emitter exits 0 on any
# error and is absent on the co-located web host, so `[ -x ]` guards it.
if [ "$vector_active" != "active" ] && [ -x /usr/local/bin/inngest-boot-phone-home.sh ]; then
  /usr/local/bin/inngest-boot-phone-home.sh inngest-server-probe-vector-down "http_code=$http_code server_active=$server_active vector_active=$vector_active redis_active=$redis_active uptime_s=$uptime_s boot_id=$boot_id image_ref=$image_ref" || true
fi
exit 0
PROBESCRIPTEOF
chmod 0755 "$PROBE_SCRIPT"

cat > "$PROBE_UNIT" <<'PROBEUNITEOF'
[Unit]
Description=Inngest server positive liveness marker (#6617a)

[Service]
Type=oneshot
# WITHOUT this, systemd derives SYSLOG_IDENTIFIER from the ExecStart basename, which matches
# ZERO vector.toml sources and the marker never leaves the host — the #6536 defect exactly.
# Source 4 (vector.toml host_scripts_journald) carries the matching exact-value entry.
SyslogIdentifier=inngest-server-probe
ExecStart=/usr/local/bin/inngest-server-probe.sh
PROBEUNITEOF

# Hourly, not per-minute. Source 4 applies NO PRIORITY filter, so every fire ships a row: at
# 60s this marker alone would cost ~1,440 rows/day against the ~25k/day Better Stack quota —
# the very cost #6617b is removing from the heartbeat in this same change. Hourly is ~24
# rows/day, which preserves the positive control at ~1.7% of the cost. OnBootSec is short
# because the highest-value probe is the one right after a replace (did the new image's
# server actually bind :8288?).
cat > "$PROBE_TIMER" <<'PROBETIMEREOF'
[Unit]
Description=Run the Inngest server liveness probe hourly (#6617a)

[Timer]
OnBootSec=90s
OnUnitActiveSec=1h
AccuracySec=1min

[Install]
WantedBy=timers.target
PROBETIMEREOF

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
  # #6555: the units dropped `--project` and now resolve the Doppler project from this file's
  # DOPPLER_PROJECT line. An env-file preserved from before #6555 lacks it, so append it
  # idempotently — otherwise an in-place re-bootstrap (ci-deploy runs this bootstrap directly on
  # the co-located web host, preserving the existing token) would start units against the
  # `${DOPPLER_PROJECT:-soleur}` default, or trip the fail-closed backstop below and down
  # inngest-server. Append only when absent.
  if ! grep -qE '^DOPPLER_PROJECT=' /etc/default/inngest-server; then
    printf 'DOPPLER_PROJECT=%s\n' "$DOPPLER_PROJECT" >> /etc/default/inngest-server
    log "/etc/default/inngest-server: appended DOPPLER_PROJECT=$DOPPLER_PROJECT (#6555 in-place augment)"
  fi
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
DOPPLER_PROJECT=$DOPPLER_PROJECT
DOPPLEREOF
  )
  chown root:deploy /etc/default/inngest-server
  chmod 0640 /etc/default/inngest-server
fi

# #6555 fail-closed backstop: every doppler-wrapped inngest unit resolves its project from
# DOPPLER_PROJECT in /etc/default/inngest-server (--project was dropped). If the line is missing
# or empty, `doppler run` falls back to the `${DOPPLER_PROJECT:-soleur}` default — the WRONG
# project on the dedicated host, which would start the dedicated scheduler against the co-located
# project. Refuse to start. On a fresh host cloud-init-inngest.yml's env-file pre-create
# (dedicated) or the heredoc above (web) writes it; on an existing host the preserve-branch
# augment adds it — so this should never fire in normal operation; it catches a genuinely broken
# env-file BEFORE any unit starts. Non-empty check (AC6): a bare `DOPPLER_PROJECT=` is as wrong as
# an absent one. NOTE it is a PRESENCE check, not a VALUE check — see the SOLEUR-DEBT marker above
# for the wrong-but-present-value residual (not reachable via today's web-host-only ci-deploy).
if ! grep -qE '^DOPPLER_PROJECT=[^[:space:]]' /etc/default/inngest-server 2>/dev/null; then
  log "ERROR: /etc/default/inngest-server has no non-empty DOPPLER_PROJECT= line. The inngest units resolve their Doppler project from it (--project dropped, #6555). Refusing to start units against a possibly-wrong project — force-replace the host (fresh disk) so cloud-init re-creates the env-file with DOPPLER_PROJECT."
  exit 1
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

# Cutover flip trio + arm-atomicity guard (#6178, ADR-100) — DEDICATED HOST ONLY.
# Gated on DOPPLER_PROJECT=soleur-inngest so the co-located web host (project `soleur`,
# which shares this same bootstrap image) never installs the flip oneshot NOR gets a
# start-blocking ExecStartPre guard on its inngest-server (cross-consumer safety —
# hr-type-widening-cross-consumer-grep: the web host's INNGEST_POSTGRES_URI is prod with
# no INNGEST_CUTOVER_FLIP, which the guard would read as "block"). The flip assets are staged
# to /tmp by cloud-init's docker-cp extraction block (cloud-init-inngest.yml, alongside the
# redis/vector assets) — NOT by the OCI image ENTRYPOINT: the dedicated host does `docker
# create` + `docker cp` then runs THIS script on the host, so the image entrypoint never fires
# for this path. (Mis-attributing the staging to the entrypoint is what masked #6178 — the
# entrypoint's cp existed, the cloud-init cp did not, so the assets never reached /tmp and this
# gate silently fell through to DEDICATED_FLIP=0.) This runs BEFORE the inngest-server unit
# write + restart below so the ExecStartPre guard script exists on disk first.
DEDICATED_FLIP=0
if [[ "$DOPPLER_PROJECT" == "soleur-inngest" ]]; then
  if [[ -f /tmp/inngest-cutover-flip.sh && -f /tmp/inngest-server-flip-guard.sh \
        && -f /tmp/inngest-cutover-flip.service && -f /tmp/inngest-cutover-flip.timer ]]; then
    log "installing cutover flip trio + arm-atomicity guard (#6178)"
    install -m 0755 /tmp/inngest-cutover-flip.sh /usr/local/bin/inngest-cutover-flip.sh
    install -m 0755 /tmp/inngest-server-flip-guard.sh /usr/local/bin/inngest-server-flip-guard.sh
    # cat-inngest-cutover-state.sh is an on-host debug aid only (NOT the operator gate).
    if [[ -f /tmp/cat-inngest-cutover-state.sh ]]; then
      install -m 0755 /tmp/cat-inngest-cutover-state.sh /usr/local/bin/cat-inngest-cutover-state.sh
    fi
    # #6555: the oneshot unit no longer carries a @@DOPPLER_PROJECT@@ sentinel (--project
    # dropped; it resolves the project from EnvironmentFile at runtime). Install it verbatim
    # like the timer below — no substitution round-trip that could mask a re-introduction.
    install -m 0644 /tmp/inngest-cutover-flip.service /etc/systemd/system/inngest-cutover-flip.service
    install -m 0644 /tmp/inngest-cutover-flip.timer /etc/systemd/system/inngest-cutover-flip.timer
    DEDICATED_FLIP=1
  else
    log "warn: cutover flip assets not staged at /tmp/inngest-cutover-flip.* (pre-#6178 image or undelivered assets); skipping flip install"
  fi
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
# Postgres pool footprint (#6258 — supersedes the #5558 "cap 10 holds total under 15"
# invariant, which was FALSE): `inngest start` opens SEPARATE Postgres pools per
# subsystem (queue/state/history/api), and --postgres-max-open-conns bounds each pool
# INDEPENDENTLY, not the total. So `10` × ~3 pools ratcheted to ~31 pinned idle conns >
# the project's session-mode pool_size (measured 30) → EMAXCONNSESSION under back-to-back
# cutover-probe scans. The durable fix bounds TOTAL footprint + DRAINS idle conns:
#   --postgres-max-open-conns 5   per-pool cap; worst-case total 4×5 = 20 < pool_size 30
#                                 (still ≥5/pool for alpha-internal <10 events/sec).
#                                 ⚠ PER HOST (#6178): the pre-flip cutover runs TWO
#                                 co-located inngest schedulers on this shared pooler
#                                 (web-1 + web-2 warm standby), so BOTH must carry this
#                                 cap or the aggregate (2×20=40) exceeds 30. web-2 is
#                                 reached only via the ADR-068 fan-out (SOLEUR_DEPLOY_
#                                 PEERS); see inngest.tf "TWO-HOST CORRECTION".
#   --postgres-max-idle-conns 2   retain ≤2 idle/pool (default 10) → pinned-idle ≤ 4×2 = 8.
#   --postgres-conn-max-idle-time 1  close idle conns after 1 MINUTE so they RELEASE their
#                                 Supavisor session (this is the release lever). ⚠ UNIT TRAP:
#                                 this IntFlag is MINUTES (default 5), NOT seconds — verified
#                                 against inngest v1.19.4 cmd/start; the plan's "SECS=30" was
#                                 mis-labelled (30 would mean 30 MINUTES — worse than default).
# default_pool_size stays 30 (the #5562 30→15 revert is SUPERSEDED — its premise "cap holds
# total under 15" is falsified by the per-pool model; a 15-slot upstream while inngest bursts
# to ~20 would GUARANTEE exhaustion). See ADR-105.
# --postgres-max-open-conns is ALSO the NON-SECRET durable-detection sentinel and MUST stay
# FIRST in BACKEND_FLAGS (see the @@BACKEND_FLAGS@@ note below + ci-deploy.sh /
# inngest-inventory.sh / wiped-volume-verify; inngest.test.sh anchors on it being first).
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
# @@FLIP_GUARD_EXECSTARTPRE@@ — the P1-5 arm-atomicity guard (#6178), substituted to an
# ExecStartPre line ON THE DEDICATED HOST ONLY (empty on the co-located web host). Wrapped
# in `doppler run` so the guard sees INNGEST_POSTGRES_URI + INNGEST_CUTOVER_FLIP; blocks a
# prod-URI start when the flip flag is not in {armed, flipping, done} — the guard's ACTUAL
# allowlist, verbatim from inngest-server-flip-guard.sh's case. #6536: that is deliberately
# NOT the full FSM (ADR-100's is armed → flipping → flushed → done), so `flushed` is omitted
# — fail-closed + self-healing, tracked separately. Do NOT add `flushed` here to "reconcile"
# it: this documents the guard's code, and a comment describing behaviour the code lacks is
# the #6536 defect itself.
@@FLIP_GUARD_EXECSTARTPRE@@
ExecStart=/usr/bin/doppler run --config prd -- /usr/bin/bash -c 'export INNGEST_SIGNING_KEY="$${INNGEST_SIGNING_KEY#signkey-prod-}"; @@BACKEND_ENV@@exec /usr/local/bin/inngest start --host 0.0.0.0 --port 8288 --sqlite-dir /var/lib/inngest @@BACKEND_FLAGS@@ --poll-interval 60 --sdk-url @@SDK_URL@@'
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
# never argv (#5560) — BACKEND_FLAGS carries only NON-SECRET pool-sizing flags: the
# --postgres-max-open-conns durable-detection sentinel (FIRST) + the #6258 idle-drain
# knobs (--postgres-max-idle-conns / --postgres-conn-max-idle-time) that bound the total
# per-pool footprint so cutover-probe scans cannot ratchet the pool to EMAXCONNSESSION.
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
  BACKEND_FLAGS='--postgres-max-open-conns 5 --postgres-max-idle-conns 2 --postgres-conn-max-idle-time 1'
  log "inngest-server ExecStart: durable backend (env-delivered URIs; bounded per-pool footprint open=5/idle=2/idle-time=1min; --postgres-max-open-conns sentinel FIRST) #6258"
else
  BACKEND_ENV='unset INNGEST_POSTGRES_URI; '
  BACKEND_FLAGS=''
  log "inngest-server ExecStart: SQLite-only fail-safe (INNGEST_DURABLE_DEGRADED — Redis not ready)"
fi
unit_content="$(cat "$UNIT_FILE")"
unit_content="${unit_content//@@BACKEND_ENV@@/$BACKEND_ENV}"
unit_content="${unit_content//@@BACKEND_FLAGS@@/$BACKEND_FLAGS}"
# #6178: wire the arm-atomicity ExecStartPre guard ONLY when the flip trio installed
# (DEDICATED_FLIP=1 ⟹ DOPPLER_PROJECT=soleur-inngest AND the guard script is on disk).
# Empty on the web host / when assets are absent, so ExecStartPre never points at a
# missing binary. Runs under doppler run so the guard sees INNGEST_POSTGRES_URI +
# INNGEST_CUTOVER_FLIP (P1-5).
if [[ "${DEDICATED_FLIP:-0}" == "1" ]]; then
  FLIP_GUARD_LINE="ExecStartPre=/usr/bin/doppler run --config prd -- /usr/local/bin/inngest-server-flip-guard.sh"
else
  FLIP_GUARD_LINE=""
fi
unit_content="${unit_content//@@FLIP_GUARD_EXECSTARTPRE@@/$FLIP_GUARD_LINE}"
# #6178: same bash-parameter-expansion mechanism (NOT sed — SDK_URL contains `/`).
unit_content="${unit_content//@@SDK_URL@@/$SDK_URL}"
# #6555: no @@DOPPLER_PROJECT@@ substitution — the unit dropped `--project` and resolves the
# project from EnvironmentFile=/etc/default/inngest-server (DOPPLER_PROJECT) at runtime.
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

# #6617a: arm the positive liveness marker. `enable --now` starts the TIMER; the immediate
# `start` below fires the oneshot once so a fresh replace ships its first marker in seconds
# rather than at OnBootSec — the replace is exactly when someone is watching. `|| log` keeps
# a probe failure from failing the whole bootstrap: this is observability, never a gate.
systemctl enable --now inngest-server-probe.timer
systemctl start inngest-server-probe.service || log "warn: server-probe oneshot non-zero (timer will retry hourly)"

# #6178: enable the cutover flip poll timer (dedicated host only; daemon-reload above
# already picked up the new units). It SHIPS ENABLED and is NEVER disabled for the host's
# whole life (P0-1) — the FSM flag on soleur-inngest/prd is the sole gate, and keeping the
# 30s poll enabled is what makes a later out-of-band rollback write observable no-SSH.
if [[ "${DEDICATED_FLIP:-0}" == "1" ]]; then
  systemctl enable --now inngest-cutover-flip.timer
  log "cutover flip poll timer enabled (#6178)"
fi

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
# `doppler run --config prd` (the project resolves from DOPPLER_PROJECT in the
# EnvironmentFile, #6555). On the dedicated arm64 host that token lives in the
# isolated soleur-inngest project (#6197).
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
      # #6396: render the shared vector.toml's @@HOST_NAME@@ sentinel to THIS host's Better
      # Stack host_name. The inngest path pins the literal `soleur-inngest-prd` (byte-identical
      # to pre-#6396 — all hosts multiplex into Logs source 2457081; host_name is the sole
      # discriminator). The ungated web-host path renders the TF-injected per-host server name.
      # Keep in lockstep with the two @@HOST_NAME@@ sites in vector.toml (tag_journald + tag_metrics).
      sed -i 's|@@HOST_NAME@@|soleur-inngest-prd|g' "$VECTOR_CONFIG"
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
ExecStart=/usr/bin/doppler run --config prd -- /usr/local/bin/vector --config /etc/vector/vector.toml
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
      # #6555: the vector unit dropped `--project` and resolves the project from
      # EnvironmentFile=/etc/default/inngest-server (DOPPLER_PROJECT) at runtime — no
      # @@DOPPLER_PROJECT@@ sentinel remains, so the re-read/substitute/rewrite round-trip that
      # was here is removed (the unit is already complete as written by the heredoc above). This
      # also settles the deferred arm64-Vector concern: when the dedicated host later sets
      # VECTOR_CLI_*, the unit resolves soleur-inngest from the env-file + scoped token, never a
      # hardcoded `--project soleur`.

      # All four vector.toml journald sources hardcode `journal_directory = "/var/log/journal"`
      # (a PERSISTENT journal). On web-1 that directory is created by
      # terraform_data.journald_persistent's remote-exec — but that provisioner targets
      # `hcloud_server.web["web-1"]` ONLY. The inngest host has no such provisioner and gets a
      # persistent /var/log/journal purely by OS-image accident. If a future image ships
      # Storage=volatile, every journald source here silently reads nothing and the host goes
      # dark through the exact channel this bootstrap spent #6617a wiring up — including the new
      # liveness probe. Create it here rather than inherit the accident. Same two idempotent
      # steps journald_persistent uses (mkdir first so tmpfiles has a dir to fix ownership/ACLs
      # on), then assert, so a failure is loud at boot instead of silent forever.
      mkdir -p /var/log/journal
      systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true
      if [ -d /var/log/journal ]; then
        # Migrate anything still volatile in /run, so rows written before this point are not
        # stranded outside the directory Vector is about to read.
        systemctl restart systemd-journald 2>/dev/null || true
        journalctl --flush 2>/dev/null || true
        log "journald: /var/log/journal present (Vector's journal_directory); flushed"
      else
        # Fail LOUD, not closed: Vector still starts (some sources may work), but this warning
        # ships via the phone-home path and names the exact cause.
        log "warn: /var/log/journal ABSENT after mkdir — vector.toml journald sources will read nothing"
        [ -x /usr/local/bin/inngest-boot-phone-home.sh ] \
          && /usr/local/bin/inngest-boot-phone-home.sh journal-dir-MISSING "vector journal_directory /var/log/journal could not be created" || true
      fi

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

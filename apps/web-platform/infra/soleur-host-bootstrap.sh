#!/bin/sh
# Fresh-host bootstrap installer (#5921).
#
# WHY THIS IS A BAKED SCRIPT, NOT INLINE CLOUD-INIT: the 22 host scripts + hooks.json were
# removed from cloud-init.yml write_files: because as base64 blobs they blew Hetzner's
# 32,768-byte user_data cap. Baking them fixed most of it, but the install/verify/assert
# ceremony was ~90 lines of inline runcmd that ALSO counts toward user_data. Moving that
# ceremony here (baked into ${image_name}) costs zero user_data bytes.
#
# TRUST MODEL: cloud-init.yml's minimal launcher `docker cp`s /opt/soleur/host-scripts/. to
# a temp dir, recomputes the combined content-hash, compares it to the Terraform-computed
# host_scripts_content_hash, and ONLY THEN runs this script. So this script (itself part of
# the hashed set) executes only when every baked asset is proven intact — a stale, mis-built
# or tampered image aborts the boot before this runs.
#
# FAIL-CLOSED: runcmd is NOT under a top-level `set -e`, so the real gate is the
# /run/soleur-hostscripts.ok sentinel written LAST here — the terminal `docker run` block
# refuses to start (poweroff -f) if it is absent. On ANY failure the EXIT trap emits a
# discriminating Sentry event (SSH-free root-cause signal) then exits non-zero so no
# sentinel is written and the host stays visibly absent to the Better Stack uptime check.
#
# Args:  $1 = extracted seed dir (contains the baked host-scripts).
# Env:   WEBHOOK_DEPLOY_SECRET (injected into the baked hooks.json.tmpl at boot).
set -e

SEED="$1"
STAGE=install
FAILED_FILE=""
HOST_ID=$( (cat /var/lib/cloud/data/instance-id 2>/dev/null || hostname) | tr -d '"' )

# Best-effort SSH-free discriminating signal (SECONDARY; the PRIMARY detector is the
# provision-armed Better Stack absence check).
#
# _sentry_emit is the SINGLE fail-open DSN-resolve + POST boundary (#6090): it prefers
# the BAKED ${SOLEUR_SENTRY_DSN} (passed by cloud-init's bootstrap invocation) over a
# `doppler secrets get` fetch, so a fatal emit fires even when doppler is itself the
# broken boot stage — the exact blind spot #6076 closed for the seed block, extended
# here to the bootstrap block. Everything runs inside a ( set +e … ) || true subshell so
# a curl/DNS hiccup can never trip `set -e` and brick the boot. The caller assembles the
# complete Sentry JSON body (message/level/tags) and passes it as $1.
_sentry_emit() {
  ( set +e
    . /etc/default/webhook-deploy 2>/dev/null || true
    DSN="${SOLEUR_SENTRY_DSN:-}"
    [ -n "$DSN" ] || DSN=$(timeout 15 doppler secrets get SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
          || timeout 15 doppler secrets get NEXT_PUBLIC_SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
          || true)
    # Transport stays BYTE-IDENTICAL to cron-egress-enforce-probe.sh (its
    # cron-egress-enforce-probe.test.sh "Sentry TRANSPORT parity" drift guard asserts these
    # exact lines + indentation appear in both) — a DSN/endpoint migration must move together.
    if [ -n "$DSN" ]; then
      KEY=$(printf '%s' "$DSN" | sed -E 's#https://([^@]+)@.*#\1#')
      SHOST=$(printf '%s' "$DSN" | sed -E 's#https://[^@]+@([^/]+)/.*#\1#')
      PROJ=$(printf '%s' "$DSN" | sed -E 's#.*/([0-9]+)$#\1#')
      curl -m 10 --retry 3 -sf -X POST "https://$SHOST/api/$PROJ/store/" \
        -H 'Content-Type: application/json' \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$KEY" \
        -d "$1" >/dev/null 2>&1 || true
    fi ) || true
}

emit_fail() {
  trap - EXIT
  _sentry_emit "$(printf '{"message":"soleur-host-bootstrap failed","level":"fatal","tags":{"stage":"%s","failed_file":"%s","host_id":"%s"}}' "$STAGE" "$FAILED_FILE" "$HOST_ID")"
  exit 1
}
trap emit_fail EXIT

# Per-file install with AUTHORITATIVE modes (scripts 0755, units/allowlists 0644, all
# root:root). NEVER a preserve-mode copy — a firewall SCRIPT at 0644 is non-executable →
# open container egress (#5046).
for f in ci-deploy.sh ci-deploy-wrapper.sh cat-deploy-state.sh canary-bundle-claim-check.sh \
         disk-monitor.sh resource-monitor.sh container-restart-monitor.sh \
         infra-config-apply.sh cat-infra-config-state.sh \
         cron-egress-nftables.sh cron-egress-resolve.sh cron-egress-alarm.sh \
         cron-egress-postapply-assert.sh cron-egress-enforce-probe.sh; do
  FAILED_FILE="$f"; install -D -m 0755 -o root -g root "$SEED/$f" "/usr/local/bin/$f"
done
# The pinned root-run escalation helper installs WITHOUT the .sh suffix (its sudoers grant +
# ci-deploy.sh reference /usr/local/bin/infra-config-install).
FAILED_FILE=infra-config-install
install -D -m 0755 -o root -g root "$SEED/infra-config-install.sh" /usr/local/bin/infra-config-install
for f in container-restart-monitor.service container-restart-monitor.timer \
         cron-egress-firewall.service cron-egress-resolve.service cron-egress-resolve.timer \
         cron-egress-alarm@.service; do
  FAILED_FILE="$f"; install -D -m 0644 -o root -g root "$SEED/$f" "/etc/systemd/system/$f"
done
for f in cron-egress-allowlist.txt cron-egress-allowlist-cidr.txt; do
  FAILED_FILE="$f"; install -D -m 0644 -o root -g root "$SEED/$f" "/etc/soleur/$f"
done
# Pinned cosign trusted root (#6005) — public trust material mounted :ro into the
# ephemeral cosign verifier by ci-deploy.sh (ADR-087). 0644 root:root; dockerd (root)
# reads the mount source, so deploy-user readability is not required.
FAILED_FILE=cosign-trusted-root.json
install -D -m 0644 -o root -g root "$SEED/cosign-trusted-root.json" /etc/soleur/cosign-trusted-root.json
# journald persistent+bounded drop-in (baked #5921). Installed here (post-extraction) and
# applied below — before the terminal app container (--log-driver journald) starts. Was
# previously an inline write_files: base64 blob (2.4 KB), the single biggest remaining
# user_data expansion; baking it keeps the rendered user_data comfortably under the cap. The
# running-host copy is still delivered byte-identically by terraform_data.journald_persistent.
FAILED_FILE=journald-soleur.conf
install -D -m 0644 -o root -g root "$SEED/journald-soleur.conf" /etc/systemd/journald.conf.d/00-soleur.conf

# hooks.json: the baked hooks.json.tmpl carries the Terraform token literally; inject the
# small webhook_deploy_secret at boot (jsonencode-equivalent via python3 json.dumps —
# python3 is a cloud-init dependency, always present), validate the JSON, then mirror the SSH
# bridge's post-write checks (server.tf infra_config_handler_bootstrap).
STAGE=hooks
FAILED_FILE=hooks.json
install -D -m 0640 -o root -g deploy /dev/null /etc/webhook/hooks.json
# NOTE: json.dumps defaults to ensure_ascii=True (\uXXXX-escapes non-ASCII), whereas the
# running-host SSH path renders hooks.json via Terraform jsonencode() (raw UTF-8). For the
# generated ASCII webhook_deploy_secret these produce byte-identical output; a non-ASCII
# secret would diverge cosmetically (HMAC is unaffected — only the decoded secret matters).
python3 - "$SEED/hooks.json.tmpl" /etc/webhook/hooks.json <<'PYEOF'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
secret = os.environ["WEBHOOK_DEPLOY_SECRET"]
data = open(src).read().replace("${jsonencode(webhook_deploy_secret)}", json.dumps(secret))
json.loads(data)  # abort (non-zero) if the injected result is not valid JSON
open(dst, "w").write(data)
PYEOF
chown root:deploy /etc/webhook/hooks.json
chmod 0640 /etc/webhook/hooks.json
grep -q infra-config-status /etc/webhook/hooks.json
grep -q cat_infra_config_state_sh_b64 /etc/webhook/hooks.json

# Per-file assertions: scripts executable, units + allowlists present, and the sudo-NOPASSWD
# escalation helper is exactly mode 755 (a group/other-writable root target would be a
# privilege-escalation surface).
STAGE=assert
for f in ci-deploy.sh ci-deploy-wrapper.sh cat-deploy-state.sh canary-bundle-claim-check.sh \
         disk-monitor.sh resource-monitor.sh container-restart-monitor.sh \
         infra-config-apply.sh cat-infra-config-state.sh \
         cron-egress-nftables.sh cron-egress-resolve.sh cron-egress-alarm.sh \
         cron-egress-postapply-assert.sh cron-egress-enforce-probe.sh; do
  FAILED_FILE="$f"; test -x "/usr/local/bin/$f"
done
FAILED_FILE=infra-config-install
test -x /usr/local/bin/infra-config-install
[ "$(stat -c %a /usr/local/bin/infra-config-install)" = 755 ]
for f in container-restart-monitor.service container-restart-monitor.timer \
         cron-egress-firewall.service cron-egress-resolve.service cron-egress-resolve.timer \
         cron-egress-alarm@.service; do
  FAILED_FILE="$f"; test -f "/etc/systemd/system/$f"
done
FAILED_FILE=cron-egress-allowlist.txt; test -f /etc/soleur/cron-egress-allowlist.txt
FAILED_FILE=cron-egress-allowlist-cidr.txt; test -f /etc/soleur/cron-egress-allowlist-cidr.txt
FAILED_FILE=cosign-trusted-root.json; test -f /etc/soleur/cosign-trusted-root.json
FAILED_FILE=journald-soleur.conf; test -f /etc/systemd/journald.conf.d/00-soleur.conf

STAGE=reload
systemctl daemon-reload

# Make systemd-journald persistent + bounded (moved here from the early runcmd, #5921). Safe
# ordering: the only --log-driver journald consumer is the terminal app container, which
# starts after this; `journalctl --flush` migrates the early boot's volatile journal into the
# now-persistent store so nothing is lost. Mirrors terraform_data.journald_persistent.
STAGE=journald
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
systemctl restart systemd-journald
journalctl --flush

# #6005: authenticate the host docker daemon to the now-PRIVATE GHCR packages so the
# fresh-boot inngest-bootstrap `docker pull` (later in cloud-init runcmd) succeeds. Lives
# HERE (baked → zero user_data cost; user_data is within ~1 KB of the 32,768-byte cap).
# Best-effort: a missing/rotated credential must NOT poweroff the host — the subshell +
# `|| true` keeps it clear of `set -e` + the emit_fail trap; the inngest pull is the hard
# gate. Token fetched at boot via the ambient DOPPLER_TOKEN — NEVER templatefile-
# interpolated (that would leak it into Hetzner metadata + cloud-init-output.log).
STAGE=ghcr_login
( set +e
  . /etc/default/webhook-deploy 2>/dev/null || true
  # Non-fatal, no-SSH CAUSE signal for a fresh-boot login failure (observability-
  # coverage-reviewer P1). The block is deliberately OUTSIDE the emit_fail EXIT trap
  # (a rotated credential must not poweroff the host), so a failure would otherwise
  # only reach the SSH-only cloud-init-output.log — and Vector (Layer 3) is not yet
  # installed at this boot stage, so journald cannot ship it either. Emit a WARNING
  # Sentry event (tag stage=ghcr_login) directly, mirroring emit_fail's DSN parse,
  # SCRUBBED to a classification (never the raw docker stderr / auth header).
  ghcr_login_warn() {
    # Routes through the shared _sentry_emit boundary (#6090) — same baked-DSN
    # preference + fail-open subshell as emit_fail; only the body differs.
    _sentry_emit "$(printf '{"message":"fresh-boot GHCR docker login failed","level":"warning","logger":"soleur-host-bootstrap","tags":{"feature":"supply-chain","op":"image-pull","stage":"ghcr_login","pull_result":"%s","host_id":"%s"}}' "$1" "$HOST_ID")"
  }
  # (#6090) Prefer the BAKED creds (cloud-init writes /etc/default/soleur-ghcr-read early in
  # runcmd, deploy:deploy 0600) so the inngest-bootstrap + app image pulls authenticate on a
  # cold host even when Doppler answers EMPTY at the boot instant — the same failure class the
  # cloud-init ghcr_login (#6090) and the ci-deploy prelude (#6161) already bake against. An
  # empty fetch here skipped docker login → anonymous inngest pull → /var/lib/inngest never
  # created. (The old downstream "→ webhook.service 226/NAMESPACE → :9000 never binds → peer
  # fan-out degrades" chain is SEVERED as of #6090: webhook.service now marks /var/lib/inngest
  # `-`-optional, so an absent dir no longer wedges the unit. This baked-creds path still matters
  # when web_colocate_inngest is ON — the inngest pull itself needs auth.) Hardened Doppler
  # fallback (timeout 45 + 3-try retry).
  GHCR_USER=""; GHCR_TOKEN=""
  if [ -r /etc/default/soleur-ghcr-read ]; then
    # shellcheck disable=SC1091
    . /etc/default/soleur-ghcr-read 2>/dev/null || true
    GHCR_USER="${GHCR_READ_USER:-}"; GHCR_TOKEN="${GHCR_READ_TOKEN:-}"
    unset GHCR_READ_TOKEN   # keep the token out of this process env + its children
  fi
  [ -n "$GHCR_USER" ] || { n=0; until GHCR_USER=$(timeout 45 doppler secrets get GHCR_READ_USER --plain --project soleur --config prd 2>/dev/null); [ -n "$GHCR_USER" ]; do n=$((n+1)); [ "$n" -ge 3 ] && break; sleep 5; done; }
  [ -n "$GHCR_TOKEN" ] || { n=0; until GHCR_TOKEN=$(timeout 45 doppler secrets get GHCR_READ_TOKEN --plain --project soleur --config prd 2>/dev/null); [ -n "$GHCR_TOKEN" ]; do n=$((n+1)); [ "$n" -ge 3 ] && break; sleep 5; done; }
  if [ -n "$GHCR_USER" ] && [ -n "$GHCR_TOKEN" ]; then
    if printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin >/dev/null 2>&1; then
      echo "soleur-host-bootstrap: docker login ghcr.io ok"
    else
      echo "soleur-host-bootstrap: docker login ghcr.io FAILED (private pull may fail-closed)"
      ghcr_login_warn auth_denied
    fi
  else
    echo "soleur-host-bootstrap: GHCR_READ_{USER,TOKEN} not both present — skipping docker login"
    ghcr_login_warn credential_absent
  fi
  # #6122/ADR-096: ALSO authenticate to the self-hosted zot registry so the downstream
  # cloud-init inngest-bootstrap + app pulls can prefer zot. Strict dark-launch: only when
  # ZOT_REGISTRY_URL is present in Doppler prd (absent until the operator provisions (1.8) +
  # backfills (1.9) → a true no-op, and an unset URL emits NO beacon so a pre-provisioning
  # boot never pages). Same fail-open shape; the login writes a zot auths entry into the
  # host docker config that the later pulls reuse.
  zot_login_warn() {
    _sentry_emit "$(printf '{"message":"fresh-boot zot docker login failed","level":"warning","logger":"soleur-host-bootstrap","tags":{"feature":"supply-chain","op":"image-pull","stage":"zot_login","pull_result":"%s","host_id":"%s"}}' "$1" "$HOST_ID")"
  }
  ZOT_URL=$(timeout 15 doppler secrets get ZOT_REGISTRY_URL --plain --project soleur --config prd 2>/dev/null || true)
  if [ -n "$ZOT_URL" ]; then
    ZOT_USER=$(timeout 15 doppler secrets get ZOT_PULL_USER --plain --project soleur --config prd 2>/dev/null || true)
    ZOT_TOKEN=$(timeout 15 doppler secrets get ZOT_PULL_TOKEN --plain --project soleur --config prd 2>/dev/null || true)
    if [ -n "$ZOT_USER" ] && [ -n "$ZOT_TOKEN" ]; then
      if printf '%s' "$ZOT_TOKEN" | docker login "$ZOT_URL" -u "$ZOT_USER" --password-stdin >/dev/null 2>&1; then
        echo "soleur-host-bootstrap: docker login $ZOT_URL ok (zot-primary)"
      else
        echo "soleur-host-bootstrap: docker login $ZOT_URL FAILED (will fall back to GHCR)"
        zot_login_warn auth_denied
      fi
    else
      echo "soleur-host-bootstrap: ZOT_PULL_{USER,TOKEN} not both present — skipping zot login"
      zot_login_warn credential_absent
    fi
  else
    echo "soleur-host-bootstrap: ZOT_REGISTRY_URL unset — skipping zot login (dark)"
  fi ) || true

# Author the shared post-bootstrap Sentry emitter + readiness poller (#6090) for the
# DOWNSTREAM cloud-init region (cloudflared → webhook → app-run), which today carries NO
# Sentry trap at all — the deeper blind spot beyond the bootstrap block. Baked HERE (0
# user_data; the rendered cloud-init has only ~0.4 KB headroom under the 32,768-byte cap,
# so a per-block emit body is infeasible). The baked ${SOLEUR_SENTRY_DSN} is spliced in via
# a placeholder + sed (avoids per-`$` heredoc escaping); a non-`/` delimiter tolerates the
# DSN URL. FAIL-CLOSED authoring (runs under the top-level set -e + emit_fail trap): a write
# miss emits a NAMED stage=boot_emit fatal and aborts, NOT a later anonymous abort at the
# fail-closed readiness gates (`soleur-wait-ready … || exit 1`) with no signal. The install
# loop above already proved /usr/local/bin writable, so this won't spuriously fire.
STAGE=boot_emit; FAILED_FILE=soleur-boot-emit
cat > /usr/local/bin/soleur-boot-emit <<'EMITEOF'
#!/bin/sh
# Fail-open Sentry breadcrumb/fatal emitter for the cloud-init post-bootstrap region
# (#6090). usage: soleur-boot-emit <stage> [info|warning|fatal]. Always returns 0.
( set +e
  STAGE="$1"; LEVEL="$2"; [ -n "$LEVEL" ] || LEVEL=info
  HOST_ID=$( (cat /var/lib/cloud/data/instance-id 2>/dev/null || hostname) | tr -d '"' )
  DSN='@@SOLEUR_SENTRY_DSN@@'
  [ -n "$DSN" ] || exit 0
  KEY=$(printf '%s' "$DSN" | sed -E 's#https://([^@]+)@.*#\1#')
  SHOST=$(printf '%s' "$DSN" | sed -E 's#https://[^@]+@([^/]+)/.*#\1#')
  PROJ=$(printf '%s' "$DSN" | sed -E 's#.*/([0-9]+)$#\1#')
  BODY=$(printf '{"message":"soleur-cloud-init boot stage","level":"%s","tags":{"stage":"%s","host_id":"%s","region":"cloud-init"}}' "$LEVEL" "$STAGE" "$HOST_ID")
  curl -m 10 --retry 3 -sf -X POST "https://$SHOST/api/$PROJ/store/" \
    -H 'Content-Type: application/json' \
    -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$KEY" \
    -d "$BODY" >/dev/null 2>&1 || true
) || true
exit 0
EMITEOF
sed -i "s|@@SOLEUR_SENTRY_DSN@@|${SOLEUR_SENTRY_DSN:-}|" /usr/local/bin/soleur-boot-emit
chmod 0755 /usr/local/bin/soleur-boot-emit
# Bounded readiness poll (#6090, H4) — baked (0 user_data; only ~0.4 KB cap headroom, so the
# poll body cannot live inline). systemd enable commands
# return 0 the instant a unit launches, NOT when it connects/binds; this polls the real
# invariant so an ASYNC death (the primary "cloudflared never comes up / :9000 never binds"
# symptom) becomes a NAMED fatal instead of a silent green-and-broken boot. Callers do
# `|| exit 1` to abort the boot on timeout — a never-ready service SHOULD fail it.
cat > /usr/local/bin/soleur-wait-ready <<'WAITEOF'
#!/bin/sh
# usage: soleur-wait-ready service <unit> <stage> | soleur-wait-ready port <port> <stage>
KIND="$1"; NAME="$2"; STAGE="$3"; n=0
while :; do
  case "$KIND" in
    service) systemctl is-active --quiet "$NAME" && break ;;
    port) { ss -ltn 2>/dev/null | grep -q ":$NAME" || curl -s -o /dev/null --max-time 3 "http://localhost:$NAME/" 2>/dev/null; } && break ;;
  esac
  n=$((n+1)); [ "$n" -ge 30 ] && { soleur-boot-emit "$STAGE" fatal; exit 1; }; sleep 2
done
soleur-boot-emit "$STAGE" info
WAITEOF
chmod 0755 /usr/local/bin/soleur-wait-ready

# Completion breadcrumb (#6090): the SINGLE signal distinguishing "died IN bootstrap"
# (emit_fail names a bootstrap stage) from "bootstrap COMPLETED, died downstream" (this
# breadcrumb present + a later cloud-init stage fatal). Fail-open via _sentry_emit.
STAGE=bootstrap_complete
_sentry_emit "$(printf '{"message":"soleur-host-bootstrap complete","level":"info","tags":{"stage":"bootstrap_complete","host_id":"%s","region":"bootstrap"}}' "$HOST_ID")"

# ---------------------------------------------------------------------------
# Vector observability shipper — UNGATED web-host path (#6396). ADR-100 moved
# scheduling off the web host (web_colocate_inngest default false), so a fresh
# web host installs NO Vector via the inngest path and ships NO logs. This
# decouples the shipper: stage the baked config here (SEED is rm -rf'd after
# bootstrap), then author /usr/local/bin/soleur-vector-install for the ungated,
# fail-open, timeout-bounded end-of-cloud-init run (AFTER the app binds :80/:3000,
# so observing the boot can NEVER break serving). Same journald/host_metrics data
# class already ships from the inngest source — no new processor.
#
# The STAGING below is under `set -e` + emit_fail ON PURPOSE: vector.toml is a
# hash-verified baked file (host_scripts_content_hash gate), so its absence is a
# coherence violation (fail-closed, like every other baked asset). The RUNTIME
# install (binary download, unit start) is where fail-open lives — see the helper.
STAGE=vector_stage; FAILED_FILE=vector.toml
mkdir -p /opt/soleur /etc/vector
# Persist the shared config with @@HOST_NAME@@ resolved to THIS host's TF-injected server
# name (SOLEUR_HOST_NAME, passed by cloud-init). Distinct per host so web-1/web-2 do not
# collapse into one host_name in the shared Better Stack source 2457081.
sed "s|@@HOST_NAME@@|${SOLEUR_HOST_NAME:-$(hostname)}|g" "$SEED/vector.toml" > /opt/soleur/vector.toml

STAGE=vector_install_author; FAILED_FILE=soleur-vector-install
cat > /usr/local/bin/soleur-vector-install <<'VINEOF'
#!/bin/sh
# Fail-open Vector installer for the ungated web-host path (#6396). Invoked once at
# end-of-cloud-init as `timeout 60 sh -c 'soleur-vector-install' || true`, AFTER the app
# container binds :80/:3000. Vector is observability, NEVER serving-critical: EVERY step
# here is swallowed (the outer ( set +e … ) || true), so a slow/failed fetch or unit start
# can never wedge the boot. Idempotent: version-pinned + sha-verified + skip-on-match.
( set +e
  # Pin MUST stay in lockstep with vector.tf locals (vector_version / vector_sha256[_arm64]);
  # soleur-host-bootstrap-observability.test.sh AC22 asserts byte-identity vs vector.tf.
  VECTOR_VERSION="0.43.1"
  case "$(uname -m)" in
    x86_64|amd64)  VEC_TRIPLE="x86_64-unknown-linux-musl";  VEC_SHA="8a3cc62d18ec88bb8433159d1d3455d3c77fefff73ce46d4f8cc464e100f65f1" ;;
    aarch64|arm64) VEC_TRIPLE="aarch64-unknown-linux-musl"; VEC_SHA="365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6" ;;
    *) echo "soleur-vector-install: unsupported arch $(uname -m); skipping" >&2; exit 0 ;;
  esac
  BIN=/usr/local/bin/vector
  VERFILE=/var/lib/vector/version
  CFG=/etc/vector/vector.toml
  UNIT=/etc/systemd/system/vector.service

  [ -f /opt/soleur/vector.toml ] || { echo "soleur-vector-install: staged config missing; skipping" >&2; exit 0; }
  mkdir -p /etc/vector /var/lib/vector
  install -m 0644 /opt/soleur/vector.toml "$CFG"
  chown -R deploy:deploy /var/lib/vector 2>/dev/null || true

  cur=""; [ -f "$VERFILE" ] && cur="$(cat "$VERFILE" 2>/dev/null)"
  if [ "$cur" != "$VECTOR_VERSION" ] || [ ! -x "$BIN" ]; then
    tmp="$(mktemp -d)" || exit 0
    url="https://packages.timber.io/vector/${VECTOR_VERSION}/vector-${VECTOR_VERSION}-${VEC_TRIPLE}.tar.gz"
    if curl -fsSL --max-time 120 -o "$tmp/v.tgz" "$url"; then
      got="$(sha256sum "$tmp/v.tgz" | awk '{print $1}')"
      if [ "$got" = "$VEC_SHA" ]; then
        if tar -xzf "$tmp/v.tgz" -C "$tmp" && install -m 0755 "$tmp/vector-${VEC_TRIPLE}/bin/vector" "$BIN"; then
          printf '%s\n' "$VECTOR_VERSION" > "$VERFILE"
        fi
      else
        echo "soleur-vector-install: sha mismatch (exp $VEC_SHA got $got); skipping" >&2
      fi
    fi
    rm -rf "$tmp"
  fi
  [ -x "$BIN" ] || { echo "soleur-vector-install: vector binary absent; skipping unit" >&2; exit 0; }

  # Web-host unit — DOPPLER_TOKEN comes from /etc/default/webhook-deploy (present on EVERY web
  # host), NOT /etc/default/inngest-server (inngest-only). Without it `doppler run` has no token
  # → Vector never starts → fail-open masks it → silent absent host_name source (spec-flow P0).
  # Project is always `soleur` for a web host (dev!=prd; web reads --config prd).
  cat > "$UNIT" <<'UNITEOF'
[Unit]
Description=Vector observability shipper (journald + host_metrics -> Better Stack Logs)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/default/webhook-deploy
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
UNITEOF
  systemctl daemon-reload 2>/dev/null || true
  # enable + restart --no-block (NOT enable --now: --now no-ops on an already-running unit and
  # keeps a stale config; --no-block keeps the fail-open install off the serving-latency path).
  systemctl enable vector.service 2>/dev/null || true
  systemctl restart --no-block vector.service 2>/dev/null || true
) || true
exit 0
VINEOF
chmod 0755 /usr/local/bin/soleur-vector-install

# Sentinel LAST: extraction + install proven complete. The terminal `docker run` block gates
# on this file; without it the host poweroffs (fail-closed) instead of serving with an
# unconfigured egress firewall / missing deploy scripts.
trap - EXIT
: > /run/soleur-hostscripts.ok

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
# provision-armed Better Stack absence check). DSN via the on-host Doppler token written to
# /etc/default/webhook-deploy earlier in runcmd. Never fatal to the trap itself.
emit_fail() {
  trap - EXIT
  ( set +e
    . /etc/default/webhook-deploy 2>/dev/null || true
    DSN=$(timeout 15 doppler secrets get SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
          || timeout 15 doppler secrets get NEXT_PUBLIC_SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
          || true)
    if [ -n "$DSN" ]; then
      KEY=$(printf '%s' "$DSN" | sed -E 's#https://([^@]+)@.*#\1#')
      SHOST=$(printf '%s' "$DSN" | sed -E 's#https://[^@]+@([^/]+)/.*#\1#')
      PROJ=$(printf '%s' "$DSN" | sed -E 's#.*/([0-9]+)$#\1#')
      BODY=$(printf '{"message":"soleur-host-bootstrap failed","level":"fatal","tags":{"stage":"%s","failed_file":"%s","host_id":"%s"}}' "$STAGE" "$FAILED_FILE" "$HOST_ID")
      curl -m 10 --retry 3 -sf -X POST "https://$SHOST/api/$PROJ/store/" \
        -H 'Content-Type: application/json' \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$KEY" \
        -d "$BODY" >/dev/null 2>&1 || true
    fi ) || true
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
# ephemeral cosign verifier by ci-deploy.sh (ADR-085). 0644 root:root; dockerd (root)
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
  GHCR_USER=$(timeout 15 doppler secrets get GHCR_READ_USER --plain --project soleur --config prd 2>/dev/null || true)
  GHCR_TOKEN=$(timeout 15 doppler secrets get GHCR_READ_TOKEN --plain --project soleur --config prd 2>/dev/null || true)
  if [ -n "$GHCR_USER" ] && [ -n "$GHCR_TOKEN" ]; then
    printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin >/dev/null 2>&1 \
      && echo "soleur-host-bootstrap: docker login ghcr.io ok" \
      || echo "soleur-host-bootstrap: docker login ghcr.io FAILED (private pull may fail-closed)"
  else
    echo "soleur-host-bootstrap: GHCR_READ_{USER,TOKEN} not both present — skipping docker login"
  fi ) || true

# Sentinel LAST: extraction + install proven complete. The terminal `docker run` block gates
# on this file; without it the host poweroffs (fail-closed) instead of serving with an
# unconfigured egress firewall / missing deploy scripts.
trap - EXIT
: > /run/soleur-hostscripts.ok

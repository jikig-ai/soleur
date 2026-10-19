---
title: "fix: resolve CI release deploy failures for web-platform and telegram-bridge"
type: fix
date: 2026-03-21
semver: patch
---

# fix: Resolve CI Release Deploy Failures for Web-Platform and Telegram-Bridge

## Enhancement Summary

**Deepened on:** 2026-03-21
**Sections enhanced:** 7 (Problem Statement, Proposed Solution, Test Scenarios, Implementation Phases, Dependencies, Acceptance Criteria, References)
**Research sources:** Cloudflare docs (connection limits, error 524), adnanh/webhook config docs, GitHub issues #181/#245 (async execution), project learnings (6 relevant)

### Key Improvements

1. **Corrected Cloudflare timeout from 100s to 120s** -- Cloudflare's actual Proxy Read Timeout is 120 seconds, not 100s; only Enterprise plans can increase it (up to 6,000s)
2. **Discovered native async support in adnanh/webhook** -- Setting `include-command-output-in-response: false` + `success-http-response-code: 202` gives fire-and-forget behavior without wrapper scripts or external tools (Task Spooler)
3. **Identified cloud-init gap as the critical blocker for telegram-bridge** -- cloud-init only runs at server creation; Terraform `ignore_changes = [user_data]` means changes to cloud-init.yml are dead code until manual reprovisioning; need a parallel manual provisioning step
4. **Clarified Terraform provider version risk** -- Project pins `cloudflare ~> 4.0`; research agents and docs default to v5 naming (`tunnel_secret` vs `secret`, `ingress {}` vs `ingress_rule {}`); must validate all new TF resources against v4 schema

### New Considerations Discovered

- The webhook's `include-command-output-in-response: true` creates a coupling between deploy duration and HTTP response time -- switching to async mode (fire-and-forget) eliminates the 524 timeout entirely but loses inline deploy output
- Cloudflare Access service tokens are account-scoped, not zone-scoped -- a single service token can authenticate to both `deploy.soleur.ai` and `deploy-bridge.soleur.ai`, reducing the number of GitHub secrets needed
- The `WEBHOOK_DEPLOY_SECRET` must be different per server if using separate webhooks (to prevent replay attacks where a captured web-platform deploy payload is sent to the bridge endpoint)
- `ProtectSystem=strict` in systemd requires explicit `ReadWritePaths` for every writable path -- Docker socket access (`/var/run/docker.sock`) may also need exemption depending on the deploy user's Docker group membership

## Overview

Both the web-platform and telegram-bridge release workflows have been failing consistently since the Cloudflare Tunnel webhook migration (#963, #967). Every push to main triggers release jobs that succeed at version computation, GitHub Release creation, and Docker image push -- but fail at the deploy step. The web-platform gets HTTP 500 (webhook command execution failure) and the telegram-bridge gets HTTP 524 (Cloudflare edge timeout) or HTTP 403 (Bot Fight Mode challenge). No code has been deployed to production since 2026-03-20 ~18:00 UTC.

Related: [#968](https://github.com/jikig-ai/soleur/issues/968)

## Problem Statement

Five distinct failure modes are interacting:

### P1: Cloudflare Bot Fight Mode blocks webhook requests (HTTP 403)

Zone-level Bot Fight Mode triggers managed challenges on ALL proxied traffic, including legitimate deploy webhook requests from GitHub Actions. The challenge is injected at the Cloudflare edge BEFORE CF Access evaluates service token headers. Documented in learning `2026-03-21-cloudflare-tunnel-server-provisioning.md` -- was supposed to be disabled during #967, but multiple 403 responses in CI logs suggest it was either not disabled or re-enabled.

**Evidence:** Runs 23365339198, 23365339193 (2026-03-20 ~22:35) return HTTP 403 with Cloudflare challenge HTML (`cZone: 'deploy.soleur.ai'`, `cType: 'managed'`).

### P2: ci-deploy.sh execution failure on the server (HTTP 500)

The webhook reaches the server but ci-deploy.sh exits non-zero. The webhook binary (`adnanh/webhook`) returns HTTP 500 with "Error occurred while executing the hook's command." Potential causes: Docker daemon issues, disk space exhaustion (documented recurrence), Doppler token expiry, or permission conflicts from systemd hardening (`ProtectSystem=strict` without adequate `ReadWritePaths`).

**Evidence:** Run 23382502736 (2026-03-21 ~15:13) returns HTTP 500.

### Research Insights (P2)

**Systemd hardening vectors from learning `2026-03-21-cloudflare-tunnel-server-provisioning.md`:**
- `NoNewPrivileges=true` blocks `sudo` (needed for `chown` in web-platform deploy) -- already removed in #967
- `ProtectHome=true` blocks Docker config access (`$HOME/.docker/`) -- changed to `read-only` in #967
- `ProtectSystem=strict` without `ReadWritePaths=/var/run/docker.sock` may block Docker socket access if the deploy user communicates with Docker via the socket rather than TCP
- Verify `/mnt/data` is in `ReadWritePaths` -- the current cloud-init.yml has `ReadWritePaths=/mnt/data` but this only applies if cloud-init was re-run after the change

**Doppler token lifecycle from learning `2026-03-20-doppler-secrets-manager-setup-patterns.md`:**
- The `DOPPLER_TOKEN` in `/etc/environment` is set at cloud-init time and never rotated
- If the Doppler personal token was regenerated during #967 provisioning, the server's `/etc/environment` may still hold the old token
- `resolve_env_file()` in ci-deploy.sh falls back to `/mnt/data/.env` on Doppler failure -- check if the fallback `.env` file exists and has valid secrets

### P3: Cloudflare 120s edge timeout exceeded (HTTP 524)

ci-deploy.sh operations (Docker prune + pull + stop + rm + run + health check) exceed Cloudflare's **120-second** Proxy Read Timeout (corrected from initial estimate of 100s). The workflow `curl --max-time 150` is higher than this limit, so Cloudflare terminates the connection before the webhook response arrives. A Docker pull of a large Next.js image (500MB+) plus a 30-second health check loop can easily exceed 120s.

**Evidence:** Run 23382502779 (2026-03-21 ~15:13) returns HTTP 524 ("error code: 524").

### Research Insights (P3)

**Cloudflare timeout facts ([Cloudflare docs](https://developers.cloudflare.com/fundamentals/reference/connection-limits/)):**
- Default Proxy Read Timeout: **120 seconds** (not 100s)
- Default Proxy Write Timeout: **30 seconds** (not configurable)
- Only **Enterprise** customers can increase the Proxy Read Timeout (up to 6,000s via API or Cache Rules)
- Free/Pro/Business plans: 120s is a hard limit
- Cloudflare's tunnel `originRequest.connectTimeout` controls the connection TO the origin (localhost:9000), NOT the edge proxy timeout -- these are independent settings
- Recommended alternative for non-Enterprise: move the endpoint to a DNS-only (grey-cloud) subdomain to bypass the proxy entirely

**adnanh/webhook native async support ([webhook docs](https://deepwiki.com/adnanh/webhook/3-hook-configuration)):**
- `include-command-output-in-response: false` causes webhook to fire the command asynchronously and return immediately
- `success-http-response-code: 202` returns HTTP 202 Accepted
- `response-message: "Deploy initiated"` provides a human-readable response
- This eliminates the 524 timeout entirely without wrapper scripts, Task Spooler, or external tools
- Trade-off: CI loses inline deploy output in the HTTP response; deploy success/failure must be verified separately (health check polling, or a status file endpoint)

**Background execution limitations ([GitHub issue #245](https://github.com/adnanh/webhook/issues/245)):**
- Shell backgrounding (`&`, `nohup`, `disown`) does NOT work with webhook's `exec.Run()` -- the Go process waits regardless
- The ONLY reliable async pattern is `include-command-output-in-response: false`
- For synchronous execution with output, there is no way to return early

### P4: Telegram-bridge deploying through the wrong server

The telegram-bridge release workflow sends deploy webhooks to `deploy.soleur.ai`, which routes through the Cloudflare Tunnel to the **web-platform** server's `localhost:9000`. But telegram-bridge runs on a separate Hetzner server (`soleur-bridge`). The shared `ci-deploy.sh` on the web-platform server has handlers for both components, so it attempts to deploy telegram-bridge containers on the web-platform server -- the wrong target.

**Evidence:** `apps/telegram-bridge/infra/server.tf` defines a separate `hcloud_server.bridge` resource. `apps/web-platform/infra/tunnel.tf` routes `deploy.soleur.ai` to `http://localhost:9000` on the web-platform server only.

### P5: Missing webhook infrastructure on telegram-bridge server

The telegram-bridge `cloud-init.yml` still uses SSH-based deploy (`ssh_authorized_keys` with `restrict,command=`). It lacks: cloudflared, the webhook binary, the systemd webhook service, and the hooks.json configuration. The #963 PR updated the CI workflow to use webhooks but did not provision the telegram-bridge server with webhook infrastructure.

**Evidence:** `apps/telegram-bridge/infra/cloud-init.yml` lines 16-17 still contain SSH key configuration. No `cloudflared`, `webhook`, or `webhook.service` entries exist in this file.

### Research Insights (P4 + P5)

**Terraform provider version risk (learning `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`):**
- Project pins `cloudflare ~> 4.0` in `main.tf`
- Research agents default to v5 naming: `tunnel_secret` (v5) vs `secret` (v4), `ingress {}` (v5) vs `ingress_rule {}` (v4)
- `cloudflare_zero_trust_*` resource names work in both v4 and v5
- Run `terraform validate` after every new resource to catch naming mismatches immediately

**Cloud-init is write-once (learning `2026-03-21-cloudflare-tunnel-server-provisioning.md`):**
- cloud-init only runs at server creation time
- Terraform `lifecycle { ignore_changes = [user_data] }` means cloud-init.yml changes are NOT applied to running servers
- For the telegram-bridge server, changes to cloud-init.yml update the Terraform template for future rebuilds but require **manual SSH provisioning** to apply to the current running server
- Manual provisioning steps: install cloudflared, install webhook binary (with checksum verification), write hooks.json, create webhook.service, enable/start both services

**Cloudflare Access service token scoping:**
- Service tokens are account-scoped, not zone-scoped
- A single `github-actions-deploy` service token CAN authenticate to both `deploy.soleur.ai` and `deploy-bridge.soleur.ai`
- However, creating separate tokens per server (`github-actions-deploy-web`, `github-actions-deploy-bridge`) provides better audit trail and independent revocation
- The existing `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` secrets may work for both endpoints if using a shared token

## Proposed Solution

### Fix 1: Verify Bot Fight Mode is disabled (P1)

Check via Cloudflare API (`GET /zones/{zone_id}/bot_management`) whether Bot Fight Mode is currently active. If active, disable it. If already disabled, the 403s were transient (pre-#967 runs) and this fix is a no-op verification.

**Files:** None (Cloudflare dashboard/API configuration)

### Fix 2: Add server-side error logging to webhook (P2)

The current `include-command-output-in-response: true` in `hooks.json` sends ci-deploy.sh stdout/stderr back in the HTTP response, but the CI workflow only prints the response body on failure -- it doesn't capture it in a structured way. Add explicit logging:
- Before the deploy: log the incoming command to syslog
- After failure: dump the last 30 lines of journal logs for the webhook service

The immediate fix is to SSH into the server and check `journalctl -u webhook --since "2026-03-21"` to identify the specific error. The structural fix is to make ci-deploy.sh failures self-diagnosing.

**Files:**
- `apps/web-platform/infra/ci-deploy.sh` -- add error context to stderr output
- `.github/workflows/web-platform-release.yml` -- log response body on failure for diagnostics

### Research Insights (Fix 2)

**Diagnostic checklist for server-side investigation:**
1. `systemctl status webhook` -- is the webhook service running?
2. `systemctl status cloudflared` -- is the tunnel daemon running?
3. `df -h` -- disk space (recurrent issue: 49 images / 77 GB filled 75 GB partition in #967)
4. `docker ps -a` -- are containers in crash loop?
5. `cat /etc/environment | grep DOPPLER` -- is the Doppler token set and current?
6. `journalctl -u webhook --since "2026-03-20" --no-pager` -- the actual error output
7. `ls -la /etc/webhook/hooks.json` -- permissions (must be readable by deploy user, per #967 learning)
8. `sudo -u deploy docker ps` -- can the deploy user actually run Docker commands?

**Error context improvement for ci-deploy.sh:**

```bash
# Add trap at top of script for structured error output
trap 'echo "DEPLOY_ERROR: ci-deploy.sh failed at line $LINENO (exit $?)" >&2' ERR
```

This outputs the failing line number, which the webhook returns in the HTTP response body (when `include-command-output-in-response` is enabled).

### Fix 3: Handle Cloudflare timeout with async deploy pattern (P3)

**Updated recommendation based on research: Option B (async webhook) is now the clear winner.**

~~Option A (recommended): Increase Cloudflare proxy timeout.~~ **Eliminated:** Only available on Enterprise plans. The project uses Free or Pro tier. The 120s Proxy Read Timeout is a hard limit.

**Option B (now recommended): Native async webhook.** adnanh/webhook supports fire-and-forget execution natively. Change the webhook configuration to:

```json
{
  "id": "deploy",
  "execute-command": "/usr/local/bin/ci-deploy.sh",
  "command-working-directory": "/",
  "include-command-output-in-response": false,
  "success-http-response-code": 202,
  "response-message": "Deploy initiated",
  "http-methods": ["POST"],
  "trigger-rule-mismatch-http-response-code": 403,
  "pass-environment-to-command": [
    {
      "source": "payload",
      "name": "command",
      "envname": "SSH_ORIGINAL_COMMAND"
    }
  ],
  "trigger-rule": {
    "match": {
      "type": "payload-hmac-sha256",
      "secret": "<webhook_deploy_secret>",
      "parameter": {
        "source": "header",
        "name": "X-Signature-256"
      }
    }
  }
}
```

Key changes from current config:
- `include-command-output-in-response`: `true` -> `false` (fire and forget)
- Added `success-http-response-code: 202` (return 202 Accepted immediately)
- Added `response-message: "Deploy initiated"` (human-readable confirmation)

**CI workflow changes for async deploy:**

The deploy step changes from "send webhook, check HTTP status" to "send webhook (expect 202), then poll health endpoint directly":

```yaml
- name: Deploy via webhook
  run: |
    # Fire deploy webhook (returns 202 immediately)
    PAYLOAD=$(printf '{"command":"deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v%s"}' "$VERSION")
    SIGNATURE=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
      --max-time 30 \
      -X POST \
      -H "Content-Type: application/json" \
      -H "X-Signature-256: sha256=$SIGNATURE" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      -d "$PAYLOAD" \
      "https://deploy.soleur.ai/hooks/deploy")
    if [[ "$HTTP_CODE" != "202" ]]; then
      echo "::error::Deploy webhook rejected (HTTP $HTTP_CODE)"
      exit 1
    fi
    echo "Deploy initiated (HTTP 202), polling health endpoint..."

- name: Verify deploy health
  run: |
    # Poll the app's public health endpoint until it reports the new version
    for i in $(seq 1 30); do
      HEALTH=$(curl -sf "https://app.soleur.ai/health" 2>/dev/null || echo "")
      if echo "$HEALTH" | grep -q "$VERSION"; then
        echo "Deploy verified: $HEALTH"
        exit 0
      fi
      echo "Attempt $i/30: waiting for v$VERSION..."
      sleep 10
    done
    echo "::error::Deploy verification timed out after 300s"
    exit 1
```

**Trade-offs:**
- Pro: Eliminates 524 timeout entirely; deploys of any duration work
- Pro: No external tools needed (Task Spooler, etc.)
- Con: CI loses inline deploy output; must verify via health endpoint
- Con: If ci-deploy.sh fails silently, CI only detects via health check timeout (slower feedback)
- Mitigation: ci-deploy.sh already logs to syslog (`logger -t ci-deploy`); add deploy failure Discord notification as a future enhancement

**Option C: Accept synchronous with retry.** Keep `include-command-output-in-response: true` and add retry logic. Only viable if deploys consistently complete in <120s. Risky because Docker pull times are unpredictable.

**Files:**
- `apps/web-platform/infra/cloud-init.yml` -- update hooks.json template (async config)
- `apps/telegram-bridge/infra/cloud-init.yml` -- same
- `.github/workflows/web-platform-release.yml` -- split into fire-and-forget + health poll
- `.github/workflows/telegram-bridge-release.yml` -- same
- Manual: update hooks.json on running servers via SSH (cloud-init doesn't reapply)

### Fix 4: Provision webhook infrastructure on telegram-bridge server (P4 + P5)

**Option A (recommended): Separate tunnel per server.** Provision cloudflared, webhook binary, and systemd services on the telegram-bridge server. Create a second Cloudflare Tunnel (e.g., `soleur-telegram-bridge`) with route `deploy-bridge.soleur.ai -> localhost:9000`. Update `telegram-bridge-release.yml` to hit the bridge-specific endpoint. This maintains server isolation and aligns with the existing architecture (separate servers, separate Terraform roots).

**Option B: Single tunnel, routing by path.** Keep a single `deploy.soleur.ai` endpoint on the web-platform server. The webhook listener dispatches to the correct server via SSH from the web-platform server to the bridge server. This adds SSH as a dependency again (defeating the purpose of the tunnel migration) and creates a single point of failure.

**Files (Option A):**
- `apps/telegram-bridge/infra/cloud-init.yml` -- add cloudflared, webhook binary, hooks.json, webhook.service (mirror web-platform pattern)
- `apps/telegram-bridge/infra/tunnel.tf` -- new Cloudflare Tunnel + Access application + service token
- `apps/telegram-bridge/infra/variables.tf` -- add `webhook_deploy_secret`, `cf_account_id`, `cf_zone_id`, `app_domain_base`
- `apps/telegram-bridge/infra/server.tf` -- add `tunnel_token` and `webhook_deploy_secret` to `templatefile()` vars; remove `deploy_ssh_public_key`
- `.github/workflows/telegram-bridge-release.yml` -- change webhook URL to `deploy-bridge.soleur.ai`

### Research Insights (Fix 4)

**Terraform resource template for telegram-bridge tunnel.tf:**

Use `cloudflare_zero_trust_*` resource names (work in both v4 and v5 per learning). Mirror the web-platform `tunnel.tf` structure exactly:

```hcl
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "bridge" {
  account_id = var.cf_account_id
  name       = "soleur-telegram-bridge"
  config_src = "cloudflare"
  secret     = random_id.tunnel_secret.b64_std
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "bridge" {
  account_id = var.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.bridge.id

  config {
    ingress_rule {
      hostname = "deploy-bridge.${var.app_domain_base}"
      service  = "http://localhost:9000"
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "cloudflare_zero_trust_access_application" "deploy" {
  zone_id          = var.cf_zone_id
  name             = "Deploy Webhook - soleur-telegram-bridge"
  domain           = "deploy-bridge.${var.app_domain_base}"
  type             = "self_hosted"
  session_duration = "24h"
}

# Reuse or create new service token
resource "cloudflare_zero_trust_access_policy" "deploy_service_token" {
  zone_id        = var.cf_zone_id
  application_id = cloudflare_zero_trust_access_application.deploy.id
  name           = "Allow GitHub Actions deploy"
  decision       = "non_identity"
  precedence     = 1

  include {
    service_token = [<shared_or_new_token_id>]
  }
}
```

**Manual provisioning steps for running telegram-bridge server:**

Since cloud-init won't re-run, these must be executed via SSH after `terraform apply` creates the tunnel:

```bash
# 1. Install cloudflared
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared noble main" > /etc/apt/sources.list.d/cloudflare-main.list
apt-get update && apt-get install -y cloudflared
cloudflared service install <TUNNEL_TOKEN>

# 2. Install webhook binary (same version + checksum as web-platform)
WEBHOOK_VERSION="2.8.2"
WEBHOOK_SHA256="7a190ec7b4c2ffbb4eb1e11755a2e7acd82f1ffe74f60f235a360441daf22fd2"
curl -fsSL "https://github.com/adnanh/webhook/releases/download/${WEBHOOK_VERSION}/webhook-linux-amd64.tar.gz" -o /tmp/webhook.tar.gz
echo "${WEBHOOK_SHA256}  /tmp/webhook.tar.gz" | sha256sum -c -
tar xzf /tmp/webhook.tar.gz -C /usr/local/bin --strip-components=1 webhook-linux-amd64/webhook
chmod +x /usr/local/bin/webhook
rm /tmp/webhook.tar.gz

# 3. Write hooks.json (async config)
mkdir -p /etc/webhook
cat > /etc/webhook/hooks.json << 'EOF'
[{
  "id": "deploy",
  "execute-command": "/usr/local/bin/ci-deploy.sh",
  "command-working-directory": "/",
  "include-command-output-in-response": false,
  "success-http-response-code": 202,
  "response-message": "Deploy initiated",
  "http-methods": ["POST"],
  "trigger-rule-mismatch-http-response-code": 403,
  "pass-environment-to-command": [{
    "source": "payload", "name": "command", "envname": "SSH_ORIGINAL_COMMAND"
  }],
  "trigger-rule": {
    "match": {
      "type": "payload-hmac-sha256",
      "secret": "<WEBHOOK_DEPLOY_SECRET>",
      "parameter": {"source": "header", "name": "X-Signature-256"}
    }
  }
}]
EOF
chown root:deploy /etc/webhook/hooks.json
chmod 640 /etc/webhook/hooks.json

# 4. Create and start webhook.service (mirror web-platform)
cat > /etc/systemd/system/webhook.service << 'EOF'
[Unit]
Description=Webhook deploy listener
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/webhook -verbose -hooks /etc/webhook/hooks.json -port 9000 -ip 127.0.0.1
Restart=on-failure
RestartSec=5
User=deploy
Group=deploy
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
ReadWritePaths=/mnt/data
ReadOnlyPaths=/etc/webhook /usr/local/bin
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now webhook
```

**Checksum verification requirement (learning `2026-03-20-checksum-verification-binary-downloads.md`):**
- Always verify the webhook binary SHA256 against the actual GitHub release artifact
- The checksum `7a190ec7b4c2ffbb4eb1e11755a2e7acd82f1ffe74f60f235a360441daf22fd2` from the web-platform cloud-init was verified during #967 provisioning
- Re-verify if upgrading the webhook version

### Fix 5: Add deploy concurrency per server (structural)

Both workflows currently use `concurrency: { group: deploy-production }`. Since they deploy to different servers, they should use separate concurrency groups (`deploy-web-platform`, `deploy-telegram-bridge`) to allow parallel deploys to different servers while still serializing deploys to the same server.

**Files:**
- `.github/workflows/web-platform-release.yml` -- change concurrency group to `deploy-web-platform`
- `.github/workflows/telegram-bridge-release.yml` -- change concurrency group to `deploy-telegram-bridge`

## Non-Goals

- Migrating to container orchestration (K8s, Nomad)
- Splitting ci-deploy.sh into separate per-component scripts
- Changing the Docker build/push pipeline (GHCR)
- Adding deploy failure Discord notifications (noted as open question in brainstorm, deferred)
- Modifying the reusable-release.yml version computation logic
- Upgrading to Cloudflare Terraform provider v5 (would require renaming all existing resources)

## Acceptance Criteria

- [ ] Web-platform release workflow deploys successfully via webhook (push trigger)
- [ ] Telegram-bridge release workflow deploys successfully via webhook (push trigger)
- [ ] `workflow_dispatch` manual deploys work for both apps
- [ ] Deploy retries work (re-running a failed workflow succeeds when the release already exists)
- [x] Deploys to different servers can run in parallel
- [x] Deploys to the same server are serialized (concurrency group)
- [ ] Cloudflare Access rejects unauthenticated requests to both deploy endpoints
- [x] ci-deploy.sh failures produce actionable error messages in CI logs (syslog + structured stderr)
- [x] Existing ci-deploy.test.sh passes unchanged
- [x] Webhook returns 202 within 5 seconds (no more 524 timeouts)
- [ ] Health check polling in CI detects successful deploy within 300 seconds

## Test Scenarios

- Given a push to main that changes `apps/web-platform/`, when the web-platform-release workflow runs, then the webhook returns HTTP 202 and the health endpoint reports the new version within 300s
- Given a push to main that changes `apps/telegram-bridge/`, when the telegram-bridge-release workflow runs, then the webhook returns HTTP 202 and the health endpoint reports the new version within 300s
- Given a prior release already exists for the computed version, when the workflow is re-run, then version output is still set and deploy proceeds (retry capability)
- Given both workflows trigger simultaneously, when deploys run, then web-platform and telegram-bridge deploy in parallel (different concurrency groups, different servers)
- Given an unauthenticated request to `deploy.soleur.ai`, then Cloudflare Access returns 403 (not a managed challenge page)
- Given an unauthenticated request to `deploy-bridge.soleur.ai`, then Cloudflare Access returns 403
- Given ci-deploy.sh fails during Docker operations, then syslog contains the error (`journalctl -u webhook -t ci-deploy`) and the CI health poll times out with a clear error message
- Given the Docker pull takes 90 seconds, when the webhook fires asynchronously, then no 524 timeout occurs (webhook returns 202 immediately)
- Given the Doppler token is expired, when ci-deploy.sh runs, then it falls back to `/mnt/data/.env` and the deploy still succeeds (graceful degradation)
- Given a webhook request with an invalid HMAC signature, then the webhook returns 403 (trigger-rule-mismatch-http-response-code)

## Implementation Phases

### Phase 1: Diagnose (30 min)

1. SSH into the web-platform server and run the diagnostic checklist:
   - `systemctl status webhook` / `systemctl status cloudflared`
   - `df -h` (check disk, especially root partition)
   - `docker ps -a` (check for crash-looping containers)
   - `journalctl -u webhook --since "2026-03-20" --no-pager | tail -100`
   - `cat /etc/environment | grep DOPPLER` (token present?)
   - `ls -la /etc/webhook/hooks.json` (readable by deploy user?)
   - `sudo -u deploy docker ps` (deploy user has Docker access?)
2. Verify Bot Fight Mode status via Cloudflare API or dashboard
3. Test webhook locally: `curl -X POST -H "Content-Type: application/json" -H "X-Signature-256: sha256=<computed>" -d '{"command":"deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v0.1.57"}' http://localhost:9000/hooks/deploy`
4. Document the specific error causing HTTP 500

### Phase 2: Fix web-platform deploy (1 hr)

1. Fix the root cause identified in Phase 1:
   - If disk full: `docker system prune -af --filter "until=24h"`, verify weekly cron exists
   - If Doppler token expired: update `/etc/environment` and restart webhook service
   - If permissions: check/fix hooks.json ownership (`root:deploy`, `0640`)
   - If Docker socket: add `/var/run/docker.sock` access if needed
2. If Bot Fight Mode is still active, disable it via API: `PATCH /zones/{zone_id}/bot_management {"fight_mode": false}`
3. Switch hooks.json to async mode (`include-command-output-in-response: false`, `success-http-response-code: 202`)
4. Update `.github/workflows/web-platform-release.yml` deploy step to fire-and-forget + health poll pattern
5. Add error trap to ci-deploy.sh: `trap 'echo "DEPLOY_ERROR: line $LINENO exit $?" >&2' ERR`
6. Trigger `workflow_dispatch` to verify fix
7. Run ci-deploy.test.sh to verify tests still pass

### Phase 3: Provision telegram-bridge webhook (1.5 hr)

1. Create `apps/telegram-bridge/infra/tunnel.tf` with Cloudflare Tunnel + Access resources (use `cloudflare_zero_trust_*` names, validated against v4 provider)
2. Update `apps/telegram-bridge/infra/variables.tf` to add `webhook_deploy_secret`, `cf_account_id`, `cf_zone_id`, `app_domain_base`
3. Update `apps/telegram-bridge/infra/cloud-init.yml` to add cloudflared, webhook binary, hooks.json (async), webhook.service (mirror web-platform pattern)
4. Update `apps/telegram-bridge/infra/server.tf`:
   - Add `tunnel_token` and `webhook_deploy_secret` to `templatefile()` vars
   - Remove `deploy_ssh_public_key` from templatefile vars
5. Run `terraform validate` to catch v4/v5 naming issues
6. Run `terraform plan` and `terraform apply`
7. **Manual provisioning:** SSH into the telegram-bridge server and execute the provisioning commands (cloudflared install, webhook binary install with checksum, hooks.json, webhook.service). cloud-init does NOT re-run on existing servers.
8. Update `.github/workflows/telegram-bridge-release.yml`:
   - Change webhook URL to `https://deploy-bridge.soleur.ai/hooks/deploy`
   - Update deploy step to fire-and-forget + health poll pattern (health endpoint: `http://localhost:8080/health` via tunnel or direct)
9. Add CF Access secrets to GitHub Actions (or verify existing shared token works)
10. Trigger `workflow_dispatch` to verify end-to-end

### Phase 4: Structural improvements (30 min)

1. Update concurrency groups: `deploy-web-platform` and `deploy-telegram-bridge`
2. Verify both workflows via `workflow_dispatch` run in parallel successfully
3. Run `apps/web-platform/infra/ci-deploy.test.sh` one final time
4. Run compound (`skill: soleur:compound`) before committing

## Dependencies and Risks

- **Server access required:** Diagnosis and manual provisioning require SSH access to both Hetzner servers (root for provisioning, deploy user for testing)
- **Terraform state:** Changes to telegram-bridge infra require Terraform credentials (Hetzner + Cloudflare + R2 backend). Use `doppler run --name-transformer tf-var -- terraform plan` per learning `2026-03-21-doppler-tf-var-naming-alignment.md`, but set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` separately (the tf-var transformer breaks S3 backend auth per learning `2026-03-21-terraform-state-r2-migration.md`)
- **GitHub Secrets:** New secrets may be needed: `WEBHOOK_DEPLOY_SECRET_BRIDGE` (separate HMAC secret per server). CF Access secrets may be reusable if using a shared account-scoped service token
- **Cloudflare plan tier:** Confirmed: 120s Proxy Read Timeout is not configurable on non-Enterprise plans. The async webhook pattern (Fix 3 Option B) eliminates this constraint entirely
- **Risk: cloud-init changes are dead code for running servers.** cloud-init only runs at server creation. The Terraform `lifecycle { ignore_changes = [user_data] }` block prevents automatic reprovisioning. Mitigation: execute manual provisioning steps via SSH after `terraform apply`. Track these as Phase 3 step 7.
- **Risk: async deploy loses inline error output.** Switching to fire-and-forget means CI cannot see ci-deploy.sh errors in the HTTP response. Mitigation: ci-deploy.sh already logs to syslog; health check polling detects failures; future enhancement can add deploy-status endpoint or Discord failure notification
- **Risk: Terraform provider v4/v5 naming.** Research agents may generate v5 resource attributes. Mitigation: run `terraform validate` after every resource addition (per learning `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`)
- **Risk: webhook checksum verification.** The SHA256 for webhook v2.8.2 was verified during #967 but must be re-downloaded and verified if using a different architecture or version (per learning `2026-03-20-checksum-verification-binary-downloads.md`)

## References

- Brainstorm: [2026-03-20-ci-release-reliability-brainstorm.md](../brainstorms/2026-03-20-ci-release-reliability-brainstorm.md)
- Learning: [2026-03-21-cloudflare-tunnel-server-provisioning.md](../learnings/2026-03-21-cloudflare-tunnel-server-provisioning.md)
- Learning: [2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md](../learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md)
- Learning: [2026-03-20-cloudflare-terraform-v4-v5-resource-names.md](../learnings/2026-03-20-cloudflare-terraform-v4-v5-resource-names.md)
- Learning: [2026-03-20-doppler-secrets-manager-setup-patterns.md](../learnings/2026-03-20-doppler-secrets-manager-setup-patterns.md)
- Learning: [2026-03-21-doppler-tf-var-naming-alignment.md](../learnings/2026-03-21-doppler-tf-var-naming-alignment.md)
- Learning: [2026-03-21-terraform-state-r2-migration.md](../learnings/2026-03-21-terraform-state-r2-migration.md)
- Issue: [#968 - deploy webhook unreachable from GitHub Actions](https://github.com/jikig-ai/soleur/issues/968)
- PR #963: Replace SSH CI deploy with Cloudflare Tunnel webhook
- PR #967: Complete Cloudflare Tunnel server-side provisioning
- Spec: [feat-webhook-deploy/spec.md](../project/specs/feat-webhook-deploy/spec.md)
- Cloudflare: [Connection limits](https://developers.cloudflare.com/fundamentals/reference/connection-limits/) -- 120s Proxy Read Timeout, Enterprise-only configuration
- Cloudflare: [Error 524](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/) -- timeout causes and remediation
- adnanh/webhook: [Hook configuration](https://deepwiki.com/adnanh/webhook/3-hook-configuration) -- async execution properties
- adnanh/webhook: [Background execution issue #245](https://github.com/adnanh/webhook/issues/245) -- exec.Run() blocks; use include-command-output-in-response: false
- `.github/workflows/web-platform-release.yml`
- `.github/workflows/telegram-bridge-release.yml`
- `.github/workflows/reusable-release.yml`
- `apps/web-platform/infra/ci-deploy.sh`
- `apps/web-platform/infra/cloud-init.yml`
- `apps/telegram-bridge/infra/cloud-init.yml`
- `apps/web-platform/infra/tunnel.tf`
- `apps/telegram-bridge/infra/server.tf`

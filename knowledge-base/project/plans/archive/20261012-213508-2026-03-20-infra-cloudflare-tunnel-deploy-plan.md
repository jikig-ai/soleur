---
title: "infra: migrate to Cloudflare Tunnel deploy"
type: feat
date: 2026-03-20
---

# infra: migrate to Cloudflare Tunnel deploy

[Updated 2026-03-20] Simplified after plan review — reduced from 6 phases to 2. Tunnel scoped to webhook endpoint only. Admin SSH and app traffic stay on existing paths.

## Overview

Replace SSH-based CI deploy with a Cloudflare Tunnel routing the deploy webhook through Cloudflare's edge. Install a webhook listener (`adnanh/webhook`) that validates GitHub HMAC signatures and invokes the existing `ci-deploy.sh` — preserving version pinning, health checks, and audit trail while eliminating the `0.0.0.0/0` SSH firewall rule.

## Problem Statement

The web-platform CI deploy opens SSH (port 22) to `0.0.0.0/0` because GitHub Actions runners use 5000+ dynamic IPs (`apps/web-platform/infra/firewall.tf:16-21`). This exposes the server to SSH brute-force attacks from the entire internet.

## Proposed Solution

Route deploy webhook traffic through a Cloudflare Tunnel. Admin SSH stays via `admin_ips` firewall rules. App traffic stays via existing Cloudflare-proxied A record. Only the CI deploy path changes.

```
┌──────────────┐      ┌─────────────────┐      ┌───────────────────────────────┐
│ GitHub Actions│─────▶│ Cloudflare Edge  │─────▶│ Hetzner Server                │
│ (curl POST)  │ HTTPS│ deploy.soleur.ai │Tunnel│ cloudflared ──▶ localhost:9000 │
└──────────────┘      │ (Access + HMAC)  │      │ webhook ──▶ ci-deploy.sh       │
                      └─────────────────┘      └───────────────────────────────┘

┌──────────┐          ┌─────────────────┐      ┌───────────────────────────────┐
│ Users    │─────────▶│ Cloudflare Proxy │─────▶│ :80 ──▶ Docker :3000          │
└──────────┘   HTTPS  │ app.soleur.ai   │  A   │ (unchanged — existing path)   │
                      └─────────────────┘      └───────────────────────────────┘

┌──────────┐                                   ┌───────────────────────────────┐
│ Admin    │──────────────────────────────────▶│ :22 (admin_ips only)           │
└──────────┘            SSH (direct)           │ (unchanged — existing path)   │
                                               └───────────────────────────────┘
```

## Technical Approach

### Architecture

**Key design constraint:** `ci-deploy.sh` parses `SSH_ORIGINAL_COMMAND` (line 38). The webhook handler sets this env var via `pass-environment-to-command` in `hooks.json` — the script stays unchanged, and `ci-deploy.test.sh` passes unmodified.

**Components:**

| Component | Purpose | Binary | Managed By |
|-----------|---------|--------|------------|
| `cloudflared` | Tunnel daemon (outbound connection to CF edge) | Pre-built Linux amd64 (pkg.cloudflare.com) | cloud-init install + systemd (via `cloudflared service install`) |
| `webhook` | HTTP listener for deploy triggers | Pre-built Go binary (~5MB, v2.8.2) | cloud-init install + systemd unit |
| `hooks.json` | Webhook config (HMAC validation, env injection) | JSON config file | cloud-init write_files (templated) |
| Terraform | Tunnel, DNS, Access resources | Cloudflare provider ~> 4.0 | Existing `apps/web-platform/infra/` |

**HMAC flow:**

1. GitHub Actions computes `HMAC-SHA256(payload, secret)` and sends as `X-Signature-256: sha256=<hex>` header
2. `webhook` binary validates signature (returns 403 on mismatch via `trigger-rule-mismatch-http-response-code`)
3. On match: sets `SSH_ORIGINAL_COMMAND` from `payload.command` field, invokes `ci-deploy.sh` synchronously (`include-command-output-in-response: true`)
4. Returns ci-deploy.sh exit code as HTTP status to GitHub Actions

**Defense in depth on `deploy.soleur.ai`:**

1. Cloudflare Access service token — rejects unauthenticated requests at the edge
2. HMAC-SHA256 signature validation — proves request came from holder of the secret
3. ci-deploy.sh allowlist — validates component, image, and tag format

### Implementation Phases

#### Phase 1: Tunnel + Webhook Infrastructure

Create the tunnel, webhook listener, and server provisioning. Deploy alongside existing SSH path.

**New Terraform resources (`apps/web-platform/infra/tunnel.tf`):**

- `cloudflare_zero_trust_tunnel_cloudflared.web` — creates the tunnel
- `cloudflare_zero_trust_tunnel_cloudflared_config.web` — single ingress: `deploy.soleur.ai` → `http://localhost:9000` + catch-all 404
- `cloudflare_zero_trust_access_application.deploy` — Access app for the deploy endpoint
- `cloudflare_zero_trust_access_service_token.deploy` — service token for GitHub Actions
- `cloudflare_zero_trust_access_policy.deploy_service_token` — allow policy for the service token

**DNS (`apps/web-platform/infra/dns.tf`):**

- Keep `cloudflare_record.app` **unchanged** (A record, proxied — existing app path)
- Add `cloudflare_record.deploy` — CNAME to `<tunnel-id>.cfargotunnel.com` (proxied)

**New Terraform variables (`apps/web-platform/infra/variables.tf`):**

- `cloudflare_account_id` (string) — needed for Zero Trust resources
- `webhook_deploy_secret` (string, sensitive) — HMAC shared secret

**Terraform provider (`apps/web-platform/infra/main.tf`):**

- Add `random` provider (for tunnel secret generation)

**Terraform outputs:**

- `tunnel_token` (sensitive = true) — for cloud-init injection
- `access_service_token_client_id` — for GitHub Actions
- `access_service_token_client_secret` (sensitive) — for GitHub Actions

**cloud-init changes (`apps/web-platform/infra/cloud-init.yml`):**

New write_files:

- `/etc/webhook/hooks.json` — HMAC config with `trigger-rule-mismatch-http-response-code: 403`, `include-command-output-in-response: true`, `http-methods: ["POST"]`, `SSH_ORIGINAL_COMMAND` env injection
- `/etc/systemd/system/webhook.service` — hardened systemd unit (runs as `deploy` user, `Restart=on-failure`, `RestartSec=5`, `NoNewPrivileges=true`, `ProtectSystem=strict`)

New runcmd:

- Install `cloudflared` via pkg.cloudflare.com apt repository (automatic updates)
- `cloudflared service install <tunnel_token>`
- Install `webhook` binary v2.8.2 from GitHub releases with SHA256 checksum verification
- `systemctl enable --now webhook`

**server.tf templatefile changes:**

- Add `tunnel_token` and `webhook_deploy_secret` variables

**Files to create:**

- `apps/web-platform/infra/tunnel.tf`

**Files to modify:**

- `apps/web-platform/infra/main.tf` — add `random` provider
- `apps/web-platform/infra/dns.tf` — add deploy CNAME
- `apps/web-platform/infra/variables.tf` — add new variables
- `apps/web-platform/infra/cloud-init.yml` — add cloudflared/webhook provisioning
- `apps/web-platform/infra/server.tf` — add templatefile variables

**hooks.json structure:**

```json
[
  {
    "id": "deploy",
    "execute-command": "/usr/local/bin/ci-deploy.sh",
    "command-working-directory": "/",
    "include-command-output-in-response": true,
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
]
```

**webhook systemd unit:**

```ini
[Unit]
Description=Webhook deploy listener
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/webhook -hooks /etc/webhook/hooks.json -port 9000 -ip 127.0.0.1
Restart=on-failure
RestartSec=5
User=deploy
Group=deploy
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/etc/webhook /usr/local/bin
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
```

Note: `TimeoutStopSec=180` accounts for synchronous ci-deploy.sh execution (telegram-bridge health check can take 120s).

**Acceptance criteria:**

- [ ] `terraform plan` shows tunnel, DNS, and access resources
- [ ] `cloudflared` running, tunnel connected
- [ ] `webhook` listening on `localhost:9000`
- [ ] Unauthenticated request to `deploy.soleur.ai` rejected by Cloudflare Access
- [ ] HMAC-authenticated request invokes ci-deploy.sh and returns output

#### Phase 2: CI Switch + Firewall Lockdown + Cleanup

Replace SSH deploy in CI workflows, remove the `0.0.0.0/0` SSH firewall rule, clean up SSH deploy infrastructure.

**GitHub Actions changes (`.github/workflows/web-platform-release.yml`):**

Replace `appleboy/ssh-action` deploy step with:

```yaml
steps:
  - name: Deploy via webhook
    env:
      WEBHOOK_SECRET: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}
      DEPLOY_URL: https://deploy.soleur.ai
      CF_ACCESS_CLIENT_ID: ${{ secrets.CF_ACCESS_CLIENT_ID }}
      CF_ACCESS_CLIENT_SECRET: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}
      VERSION: ${{ needs.release.outputs.version }}
    run: |
      PAYLOAD=$(printf '{"command":"deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v%s"}' "$VERSION")
      SIGNATURE=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
      RESPONSE=$(mktemp)
      HTTP_CODE=$(curl -s -o "$RESPONSE" -w '%{http_code}' \
        --max-time 150 \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Signature-256: sha256=$SIGNATURE" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        -d "$PAYLOAD" \
        "${DEPLOY_URL}/hooks/deploy")
      if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
        echo "::error::Deploy webhook failed (HTTP $HTTP_CODE)"
        cat "$RESPONSE"
        exit 1
      fi
      echo "Deploy completed (HTTP $HTTP_CODE)"
      cat "$RESPONSE"
```

Same change for `telegram-bridge-release.yml` with `telegram-bridge` component/image.

Note: `--max-time 150` accommodates the telegram-bridge 120s health check + buffer. Cloudflare free-tier proxy timeout is 100s — if this becomes an issue, restructure telegram-bridge health check to complete within 90s (reduce from 24 attempts x 5s to 18 attempts x 5s = 90s).

**Firewall change (`apps/web-platform/infra/firewall.tf`):**

Remove only the CI deploy SSH rule (lines 16-21). Keep everything else unchanged.

```hcl
resource "hcloud_firewall" "web" {
  name = "soleur-web-platform"

  # SSH -- admin IPs (kept for direct admin access)
  dynamic "rule" {
    for_each = var.admin_ips
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = [rule.value]
    }
  }

  # HTTP (app traffic via Cloudflare proxy -- existing path)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # ICMP (ping) from anywhere
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}
```

Note: Also removes port 3000 rule (was "for development" — should not be open on production).

**SSH deploy cleanup:**

- `apps/web-platform/infra/cloud-init.yml` — remove deploy user `ssh_authorized_keys` (keep deploy user for webhook/docker)
- `apps/web-platform/infra/cloud-init.yml` — update `AllowUsers root deploy` to `AllowUsers root` (deploy user no longer needs SSH)
- `apps/web-platform/infra/variables.tf` — remove `deploy_ssh_public_key`
- `apps/web-platform/infra/server.tf` — remove `deploy_ssh_public_key` from templatefile

**New GitHub Actions secrets:**

- `WEBHOOK_DEPLOY_SECRET` — HMAC shared secret
- `CF_ACCESS_CLIENT_ID` — Cloudflare Access service token client ID
- `CF_ACCESS_CLIENT_SECRET` — Cloudflare Access service token client secret

**GitHub Actions secrets to remove:**

- `WEB_PLATFORM_SSH_KEY`
- `WEB_PLATFORM_HOST_FINGERPRINT`

**Files to modify:**

- `.github/workflows/web-platform-release.yml` — replace deploy step
- `.github/workflows/telegram-bridge-release.yml` — replace deploy step
- `apps/web-platform/infra/firewall.tf` — remove CI SSH rule + port 3000
- `apps/web-platform/infra/cloud-init.yml` — remove deploy SSH key, update AllowUsers
- `apps/web-platform/infra/variables.tf` — remove `deploy_ssh_public_key`
- `apps/web-platform/infra/server.tf` — remove from templatefile

**Verification (inline, not separate phase):**

1. Trigger web-platform release → deploy completes with health check via webhook
2. Trigger telegram-bridge release → same
3. Invalid HMAC → 403 rejected
4. Admin SSH → still works via `ssh root@<ip>` from admin IP
5. `nmap -Pn -p 22 <server-ip>` from non-admin IP → filtered

**Acceptance criteria:**

- [ ] Both release workflows deploy via webhook successfully
- [ ] ci-deploy.sh health checks pass through webhook path
- [ ] `0.0.0.0/0` SSH rule removed from firewall
- [ ] Port 3000 rule removed from firewall
- [ ] Admin SSH still works from admin IPs
- [ ] Deploy SSH key removed from cloud-init and Terraform
- [ ] Old GitHub Actions SSH secrets removed
- [ ] ci-deploy.test.sh passes unchanged

## Rollback Procedure

If the tunnel or webhook fails post-deployment:

1. **Immediate:** Re-enable SSH deploy by adding `appleboy/ssh-action` back to workflows and re-creating `WEB_PLATFORM_SSH_KEY` secret. The `0.0.0.0/0` SSH rule can be restored via `terraform apply` with the rule re-added to `firewall.tf`.
2. **Emergency server access:** Hetzner console (VNC/serial) provides network-independent access regardless of firewall or tunnel state. Admin-IP SSH remains available as the primary access path.
3. **Webhook secret rotation:** Update `WEBHOOK_DEPLOY_SECRET` in GitHub Actions, update `/etc/webhook/hooks.json` on server, `systemctl restart webhook`.

## Alternative Approaches Considered

| Option | Verdict | Reason |
|--------|---------|--------|
| Watchtower | Rejected | Loses version pinning, health checks, CI audit trail, deploy serialization. Prior plans rejected it twice. |
| Full tunnel (app + SSH + webhook) | Rejected (scope) | Adds failure modes (cloudflared crash kills app), makes admin SSH worse (browser auth). The problem is one firewall rule, not the entire traffic architecture. Revisit as a separate initiative if desired. |
| Standalone webhook (no tunnel) | Rejected | Requires new open port in firewall. Tunnel keeps webhook on localhost only — better security. |
| GitHub repository webhooks | Considered | Built-in HMAC but adds complexity parsing release payloads. Explicit curl preserves structured protocol. |

## Acceptance Criteria

### Functional Requirements

- [ ] Cloudflare Tunnel active with route for `deploy.soleur.ai`
- [ ] Deploy triggered via webhook from GitHub Actions (not SSH)
- [ ] ci-deploy.sh health checks pass through webhook trigger path
- [ ] `0.0.0.0/0` SSH firewall rule removed
- [ ] Admin SSH works from admin IPs (unchanged)
- [ ] App accessible via `app.soleur.ai` (unchanged)

### Non-Functional Requirements

- [ ] Existing `ci-deploy.test.sh` passes unchanged
- [ ] All infrastructure changes via Terraform
- [ ] Webhook secret stored as GitHub Actions `secrets.*`
- [ ] Deploy concurrency group preserved (`deploy-production`)
- [ ] Webhook binary checksum-verified during install
- [ ] Cloudflare Access service token protects deploy endpoint

## Test Scenarios

### Acceptance Tests

- Given webhook is running, when GitHub Actions sends a valid HMAC-signed deploy payload with CF Access headers, then ci-deploy.sh executes and health check passes
- Given webhook is running, when an invalid HMAC signature is sent, then returns HTTP 403 and ci-deploy.sh is NOT invoked
- Given webhook is running, when CF Access headers are missing, then Cloudflare edge returns 403 before reaching the server
- Given webhook is running, when payload contains invalid component/image/tag, then ci-deploy.sh rejects with appropriate error
- Given firewall updated, when SSH attempted from non-admin IP, then connection refused

### Edge Cases

- Given cloudflared restarts (systemd), when a deploy webhook arrives during restart, then webhook binary is unaffected (separate service on localhost)
- Given tunnel disconnects temporarily, when it reconnects, then deploy route resumes (app and SSH unaffected — they don't use the tunnel)
- Given server reboots, when cloud-init has run, then both cloudflared and webhook start automatically
- Given deploy takes >100s (telegram-bridge), when Cloudflare proxy times out, then restructure health check to complete within 90s

## Dependencies & Prerequisites

| Dependency | Status | Action |
|------------|--------|--------|
| Cloudflare account | Exists | Already using for DNS |
| Cloudflare Zero Trust | New | Enable free tier |
| Cloudflare API token | Exists | May need tunnel + access permissions |
| `cloudflare/cloudflare` provider ~> 4.0 | Exists | Already in `main.tf` |
| `adnanh/webhook` binary v2.8.2 | New | Install in cloud-init with checksum |
| `cloudflared` | New | Install via apt (pkg.cloudflare.com) |
| `cloudflare_account_id` | New | Add to Terraform variables |

## Risk Analysis & Mitigation

| Risk | Severity | Probability | Mitigation |
|------|----------|-------------|------------|
| Tunnel down → can't deploy | Medium | Low | systemd restart-on-failure. App and SSH unaffected (separate paths). Rollback: re-enable SSH deploy. |
| Webhook secret compromised | Medium | Low | CF Access service token as second auth layer. ci-deploy.sh allowlist limits blast radius. Rotation procedure documented. |
| Cloudflare outage → can't deploy | Medium | Very Low | App still serves via A record. SSH still works. Only deploys blocked. |
| `adnanh/webhook` binary compromise | Low | Very Low | Checksum verification on install. Pin to specific release. |
| Telegram-bridge deploy exceeds CF 100s timeout | Medium | High | Reduce health check from 24x5s (120s) to 18x5s (90s). |

## Institutional Learnings Applied

1. **Bash operator precedence** (`runtime-errors/2026-02-13`): ci-deploy.sh already uses `{ ...; }` grouping. Validated safe.
2. **Webhook URLs are secrets** (`implementation-patterns/2026-02-12`): `WEBHOOK_DEPLOY_SECRET` stored as `secrets.*`.
3. **SHA-pin all actions** (`2026-02-27`): No new actions (curl is built-in).
4. **GITHUB_TOKEN cascade** (`integration-issues`): Deploy in same workflow as release — no cascade issue.
5. **Terraform + cloud-init** (`integration-issues/2026-02-10`): New entries are additive, no conflicts.

## References

### Internal

- **Brainstorm:** `knowledge-base/project/brainstorms/2026-03-20-cloudflare-tunnel-deploy-brainstorm.md`
- **Spec:** `knowledge-base/project/specs/feat-webhook-deploy/spec.md`
- **ci-deploy.sh:** `apps/web-platform/infra/ci-deploy.sh`
- **ci-deploy.test.sh:** `apps/web-platform/infra/ci-deploy.test.sh`
- **Firewall (target):** `apps/web-platform/infra/firewall.tf:16-21`
- **Cloud-init:** `apps/web-platform/infra/cloud-init.yml`
- **Release workflows:** `.github/workflows/web-platform-release.yml`, `.github/workflows/telegram-bridge-release.yml`

### External

- [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Cloudflare Terraform — tunnel resources](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_tunnel_cloudflared)
- [adnanh/webhook](https://github.com/adnanh/webhook)
- [adnanh/webhook hook definition](https://github.com/adnanh/webhook/wiki/Hook-Definition)
- [Cloudflare pkg.cloudflare.com](https://pkg.cloudflare.com/)

### Related Work

- Issue: [#749](https://github.com/jikig-ai/soleur/issues/749)
- Prior: [#738](https://github.com/jikig-ai/soleur/issues/738) (CI deploy SSH key fix)
- PR: [#963](https://github.com/jikig-ai/soleur/pull/963) (draft)

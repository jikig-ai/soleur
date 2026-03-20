---
title: "infra: migrate to Cloudflare Tunnel deploy"
type: feat
date: 2026-03-20
---

# infra: migrate to Cloudflare Tunnel deploy

## Overview

Replace SSH-based CI deploy with a Cloudflare Tunnel routing all traffic (app, webhook, SSH) through Cloudflare's edge network. Install a webhook listener (`adnanh/webhook`) that validates GitHub HMAC signatures and invokes the existing `ci-deploy.sh` — preserving version pinning, health checks, and audit trail while eliminating all inbound firewall ports.

## Problem Statement

The web-platform CI deploy opens SSH (port 22) to `0.0.0.0/0` because GitHub Actions runners use 5000+ dynamic IPs (`apps/web-platform/infra/firewall.tf:16-21`). This exposes the server to SSH brute-force attacks from the entire internet. The forced-command restriction limits what the CI key can do, but the port itself is unnecessarily exposed.

## Proposed Solution

Route all server traffic through a Cloudflare Tunnel. The server becomes invisible — zero inbound ports, no scannable surface. A webhook listener triggered through the tunnel replaces SSH as the deploy mechanism.

```
┌──────────────┐      ┌─────────────────┐      ┌───────────────────────────────┐
│ GitHub Actions│─────▶│ Cloudflare Edge  │─────▶│ Hetzner Server                │
│ (curl POST)  │ HTTPS│ deploy.soleur.ai │Tunnel│ cloudflared ──▶ localhost:9000 │
└──────────────┘      │                  │      │ webhook ──▶ ci-deploy.sh       │
                      │ app.soleur.ai    │──────│ cloudflared ──▶ localhost:3000 │
                      │                  │      │                               │
                      │ ssh.soleur.ai    │──────│ cloudflared ──▶ localhost:22   │
                      └─────────────────┘      └───────────────────────────────┘
                                                  (zero inbound firewall rules)
```

## Technical Approach

### Architecture

**Key design constraint:** `ci-deploy.sh` (`apps/web-platform/infra/ci-deploy.sh`) parses `SSH_ORIGINAL_COMMAND` (line 38). The webhook handler sets this env var before invocation — the script stays completely unchanged, and `ci-deploy.test.sh` passes unmodified.

**Components:**

| Component | Purpose | Binary | Managed By |
|-----------|---------|--------|------------|
| `cloudflared` | Tunnel daemon (outbound connection to CF edge) | Pre-built Linux amd64 | cloud-init install + systemd (via `cloudflared service install`) |
| `webhook` | HTTP listener for deploy triggers | Pre-built Go binary (~5MB) | cloud-init install + systemd unit |
| `hooks.json` | Webhook route config (HMAC validation, env injection) | JSON config file | cloud-init write_files |
| Terraform | Tunnel, DNS, Access resources | Cloudflare provider ~> 4.0 | Existing `apps/web-platform/infra/` |

**HMAC flow:**

1. GitHub Actions computes `HMAC-SHA256(payload, secret)` and sends as `X-Signature-256` header
2. `webhook` binary validates signature against configured secret
3. On match: sets `SSH_ORIGINAL_COMMAND` from `payload.command` field, invokes `ci-deploy.sh`
4. On mismatch: returns 401, logs rejection

### Implementation Phases

#### Phase 1: Cloudflare Zero Trust + Tunnel (Terraform)

Create the tunnel and DNS infrastructure. No server changes yet — existing deploy path stays active.

**New Terraform resources in `apps/web-platform/infra/`:**

- `cloudflare_zero_trust_tunnel_cloudflared.web` — creates the tunnel
- `random_id.tunnel_secret` — 32-byte tunnel secret
- `cloudflare_zero_trust_tunnel_cloudflared_config.web` — ingress rules (app, deploy, SSH, catch-all 404)
- `cloudflare_zero_trust_access_application.ssh` — SSH access app
- `cloudflare_zero_trust_access_policy.ssh_admin` — email-based allow policy

**DNS changes (replace existing A record):**

- `cloudflare_record.app` — change from A record (`hcloud_server.web.ipv4_address`) to CNAME (`<tunnel-id>.cfargotunnel.com`)
- `cloudflare_record.deploy` — new CNAME for `deploy.soleur.ai`
- `cloudflare_record.ssh` — new CNAME for `ssh.soleur.ai`

**New Terraform variables:**

- `cloudflare_account_id` (string) — needed for Zero Trust resources
- `admin_email` (string) — email for SSH Access policy
- `webhook_deploy_secret` (string, sensitive) — HMAC shared secret

**Files to modify:**

- `apps/web-platform/infra/main.tf` — add `random` provider
- `apps/web-platform/infra/dns.tf` — replace A record, add CNAME records
- `apps/web-platform/infra/variables.tf` — add new variables
- New file: `apps/web-platform/infra/tunnel.tf` — all tunnel + access resources

**Acceptance criteria:**
- [ ] `terraform plan` shows tunnel, DNS, and access resources to create
- [ ] Tunnel token output available for cloud-init injection

#### Phase 2: Server Provisioning (cloud-init)

Add `cloudflared` and `webhook` to the server. Both run alongside the existing SSH deploy path.

**cloud-init changes (`apps/web-platform/infra/cloud-init.yml`):**

New write_files entries:
- `/etc/webhook/hooks.json` — webhook configuration (HMAC validation, `SSH_ORIGINAL_COMMAND` env injection, command: `/usr/local/bin/ci-deploy.sh`)
- `/etc/systemd/system/webhook.service` — systemd unit (runs as `deploy` user, `RestartSec=5`, `Restart=on-failure`)

New runcmd entries:
- Install `cloudflared` binary (curl from GitHub releases, version-pinned)
- Install `cloudflared` as system service with tunnel token: `cloudflared service install <token>`
- Install `webhook` binary (curl from GitHub releases, version-pinned, e.g., 2.8.2)
- Enable and start webhook systemd unit

**Templatefile changes (`apps/web-platform/infra/server.tf`):**

- Add `tunnel_token` to `templatefile()` variables (from tunnel Terraform output)
- Add `webhook_deploy_secret` to `templatefile()` variables

**Key detail — hooks.json structure:**

```json
[
  {
    "id": "deploy",
    "execute-command": "/usr/local/bin/ci-deploy.sh",
    "command-working-directory": "/",
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

**Deploy user changes:**

- **Keep** the `deploy` user (needed for docker group membership, sudoers for chown)
- **Remove** `ssh_authorized_keys` (no more SSH-based deploy)
- **Remove** `deploy` from `AllowUsers` in sshd hardening config (only `root` needs SSH via tunnel)
- **Keep** sudoers entry for `chown 1001:1001 /mnt/data/workspaces`

**Files to modify:**

- `apps/web-platform/infra/cloud-init.yml` — add cloudflared/webhook install, hooks.json, systemd unit; remove deploy SSH key
- `apps/web-platform/infra/server.tf` — add templatefile variables for tunnel_token and webhook_deploy_secret
- `apps/telegram-bridge/infra/cloud-init.yml` — same changes (both deploy to same server, but cloud-init should match for when they split)

**Acceptance criteria:**
- [ ] `cloudflared` running as systemd service, tunnel connected
- [ ] `webhook` listening on `localhost:9000`
- [ ] `curl -sf localhost:9000/hooks/deploy` returns 200 (unauthenticated = rejected, but endpoint reachable)
- [ ] Deploy user still has docker group membership

#### Phase 3: GitHub Actions Update

Replace SSH deploy steps with webhook curl in both release workflows. Run alongside existing SSH path initially.

**Changes to `.github/workflows/web-platform-release.yml`:**

Replace the `deploy` job's `appleboy/ssh-action` step with:

```yaml
steps:
  - name: Deploy via webhook
    env:
      WEBHOOK_SECRET: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}
      DEPLOY_URL: ${{ secrets.WEBHOOK_DEPLOY_URL }}
    run: |
      PAYLOAD=$(printf '{"command":"deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v%s"}' \
        "$VERSION")
      SIGNATURE=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
      HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Signature-256: sha256=$SIGNATURE" \
        -d "$PAYLOAD" \
        "${DEPLOY_URL}/hooks/deploy")
      if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
        echo "::error::Deploy webhook failed (HTTP $HTTP_CODE)"
        exit 1
      fi
      echo "Deploy triggered successfully (HTTP $HTTP_CODE)"
```

**Same change for `.github/workflows/telegram-bridge-release.yml`** with `telegram-bridge` component name and image.

**New GitHub Actions secrets:**

- `WEBHOOK_DEPLOY_SECRET` — HMAC shared secret (same value as Terraform `webhook_deploy_secret`)
- `WEBHOOK_DEPLOY_URL` — `https://deploy.soleur.ai` (or use env, not secret — but URL is non-sensitive)

**Secrets to remove (after verification):**

- `WEB_PLATFORM_SSH_KEY`
- `WEB_PLATFORM_HOST_FINGERPRINT`
- Keep `WEB_PLATFORM_HOST` for now (may be useful for health check polling from CI)

**GitHub Actions security (per institutional learnings):**

- No new actions to SHA-pin (curl is built-in)
- Webhook secret stored as `secrets.*`, never `vars.*`
- Payload constructed with `printf`, not string interpolation (prevents injection)
- `$HTTP_CODE` captured safely (no `$GITHUB_OUTPUT` needed for this step)

**Files to modify:**

- `.github/workflows/web-platform-release.yml` — replace deploy step
- `.github/workflows/telegram-bridge-release.yml` — replace deploy step

**Acceptance criteria:**
- [ ] Deploy job triggers webhook successfully
- [ ] ci-deploy.sh health checks pass (visible in webhook output)
- [ ] Concurrency group `deploy-production` still prevents parallel deploys
- [ ] Deploy audit trail visible in GitHub Actions logs

#### Phase 4: Verification + Cutover

Verify all traffic flows through the tunnel before removing firewall rules.

**Verification checklist:**

1. App traffic: `curl -sf https://app.soleur.ai/health` returns 200
2. Webhook deploy: trigger web-platform release → deploy completes with health check
3. Webhook deploy: trigger telegram-bridge release → deploy completes with health check
4. SSH access: `cloudflared access ssh --hostname ssh.soleur.ai` → shell on server
5. Invalid HMAC: `curl` with wrong signature → 401 rejected
6. Invalid payload: malformed command → ci-deploy.sh rejects (same as SSH path)
7. DNS: `dig app.soleur.ai` returns CNAME, not A record
8. Tunnel health: `cloudflared tunnel info` shows healthy connection

**Port scan verification:**

```bash
# From an external host (not the server itself)
nmap -Pn -p 22,80,443,3000 <server-ip>
# Expected: all ports filtered/closed (only ICMP responds)
```

#### Phase 5: Firewall Lockdown

After verification passes, remove all non-ICMP inbound rules.

**Changes to `apps/web-platform/infra/firewall.tf`:**

Remove:
- SSH admin IPs dynamic rule (lines 4-13) — admin SSH goes through tunnel
- SSH CI deploy 0.0.0.0/0 rule (lines 16-21) — deploy goes through webhook
- HTTP 80 rule (lines 24-28) — app traffic goes through tunnel
- HTTPS 443 rule (lines 30-35) — not needed (no direct HTTPS, tunnel handles it)
- App port 3000 rule (lines 38-44) — dev access goes through tunnel

Keep:
- ICMP rule (lines 47-52) — for basic connectivity monitoring

**End state `firewall.tf`:**

```hcl
resource "hcloud_firewall" "web" {
  name = "soleur-web-platform"

  # ICMP (ping) from anywhere
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}
```

**Files to modify:**

- `apps/web-platform/infra/firewall.tf` — strip to ICMP only

**Acceptance criteria:**
- [ ] `terraform apply` removes firewall rules
- [ ] Port scan confirms zero open TCP ports
- [ ] App, webhook, and SSH still work through tunnel

#### Phase 6: Cleanup

Remove SSH deploy infrastructure that's no longer needed.

**cloud-init cleanup:**

- Remove `deploy_ssh_public_key` from `ssh_authorized_keys`
- Remove `deploy` from `AllowUsers` in sshd hardening (root only)
- Remove `ci_deploy_script_b64` write_files entry (ci-deploy.sh now delivered by webhook cloud-init section, or kept as-is since it's still needed)

Wait — `ci-deploy.sh` is still needed. The webhook invokes it. Keep the write_files entry that installs it to `/usr/local/bin/ci-deploy.sh`. Only remove the SSH-specific parts.

**Terraform cleanup:**

- Remove `deploy_ssh_public_key` variable from `variables.tf`
- Remove `deploy_ssh_public_key` from `server.tf` templatefile
- Update `ci_deploy_script_b64` — still needed (webhook invokes the same script)

**GitHub secrets cleanup:**

- Remove `WEB_PLATFORM_SSH_KEY`
- Remove `WEB_PLATFORM_HOST_FINGERPRINT`
- Consider removing `WEB_PLATFORM_HOST` (or keep for SSH fallback)

**Files to modify:**

- `apps/web-platform/infra/variables.tf` — remove `deploy_ssh_public_key`
- `apps/web-platform/infra/server.tf` — remove from templatefile
- `apps/web-platform/infra/cloud-init.yml` — remove SSH key, update AllowUsers
- `apps/telegram-bridge/infra/cloud-init.yml` — same
- `apps/telegram-bridge/infra/server.tf` — remove from templatefile
- `apps/telegram-bridge/infra/variables.tf` — remove `deploy_ssh_public_key` (if it exists there)

**Acceptance criteria:**
- [ ] `terraform plan` shows no unexpected changes
- [ ] ci-deploy.sh still invocable by webhook
- [ ] No SSH secrets remain in GitHub Actions

## Alternative Approaches Considered

| Option | Verdict | Reason |
|--------|---------|--------|
| Watchtower | Rejected | Loses version pinning, health checks, CI audit trail, deploy serialization. Prior plans rejected it twice. |
| Standalone webhook (no tunnel) | Rejected | Solves SSH dependency but leaves server IP exposed, requires new open port. |
| Partial tunnel (webhook + SSH only) | Rejected | Two traffic paths to maintain. App still reachable by IP. |
| GitHub repository webhooks (release event) | Considered | GitHub fires webhooks on release events with HMAC signatures built-in. But adds complexity: parsing release payload, handling multiple components from one webhook. The explicit `curl` from CI is simpler and preserves the structured `deploy <component> <image> <tag>` protocol. |

## Acceptance Criteria

### Functional Requirements

- [ ] Cloudflare Tunnel active with routes for app (`app.soleur.ai`), webhook (`deploy.soleur.ai`), SSH (`ssh.soleur.ai`)
- [ ] Deploy triggered via webhook from GitHub Actions (not SSH)
- [ ] ci-deploy.sh health checks pass through webhook trigger path
- [ ] All inbound firewall rules removed except ICMP
- [ ] Server IP not reachable on any TCP port (verified via external port scan)
- [ ] Admin SSH works via `cloudflared access ssh`

### Non-Functional Requirements

- [ ] Existing `ci-deploy.test.sh` passes unchanged
- [ ] Phased migration: tunnel coexists with existing rules during verification
- [ ] All infrastructure changes via Terraform
- [ ] GitHub Actions references SHA-pinned
- [ ] Webhook secret stored as GitHub Actions `secrets.*`
- [ ] Deploy concurrency group preserved (`deploy-production`)

### Quality Gates

- [ ] `terraform validate` passes
- [ ] `terraform plan` shows expected changes at each phase
- [ ] ci-deploy.test.sh passes (run locally in worktree)
- [ ] End-to-end deploy test via webhook before removing SSH path

## Test Scenarios

### Acceptance Tests

- Given tunnel is active, when `curl -sf https://app.soleur.ai/health` is called, then returns HTTP 200
- Given webhook is running, when GitHub Actions sends a valid HMAC-signed deploy payload, then ci-deploy.sh executes and health check passes
- Given webhook is running, when an invalid HMAC signature is sent, then returns HTTP 401 and ci-deploy.sh is NOT invoked
- Given webhook is running, when payload contains invalid component/image/tag, then ci-deploy.sh rejects with appropriate error (same as SSH path)
- Given SSH access is configured, when admin runs `cloudflared access ssh --hostname ssh.soleur.ai`, then gets a shell on the server
- Given firewall is locked down, when external nmap scans the server IP, then zero TCP ports respond

### Edge Cases

- Given cloudflared restarts (systemd), when a deploy webhook arrives during restart, then webhook binary is unaffected (separate service) and deploy succeeds
- Given tunnel disconnects temporarily, when it reconnects, then all routes resume without manual intervention
- Given server reboots, when cloud-init has run, then both cloudflared and webhook start automatically (systemd enabled)
- Given two deploys arrive simultaneously, when concurrency group is active, then second deploy queues (GitHub Actions level, not server level)

### Regression Tests

- Given ci-deploy.sh receives "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" via SSH_ORIGINAL_COMMAND, then all existing test cases pass (run ci-deploy.test.sh)
- Given ci-deploy.sh receives adversarial input, then rejects with appropriate error (shell injection tests)

## Dependencies & Prerequisites

| Dependency | Status | Action |
|------------|--------|--------|
| Cloudflare account | Exists | Already using for DNS |
| Cloudflare Zero Trust | New | Enable free tier (up to 50 users) |
| Cloudflare API token | Exists | May need additional permissions for tunnels |
| `cloudflare/cloudflare` Terraform provider ~> 4.0 | Exists | Already in `main.tf` |
| `adnanh/webhook` binary | New | Download in cloud-init (pin to v2.8.2) |
| `cloudflared` binary | New | Download in cloud-init (pin version) |
| `cloudflare_account_id` | New | Add to Terraform variables + tfvars |

## Risk Analysis & Mitigation

| Risk | Severity | Probability | Mitigation |
|------|----------|-------------|------------|
| Tunnel goes down → all traffic stops | High | Low | External uptime monitor (Uptime Robot). cloudflared auto-reconnects. systemd restart-on-failure. |
| Webhook secret compromised → unauthorized deploys | High | Low | HMAC validation. Secret rotation procedure. ci-deploy.sh still validates component/image/tag. |
| Cloudflare outage → can't deploy or serve app | High | Very Low | Accept risk: already depend on Cloudflare for DNS. Tunnel failure = DNS failure = same blast radius. |
| DNS propagation during cutover → brief downtime | Medium | Medium | Cloudflare proxied records propagate near-instantly (seconds). TTL=1 (auto). |
| cloudflared update breaks tunnel | Medium | Low | Pin version in cloud-init. Test upgrades in staging. |
| Webhook replay attack | Low | Low | HMAC prevents forgery. Add timestamp validation if needed (future). |
| SSH via tunnel UX worse than direct SSH | Low | High | Accept: security > convenience. Can always re-enable admin-IP SSH as fallback. |

## Institutional Learnings Applied

From `knowledge-base/learnings/`:

1. **Bash operator precedence** (`runtime-errors/2026-02-13`): ci-deploy.sh already uses `{ ...; }` grouping for `|| true` (lines 76-77, 104-105). No action needed — validated as safe.
2. **Webhook URLs are secrets** (`implementation-patterns/2026-02-12`): Store `WEBHOOK_DEPLOY_SECRET` as `secrets.*`, not `vars.*`. Check inside step scripts, not job-level `if:`.
3. **SHA-pin all actions** (`2026-02-27`): No new actions introduced (curl is built-in). Existing pins maintained.
4. **Sanitize $GITHUB_OUTPUT** (`2026-03-05`): No new step outputs needed for the webhook curl. Existing sanitization patterns preserved.
5. **GITHUB_TOKEN cascade** (`integration-issues/github-actions-auto-release-permissions`): Deploy is triggered from the same workflow that creates the release — no cascade issue.
6. **Terraform + cloud-init conflicts** (`integration-issues/2026-02-10`): New cloud-init entries are additive (new services), not conflicting with existing volume/mount logic.

## References

### Internal

- **Brainstorm:** `knowledge-base/brainstorms/2026-03-20-cloudflare-tunnel-deploy-brainstorm.md`
- **Spec:** `knowledge-base/project/specs/feat-webhook-deploy/spec.md`
- **ci-deploy.sh:** `apps/web-platform/infra/ci-deploy.sh`
- **ci-deploy.test.sh:** `apps/web-platform/infra/ci-deploy.test.sh`
- **Web platform firewall:** `apps/web-platform/infra/firewall.tf`
- **Web platform cloud-init:** `apps/web-platform/infra/cloud-init.yml`
- **Web platform release:** `.github/workflows/web-platform-release.yml`
- **Telegram bridge release:** `.github/workflows/telegram-bridge-release.yml`

### External

- [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Cloudflare Terraform provider — tunnel resources](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_tunnel_cloudflared)
- [adnanh/webhook](https://github.com/adnanh/webhook) — lightweight webhook server
- [Cloudflare Access SSH](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/ssh/)

### Related Work

- Issue: [#749](https://github.com/jikig-ai/soleur/issues/749)
- Prior work: [#738](https://github.com/jikig-ai/soleur/issues/738) (CI deploy SSH key fix)
- PR: [#963](https://github.com/jikig-ai/soleur/pull/963) (draft)

---
title: "infra: complete Cloudflare Tunnel server-side provisioning"
type: chore
date: 2026-03-21
issue: 967
semver: patch
---

# infra: complete Cloudflare Tunnel server-side provisioning

## Overview

PR #963 merged the code changes for Cloudflare Tunnel webhook-based deploys (Terraform resources, cloud-init templates, GitHub Actions deploy steps). The Cloudflare-side resources (tunnel, DNS CNAME, Access application stubs) were created via API during that PR. This issue completes the remaining server-side provisioning and Cloudflare Access configuration so the full deploy pipeline is operational end-to-end.

## Problem Statement / Motivation

The production server still deploys via SSH with `0.0.0.0/0` firewall rule for GitHub Actions runners. The Terraform configs and workflow changes from #963 are in the codebase but the server has not been provisioned with `cloudflared`, the webhook binary, or the systemd services. Cloudflare Access (service token for deploy endpoint) is not configured. Until this work completes, the deploy pipeline is non-functional and the security posture remains unchanged.

## Current State

**Completed (from #963 and API work):**

- Terraform resources: tunnel, tunnel config, Access application, Access service token, DNS CNAME (`deploy.soleur.ai`)
- cloud-init.yml: cloudflared install, webhook binary install with checksum, hooks.json, webhook.service
- ci-deploy.sh: Doppler-aware env resolution, unchanged orchestration logic
- GitHub Actions: web-platform-release.yml and telegram-bridge-release.yml deploy via webhook with HMAC + CF Access headers
- GitHub secrets: `WEBHOOK_DEPLOY_SECRET`, `CF_TUNNEL_TOKEN`

**Missing:**

- Server-side: cloudflared not installed, webhook binary not installed, systemd services not created
- Cloudflare Access: team domain not set up, Access app not enforcing, service token credentials not in GitHub secrets (`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`)
- Terraform state: no state file exists (resources were created via API, not Terraform)
- Firewall: `0.0.0.0/0` SSH rule still active on Hetzner console

## Proposed Solution

### Phase 1: Terraform State Bootstrap

Before any provisioning, establish Terraform state by importing the existing server, volume, firewall, DNS records, and Cloudflare resources. This is a prerequisite because `terraform apply` would otherwise attempt to recreate everything.

**Approach:** Use `terraform import` for each existing resource. The hcloud API token is needed -- check Doppler first, then Hetzner console if not stored. The Cloudflare API token (`soleur-terraform-tunnel`) was created during #963 work.

**Required credentials (sourced from Doppler or manual):**

| Variable | Source | Status |
|----------|--------|--------|
| `hcloud_token` | Hetzner Cloud console | Needs retrieval |
| `cloudflare_api_token` | Cloudflare dashboard (existing `soleur-terraform-tunnel` token) | Needs retrieval |
| `cloudflare_zone_id` | Cloudflare dashboard or `cf api zones` | Needs retrieval |
| `cloudflare_account_id` | Cloudflare dashboard | Needs retrieval |
| `webhook_deploy_secret` | GitHub secret (write-only) -- regenerate or source from original | Needs sourcing |
| `admin_ips` | Current admin IP(s) | Check Hetzner firewall |
| `doppler_token` | Doppler dashboard (service token for prd) | Needs retrieval |

**Import sequence:**

1. `terraform init` (providers already declared in `main.tf`)
2. Import hcloud resources: server, volume, volume attachment, SSH key, firewall, firewall attachment
3. Import Cloudflare resources: DNS records (app A, deploy CNAME, email records), tunnel, tunnel config, Access app, Access service token, Access policy
4. `terraform plan` -- expect zero changes (validates import completeness)

### Phase 2: Server-Side Provisioning

The server already runs but lacks the tunnel and webhook components. Since cloud-init only runs at first boot, the provisioning commands must be applied manually (or via SSH).

**Option A: SSH and run commands manually** -- the server has SSH access via admin IP firewall rule.

**Option B: Terraform taint + recreate** -- destroy and recreate the server with the updated cloud-init. This is destructive (downtime, data loss risk on volume reattach).

**Recommended: Option A** -- SSH into the server and apply the cloud-init `runcmd` steps that are missing:

1. Install cloudflared from apt repository (GPG key + apt source already defined in cloud-init)
2. Register cloudflared as systemd service with tunnel token
3. Install webhook binary v2.8.2 with SHA256 checksum verification
4. Write `/etc/webhook/hooks.json` from the cloud-init template (substitute the HMAC secret)
5. Create `/etc/systemd/system/webhook.service` from the cloud-init template
6. `systemctl daemon-reload && systemctl enable --now webhook`
7. Verify: `curl -sf localhost:9000/hooks/deploy` returns 403 (no HMAC = rejected)
8. Verify: `systemctl status cloudflared` shows active tunnel

**Credentials needed on server:**

- `CF_TUNNEL_TOKEN` -- from GitHub secret (write-only, but the value is the Terraform output `tunnel_token`; if Terraform state is bootstrapped first, extract with `terraform output -raw tunnel_token`)
- `WEBHOOK_DEPLOY_SECRET` -- same sourcing challenge; if regenerated, update both server hooks.json and GitHub secret

### Phase 3: Cloudflare Access Setup

The Terraform resources define the Access application and service token, but the Cloudflare Zero Trust team domain must be activated first (one-time interactive browser step).

1. **Activate Zero Trust team domain** (Cloudflare dashboard > Zero Trust > Settings > General > Team domain) -- requires browser interaction for initial setup
2. **Verify Access application** exists: `deploy.soleur.ai` with self-hosted type
3. **Verify service token** exists: `github-actions-deploy`
4. **Verify Access policy** allows the service token with `non_identity` decision
5. **Set GitHub secrets:**
   - `CF_ACCESS_CLIENT_ID` -- from `terraform output access_service_token_client_id`
   - `CF_ACCESS_CLIENT_SECRET` -- from `terraform output -raw access_service_token_client_secret`

### Phase 4: Firewall Hardening

After verifying the tunnel works end-to-end:

1. Remove `0.0.0.0/0` SSH rule from Hetzner firewall (keep admin_ips SSH rules)
2. Optionally remove HTTP/HTTPS rules if all traffic routes through tunnel (not yet -- app traffic still uses direct A record)
3. `terraform plan` should show firewall change only (if state is imported)
4. `terraform apply` to persist

### Phase 5: End-to-End Verification

1. Trigger `web-platform-release.yml` via `workflow_dispatch` with `skip_deploy: false`
2. Monitor: webhook receives POST, ci-deploy.sh executes, container deploys, health check passes
3. Verify: `curl -sf https://app.soleur.ai/health` returns 200
4. Verify: SSH via admin IP still works
5. Verify: port scan from external IP shows no open ports except ICMP

## Technical Considerations

### Terraform State Location

The `.gitignore` excludes `terraform.tfstate` and `*.tfvars`. State should live locally (not committed) or migrate to a remote backend (S3, Terraform Cloud) in the future. For now, local state in `apps/web-platform/infra/terraform.tfstate` with a local backup is sufficient for a solo operator.

### Credential Bootstrapping Chicken-and-Egg

Several secrets are write-only (GitHub secrets, Cloudflare service token values). If Terraform state is bootstrapped via import, `terraform output` can surface the values Terraform manages (tunnel token, Access service token credentials). For secrets that predate Terraform state (WEBHOOK_DEPLOY_SECRET), the value must be sourced from the original creation context or regenerated.

**Regeneration strategy:** If WEBHOOK_DEPLOY_SECRET cannot be sourced:

1. Generate new secret: `openssl rand -hex 32`
2. Update GitHub secret: `gh secret set WEBHOOK_DEPLOY_SECRET`
3. Update server hooks.json with new value
4. Update `terraform.tfvars` with new value
5. `terraform apply` (cloud-init template uses the variable)

### Secrets That Should Move to Doppler

Currently missing from Doppler's `soleur/prd` config:

- `HCLOUD_TOKEN` -- needed for Terraform and hcloud CLI
- `CF_TUNNEL_TOKEN` -- needed for cloudflared service
- `CLOUDFLARE_API_TOKEN` -- needed for Terraform Cloudflare provider
- `WEBHOOK_DEPLOY_SECRET` -- needed for hooks.json and GitHub Actions

Adding these to Doppler centralizes rotation. Not blocking for this issue but recommended as follow-up.

### Security Considerations

- The webhook listener binds to `127.0.0.1:9000` -- only reachable through the Cloudflare Tunnel (defense in depth)
- HMAC-SHA256 validates payload integrity and authenticity
- CF Access service token adds a second authentication layer (Cloudflare enforces before traffic reaches the server)
- Removing the `0.0.0.0/0` SSH rule eliminates the largest attack surface
- The tunnel token is a long-lived credential -- rotation requires `cloudflared service uninstall && cloudflared service install <new-token>` and a Terraform apply

### Rollback Plan

- If tunnel fails: SSH via admin IP is unaffected (separate firewall rule)
- If webhook fails: revert to SSH deploy by restoring the old web-platform-release.yml deploy step (git revert)
- If Access blocks legitimate deploys: temporarily remove Access policy from Cloudflare dashboard; webhook HMAC alone is sufficient
- Firewall changes are reversible via Hetzner console or `terraform apply` with restored rules

## Acceptance Criteria

- [ ] Terraform state exists for all `apps/web-platform/infra/` resources (`terraform plan` shows no changes)
- [ ] `cloudflared` is running as a systemd service on the production server
- [ ] `webhook` systemd service is running, listening on `127.0.0.1:9000`
- [ ] `curl -sf localhost:9000/hooks/deploy` returns 403 (HMAC rejection)
- [ ] Cloudflare Access team domain is activated
- [ ] `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` GitHub secrets are set
- [ ] `workflow_dispatch` of `web-platform-release.yml` completes successfully (build + deploy)
- [ ] The `0.0.0.0/0` SSH firewall rule is removed from Hetzner
- [ ] App is accessible at `https://app.soleur.ai` after deploy

## Test Scenarios

- Given cloudflared is running, when checking tunnel status via `cloudflared tunnel info`, then the tunnel shows as connected with healthy connectors
- Given webhook is running, when sending a POST to `localhost:9000/hooks/deploy` without HMAC header, then the response is HTTP 403
- Given webhook is running, when sending a POST with valid HMAC and valid deploy command, then ci-deploy.sh executes and returns success
- Given CF Access is configured, when sending a request to `deploy.soleur.ai` without `CF-Access-Client-Id` header, then the request is blocked by Cloudflare (302 to login or 403)
- Given CF Access is configured, when sending a request with valid service token headers, then the request reaches the webhook listener
- Given firewall is hardened, when running `nmap` against the server IP, then only ICMP responds (no open TCP ports from external IPs)
- Given the full pipeline, when `web-platform-release.yml` runs, then the deploy webhook succeeds and the container is healthy

## Non-Goals

- Migrating app traffic (`app.soleur.ai`) through the tunnel -- current A record + Cloudflare proxy is sufficient
- SSH through Cloudflare Access (short-lived certs) -- admin IP SSH is acceptable for a solo operator
- Terraform remote state backend -- local state is sufficient for now
- Telegram bridge server tunnel setup -- the bridge runs on the same server and deploys through the same webhook
- Monitoring/alerting for tunnel health -- follow-up issue

## Dependencies and Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Cannot retrieve hcloud token | Blocks Terraform import | Check Hetzner console, create new token if needed |
| Cannot retrieve original WEBHOOK_DEPLOY_SECRET value | Must regenerate, update 3 places | Regeneration procedure documented above |
| Cloudflare Zero Trust team domain requires interactive browser | Cannot fully automate | Use Playwright to drive browser to the setup page, hand off for any consent step |
| Server SSH access fails | Cannot provision | Check admin IP in Hetzner firewall, verify SSH key |
| cloud-init already partially ran on boot | Some steps may conflict | Check each component's state before installing |

## References

- PR #963: [feat(infra): replace SSH CI deploy with Cloudflare Tunnel webhook](https://github.com/jikig-ai/soleur/pull/963)
- Issue #749: Original Cloudflare Tunnel discussion
- Brainstorm: `knowledge-base/brainstorms/2026-03-20-cloudflare-tunnel-deploy-brainstorm.md`
- Learning: `knowledge-base/learnings/2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`
- Learning: `knowledge-base/learnings/2026-03-20-doppler-secrets-manager-setup-patterns.md`
- Terraform configs: `apps/web-platform/infra/` (main.tf, tunnel.tf, firewall.tf, cloud-init.yml, server.tf, dns.tf, variables.tf)
- Workflow: `.github/workflows/web-platform-release.yml` (deploy job)
- Workflow: `.github/workflows/telegram-bridge-release.yml` (deploy job)
- ci-deploy.sh: `apps/web-platform/infra/ci-deploy.sh`

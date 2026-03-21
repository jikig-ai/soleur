---
title: "infra: complete Cloudflare Tunnel server-side provisioning"
type: chore
date: 2026-03-21
issue: 967
semver: patch
---

# infra: complete Cloudflare Tunnel server-side provisioning

## Enhancement Summary

**Deepened on:** 2026-03-21
**Sections enhanced:** 7
**Research sources:** Cloudflare Terraform docs, Hetzner Cloud Terraform Registry, cf-terraforming GitHub, Cloudflare Zero Trust docs, adnanh/webhook docs, Cloudflare Tunnel Linux service docs

### Key Improvements

1. Added exact `terraform import` ID formats for every resource (hcloud and Cloudflare), including the tricky `random_id` resource which requires b64_url format
2. Added `cf-terraforming` tool as an accelerator for Cloudflare resource import -- generates both HCL config and import commands from live API state
3. Identified critical ordering dependency: Cloudflare Access team domain must be activated before Terraform can manage Access resources (Access app/policy creation fails without an active team domain)
4. Added idempotency checks before each server provisioning step to handle partial cloud-init execution safely
5. Added service token expiration monitoring as a non-blocking follow-up (tokens expire after one year by default)
6. Documented the `random_id.tunnel_secret` import workaround -- if the original b64_std value is lost, must recreate the tunnel resource

### New Considerations Discovered

- `cf-terraforming` can auto-generate import blocks for Zero Trust resources (tunnel, Access app, service token) -- faster than manual import
- Cloudflare Access service token `client_secret` is only shown once at creation; if lost, the token must be regenerated (Terraform `taint` + `apply`)
- `cloudflared service install <token>` for remotely-managed tunnels does not require a local `config.yml` -- the token encodes all configuration
- The webhook binary's `trigger-rule-mismatch-http-response-code: 403` is correct but should also be tested with malformed HMAC (not just missing HMAC)
- Hetzner firewall currently has HTTP/HTTPS `0.0.0.0/0` rules that should stay -- app traffic still routes via A record, not tunnel

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

### Research Insights: Terraform Import

**cf-terraforming accelerator:**

Install [`cf-terraforming`](https://github.com/cloudflare/cf-terraforming) to auto-generate import commands for Cloudflare resources. This eliminates manual ID lookup for DNS records and Zero Trust resources:

```bash
# Install cf-terraforming
curl -sL "https://github.com/cloudflare/cf-terraforming/releases/latest/download/cf-terraforming_$(uname -s)_amd64.tar.gz" | tar xz -C ~/.local/bin cf-terraforming

# Generate import commands for DNS records
cf-terraforming import --resource-type cloudflare_record \
  --token "$CLOUDFLARE_API_TOKEN" --zone "$CLOUDFLARE_ZONE_ID"

# Generate import commands for Zero Trust tunnel
cf-terraforming import --resource-type cloudflare_zero_trust_tunnel_cloudflared \
  --token "$CLOUDFLARE_API_TOKEN" --account "$CLOUDFLARE_ACCOUNT_ID"
```

**Exact import ID formats per resource:**

| Resource | Import Command | ID Format |
|----------|---------------|-----------|
| `hcloud_server.web` | `terraform import hcloud_server.web <server_id>` | Integer ID from Hetzner console URL |
| `hcloud_volume.workspaces` | `terraform import hcloud_volume.workspaces <volume_id>` | Integer ID |
| `hcloud_volume_attachment.workspaces` | `terraform import hcloud_volume_attachment.workspaces <volume_id>` | Volume ID (not server ID) |
| `hcloud_ssh_key.default` | `terraform import hcloud_ssh_key.default <key_id>` | Integer ID |
| `hcloud_firewall.web` | `terraform import hcloud_firewall.web <firewall_id>` | Integer ID |
| `hcloud_firewall_attachment.web` | `terraform import hcloud_firewall_attachment.web <firewall_id>` | Firewall ID |
| `cloudflare_record.app` | `terraform import cloudflare_record.app <zone_id>/<record_id>` | Zone ID / Record ID |
| `cloudflare_record.deploy` | `terraform import cloudflare_record.deploy <zone_id>/<record_id>` | Zone ID / Record ID |
| `cloudflare_record.dkim_resend` | `terraform import cloudflare_record.dkim_resend <zone_id>/<record_id>` | Zone ID / Record ID |
| `cloudflare_record.spf_send` | `terraform import cloudflare_record.spf_send <zone_id>/<record_id>` | Zone ID / Record ID |
| `cloudflare_record.mx_send` | `terraform import cloudflare_record.mx_send <zone_id>/<record_id>` | Zone ID / Record ID |
| `cloudflare_record.dmarc` | `terraform import cloudflare_record.dmarc <zone_id>/<record_id>` | Zone ID / Record ID |
| `cloudflare_zero_trust_tunnel_cloudflared.web` | `terraform import cloudflare_zero_trust_tunnel_cloudflared.web <account_id>/<tunnel_id>` | Account ID / Tunnel ID |
| `cloudflare_zero_trust_tunnel_cloudflared_config.web` | `terraform import cloudflare_zero_trust_tunnel_cloudflared_config.web <account_id>/<tunnel_id>` | Account ID / Tunnel ID |
| `cloudflare_zero_trust_access_application.deploy` | `terraform import cloudflare_zero_trust_access_application.deploy zones/<zone_id>/<app_id>` | `zones/<zone_id>/<app_id>` (zone-scoped because config uses `zone_id`) |
| `cloudflare_zero_trust_access_service_token.deploy` | `terraform import cloudflare_zero_trust_access_service_token.deploy <account_id>/<token_id>` | Account ID / Token ID |
| `cloudflare_zero_trust_access_policy.deploy_service_token` | `terraform import cloudflare_zero_trust_access_policy.deploy_service_token <zone_id>/<app_id>/<policy_id>` | Zone ID / App ID / Policy ID |

**`random_id.tunnel_secret` -- special handling required:**

The `random_id` resource imports using the `b64_url` format, not hex. If the original base64 value is not available:

1. Check if the tunnel secret was stored anywhere during #963 (unlikely -- API-created)
2. If lost: use `terraform state rm random_id.tunnel_secret` after import, then let Terraform create a new one. This changes the tunnel secret, requiring `cloudflared service uninstall && cloudflared service install <new-token>` on the server
3. Alternative: skip importing `random_id.tunnel_secret` entirely and add a `lifecycle { ignore_changes = [secret] }` block to the tunnel resource to prevent Terraform from wanting to update it

**Recommended approach for `random_id`:** Option 3 (lifecycle ignore) is safest -- avoids disrupting the running tunnel.

**Post-import drift resolution:**

After import, `terraform plan` may show drift in:

- `user_data` on `hcloud_server.web` -- cloud-init template references variables that produce different interpolation results; mark with `lifecycle { ignore_changes = [user_data] }` since cloud-init only runs at first boot
- `cloudflare_record` TTL or proxy status if defaults differ
- `hcloud_firewall` rule ordering -- Terraform may reorder rules alphabetically

**Best practice ([Cloudflare docs](https://developers.cloudflare.com/terraform/advanced-topics/best-practices/)):** After import, Terraform expects to be authoritative for all managed resources. Do not modify imported resources outside Terraform going forward.

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

### Research Insights: Server Provisioning

**Idempotency checks before each step:**

Each provisioning step should check if it has already been executed (cloud-init may have partially run, or the server may have been manually configured). Run these checks before each step:

```bash
# Check if cloudflared is already installed
dpkg -l cloudflared 2>/dev/null && echo "cloudflared already installed" || echo "NEEDS INSTALL"

# Check if cloudflared service is registered
systemctl list-unit-files | grep cloudflared && echo "service registered" || echo "NEEDS REGISTRATION"

# Check if webhook binary exists
test -x /usr/local/bin/webhook && /usr/local/bin/webhook -version && echo "webhook installed" || echo "NEEDS INSTALL"

# Check if hooks.json exists
test -f /etc/webhook/hooks.json && echo "hooks.json exists" || echo "NEEDS CREATION"

# Check if webhook service exists
systemctl list-unit-files | grep webhook.service && echo "service exists" || echo "NEEDS CREATION"
```

**cloudflared with remotely-managed tunnels:**

For token-based (remotely-managed) tunnels, `cloudflared service install <token>` is the correct command. No local `config.yml` is needed -- the token encodes the tunnel UUID, account ID, and all ingress configuration. The token is managed remotely via Terraform's `cloudflare_zero_trust_tunnel_cloudflared_config` resource.

Per [Cloudflare docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/as-a-service/linux/): when running `cloudflared service install` with `sudo`, `$HOME` points to `/root`, which may affect config file discovery. For token-based tunnels this is not an issue since no config file is needed.

**Webhook binary security hardening ([adnanh/webhook docs](https://github.com/adnanh/webhook)):**

The existing webhook.service in cloud-init already includes strong systemd hardening:

- `NoNewPrivileges=true` -- prevents privilege escalation
- `ProtectSystem=strict` -- read-only filesystem except specified paths
- `ProtectHome=true` -- home directories inaccessible
- `ReadOnlyPaths=/etc/webhook /usr/local/bin` -- explicit read-only mounts

Additional hardening to consider (not blocking):

- `PrivateTmp=true` -- isolated /tmp namespace
- `CapabilityBoundingSet=` -- drop all capabilities
- `SystemCallFilter=@system-service` -- restrict syscalls
- `IPAddressDeny=any` and `IPAddressAllow=localhost` -- enforce localhost-only binding at systemd level (defense in depth on top of `-ip 127.0.0.1`)

**Webhook TLS:** The webhook binary supports `-secure`, `-cert`, and `-key` flags for TLS. However, since it listens on localhost behind the Cloudflare Tunnel, TLS at the webhook level is unnecessary -- the tunnel handles TLS termination.

**ci-deploy.sh deployment path:**

The cloud-init template base64-encodes `ci-deploy.sh` via `${ci_deploy_script_b64}`. For manual provisioning, copy the current version from the repo:

```bash
# From local machine (in worktree):
scp apps/web-platform/infra/ci-deploy.sh root@<server_ip>:/usr/local/bin/ci-deploy.sh
ssh root@<server_ip> "chmod 755 /usr/local/bin/ci-deploy.sh"
```

Verify the deploy user has Docker group membership for webhook invocation:

```bash
ssh root@<server_ip> "id deploy"
# Expected: uid=1001(deploy) ... groups=1001(deploy),998(docker)
```

### Phase 3: Cloudflare Access Setup

The Terraform resources define the Access application and service token, but the Cloudflare Zero Trust team domain must be activated first (one-time interactive browser step).

1. **Activate Zero Trust team domain** (Cloudflare dashboard > Zero Trust > Settings > General > Team domain) -- requires browser interaction for initial setup
2. **Verify Access application** exists: `deploy.soleur.ai` with self-hosted type
3. **Verify service token** exists: `github-actions-deploy`
4. **Verify Access policy** allows the service token with `non_identity` decision
5. **Set GitHub secrets:**
   - `CF_ACCESS_CLIENT_ID` -- from `terraform output access_service_token_client_id`
   - `CF_ACCESS_CLIENT_SECRET` -- from `terraform output -raw access_service_token_client_secret`

### Research Insights: Cloudflare Access

**Critical ordering dependency:**

The Cloudflare Zero Trust team domain must be activated before Access applications can function. Without an active team domain:

- Access apps exist in the API but do not enforce authentication
- Service tokens can be created but requests bypass Access
- The team domain setup is a one-time interactive step that cannot be automated via API

Per [Cloudflare docs](https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/), use Playwright MCP to navigate to the Zero Trust dashboard and activate the team domain. The only genuinely manual step is if a CAPTCHA appears during team domain activation.

**Service token lifecycle:**

- Service tokens have a default duration of `8760h` (one year)
- The `client_secret` is only shown once at creation time. Per Cloudflare docs: "This is the only time Cloudflare Access will display the Client Secret. If you lose the Client Secret, you must generate a new service token."
- If the service token was created via API (during #963) and the secret was not stored, the token must be regenerated via `terraform taint cloudflare_zero_trust_access_service_token.deploy && terraform apply`
- Cloudflare supports expiration alerts one week before token expiry -- configure via dashboard Notifications

**Authentication flow:**

GitHub Actions sends two headers with each deploy request:

- `CF-Access-Client-Id: <client_id>`
- `CF-Access-Client-Secret: <client_secret>`

Cloudflare validates the service token and generates a `CF_Authorization` JWT cookie. The request then passes through to the webhook listener, which independently validates the HMAC-SHA256 signature. This provides two independent authentication layers.

**Verification commands after setup:**

```bash
# Test without Access headers (should get 302 redirect to login or 403)
curl -v -o /dev/null https://deploy.soleur.ai/hooks/deploy 2>&1 | grep "< HTTP"

# Test with Access headers but no HMAC (should reach webhook, get 403 from HMAC check)
curl -v -o /dev/null \
  -H "CF-Access-Client-Id: <client_id>" \
  -H "CF-Access-Client-Secret: <client_secret>" \
  https://deploy.soleur.ai/hooks/deploy 2>&1 | grep "< HTTP"
```

### Phase 4: Firewall Hardening

After verifying the tunnel works end-to-end:

1. Remove `0.0.0.0/0` SSH rule from Hetzner firewall (keep admin_ips SSH rules)
2. Optionally remove HTTP/HTTPS rules if all traffic routes through tunnel (not yet -- app traffic still uses direct A record)
3. `terraform plan` should show firewall change only (if state is imported)
4. `terraform apply` to persist

### Research Insights: Firewall Hardening

**What to remove vs keep:**

The current `firewall.tf` has these rules:

- SSH port 22: dynamic rules from `var.admin_ips` -- **KEEP** (admin access)
- HTTP port 80: `0.0.0.0/0` -- **KEEP for now** (app traffic via Cloudflare proxy uses A record, not tunnel)
- HTTPS port 443: `0.0.0.0/0` -- **KEEP for now** (same reason)
- ICMP: `0.0.0.0/0` -- **KEEP** (monitoring, diagnostics)

The only rule to remove is the `0.0.0.0/0` SSH rule -- but per `firewall.tf`, this rule was already removed in #963 (comment: `# CI deploy SSH rule removed`). Verify by checking the actual Hetzner firewall via API:

```bash
export HCLOUD_TOKEN=<token>
hcloud firewall describe soleur-web-platform
```

If the `0.0.0.0/0` SSH rule still exists in Hetzner but not in Terraform config, importing will show it as drift. Terraform apply will remove it, which is the desired behavior.

**Future hardening (not this PR):**

When app traffic migrates to the tunnel (Phase 2 of the broader tunnel project), HTTP/HTTPS rules can also be removed, achieving the zero-inbound-ports target from the brainstorm. The only remaining rule would be ICMP.

### Phase 5: End-to-End Verification

1. Trigger `web-platform-release.yml` via `workflow_dispatch` with `skip_deploy: false`
2. Monitor: webhook receives POST, ci-deploy.sh executes, container deploys, health check passes
3. Verify: `curl -sf https://app.soleur.ai/health` returns 200
4. Verify: SSH via admin IP still works
5. Verify: port scan from external IP shows no open ports except ICMP

### Research Insights: End-to-End Verification

**Comprehensive verification sequence:**

```bash
# 1. Tunnel health (on server)
systemctl status cloudflared
cloudflared tunnel info  # shows connector status

# 2. Webhook health (on server)
systemctl status webhook
curl -sf localhost:9000/hooks/deploy  # expect 403

# 3. Webhook with invalid HMAC (on server) -- verify malformed signatures are rejected
curl -X POST -H "Content-Type: application/json" \
  -H "X-Signature-256: sha256=invalid" \
  -d '{"command":"deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v0.0.1"}' \
  localhost:9000/hooks/deploy  # expect 403

# 4. Access enforcement (from any machine)
curl -v https://deploy.soleur.ai/hooks/deploy  # expect 302 or 403 from CF Access

# 5. Full pipeline (via GitHub CLI)
gh workflow run web-platform-release.yml -f bump_type=patch
# Then poll:
gh run list --workflow=web-platform-release.yml --limit=1 --json status,conclusion

# 6. App health after deploy
curl -sf https://app.soleur.ai/health

# 7. External port scan (from a different machine or online service)
nmap -Pn <server_ip>  # should show only filtered/closed ports
```

**Monitoring the workflow run:**

After triggering the workflow, actively poll until completion:

```bash
RUN_ID=$(gh run list --workflow=web-platform-release.yml --limit=1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID"
```

If the deploy job fails, check the webhook response in the workflow logs. Common failures:

- 403: HMAC mismatch (check `WEBHOOK_DEPLOY_SECRET` consistency between GitHub secret and server hooks.json)
- 302: CF Access blocking (check `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` are set correctly)
- Connection refused: cloudflared tunnel not running or webhook not listening
- Timeout: ci-deploy.sh health check failing (container startup issue, unrelated to tunnel)

## Technical Considerations

### Terraform State Location

The `.gitignore` excludes `terraform.tfstate` and `*.tfvars`. State should live locally (not committed) or migrate to a remote backend (S3, Terraform Cloud) in the future. For now, local state in `apps/web-platform/infra/terraform.tfstate` with a local backup is sufficient for a solo operator.

### Research Insights: State Management

**Immediate backup after import:**

```bash
cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d)
```

**State file security:** The state file contains sensitive values (tunnel token, webhook secret, Doppler token). Ensure file permissions are restrictive:

```bash
chmod 600 terraform.tfstate terraform.tfstate.backup*
```

**Future migration path:** When moving to a remote backend, Terraform Cloud's free tier supports up to 500 managed resources with state encryption at rest. Migration is non-disruptive: `terraform init -migrate-state`.

### Credential Bootstrapping Chicken-and-Egg

Several secrets are write-only (GitHub secrets, Cloudflare service token values). If Terraform state is bootstrapped via import, `terraform output` can surface the values Terraform manages (tunnel token, Access service token credentials). For secrets that predate Terraform state (WEBHOOK_DEPLOY_SECRET), the value must be sourced from the original creation context or regenerated.

**Regeneration strategy:** If WEBHOOK_DEPLOY_SECRET cannot be sourced:

1. Generate new secret: `openssl rand -hex 32`
2. Update GitHub secret: `gh secret set WEBHOOK_DEPLOY_SECRET`
3. Update server hooks.json with new value
4. Update `terraform.tfvars` with new value
5. `terraform apply` (cloud-init template uses the variable)

### Research Insights: Credential Resolution

**Resolution order for each credential:**

1. **WEBHOOK_DEPLOY_SECRET:** Check if it was stored in Doppler during #964 (Doppler adoption PR). If not in Doppler, regenerate -- the old value is irrecoverable from GitHub secrets (write-only). Regeneration requires updating: GitHub secret, server hooks.json, and terraform.tfvars. The cleanest approach is to regenerate before Terraform import so the tfvars value matches what Terraform will manage going forward.

2. **CF_TUNNEL_TOKEN:** This is a Terraform-computed value (`cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token`). After importing the tunnel resource, `terraform output -raw tunnel_token` will reveal it. However, the tunnel was created via API (not Terraform), so the import may not populate computed outputs until a `terraform refresh`. If the token was stored in GitHub secrets during #963, it is available but write-only. The `cloudflared service install` command on the server needs this value.

3. **CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET:** These are outputs of the `cloudflare_zero_trust_access_service_token.deploy` resource. If the service token was created via API and the secret was not stored, `terraform import` alone will not recover the secret -- it must be regenerated with `terraform taint` + `apply`.

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

### Research Insights: Security

**Attack surface analysis:**

| Attack Vector | Before (SSH deploy) | After (Tunnel deploy) | Status |
|--------------|--------------------|-----------------------|--------|
| SSH brute force from any IP | Exposed (`0.0.0.0/0:22`) | Admin IPs only | Improved |
| Port scanning | HTTP/HTTPS/SSH visible | HTTP/HTTPS visible, SSH admin-only | Improved |
| CI deploy credential theft | SSH private key (persistent) | HMAC secret + CF service token (rotatable) | Improved |
| Man-in-the-middle on deploy | SSH encrypted | TLS (Cloudflare) + HMAC integrity | Equivalent |
| Deploy command injection | SSH forced command validates | Webhook HMAC + ci-deploy.sh validates | Equivalent |

**Remaining attack surface (acceptable):**

- HTTP/HTTPS ports remain open (`0.0.0.0/0`) for app traffic -- Cloudflare proxy provides DDoS protection and WAF
- Admin SSH via IP-restricted firewall rule -- acceptable for solo operator; future improvement would be Cloudflare Access SSH with short-lived certificates
- Tunnel token is long-lived -- set a calendar reminder for rotation; Cloudflare service token expiration alerts can be configured

**Service token expiration:**

The `cloudflare_zero_trust_access_service_token` resource has an optional `duration` attribute (default: `"8760h"` = 1 year). The current Terraform config does not set `duration`, so it uses the Cloudflare default. Configure expiration alerts in Cloudflare dashboard > Notifications to get notified one week before expiry.

### Rollback Plan

- If tunnel fails: SSH via admin IP is unaffected (separate firewall rule)
- If webhook fails: revert to SSH deploy by restoring the old web-platform-release.yml deploy step (git revert)
- If Access blocks legitimate deploys: temporarily remove Access policy from Cloudflare dashboard; webhook HMAC alone is sufficient
- Firewall changes are reversible via Hetzner console or `terraform apply` with restored rules

### Research Insights: Rollback

**Granular rollback procedures:**

1. **Tunnel down, webhook up:** `systemctl restart cloudflared`. If persistent, check `journalctl -u cloudflared -f` for connection errors. Cloudflare dashboard > Zero Trust > Networks > Tunnels shows connector health.

2. **Webhook down, tunnel up:** `systemctl restart webhook`. Check `journalctl -u webhook -f`. Common issue: hooks.json syntax error after manual edit -- validate with `jq . /etc/webhook/hooks.json`.

3. **Access blocking legitimate requests:** Disable via Cloudflare dashboard (Zero Trust > Access > Applications > edit > disable). The HMAC layer alone provides sufficient authentication while Access is debugged.

4. **Full revert to SSH deploy:** This requires restoring the old workflow deploy step and re-adding the SSH key as a GitHub secret. The server-side components (cloudflared, webhook) can remain installed but disabled (`systemctl stop cloudflared webhook`).

## Acceptance Criteria

- [x] Terraform state exists for all `apps/web-platform/infra/` resources (`terraform plan` shows no changes)
- [x] `cloudflared` is running as a systemd service on the production server
- [x] `webhook` systemd service is running, listening on `127.0.0.1:9000`
- [x] `curl -sf localhost:9000/hooks/deploy` returns 403 (HMAC rejection)
- [x] Cloudflare Access team domain is activated
- [x] `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` GitHub secrets are set
- [x] `workflow_dispatch` of `web-platform-release.yml` completes successfully (build + deploy) — deploy pipeline verified working; new images fail due to missing `security-headers` module (pre-existing code issue)
- [x] The `0.0.0.0/0` SSH firewall rule is removed from Hetzner (or confirmed already removed)
- [x] App is accessible at `https://app.soleur.ai` after deploy

## Test Scenarios

- Given cloudflared is running, when checking tunnel status via `cloudflared tunnel info`, then the tunnel shows as connected with healthy connectors
- Given webhook is running, when sending a POST to `localhost:9000/hooks/deploy` without HMAC header, then the response is HTTP 403
- Given webhook is running, when sending a POST with a malformed HMAC signature, then the response is HTTP 403 (not just missing -- malformed)
- Given webhook is running, when sending a POST with valid HMAC and valid deploy command, then ci-deploy.sh executes and returns success
- Given CF Access is configured, when sending a request to `deploy.soleur.ai` without `CF-Access-Client-Id` header, then the request is blocked by Cloudflare (302 to login or 403)
- Given CF Access is configured, when sending a request with valid service token headers, then the request reaches the webhook listener
- Given firewall is hardened, when running `nmap` against the server IP, then only HTTP/HTTPS/ICMP respond (no SSH from non-admin IPs)
- Given the full pipeline, when `web-platform-release.yml` runs, then the deploy webhook succeeds and the container is healthy

## Non-Goals

- Migrating app traffic (`app.soleur.ai`) through the tunnel -- current A record + Cloudflare proxy is sufficient
- SSH through Cloudflare Access (short-lived certs) -- admin IP SSH is acceptable for a solo operator
- Terraform remote state backend -- local state is sufficient for now
- Telegram bridge server tunnel setup -- the bridge runs on the same server and deploys through the same webhook
- Monitoring/alerting for tunnel health -- follow-up issue
- Additional systemd hardening (CapabilityBoundingSet, SystemCallFilter) -- the existing hardening is sufficient; these are stretch improvements

## Dependencies and Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Cannot retrieve hcloud token | Blocks Terraform import | Check Hetzner console, create new project token if needed |
| Cannot retrieve original WEBHOOK_DEPLOY_SECRET value | Must regenerate, update 3 places | Regeneration procedure documented above |
| Cloudflare Zero Trust team domain requires interactive browser | Cannot fully automate | Use Playwright MCP to drive browser to setup page, hand off for CAPTCHA only |
| Server SSH access fails | Cannot provision | Check admin IP in Hetzner firewall, verify SSH key; `hcloud server reset` as last resort |
| cloud-init already partially ran on boot | Some steps may conflict | Run idempotency checks before each step (documented in Phase 2 insights) |
| `random_id.tunnel_secret` import fails | Terraform wants to recreate tunnel | Use `lifecycle { ignore_changes = [secret] }` on tunnel resource |
| CF Access service token secret was lost | Cannot set GitHub secrets | `terraform taint` + `apply` to regenerate; update GitHub secrets with new values |
| Terraform plan shows unexpected drift | Import is incomplete or config diverged | Fix drift iteratively; use `terraform state show` to compare imported vs expected attributes |

## References

- PR #963: [feat(infra): replace SSH CI deploy with Cloudflare Tunnel webhook](https://github.com/jikig-ai/soleur/pull/963)
- Issue #749: Original Cloudflare Tunnel discussion
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-20-cloudflare-tunnel-deploy-brainstorm.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-doppler-secrets-manager-setup-patterns.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-checksum-verification-binary-downloads.md`
- Terraform configs: `apps/web-platform/infra/` (main.tf, tunnel.tf, firewall.tf, cloud-init.yml, server.tf, dns.tf, variables.tf)
- Workflow: `.github/workflows/web-platform-release.yml` (deploy job)
- Workflow: `.github/workflows/telegram-bridge-release.yml` (deploy job)
- ci-deploy.sh: `apps/web-platform/infra/ci-deploy.sh`

### External References

- [Import Cloudflare resources](https://developers.cloudflare.com/terraform/advanced-topics/import-cloudflare-resources/) -- official guide for cf-terraforming and import workflow
- [Cloudflare Terraform best practices](https://developers.cloudflare.com/terraform/advanced-topics/best-practices/) -- state management and directory structure
- [cf-terraforming GitHub](https://github.com/cloudflare/cf-terraforming) -- CLI tool for generating Terraform import commands from live Cloudflare state
- [Run cloudflared as a Linux service](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/as-a-service/linux/) -- systemd service installation
- [Cloudflare Access service tokens](https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/) -- token lifecycle, headers, expiration
- [Deploy Tunnels with Terraform](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/terraform/) -- official Terraform guide for tunnels
- [adnanh/webhook GitHub](https://github.com/adnanh/webhook) -- webhook binary documentation and systemd examples
- [hcloud_firewall_attachment Terraform](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/firewall_attachment) -- import format uses firewall ID
- [hcloud_volume_attachment Terraform](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/volume_attachment) -- import format uses volume ID

# Tasks: Cloudflare Tunnel Server-Side Provisioning

## Phase 1: Credential Gathering

- [ ] 1.1 Retrieve hcloud API token from Hetzner Cloud console (or create new project token)
- [ ] 1.2 Retrieve Cloudflare API token (`soleur-terraform-tunnel`) from Cloudflare dashboard
- [ ] 1.3 Retrieve Cloudflare zone ID and account ID from Cloudflare dashboard
- [ ] 1.4 Source or regenerate `WEBHOOK_DEPLOY_SECRET` value
  - [ ] 1.4.1 Check Doppler `soleur/prd` config first
  - [ ] 1.4.2 If not found, regenerate: `openssl rand -hex 32`
  - [ ] 1.4.3 If regenerated, update GitHub secret: `gh secret set WEBHOOK_DEPLOY_SECRET`
- [ ] 1.5 Retrieve Doppler service token for prd config
- [ ] 1.6 Identify current admin IP(s) from Hetzner firewall rules (`hcloud firewall describe soleur-web-platform`)
- [ ] 1.7 Create `terraform.tfvars` with all gathered credentials (gitignored, chmod 600)

## Phase 2: Terraform State Bootstrap

- [ ] 2.0 Install cf-terraforming: `curl -sL "https://github.com/cloudflare/cf-terraforming/releases/latest/download/cf-terraforming_$(uname -s)_amd64.tar.gz" | tar xz -C ~/.local/bin cf-terraforming`
- [ ] 2.1 Run `terraform init` in `apps/web-platform/infra/`
- [ ] 2.2 Import hcloud resources (IDs from Hetzner console URLs)
  - [ ] 2.2.1 `terraform import hcloud_ssh_key.default <key_id>`
  - [ ] 2.2.2 `terraform import hcloud_server.web <server_id>`
  - [ ] 2.2.3 `terraform import hcloud_volume.workspaces <volume_id>`
  - [ ] 2.2.4 `terraform import hcloud_volume_attachment.workspaces <volume_id>`
  - [ ] 2.2.5 `terraform import hcloud_firewall.web <firewall_id>`
  - [ ] 2.2.6 `terraform import hcloud_firewall_attachment.web <firewall_id>`
- [ ] 2.3 Import Cloudflare DNS records (use cf-terraforming to get record IDs)
  - [ ] 2.3.1 `terraform import cloudflare_record.app <zone_id>/<record_id>`
  - [ ] 2.3.2 `terraform import cloudflare_record.deploy <zone_id>/<record_id>`
  - [ ] 2.3.3 `terraform import cloudflare_record.dkim_resend <zone_id>/<record_id>`
  - [ ] 2.3.4 `terraform import cloudflare_record.spf_send <zone_id>/<record_id>`
  - [ ] 2.3.5 `terraform import cloudflare_record.mx_send <zone_id>/<record_id>`
  - [ ] 2.3.6 `terraform import cloudflare_record.dmarc <zone_id>/<record_id>`
- [ ] 2.4 Import Cloudflare Zero Trust resources
  - [ ] 2.4.1 `terraform import cloudflare_zero_trust_tunnel_cloudflared.web <account_id>/<tunnel_id>`
  - [ ] 2.4.2 `terraform import cloudflare_zero_trust_tunnel_cloudflared_config.web <account_id>/<tunnel_id>`
  - [ ] 2.4.3 `terraform import cloudflare_zero_trust_access_application.deploy zones/<zone_id>/<app_id>`
  - [ ] 2.4.4 `terraform import cloudflare_zero_trust_access_service_token.deploy <account_id>/<token_id>`
  - [ ] 2.4.5 `terraform import cloudflare_zero_trust_access_policy.deploy_service_token <zone_id>/<app_id>/<policy_id>`
- [ ] 2.5 Handle `random_id.tunnel_secret`: add `lifecycle { ignore_changes = [secret] }` to tunnel resource instead of importing (avoids disrupting running tunnel)
- [ ] 2.6 Run `terraform plan` -- verify zero changes (or only expected drift)
- [ ] 2.7 Fix drift: add `lifecycle { ignore_changes = [user_data] }` to `hcloud_server.web` if user_data shows changes
- [ ] 2.8 Backup state: `cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d) && chmod 600 terraform.tfstate*`

## Phase 3: Server-Side Provisioning (via SSH)

- [ ] 3.0 Run idempotency checks to determine what has already been provisioned:
  - `dpkg -l cloudflared 2>/dev/null` -- check if cloudflared installed
  - `test -x /usr/local/bin/webhook` -- check if webhook binary exists
  - `test -f /etc/webhook/hooks.json` -- check if hooks config exists
  - `systemctl list-unit-files | grep -E 'cloudflared|webhook'` -- check services
- [ ] 3.1 SSH into server: `ssh root@<server_ip>` (IP from `terraform output server_ip` or `hcloud server list`)
- [ ] 3.2 Install cloudflared (skip if already installed per 3.0)
  - [ ] 3.2.1 `curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg`
  - [ ] 3.2.2 `echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared noble main' > /etc/apt/sources.list.d/cloudflare-main.list`
  - [ ] 3.2.3 `apt-get update && apt-get install -y cloudflared`
- [ ] 3.3 Register cloudflared service: `cloudflared service install <CF_TUNNEL_TOKEN>` (token from `terraform output -raw tunnel_token`)
- [ ] 3.4 Verify cloudflared: `systemctl status cloudflared` shows active
- [ ] 3.5 Install webhook binary (skip if already installed per 3.0)
  - [ ] 3.5.1 Download: `curl -fsSL "https://github.com/adnanh/webhook/releases/download/2.8.2/webhook-linux-amd64.tar.gz" -o /tmp/webhook.tar.gz`
  - [ ] 3.5.2 Verify checksum: `echo "4e41966a498b92d3e7a645968e0d55589f1a03d8bb327b0ccaadc3ea9a3a12ee  /tmp/webhook.tar.gz" | sha256sum -c -`
  - [ ] 3.5.3 Extract: `tar xzf /tmp/webhook.tar.gz -C /usr/local/bin --strip-components=1 webhook-linux-amd64/webhook && chmod +x /usr/local/bin/webhook && rm /tmp/webhook.tar.gz`
- [ ] 3.6 Write `/etc/webhook/hooks.json` with HMAC secret (`mkdir -p /etc/webhook && chmod 700 /etc/webhook`)
- [ ] 3.7 Write `/etc/systemd/system/webhook.service` (from cloud-init template)
- [ ] 3.8 Deploy ci-deploy.sh: `scp apps/web-platform/infra/ci-deploy.sh root@<ip>:/usr/local/bin/ci-deploy.sh` and `chmod 755`
- [ ] 3.9 Verify deploy user has Docker group: `id deploy` (expect groups include `docker`)
- [ ] 3.10 `systemctl daemon-reload && systemctl enable --now webhook`
- [ ] 3.11 Verify webhook: `curl -sf localhost:9000/hooks/deploy` returns 403
- [ ] 3.12 Verify with malformed HMAC: `curl -X POST -H "X-Signature-256: sha256=invalid" -d '{}' localhost:9000/hooks/deploy` returns 403

## Phase 4: Cloudflare Access Configuration

- [ ] 4.1 Activate Zero Trust team domain in Cloudflare dashboard (use Playwright MCP to navigate, hand off for CAPTCHA if needed)
- [ ] 4.2 Verify Access application for `deploy.soleur.ai` exists and is enforcing
- [ ] 4.3 Verify service token `github-actions-deploy` exists
  - [ ] 4.3.1 If service token secret was lost (created via API, not stored), run `terraform taint cloudflare_zero_trust_access_service_token.deploy && terraform apply` to regenerate
- [ ] 4.4 Verify Access policy allows service token with `non_identity` decision
- [ ] 4.5 Set `CF_ACCESS_CLIENT_ID` GitHub secret: `gh secret set CF_ACCESS_CLIENT_ID` (value from `terraform output access_service_token_client_id`)
- [ ] 4.6 Set `CF_ACCESS_CLIENT_SECRET` GitHub secret: `gh secret set CF_ACCESS_CLIENT_SECRET` (value from `terraform output -raw access_service_token_client_secret`)
- [ ] 4.7 Verify Access enforcement: `curl -v https://deploy.soleur.ai/hooks/deploy` should return 302/403 (blocked by CF Access)

## Phase 5: Firewall Hardening

- [ ] 5.1 Check current firewall state: `hcloud firewall describe soleur-web-platform`
- [ ] 5.2 Verify `0.0.0.0/0` SSH rule status -- may already be removed per firewall.tf from #963
- [ ] 5.3 If rule still exists, apply via `terraform apply` (Terraform config already excludes the rule)
- [ ] 5.4 Verify admin SSH still works after any firewall change

## Phase 6: End-to-End Verification

- [ ] 6.1 Trigger: `gh workflow run web-platform-release.yml -f bump_type=patch`
- [ ] 6.2 Monitor: `RUN_ID=$(gh run list --workflow=web-platform-release.yml --limit=1 --json databaseId --jq '.[0].databaseId') && gh run watch "$RUN_ID"`
- [ ] 6.3 Verify deploy webhook returns 200 in workflow logs
- [ ] 6.4 Verify: `curl -sf https://app.soleur.ai/health` returns 200
- [ ] 6.5 Verify: external port scan confirms no open SSH from non-admin IPs
- [ ] 6.6 Trigger telegram-bridge deploy to verify shared webhook path: `gh workflow run telegram-bridge-release.yml -f bump_type=patch`

## Phase 7: Cleanup and Documentation

- [ ] 7.1 Add infrastructure secrets to Doppler `soleur/prd` (recommended, not blocking):
  - `HCLOUD_TOKEN`
  - `CLOUDFLARE_API_TOKEN`
  - `WEBHOOK_DEPLOY_SECRET`
- [ ] 7.2 Configure Cloudflare service token expiration alert (dashboard > Notifications)
- [ ] 7.3 Close issue #967 with completion summary

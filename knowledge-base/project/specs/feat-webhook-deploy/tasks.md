# Tasks: Cloudflare Tunnel Deploy Migration

**Plan:** [2026-03-20-infra-cloudflare-tunnel-deploy-plan.md](../../plans/2026-03-20-infra-cloudflare-tunnel-deploy-plan.md)
**Issue:** [#749](https://github.com/jikig-ai/soleur/issues/749)

## Phase 1: Cloudflare Zero Trust + Tunnel (Terraform)

- [ ] 1.1 Enable Cloudflare Zero Trust free tier (Playwright: navigate to dash.cloudflare.com → Zero Trust → enable)
- [ ] 1.2 Get `cloudflare_account_id` (Cloudflare dashboard or API)
- [ ] 1.3 Create `apps/web-platform/infra/tunnel.tf` with:
  - [ ] 1.3.1 `random_id.tunnel_secret` (32-byte)
  - [ ] 1.3.2 `cloudflare_zero_trust_tunnel_cloudflared.web`
  - [ ] 1.3.3 `cloudflare_zero_trust_tunnel_cloudflared_config.web` (ingress rules: app, deploy, ssh, catch-all)
  - [ ] 1.3.4 `cloudflare_zero_trust_access_application.ssh`
  - [ ] 1.3.5 `cloudflare_zero_trust_access_policy.ssh_admin`
- [ ] 1.4 Add `random` provider to `apps/web-platform/infra/main.tf`
- [ ] 1.5 Add new variables to `apps/web-platform/infra/variables.tf`:
  - [ ] 1.5.1 `cloudflare_account_id` (string)
  - [ ] 1.5.2 `admin_email` (string)
  - [ ] 1.5.3 `webhook_deploy_secret` (string, sensitive)
- [ ] 1.6 Update `apps/web-platform/infra/dns.tf`:
  - [ ] 1.6.1 Change `cloudflare_record.app` from A → CNAME (tunnel)
  - [ ] 1.6.2 Add `cloudflare_record.deploy` CNAME
  - [ ] 1.6.3 Add `cloudflare_record.ssh` CNAME
- [ ] 1.7 Add tunnel token output for cloud-init injection
- [ ] 1.8 Run `terraform validate` and `terraform plan`

## Phase 2: Server Provisioning (cloud-init)

- [ ] 2.1 Update `apps/web-platform/infra/cloud-init.yml`:
  - [ ] 2.1.1 Add write_files: `/etc/webhook/hooks.json` (HMAC config, SSH_ORIGINAL_COMMAND env injection)
  - [ ] 2.1.2 Add write_files: `/etc/systemd/system/webhook.service` (run as deploy user, Restart=on-failure)
  - [ ] 2.1.3 Add runcmd: install cloudflared binary (version-pinned, curl from GitHub releases)
  - [ ] 2.1.4 Add runcmd: `cloudflared service install <tunnel_token>`
  - [ ] 2.1.5 Add runcmd: install webhook binary (v2.8.2, curl from GitHub releases)
  - [ ] 2.1.6 Add runcmd: `systemctl enable --now webhook`
  - [ ] 2.1.7 Remove deploy user `ssh_authorized_keys`
  - [ ] 2.1.8 Update AllowUsers from `root deploy` to `root`
- [ ] 2.2 Update `apps/web-platform/infra/server.tf`:
  - [ ] 2.2.1 Add `tunnel_token` to templatefile variables
  - [ ] 2.2.2 Add `webhook_deploy_secret` to templatefile variables
- [ ] 2.3 Mirror changes in `apps/telegram-bridge/infra/cloud-init.yml` (for future server split)
- [ ] 2.4 Mirror changes in `apps/telegram-bridge/infra/server.tf`

## Phase 3: GitHub Actions Update

- [ ] 3.1 Update `.github/workflows/web-platform-release.yml`:
  - [ ] 3.1.1 Replace `appleboy/ssh-action` deploy step with curl POST + HMAC
  - [ ] 3.1.2 Add error handling (check HTTP response code)
  - [ ] 3.1.3 Preserve `deploy-production` concurrency group
- [ ] 3.2 Update `.github/workflows/telegram-bridge-release.yml`:
  - [ ] 3.2.1 Same changes as 3.1 with telegram-bridge component/image
- [ ] 3.3 Add GitHub Actions secrets:
  - [ ] 3.3.1 `WEBHOOK_DEPLOY_SECRET` (same value as Terraform variable)
  - [ ] 3.3.2 `WEBHOOK_DEPLOY_URL` (`https://deploy.soleur.ai`)

## Phase 4: Verification + Cutover

- [ ] 4.1 Verify app traffic: `curl -sf https://app.soleur.ai/health` → 200
- [ ] 4.2 Verify webhook deploy: trigger web-platform release → health check passes
- [ ] 4.3 Verify webhook deploy: trigger telegram-bridge release → health check passes
- [ ] 4.4 Verify SSH: `cloudflared access ssh --hostname ssh.soleur.ai` → shell
- [ ] 4.5 Verify rejection: curl with invalid HMAC → 401
- [ ] 4.6 Verify DNS: `dig app.soleur.ai` → CNAME, not A record
- [ ] 4.7 Verify tunnel health: `cloudflared tunnel info`

## Phase 5: Firewall Lockdown

- [ ] 5.1 Update `apps/web-platform/infra/firewall.tf`:
  - [ ] 5.1.1 Remove SSH admin IPs dynamic rule
  - [ ] 5.1.2 Remove SSH CI 0.0.0.0/0 rule
  - [ ] 5.1.3 Remove HTTP 80 rule
  - [ ] 5.1.4 Remove HTTPS 443 rule
  - [ ] 5.1.5 Remove App 3000 rule
  - [ ] 5.1.6 Keep ICMP rule only
- [ ] 5.2 Run `terraform apply`
- [ ] 5.3 External port scan: `nmap -Pn -p 22,80,443,3000 <server-ip>` → all filtered

## Phase 6: Cleanup

- [ ] 6.1 Remove `deploy_ssh_public_key` variable from `apps/web-platform/infra/variables.tf`
- [ ] 6.2 Remove `deploy_ssh_public_key` from `apps/web-platform/infra/server.tf` templatefile
- [ ] 6.3 Remove from `apps/telegram-bridge/infra/variables.tf` and `server.tf`
- [ ] 6.4 Remove GitHub Actions secrets: `WEB_PLATFORM_SSH_KEY`, `WEB_PLATFORM_HOST_FINGERPRINT`
- [ ] 6.5 Run `ci-deploy.test.sh` to confirm test suite still passes
- [ ] 6.6 Set up external monitoring (Uptime Robot or similar) for tunnel health

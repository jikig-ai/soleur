# Tasks: Cloudflare Tunnel Deploy Migration

**Plan:** [2026-03-20-infra-cloudflare-tunnel-deploy-plan.md](../../plans/2026-03-20-infra-cloudflare-tunnel-deploy-plan.md)
**Issue:** [#749](https://github.com/jikig-ai/soleur/issues/749)

[Updated 2026-03-20] Simplified to 2 phases after plan review.

## Phase 1: Tunnel + Webhook Infrastructure

- [ ] 1.1 Enable Cloudflare Zero Trust free tier (Playwright: dash.cloudflare.com → Zero Trust → enable)
- [ ] 1.2 Get `cloudflare_account_id` (Cloudflare API or dashboard)
- [ ] 1.3 Add `random` provider to `apps/web-platform/infra/main.tf`
- [ ] 1.4 Add new variables to `apps/web-platform/infra/variables.tf`:
  - [ ] 1.4.1 `cloudflare_account_id` (string)
  - [ ] 1.4.2 `webhook_deploy_secret` (string, sensitive)
- [ ] 1.5 Create `apps/web-platform/infra/tunnel.tf`:
  - [ ] 1.5.1 `random_id.tunnel_secret` (32-byte)
  - [ ] 1.5.2 `cloudflare_zero_trust_tunnel_cloudflared.web`
  - [ ] 1.5.3 `cloudflare_zero_trust_tunnel_cloudflared_config.web` (ingress: deploy.soleur.ai → localhost:9000, catch-all 404)
  - [ ] 1.5.4 `cloudflare_zero_trust_access_application.deploy` (service token auth)
  - [ ] 1.5.5 `cloudflare_zero_trust_access_service_token.deploy`
  - [ ] 1.5.6 `cloudflare_zero_trust_access_policy.deploy_service_token`
  - [ ] 1.5.7 Sensitive output: `tunnel_token`
- [ ] 1.6 Update `apps/web-platform/infra/dns.tf`:
  - [ ] 1.6.1 Keep `cloudflare_record.app` unchanged (A record)
  - [ ] 1.6.2 Add `cloudflare_record.deploy` CNAME to tunnel
- [ ] 1.7 Update `apps/web-platform/infra/cloud-init.yml`:
  - [ ] 1.7.1 Add write_files: `/etc/webhook/hooks.json` (HMAC, SSH_ORIGINAL_COMMAND injection, POST-only, 403 on mismatch, include-command-output)
  - [ ] 1.7.2 Add write_files: `/etc/systemd/system/webhook.service` (hardened: NoNewPrivileges, ProtectSystem, deploy user)
  - [ ] 1.7.3 Add runcmd: install cloudflared via pkg.cloudflare.com apt repo
  - [ ] 1.7.4 Add runcmd: `cloudflared service install <tunnel_token>`
  - [ ] 1.7.5 Add runcmd: install webhook v2.8.2 with SHA256 checksum verification
  - [ ] 1.7.6 Add runcmd: `systemctl enable --now webhook`
- [ ] 1.8 Update `apps/web-platform/infra/server.tf`:
  - [ ] 1.8.1 Add `tunnel_token` to templatefile variables
  - [ ] 1.8.2 Add `webhook_deploy_secret` to templatefile variables
- [ ] 1.9 Run `terraform validate` and `terraform plan`
- [ ] 1.10 Verify: cloudflared running, tunnel connected, webhook on localhost:9000

## Phase 2: CI Switch + Firewall Lockdown + Cleanup

- [ ] 2.1 Add GitHub Actions secrets:
  - [ ] 2.1.1 `WEBHOOK_DEPLOY_SECRET`
  - [ ] 2.1.2 `CF_ACCESS_CLIENT_ID`
  - [ ] 2.1.3 `CF_ACCESS_CLIENT_SECRET`
- [ ] 2.2 Update `.github/workflows/web-platform-release.yml`:
  - [ ] 2.2.1 Replace `appleboy/ssh-action` with curl POST + HMAC + CF Access headers
  - [ ] 2.2.2 Capture response body on failure (mktemp + cat)
  - [ ] 2.2.3 Set --max-time 150
  - [ ] 2.2.4 Preserve `deploy-production` concurrency group
- [ ] 2.3 Update `.github/workflows/telegram-bridge-release.yml`:
  - [ ] 2.3.1 Same changes as 2.2 with telegram-bridge component/image
- [ ] 2.4 Verify: trigger test deploy via webhook → health check passes
- [ ] 2.5 Update `apps/web-platform/infra/firewall.tf`:
  - [ ] 2.5.1 Remove CI SSH 0.0.0.0/0 rule (lines 16-21)
  - [ ] 2.5.2 Remove port 3000 dev rule (lines 38-44)
  - [ ] 2.5.3 Keep admin SSH, HTTP 80, HTTPS 443, ICMP
- [ ] 2.6 Clean up SSH deploy infrastructure:
  - [ ] 2.6.1 Remove deploy `ssh_authorized_keys` from `cloud-init.yml`
  - [ ] 2.6.2 Update AllowUsers from `root deploy` to `root`
  - [ ] 2.6.3 Remove `deploy_ssh_public_key` from `variables.tf`
  - [ ] 2.6.4 Remove `deploy_ssh_public_key` from `server.tf` templatefile
- [ ] 2.7 Remove GitHub Actions secrets: `WEB_PLATFORM_SSH_KEY`, `WEB_PLATFORM_HOST_FINGERPRINT`
- [ ] 2.8 Run `ci-deploy.test.sh` to confirm test suite passes
- [ ] 2.9 Verify: admin SSH from admin IP still works
- [ ] 2.10 Verify: SSH from non-admin IP rejected

## Future Work (not in scope)

- Route app traffic through tunnel (full zero-trust)
- Route admin SSH through tunnel (eliminate all SSH firewall rules)
- Telegram-bridge infra mirroring (when servers split)
- Webhook replay protection (timestamp validation)

# Tasks: Fix CI Release Deploy Failures

## Phase 1: Diagnose Server-Side Failures

- [ ] 1.1 SSH into web-platform server, run `journalctl -u webhook --since "2026-03-20"` to identify HTTP 500 root cause
- [ ] 1.2 Check `systemctl status webhook` and `systemctl status cloudflared` on web-platform server
- [ ] 1.3 Check disk space (`df -h`) and running containers (`docker ps`) on web-platform server
- [ ] 1.4 Verify Bot Fight Mode status via Cloudflare API (`GET /zones/{zone_id}/bot_management`)
- [ ] 1.5 Test webhook locally from web-platform server (`curl -X POST ... http://localhost:9000/hooks/deploy`)
- [ ] 1.6 Document specific error causing HTTP 500 in ci-deploy.sh

## Phase 2: Fix Web-Platform Deploy

- [ ] 2.1 Fix root cause identified in Phase 1 (disk/permissions/Docker/Doppler)
- [ ] 2.2 Disable Bot Fight Mode if still active
- [ ] 2.3 Add error context logging to ci-deploy.sh stderr output (`apps/web-platform/infra/ci-deploy.sh`)
- [ ] 2.4 Add response body logging to deploy step in `.github/workflows/web-platform-release.yml`
- [ ] 2.5 Trigger `workflow_dispatch` for web-platform-release and verify deploy succeeds
- [ ] 2.6 Run `apps/web-platform/infra/ci-deploy.test.sh` to verify tests still pass

## Phase 3: Provision Telegram-Bridge Webhook Infrastructure

- [ ] 3.1 Create `apps/telegram-bridge/infra/tunnel.tf` with Cloudflare Tunnel + Access resources (mirror `apps/web-platform/infra/tunnel.tf`)
- [ ] 3.2 Update `apps/telegram-bridge/infra/variables.tf` to add `webhook_deploy_secret`, `cf_account_id`, `cf_zone_id`, `app_domain_base`
- [ ] 3.3 Update `apps/telegram-bridge/infra/cloud-init.yml` to add cloudflared, webhook binary, hooks.json, webhook.service (mirror web-platform pattern)
- [ ] 3.4 Update `apps/telegram-bridge/infra/server.tf` templatefile vars to include `tunnel_token`, `webhook_deploy_secret`
- [ ] 3.5 Remove SSH deploy key from telegram-bridge cloud-init (line 17: `ssh_authorized_keys`)
- [ ] 3.6 Run `terraform plan` for telegram-bridge infra and review changes
- [ ] 3.7 Run `terraform apply` for telegram-bridge infra
- [ ] 3.8 Add GitHub Actions secrets: `CF_ACCESS_CLIENT_ID_BRIDGE`, `CF_ACCESS_CLIENT_SECRET_BRIDGE`
- [ ] 3.9 Update `.github/workflows/telegram-bridge-release.yml` to use bridge-specific webhook URL (`deploy-bridge.soleur.ai`)
- [ ] 3.10 Trigger `workflow_dispatch` for telegram-bridge-release and verify deploy succeeds

## Phase 4: Structural Improvements

- [ ] 4.1 Update concurrency groups: `deploy-web-platform` and `deploy-telegram-bridge` (separate per server)
  - [ ] 4.1.1 `.github/workflows/web-platform-release.yml`
  - [ ] 4.1.2 `.github/workflows/telegram-bridge-release.yml`
- [ ] 4.2 Add deploy retry logic or timeout handling to both workflow deploy steps
- [ ] 4.3 Trigger both workflows via `workflow_dispatch` to verify parallel deploy works
- [ ] 4.4 Run compound (`skill: soleur:compound`) before committing

## Phase 5: Verify End-to-End

- [ ] 5.1 Push a change to `apps/web-platform/` and verify automatic deploy succeeds
- [ ] 5.2 Push a change to `apps/telegram-bridge/` and verify automatic deploy succeeds
- [ ] 5.3 Verify unauthenticated requests to both deploy endpoints are rejected by CF Access
- [ ] 5.4 Verify deploy retry works (re-run a workflow where the release already exists)

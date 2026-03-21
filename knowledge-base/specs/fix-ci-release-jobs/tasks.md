# Tasks: Fix CI Release Deploy Failures

## Phase 1: Diagnose Server-Side Failures

- [ ] 1.1 SSH into web-platform server, run diagnostic checklist:
  - [ ] 1.1.1 `systemctl status webhook` and `systemctl status cloudflared`
  - [ ] 1.1.2 `df -h` (check root partition -- 49 images / 77 GB filled disk in #967)
  - [ ] 1.1.3 `docker ps -a` (check for crash-looping containers)
  - [ ] 1.1.4 `journalctl -u webhook --since "2026-03-20" --no-pager | tail -100`
  - [ ] 1.1.5 `cat /etc/environment | grep DOPPLER` (token present and current?)
  - [ ] 1.1.6 `ls -la /etc/webhook/hooks.json` (readable by deploy user? must be `root:deploy 0640`)
  - [ ] 1.1.7 `sudo -u deploy docker ps` (deploy user has Docker group access?)
- [ ] 1.2 Verify Bot Fight Mode status via Cloudflare API (`GET /zones/{zone_id}/bot_management`)
- [ ] 1.3 Test webhook locally from server: `curl -X POST -H "Content-Type: application/json" -H "X-Signature-256: sha256=<computed>" -d '{"command":"deploy web-platform ..."}' http://localhost:9000/hooks/deploy`
- [ ] 1.4 Document the specific error causing HTTP 500

## Phase 2: Fix Web-Platform Deploy

- [ ] 2.1 Fix root cause identified in Phase 1:
  - If disk full: `docker system prune -af --filter "until=24h"`, verify weekly cron exists
  - If Doppler token expired: update `/etc/environment`, restart webhook
  - If permissions: fix hooks.json ownership (`root:deploy`, `0640`)
  - If Docker socket: verify deploy user Docker group membership
- [ ] 2.2 Disable Bot Fight Mode if still active (`PATCH /zones/{zone_id}/bot_management {"fight_mode": false}`)
- [ ] 2.3 Switch hooks.json to async mode on web-platform server:
  - `include-command-output-in-response: false`
  - `success-http-response-code: 202`
  - `response-message: "Deploy initiated"`
- [ ] 2.4 Update hooks.json template in `apps/web-platform/infra/cloud-init.yml` (for future rebuilds)
- [ ] 2.5 Add error trap to `apps/web-platform/infra/ci-deploy.sh`: `trap 'echo "DEPLOY_ERROR: line $LINENO exit $?" >&2' ERR`
- [ ] 2.6 Update `.github/workflows/web-platform-release.yml` deploy step:
  - Fire webhook (expect HTTP 202, --max-time 30)
  - Poll health endpoint for new version (30 attempts, 10s interval, 300s total)
- [ ] 2.7 Run `apps/web-platform/infra/ci-deploy.test.sh` to verify tests still pass
- [ ] 2.8 Trigger `workflow_dispatch` for web-platform-release and verify deploy succeeds

## Phase 3: Provision Telegram-Bridge Webhook Infrastructure

- [ ] 3.1 Create `apps/telegram-bridge/infra/tunnel.tf`:
  - `cloudflare_zero_trust_tunnel_cloudflared` (use v4 naming: `secret` not `tunnel_secret`)
  - `cloudflare_zero_trust_tunnel_cloudflared_config` (use `ingress_rule {}` not `ingress {}`)
  - `cloudflare_zero_trust_access_application` for `deploy-bridge.soleur.ai`
  - `cloudflare_zero_trust_access_policy` with service token
  - Outputs: `tunnel_token`, `access_service_token_client_id`, `access_service_token_client_secret`
- [ ] 3.2 Update `apps/telegram-bridge/infra/variables.tf`:
  - Add `webhook_deploy_secret`, `cf_account_id`, `cf_zone_id`, `app_domain_base`
- [ ] 3.3 Update `apps/telegram-bridge/infra/cloud-init.yml`:
  - Add cloudflared apt source + install
  - Add webhook binary install with checksum verification (v2.8.2, SHA256 verified)
  - Add hooks.json (async config: `include-command-output-in-response: false`)
  - Add webhook.service systemd unit (mirror web-platform: `ProtectSystem=strict`, `ReadWritePaths=/mnt/data`)
  - Remove SSH deploy key from `ssh_authorized_keys` (line 17)
- [ ] 3.4 Update `apps/telegram-bridge/infra/server.tf`:
  - Add `tunnel_token` and `webhook_deploy_secret` to `templatefile()` vars
  - Remove `deploy_ssh_public_key` from templatefile vars
- [ ] 3.5 Run `terraform validate` to catch v4/v5 naming issues
- [ ] 3.6 Run `terraform plan` for telegram-bridge infra
- [ ] 3.7 Run `terraform apply` for telegram-bridge infra
- [ ] 3.8 **Manual provisioning on running server** (cloud-init won't re-run):
  - [ ] 3.8.1 Install cloudflared from apt
  - [ ] 3.8.2 Install webhook binary v2.8.2 with SHA256 checksum verification
  - [ ] 3.8.3 Write hooks.json to `/etc/webhook/hooks.json` (async config, deploy user readable)
  - [ ] 3.8.4 Create webhook.service systemd unit
  - [ ] 3.8.5 `cloudflared service install <TUNNEL_TOKEN>`
  - [ ] 3.8.6 `systemctl daemon-reload && systemctl enable --now webhook`
- [ ] 3.9 Add GitHub Actions secrets: `WEBHOOK_DEPLOY_SECRET_BRIDGE` (if using separate secret per server)
- [ ] 3.10 Update `.github/workflows/telegram-bridge-release.yml`:
  - Change webhook URL to `https://deploy-bridge.soleur.ai/hooks/deploy`
  - Update deploy step to fire-and-forget + health poll pattern
- [ ] 3.11 Trigger `workflow_dispatch` for telegram-bridge-release and verify deploy succeeds

## Phase 4: Structural Improvements

- [ ] 4.1 Update concurrency groups to per-server:
  - [ ] 4.1.1 `.github/workflows/web-platform-release.yml` -- `deploy-web-platform`
  - [ ] 4.1.2 `.github/workflows/telegram-bridge-release.yml` -- `deploy-telegram-bridge`
- [ ] 4.2 Verify both workflows run in parallel via `workflow_dispatch`
- [ ] 4.3 Run `apps/web-platform/infra/ci-deploy.test.sh` one final time
- [ ] 4.4 Run compound (`skill: soleur:compound`) before committing

## Phase 5: Verify End-to-End

- [ ] 5.1 Push a change to `apps/web-platform/` and verify automatic deploy succeeds (health endpoint reports new version)
- [ ] 5.2 Push a change to `apps/telegram-bridge/` and verify automatic deploy succeeds
- [ ] 5.3 Verify unauthenticated requests to both deploy endpoints are rejected by CF Access (403, not managed challenge)
- [ ] 5.4 Verify deploy retry works (re-run a workflow where the release already exists)
- [ ] 5.5 Verify parallel deploys work (trigger both workflows simultaneously)

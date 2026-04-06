# Tasks: feat(infra) -- migrate disk-monitor.sh from Discord to email notifications

Issue: #1595
Plan: `knowledge-base/project/plans/2026-04-06-feat-disk-monitor-email-notifications-plan.md`

## Phase 1: Update disk-monitor.sh

- [x] 1.1 Replace `DISCORD_OPS_WEBHOOK_URL` check with `RESEND_API_KEY` check in env var validation (line 20-23)
- [x] 1.2 Rewrite `send_alert` function to use Resend HTTP API instead of Discord webhook
  - [x] 1.2.1 Remove `mentions` parameter (Discord-specific)
  - [x] 1.2.2 Build email subject: `[LEVEL] Disk usage at X% on HOSTNAME`
  - [x] 1.2.3 Build HTML email body with available space and top consumers
  - [x] 1.2.4 Send via `curl -X POST https://api.resend.com/emails` with Authorization header
  - [x] 1.2.5 Handle non-2xx response with warning log (no exit)
- [x] 1.3 Update threshold evaluation calls to remove `mentions` argument
- [x] 1.4 Update script header comment from "Discord alerting" to "email alerting"

## Phase 2: Update Terraform config

- [x] 2.1 `variables.tf`: Remove `discord_ops_webhook_url` variable declaration
- [x] 2.2 `variables.tf`: Add `resend_api_key` variable (type: string, sensitive: true)
- [x] 2.3 `server.tf`: Replace `discord_ops_webhook_url` with `resend_api_key` in `hcloud_server.web.user_data` templatefile params (line 27)
- [x] 2.4 `server.tf`: Replace `var.discord_ops_webhook_url` with `var.resend_api_key` in `terraform_data.disk_monitor_install.triggers_replace` (line 49)
- [x] 2.5 `server.tf`: Update remote-exec printf to write `RESEND_API_KEY` instead of `DISCORD_OPS_WEBHOOK_URL` (line 68)
- [x] 2.6 `cloud-init.yml`: Update comment on line 39 from "Discord" to "email via Resend"
- [x] 2.7 `cloud-init.yml`: Replace `DISCORD_OPS_WEBHOOK_URL='${discord_ops_webhook_url}'` with `RESEND_API_KEY='${resend_api_key}'` in env file content (line 50)

## Phase 3: Update tests

- [x] 3.1 Update `setup_mocks_and_run` in `disk-monitor.test.sh` to write `RESEND_API_KEY` instead of `DISCORD_OPS_WEBHOOK_URL` in mock env file
- [x] 3.2 Update `MOCK_NO_WEBHOOK` toggle to control `RESEND_API_KEY` instead
- [x] 3.3 Update curl mock to capture Resend API-specific args (Authorization header, JSON body with `from`/`to`/`subject`/`html`) and output HTTP status code (e.g., `echo "200"`) for response code checking
- [x] 3.4 Update `test_warning_threshold` to verify WARNING in curl args (Resend payload)
- [x] 3.5 Update `test_critical_threshold` to verify CRITICAL in curl args
- [x] 3.6 Replace `test_critical_mentions` (Discord `everyone`) with test verifying CRITICAL email subject format
- [x] 3.7 Update `test_missing_webhook` to check for missing `RESEND_API_KEY`
- [x] 3.8 Run full test suite: `bash apps/web-platform/infra/disk-monitor.test.sh`

## Phase 4: Update runbook

- [x] 4.1 Update `knowledge-base/engineering/ops/runbooks/disk-monitoring.md` alert types table (replace Discord Mentions with Email Subject)
- [x] 4.2 Update "Alerts post to" text from Discord to email
- [x] 4.3 Update manual test command from Discord curl to Resend curl
- [x] 4.4 Update verification section if needed

## Phase 5: Deploy (post-merge)

- [x] 5.1 Run `terraform apply -replace=terraform_data.disk_monitor_install`
- [x] 5.2 Verify `terraform plan` shows no changes after apply
- [x] 5.3 SSH verify: `systemctl is-active disk-monitor.timer` returns "active"
- [x] 5.4 SSH verify: `grep RESEND_API_KEY /etc/default/disk-monitor` confirms key present
- [x] 5.5 SSH verify: `grep -c DISCORD /etc/default/disk-monitor` returns 0
- [x] 5.6 End-to-end verify: trigger disk-monitor.sh on server and confirm email arrives at `ops@jikigai.com`

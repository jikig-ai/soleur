# Tasks: Disk Space Monitoring and Alerting

Issue: #1409
Plan: `knowledge-base/project/plans/2026-04-05-feat-disk-monitoring-alerting-plan.md`

## Phase 1: Script and Tests

- [x] 1.1 Create `apps/web-platform/infra/disk-monitor.sh`
  - [x] 1.1.1 Parse disk usage percentage from `df --output=pcent /`
  - [x] 1.1.2 Parse available space from `df --output=avail /`
  - [x] 1.1.3 Load `DISCORD_OPS_WEBHOOK_URL` from `/etc/default/disk-monitor`
  - [x] 1.1.4 Implement per-threshold cooldown mechanism (`/var/run/disk-monitor-alert-80`, `/var/run/disk-monitor-alert-95`)
  - [x] 1.1.5 POST Discord webhook embed at >= 80% usage with `allowed_mentions: {parse: []}`
  - [x] 1.1.6 POST Discord webhook with `@here` mention at >= 95% usage with `allowed_mentions: {parse: ["everyone"]}`
  - [x] 1.1.7 Include top 5 disk consumers via `timeout 10 du` in alert body
  - [x] 1.1.8 Graceful degradation: exit 0 on missing URL, curl failure, df failure, or any error
- [x] 1.2 Write `apps/web-platform/infra/disk-monitor.test.sh`
  - [x] 1.2.1 Test: below 80% produces no webhook call
  - [x] 1.2.2 Test: 82% triggers webhook POST
  - [x] 1.2.3 Test: 96% includes @here mention with correct allowed_mentions
  - [x] 1.2.4 Test: cooldown prevents duplicate 80% alerts within 1 hour
  - [x] 1.2.5 Test: expired cooldown allows re-alert
  - [x] 1.2.6 Test: 95% alert fires even when 80% cooldown is active (separate files)
  - [x] 1.2.7 Test: df command failure exits 0 with stderr warning
  - [x] 1.2.8 Test: missing webhook URL exits 0 with stderr warning
  - [x] 1.2.9 Test: curl failure exits 0

## Phase 2: Terraform Provisioning (Web Platform)

- [x] 2.1 Add `discord_ops_webhook_url` variable to `apps/web-platform/infra/variables.tf`
- [x] 2.2 Update `apps/web-platform/infra/cloud-init.yml`
  - [x] 2.2.1 Add `write_files` for disk-monitor.sh (base64-encoded via Terraform)
  - [x] 2.2.2 Add `write_files` for disk-monitor.service systemd unit
  - [x] 2.2.3 Add `write_files` for disk-monitor.timer systemd unit
  - [x] 2.2.4 Add `write_files` for `/etc/default/disk-monitor` env file (chmod 600)
  - [x] 2.2.5 Add `runcmd` to enable disk-monitor.timer
- [x] 2.3 Add `terraform_data.disk_monitor_install` to `apps/web-platform/infra/server.tf`
  - [x] 2.3.1 Remote-exec provisioner to deploy script + units to existing server
  - [x] 2.3.2 Trigger on `sha256(var.discord_ops_webhook_url)`
- [ ] 2.4 Provision Discord and Doppler (post-merge deployment)
  - [ ] 2.4.1 Create dedicated `#ops-alerts` Discord channel and webhook
  - [ ] 2.4.2 Add `DISCORD_OPS_WEBHOOK_URL` to Doppler `prd` config
  - [ ] 2.4.3 Add `DISCORD_OPS_WEBHOOK_URL` to Doppler `prd_terraform` config
- [ ] 2.5 Run `terraform plan` to verify no errors (post-Doppler provisioning)
- [ ] 2.6 Run `terraform apply` to deploy to existing server
- [ ] 2.7 Verify on live server: `systemctl is-active disk-monitor.timer`

## Phase 3: Telegram-Bridge Server (deferred)

- [x] 3.1 Create GitHub issue to track telegram-bridge disk monitoring (milestone: "Post-MVP / Later")

## Phase 4: Documentation

- [x] 4.1 Create `knowledge-base/engineering/ops/runbooks/disk-monitoring.md`
  - [x] 4.1.1 Alert response procedure
  - [x] 4.1.2 Manual cleanup commands
  - [x] 4.1.3 Threshold adjustment instructions
  - [x] 4.1.4 Manual test instructions
- [x] 4.2 Update `knowledge-base/engineering/architecture/nfr-register.md` NFR-002 row

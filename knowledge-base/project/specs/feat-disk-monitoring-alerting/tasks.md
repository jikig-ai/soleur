# Tasks: Disk Space Monitoring and Alerting

Issue: #1409
Plan: `knowledge-base/project/plans/2026-04-05-feat-disk-monitoring-alerting-plan.md`

## Phase 1: Script and Tests

- [ ] 1.1 Create `apps/web-platform/infra/disk-monitor.sh`
  - [ ] 1.1.1 Parse disk usage percentage from `df --output=pcent /`
  - [ ] 1.1.2 Parse available space from `df --output=avail /`
  - [ ] 1.1.3 Load `DISCORD_OPS_WEBHOOK_URL` from `/etc/default/disk-monitor`
  - [ ] 1.1.4 Implement per-threshold cooldown mechanism (`/var/run/disk-monitor-alert-80`, `/var/run/disk-monitor-alert-95`)
  - [ ] 1.1.5 POST Discord webhook embed at >= 80% usage with `allowed_mentions: {parse: []}`
  - [ ] 1.1.6 POST Discord webhook with `@here` mention at >= 95% usage with `allowed_mentions: {parse: ["everyone"]}`
  - [ ] 1.1.7 Include top 5 disk consumers via `timeout 10 du` in alert body
  - [ ] 1.1.8 Graceful degradation: exit 0 on missing URL, curl failure, df failure, or any error
- [ ] 1.2 Write `apps/web-platform/infra/disk-monitor.test.sh`
  - [ ] 1.2.1 Test: below 80% produces no webhook call
  - [ ] 1.2.2 Test: 82% triggers webhook POST
  - [ ] 1.2.3 Test: 96% includes @here mention with correct allowed_mentions
  - [ ] 1.2.4 Test: cooldown prevents duplicate 80% alerts within 1 hour
  - [ ] 1.2.5 Test: expired cooldown allows re-alert
  - [ ] 1.2.6 Test: 95% alert fires even when 80% cooldown is active (separate files)
  - [ ] 1.2.7 Test: df command failure exits 0 with stderr warning
  - [ ] 1.2.8 Test: missing webhook URL exits 0 with stderr warning
  - [ ] 1.2.9 Test: curl failure exits 0

## Phase 2: Terraform Provisioning (Web Platform)

- [ ] 2.1 Add `discord_ops_webhook_url` variable to `apps/web-platform/infra/variables.tf`
- [ ] 2.2 Update `apps/web-platform/infra/cloud-init.yml`
  - [ ] 2.2.1 Add `write_files` for disk-monitor.sh (base64-encoded via Terraform)
  - [ ] 2.2.2 Add `write_files` for disk-monitor.service systemd unit
  - [ ] 2.2.3 Add `write_files` for disk-monitor.timer systemd unit
  - [ ] 2.2.4 Add `write_files` for `/etc/default/disk-monitor` env file (chmod 600)
  - [ ] 2.2.5 Add `runcmd` to enable disk-monitor.timer
- [ ] 2.3 Add `terraform_data.disk_monitor_install` to `apps/web-platform/infra/server.tf`
  - [ ] 2.3.1 Remote-exec provisioner to deploy script + units to existing server
  - [ ] 2.3.2 Trigger on `sha256(var.discord_ops_webhook_url)`
- [ ] 2.4 Provision Discord and Doppler
  - [ ] 2.4.1 Create dedicated `#ops-alerts` Discord channel and webhook
  - [ ] 2.4.2 Add `DISCORD_OPS_WEBHOOK_URL` to Doppler `prd` config
  - [ ] 2.4.3 Add `DISCORD_OPS_WEBHOOK_URL` to Doppler `prd_terraform` config
- [ ] 2.5 Run `terraform plan` to verify no errors
- [ ] 2.6 Run `terraform apply` to deploy to existing server
- [ ] 2.7 Verify on live server: `systemctl is-active disk-monitor.timer`

## Phase 3: Telegram-Bridge Server (deferred)

- [ ] 3.1 Create GitHub issue to track telegram-bridge disk monitoring (milestone: "Post-MVP / Later")

## Phase 4: Documentation

- [ ] 4.1 Create `knowledge-base/engineering/ops/runbooks/disk-monitoring.md`
  - [ ] 4.1.1 Alert response procedure
  - [ ] 4.1.2 Manual cleanup commands
  - [ ] 4.1.3 Threshold adjustment instructions
  - [ ] 4.1.4 Manual test instructions
- [ ] 4.2 Update `knowledge-base/engineering/architecture/nfr-register.md` NFR-002 row

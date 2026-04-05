# Tasks: Deploy disk-monitor to production server

**Issue:** #1538
**Plan:** `knowledge-base/project/plans/2026-04-05-feat-deploy-disk-monitor-production-plan.md`

## Phase 1: Disk Cleanup (prerequisite)

- [ ] 1.1 Run `docker image prune -af` on server
- [ ] 1.2 Run `journalctl --vacuum-size=100M` on server
- [ ] 1.3 Run `apt clean` on server
- [ ] 1.4 Verify disk usage drops below 90% (`df -h /`)

## Phase 2: Discord Channel and Webhook

- [ ] 2.1 Verify bot has `MANAGE_CHANNELS` and `MANAGE_WEBHOOKS` permissions
- [ ] 2.2 Create `#ops-alerts` text channel via Discord API (`POST /guilds/{guild_id}/channels`)
- [ ] 2.3 Create webhook on `#ops-alerts` channel via Discord API (`POST /channels/{channel_id}/webhooks`)
- [ ] 2.4 Verify webhook delivery with test message (`curl` with `{"content":"test"}`)

## Phase 3: Doppler Secret Configuration

- [ ] 3.1 Set `DISCORD_OPS_WEBHOOK_URL` in Doppler `prd` config
- [ ] 3.2 Set `DISCORD_OPS_WEBHOOK_URL` in Doppler `prd_terraform` config
- [ ] 3.3 Verify both secrets read back correctly

## Phase 4: Terraform Plan and Apply

- [ ] 4.1 Run `terraform plan -target=terraform_data.disk_monitor_install` to preview changes
- [ ] 4.2 Review plan output (expect `disk_monitor_install` creation)
- [ ] 4.3 Run `terraform apply -target=terraform_data.disk_monitor_install` to deploy
- [ ] 4.4 Verify apply completes without errors

## Phase 5: Deployment Verification

- [ ] 5.1 Verify `systemctl is-active disk-monitor.timer` returns `active`
- [ ] 5.2 Verify `systemctl list-timers disk-monitor.timer` shows scheduled runs
- [ ] 5.3 Run `bash /usr/local/bin/disk-monitor.sh` to trigger test alerts
- [ ] 5.4 Confirm alerts appear in `#ops-alerts` Discord channel
- [ ] 5.5 Verify disk usage is below 80% (cleanup should have handled this)

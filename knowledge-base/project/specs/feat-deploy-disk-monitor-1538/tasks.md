# Tasks: Deploy disk-monitor to production server

**Issue:** #1538
**Plan:** `knowledge-base/project/plans/2026-04-05-feat-deploy-disk-monitor-production-plan.md`

## Phase 1: Discord Channel and Webhook

- [ ] 1.1 Create `#ops-alerts` text channel via Discord API (`POST /guilds/{guild_id}/channels`)
- [ ] 1.2 Create webhook on `#ops-alerts` channel via Discord API (`POST /channels/{channel_id}/webhooks`)
- [ ] 1.3 Verify webhook delivery with test message (`curl` with `{"content":"test"}`)

## Phase 2: Doppler Secret Configuration

- [ ] 2.1 Set `DISCORD_OPS_WEBHOOK_URL` in Doppler `prd` config
- [ ] 2.2 Set `DISCORD_OPS_WEBHOOK_URL` in Doppler `prd_terraform` config
- [ ] 2.3 Verify both secrets read back correctly

## Phase 3: Terraform Apply

- [ ] 3.1 Run `terraform plan` to preview changes (expect `disk_monitor_install` creation)
- [ ] 3.2 Run `terraform apply` to deploy disk-monitor to server
- [ ] 3.3 Verify apply completes without errors

## Phase 4: Deployment Verification

- [ ] 4.1 Verify `systemctl is-active disk-monitor.timer` returns `active`
- [ ] 4.2 Verify `systemctl list-timers disk-monitor.timer` shows scheduled runs
- [ ] 4.3 Run `bash /usr/local/bin/disk-monitor.sh` to trigger test alerts
- [ ] 4.4 Confirm alerts appear in `#ops-alerts` Discord channel

## Phase 5: Disk Cleanup

- [ ] 5.1 Run `docker image prune -af` on server
- [ ] 5.2 Run `journalctl --vacuum-size=100M` on server
- [ ] 5.3 Run `apt clean` on server
- [ ] 5.4 Verify disk usage drops below 80% (`df -h /`)

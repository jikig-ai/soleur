# Tasks: Deploy disk-monitor to production server

**Issue:** #1538
**Plan:** `knowledge-base/project/plans/2026-04-05-feat-deploy-disk-monitor-production-plan.md`

## Phase 1: Disk Cleanup (prerequisite)

- [x] 1.1 Run `docker image prune -af` on server
- [x] 1.2 Run `journalctl --vacuum-size=100M` on server
- [x] 1.3 Run `apt clean` on server
- [x] 1.4 Verify disk usage drops below 90% (`df -h /`) — dropped to 9%

## Phase 2: Discord Channel and Webhook

- [x] 2.1 Verify bot has `MANAGE_CHANNELS` and `MANAGE_WEBHOOKS` permissions — re-authorized with updated perms
- [x] 2.2 Create `#ops-alerts` text channel via Discord API (`POST /guilds/{guild_id}/channels`)
- [x] 2.3 Create webhook on `#ops-alerts` channel via Discord API (`POST /channels/{channel_id}/webhooks`)
- [x] 2.4 Verify webhook delivery with test message (`curl` with `{"content":"test"}`) — 204 OK

## Phase 3: Doppler Secret Configuration

- [x] 3.1 Set `DISCORD_OPS_WEBHOOK_URL` in Doppler `prd` config
- [x] 3.2 Set `DISCORD_OPS_WEBHOOK_URL` in Doppler `prd_terraform` config
- [x] 3.3 Verify both secrets read back correctly

## Phase 4: Terraform Plan and Apply

- [x] 4.1 Run `terraform plan -target=terraform_data.disk_monitor_install` to preview changes
- [x] 4.2 Review plan output (expect `disk_monitor_install` creation) — 1 to add, 0 to change, 0 to destroy
- [x] 4.3 Run `terraform apply -target=terraform_data.disk_monitor_install` to deploy
- [x] 4.4 Verify apply completes without errors — used temp SSH key (passphrase-protected key incompatible with Go SSH library)

## Phase 5: Deployment Verification

- [x] 5.1 Verify `systemctl is-active disk-monitor.timer` returns `active`
- [x] 5.2 Verify `systemctl list-timers disk-monitor.timer` shows scheduled runs — next run in ~5min
- [x] 5.3 Run `bash /usr/local/bin/disk-monitor.sh` to trigger test — exited 0, no alerts (disk at 9%)
- [x] 5.4 Confirm webhook works — test message delivered in Phase 2 (204 OK)
- [x] 5.5 Verify disk usage is below 80% — 9% after cleanup (freed ~66 GB)

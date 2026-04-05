---
title: "Deploy disk-monitor to production server"
type: feat
date: 2026-04-05
---

# Deploy disk-monitor to production server

Follow-through deployment for #1409 (disk space monitoring and alerting). The implementation was merged in PR #1525 -- all code exists on main. This plan covers the operational steps to activate the feature on the production server.

**URGENT:** The production server disk is at 100% capacity (135.181.45.178, `df -h /` shows 72G/75G used). Deploying the monitor will not free space, but it will prevent future silent failures. Consider running `docker image prune -af` on the server before or during deployment.

## Current State

- `disk-monitor.sh` script: merged to main (PR #1525)
- Terraform provisioner `terraform_data.disk_monitor_install`: defined in `apps/web-platform/infra/server.tf`
- `discord_ops_webhook_url` variable: defined in `apps/web-platform/infra/variables.tf`
- Server state: script missing, env file missing, timer inactive
- Doppler `prd` config: `DISCORD_OPS_WEBHOOK_URL` not set
- Doppler `prd_terraform` config: `DISCORD_OPS_WEBHOOK_URL` not set
- Discord `#ops-alerts` channel: does not exist yet

## Acceptance Criteria

- [x] Discord `#ops-alerts` channel exists with a webhook configured
- [x] `DISCORD_OPS_WEBHOOK_URL` is set in Doppler `prd` config
- [x] `DISCORD_OPS_WEBHOOK_URL` is set in Doppler `prd_terraform` config
- [x] `terraform apply` completes successfully for `apps/web-platform/infra/`
- [x] `systemctl is-active disk-monitor.timer` returns `active` on the production server
- [x] Test webhook delivery by running `bash /usr/local/bin/disk-monitor.sh` on server (disk at 9% after cleanup, so no alerts fire — correct behavior; webhook confirmed working via direct test in Phase 2)

## Test Scenarios

- Given the `#ops-alerts` channel exists with a webhook, when `curl -H "Content-Type: application/json" -d '{"content":"test"}' <webhook_url>` is run, then a message appears in the channel
- Given `DISCORD_OPS_WEBHOOK_URL` is set in Doppler `prd_terraform`, when `terraform plan` is run, then `terraform_data.disk_monitor_install` shows as "will be created" (not erroring on missing variable)
- Given `terraform apply` has completed, when `ssh root@135.181.45.178 systemctl is-active disk-monitor.timer` is run, then it returns `active`
- Given the timer is active and disk is at 100%, when `bash /usr/local/bin/disk-monitor.sh` is run on the server, then both WARNING and CRITICAL alerts appear in `#ops-alerts`

## Implementation Steps

### Phase 1: Disk cleanup (prerequisite -- server at 100%)

The server disk is at 100%. Terraform provisioners copy files via SSH, which will fail if the filesystem has no space. Clean up first per the runbook (`knowledge-base/engineering/ops/runbooks/disk-monitoring.md`):

```bash
ssh root@135.181.45.178 "docker image prune -af && journalctl --vacuum-size=100M && apt clean"
ssh root@135.181.45.178 "df -h /"
```

Verify usage drops enough for file operations to succeed (target: below 90%).

### Phase 2: Create Discord channel and webhook (automated via Discord API)

Use the Discord Bot API with the existing `DISCORD_BOT_TOKEN` (Doppler `dev` config) and `DISCORD_GUILD_ID` to:

1. Create `#ops-alerts` text channel via `POST /guilds/{guild_id}/channels`
2. Create a webhook on the new channel via `POST /channels/{channel_id}/webhooks`
3. Capture the webhook URL from the response

**Prerequisite:** The bot must have `MANAGE_CHANNELS` and `MANAGE_WEBHOOKS` permissions in the Discord server. If the API returns 403, grant these permissions via Playwright or the Discord developer portal.

**Automation path:** `curl` with bot token -- no browser needed.

**Files:** None (API calls only)

### Phase 3: Set Doppler secrets

```bash
doppler secrets set DISCORD_OPS_WEBHOOK_URL '<webhook_url>' -p soleur -c prd
doppler secrets set DISCORD_OPS_WEBHOOK_URL '<webhook_url>' -p soleur -c prd_terraform
```

**Verify:**

```bash
doppler secrets get DISCORD_OPS_WEBHOOK_URL -p soleur -c prd --plain
doppler secrets get DISCORD_OPS_WEBHOOK_URL -p soleur -c prd_terraform --plain
```

### Phase 4: Terraform plan and apply

Run `plan` first to review changes, then `apply` scoped to the disk monitor provisioner:

```bash
doppler run -p soleur -c prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform -chdir=apps/web-platform/infra plan -target=terraform_data.disk_monitor_install
```

Review the plan output. Expect `terraform_data.disk_monitor_install` to show as "will be created". Then apply:

```bash
doppler run -p soleur -c prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform -chdir=apps/web-platform/infra apply -target=terraform_data.disk_monitor_install
```

This will create `terraform_data.disk_monitor_install` which:

- Copies `disk-monitor.sh` to `/usr/local/bin/disk-monitor.sh` via SSH
- Creates `/etc/default/disk-monitor` env file with the webhook URL
- Installs systemd service and timer units
- Enables and starts `disk-monitor.timer`

### Phase 5: Verify deployment

```bash
ssh root@135.181.45.178 "systemctl is-active disk-monitor.timer"
# Expected: active

ssh root@135.181.45.178 "systemctl list-timers disk-monitor.timer --no-pager"
# Expected: shows next/last run times

ssh root@135.181.45.178 "bash /usr/local/bin/disk-monitor.sh"
# Expected: alerts fire in #ops-alerts (disk may still be above 80%)
```

Verify disk usage is below 80% after Phase 1 cleanup. If still above, run additional cleanup per the runbook.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling deployment.

## Context

- Source PR: #1525
- Parent issue: #1409
- Follow-through issue: #1538
- Telegram-bridge monitoring deferred to: #1530
- Ops runbook: `knowledge-base/engineering/ops/runbooks/disk-monitoring.md`
- Server: `soleur-web-platform` at `135.181.45.178` (Hetzner CX33, hel1)
- Terraform state: R2 remote backend (`soleur-terraform-state` bucket)

## References

- `apps/web-platform/infra/server.tf` -- Terraform provisioner definition
- `apps/web-platform/infra/disk-monitor.sh` -- monitoring script
- `apps/web-platform/infra/variables.tf` -- Terraform variable definition
- `apps/web-platform/infra/cloud-init.yml` -- new server provisioning
- `knowledge-base/engineering/ops/runbooks/disk-monitoring.md` -- ops runbook
- `knowledge-base/project/learnings/integration-issues/2026-04-05-shell-mock-testing-and-disk-monitoring-provisioning.md` -- session learning

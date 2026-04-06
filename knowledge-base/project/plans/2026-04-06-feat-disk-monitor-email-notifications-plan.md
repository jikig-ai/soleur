---
title: "feat(infra): migrate disk-monitor.sh from Discord to email notifications"
type: feat
date: 2026-04-06
issue: "#1595"
---

# feat(infra): migrate disk-monitor.sh from Discord to email notifications

## Overview

Replace the Discord webhook notification channel in `disk-monitor.sh` with the Resend email API, sending disk space alerts to `ops@jikigai.com`. This aligns server-side monitoring with the project-wide email notification standard established in #1420, where all 14 GitHub Actions workflows were migrated from Discord to email. After this change, Discord webhooks are fully eliminated from ops alerting -- Discord is reserved for community content only (AGENTS.md rule).

## Problem Statement / Motivation

After #1420 migrated all GitHub Actions notifications to email, `disk-monitor.sh` remains the last ops alerting script using Discord. This creates a split notification channel: CI/workflow alerts arrive in email while disk space alerts arrive in Discord. The AGENTS.md rule is unambiguous: "Discord channels are for community content only (release announcements, blog posts, community updates -- NOT ops alerts like CI failures, drift detection, or workflow errors)."

## Proposed Solution

Mirror the Resend HTTP API pattern from `.github/actions/notify-ops-email/action.yml` into `disk-monitor.sh`:

1. Replace `DISCORD_OPS_WEBHOOK_URL` env var with `RESEND_API_KEY`
2. Replace the Discord JSON payload + curl with a Resend-compatible JSON payload + curl to `https://api.resend.com/emails`
3. Update Terraform (`variables.tf`, `server.tf`, `cloud-init.yml`) to wire the new variable through
4. Update `disk-monitor.test.sh` to mock the Resend API instead of Discord
5. Update the disk-monitoring runbook to reflect email alerting
6. Run `terraform apply -replace=terraform_data.disk_monitor_install` to deploy

## Technical Considerations

### Resend API pattern (from notify-ops-email composite action)

The existing pattern sends email via:

```bash
PAYLOAD=$(jq -n \
  --arg from "Soleur Ops <noreply@send.soleur.ai>" \
  --arg subject "$EMAIL_SUBJECT" \
  --arg html "$EMAIL_BODY" \
  '{from: $from, to: ["ops@jikigai.com"], subject: $subject, html: $html}')

curl -s -o /dev/null -w "%{http_code}" \
  -X POST "https://api.resend.com/emails" \
  -H "Authorization: Bearer ${RESEND_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
```

The disk-monitor.sh script will use this exact pattern, with `jq` already available on the server (installed via cloud-init packages).

### Terraform variable wiring

- `RESEND_API_KEY` already exists in Doppler `prd_terraform` config
- The `--name-transformer tf-var` converts it to `TF_VAR_resend_api_key`
- Add `variable "resend_api_key"` to `variables.tf` (sensitive)
- Replace `discord_ops_webhook_url` with `resend_api_key` in `server.tf` templatefile call and `terraform_data.disk_monitor_install` triggers/provisioner
- Replace env file content in `cloud-init.yml` from `DISCORD_OPS_WEBHOOK_URL` to `RESEND_API_KEY`

### Variable removal

After this change, `discord_ops_webhook_url` can be fully removed from:

- `variables.tf` (variable declaration)
- `server.tf` (templatefile parameter, terraform_data triggers, remote-exec provisioner)
- `cloud-init.yml` (env file content)

The `DISCORD_OPS_WEBHOOK_URL` secret can remain in Doppler `prd_terraform` for now (cleanup is a separate task -- removing secrets from Doppler is a manual action that should not gate this PR).

### Email content format

The email should include the same information as the Discord message but formatted as HTML:

- Subject: `[CRITICAL] Disk usage at 96% on soleur-web-platform` or `[WARNING] Disk usage at 82% on soleur-web-platform`
- Body: Available space, top disk consumers (same data as current Discord message)
- From: `Soleur Ops <noreply@send.soleur.ai>` (matches the composite action sender)
- To: `ops@jikigai.com`

### Cooldown and threshold behavior

No changes to cooldown logic, threshold values, or evaluation flow. Only the `send_alert` function changes its transport from Discord webhook to Resend email API.

### Server deployment

Since `user_data` has `ignore_changes` in the lifecycle block, the cloud-init changes only apply to new servers. For the existing server, `terraform_data.disk_monitor_install` handles deployment:

1. Pushes updated `disk-monitor.sh` via file provisioner
2. Writes the new `/etc/default/disk-monitor` env file with `RESEND_API_KEY` (replaces `DISCORD_OPS_WEBHOOK_URL`)
3. Reloads systemd and re-enables the timer

The `triggers_replace` hash must change from `var.discord_ops_webhook_url` to `var.resend_api_key` to trigger reprovisioning on key rotation.

## Files Changed

| File | Change |
|------|--------|
| `apps/web-platform/infra/disk-monitor.sh` | Replace Discord webhook curl with Resend email API curl |
| `apps/web-platform/infra/server.tf` | Replace `discord_ops_webhook_url` with `resend_api_key` in templatefile, terraform_data triggers, and remote-exec |
| `apps/web-platform/infra/cloud-init.yml` | Replace `DISCORD_OPS_WEBHOOK_URL` with `RESEND_API_KEY` in env file, update comment |
| `apps/web-platform/infra/variables.tf` | Remove `discord_ops_webhook_url`, add `resend_api_key` |
| `apps/web-platform/infra/disk-monitor.test.sh` | Update mocks and assertions for Resend API instead of Discord webhook |
| `knowledge-base/engineering/ops/runbooks/disk-monitoring.md` | Update runbook to reflect email alerting |

## Acceptance Criteria

- [ ] `disk-monitor.sh` sends alerts via Resend email API to `ops@jikigai.com` instead of Discord webhook
- [ ] `RESEND_API_KEY` env var replaces `DISCORD_OPS_WEBHOOK_URL` in `/etc/default/disk-monitor`
- [ ] Email subject includes alert level and hostname (e.g., `[CRITICAL] Disk usage at 96% on soleur-web-platform`)
- [ ] Email body includes available disk space and top 5 consumers
- [ ] Cooldown mechanism continues to work (per-threshold, 1-hour window)
- [ ] Script always exits 0 (resilient to Resend API failures)
- [ ] `terraform plan` shows clean after apply (no drift)
- [ ] All existing tests in `disk-monitor.test.sh` pass with updated mocks
- [ ] Disk-monitoring runbook updated with email alerting instructions
- [ ] `discord_ops_webhook_url` variable fully removed from Terraform config

## Test Scenarios

- Given disk usage is below 80%, when disk-monitor runs, then no email is sent and exit code is 0
- Given disk usage is 82%, when disk-monitor runs, then a WARNING email is sent to `ops@jikigai.com` with subject containing "[WARNING]"
- Given disk usage is 96%, when disk-monitor runs, then a CRITICAL email is sent with subject containing "[CRITICAL]"
- Given `RESEND_API_KEY` is not set in env file, when disk-monitor runs, then it exits 0 with a warning on stderr
- Given Resend API returns non-2xx, when disk-monitor sends alert, then it logs a warning and exits 0
- Given a WARNING alert was sent 30 minutes ago, when disk-monitor runs at 82%, then no email is sent (cooldown active)
- Given a WARNING alert was sent 2 hours ago, when disk-monitor runs at 82%, then email is sent (cooldown expired)
- Given 80% cooldown is active and disk usage is 96%, when disk-monitor runs, then CRITICAL email fires independently

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Implementation Notes

### Phase 1: Update disk-monitor.sh

Replace the `send_alert` function body. Keep the same function signature `send_alert(level, threshold, mentions)` but the `mentions` parameter becomes unused (email has no equivalent of Discord `allowed_mentions`). The parameter can be kept for backward compatibility in the threshold evaluation section or removed since both callers are in the same file.

Recommended: remove the `mentions` parameter entirely since it is Discord-specific and the evaluation section is trivially updated.

### Phase 2: Update Terraform config

1. `variables.tf`: Remove `discord_ops_webhook_url`, add `resend_api_key` (sensitive, string)
2. `server.tf` line 27: Replace `discord_ops_webhook_url = var.discord_ops_webhook_url` with `resend_api_key = var.resend_api_key` in templatefile
3. `server.tf` line 49: Replace `var.discord_ops_webhook_url` with `var.resend_api_key` in triggers_replace
4. `server.tf` line 68: Replace the printf line to write `RESEND_API_KEY` instead of `DISCORD_OPS_WEBHOOK_URL`
5. `cloud-init.yml` line 39: Update comment from Discord to email
6. `cloud-init.yml` line 50: Replace `DISCORD_OPS_WEBHOOK_URL='${discord_ops_webhook_url}'` with `RESEND_API_KEY='${resend_api_key}'`

### Phase 3: Update tests

Update `disk-monitor.test.sh`:

- Replace `DISCORD_OPS_WEBHOOK_URL` with `RESEND_API_KEY` in mock env file creation
- Update `MOCK_NO_WEBHOOK` toggle description and env var name
- Update curl mock to capture Resend API call args (Authorization header, JSON body) and output an HTTP status code (e.g., `echo "200"`) since the new implementation may use `-w "%{http_code}"` to check response codes
- Update assertions to check for Resend API URL instead of Discord webhook URL
- Update "everyone" mentions test to verify CRITICAL emails include "[CRITICAL]" in subject instead

### Phase 4: Update runbook

Update `knowledge-base/engineering/ops/runbooks/disk-monitoring.md`:

- Replace Discord references with email
- Update alert types table (remove Discord Mentions column, add Email Subject column)
- Update manual test command to use Resend API curl
- Update webhook-testing section

### Phase 5: Deploy

Run `terraform apply -replace=terraform_data.disk_monitor_install` to force-replace the disk monitor provisioner:

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply -replace=terraform_data.disk_monitor_install
```

Verify post-apply:

- `terraform plan` shows no changes
- SSH verify: `systemctl is-active disk-monitor.timer` returns "active"
- SSH verify: `grep RESEND_API_KEY /etc/default/disk-monitor` shows the key
- End-to-end verify: trigger `bash /usr/local/bin/disk-monitor.sh` on the server (if disk usage is above 80%) or temporarily lower `WARN_THRESHOLD` in the script, run it, and confirm an email arrives at `ops@jikigai.com`

## References

- Issue: #1595
- Prior migration: #1420 (GH Actions Discord-to-email migration)
- Composite action pattern: `.github/actions/notify-ops-email/action.yml`
- Resend API docs: `https://resend.com/docs/api-reference/emails/send-email`
- Terraform learning: `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md`
- Doppler config: `prd_terraform` contains both `DISCORD_OPS_WEBHOOK_URL` and `RESEND_API_KEY`

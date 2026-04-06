---
title: "feat(infra): migrate disk-monitor.sh from Discord to email notifications"
type: feat
date: 2026-04-06
issue: "#1595"
deepened: 2026-04-06
---

# feat(infra): migrate disk-monitor.sh from Discord to email notifications

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 4 (Technical Considerations, Implementation Notes Phase 1/3/5)
**Research sources:** Resend API docs (Context7), shell-api-wrapper-hardening-patterns learning, shell-script-defensive-patterns learning, doppler-tf-var-naming-alignment learning, terraform-data-connection-block-no-auto-replace learning

### Key Improvements

1. Added concrete `send_alert` function implementation with shell API hardening patterns (curl stderr suppression, jq fallback chains, HTTP response code checking)
2. Added Resend API rate limit context (2 req/s default -- no concern for disk monitor's usage pattern)
3. Added curl mock implementation detail for tests (must output HTTP code on stdout for `-w "%{http_code}"` pattern)
4. Specified `text` parameter (not `html`) for email body since disk usage output is plain text data, avoiding unnecessary HTML formatting

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

The disk-monitor.sh script will use this pattern with one modification: use `text` instead of `html` since disk usage output is plain text (top consumers from `du`, available GB). No HTML formatting needed for ops alerts.

### Research Insights: Resend API

- **Rate limit:** 2 requests/second per team (default). Disk monitor runs every 5 min with max 2 alerts per run -- nowhere near the limit. No retry/backoff logic needed.
- **Error codes:** 429 (rate limit), 422 (validation), 403 (auth). The script should log the HTTP code on failure for diagnostics.
- **Idempotency:** Resend supports `Idempotency-Key` header for deduplication, but the cooldown mechanism already prevents duplicate alerts. Not needed here.
- **`text` vs `html` parameter:** Resend accepts both. Use `text` for plain text body (disk usage data is inherently plain text). The composite action uses `html` because workflow notifications benefit from formatting; disk alerts do not.

### Research Insights: Shell API Hardening (from learnings)

Per `knowledge-base/project/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`, shell scripts calling REST APIs need defense at five layers. For disk-monitor.sh specifically:

1. **Transport:** Keep `2>/dev/null` on curl to prevent `Authorization: Bearer` header leaking to systemd journal on connection failure
2. **Response checking:** Use `-w "%{http_code}"` pattern to capture HTTP status and log non-2xx codes
3. **jq fallback:** The `jq -n` call for payload construction cannot fail with malformed input (it creates JSON from args, not from untrusted data), so no fallback chain needed here -- but the `du` output piped into `jq --arg` must handle the case where `du` output contains characters that break JSON (backslashes, quotes). Use `--rawfile` or sanitize via `tr`
4. **Input validation:** All inputs (USAGE_PCT, AVAIL_GB, hostname) come from system commands, not user input -- no URL interpolation risk
5. **HTTPS hardcoded:** The Resend API URL is hardcoded (`https://api.resend.com/emails`), not configurable -- no scheme validation needed

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

Replace the `send_alert` function body. Remove the `mentions` parameter entirely (Discord-specific). Update the two callers in the threshold evaluation section to pass only `level` and `threshold`.

**Concrete `send_alert` implementation:**

```bash
send_alert() {
  local level="$1" threshold="$2"
  local server_hostname
  server_hostname=$(hostname)

  # Build disk consumer report lazily (only when alerting)
  local TOP_CONSUMERS
  TOP_CONSUMERS=$(timeout 10 du -sh /* 2>/dev/null | sort -rh | head -5) || TOP_CONSUMERS="(timed out)"

  local SUBJECT="[${level}] Disk usage at ${USAGE_PCT}% on ${server_hostname}"
  local BODY
  BODY=$(printf 'Disk usage: %s%%\nAvailable: %sGB\n\nTop consumers:\n%s' \
    "$USAGE_PCT" "$AVAIL_GB" "$TOP_CONSUMERS")

  local PAYLOAD
  PAYLOAD=$(jq -n \
    --arg from "Soleur Ops <noreply@send.soleur.ai>" \
    --arg subject "$SUBJECT" \
    --arg text "$BODY" \
    '{from: $from, to: ["ops@jikigai.com"], subject: $subject, text: $text}')

  local HTTP_CODE
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -X POST "https://api.resend.com/emails" \
    -H "Authorization: Bearer ${RESEND_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null) || HTTP_CODE="000"

  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    echo "WARNING: Resend API POST failed (HTTP ${HTTP_CODE})" >&2
  fi
}
```

Key design decisions:

- Uses `text` parameter (not `html`) -- disk usage data is plain text
- `2>/dev/null` on curl prevents Authorization header leaking to journal on connection failure
- `|| HTTP_CODE="000"` handles curl transport failure (no response at all)
- `--max-time 10` matches existing Discord implementation timeout
- `jq --arg text "$BODY"` safely escapes newlines and special characters in `du` output

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
- Update curl mock to handle the `-w "%{http_code}"` pattern: the mock must output the HTTP status code on stdout (the real curl writes it to stdout when `-w` is used with `-o /dev/null`)
- Update assertions to check for Resend API URL (`api.resend.com`) instead of Discord webhook URL
- Update "everyone" mentions test to verify CRITICAL emails include "[CRITICAL]" in the subject (check the `-d` payload arg for the subject field)

**Concrete curl mock update:**

```bash
# Mock curl -- writes args to file, outputs HTTP status code for -w "%{http_code}"
cat > "$mock_dir/curl" << MOCK
#!/bin/bash
if [[ "\${MOCK_CURL_FAIL:-}" == "1" ]]; then
  echo "000"  # transport failure
  exit 1
fi
echo "\$*" >> "$mock_dir/curl_args"
echo "200"  # HTTP status code (matches -w "%{http_code}" output)
exit 0
MOCK
```

This ensures the test mock accurately simulates the `-s -o /dev/null -w "%{http_code}"` pattern where curl outputs the HTTP code on stdout.

### Phase 4: Update runbook

Update `knowledge-base/engineering/ops/runbooks/disk-monitoring.md`:

- Replace Discord references with email
- Update alert types table (remove Discord Mentions column, add Email Subject column)
- Update manual test command to use Resend API curl
- Update webhook-testing section

### Phase 5: Deploy

**Note:** Per `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md`, changing `triggers_replace` from `var.discord_ops_webhook_url` to `var.resend_api_key` WILL trigger automatic replacement of `terraform_data.disk_monitor_install` because the hash value changes. However, use `-replace` explicitly for safety to ensure the provisioner runs even if the hash computation has an edge case.

Run `terraform apply -replace=terraform_data.disk_monitor_install` to force-replace the disk monitor provisioner:

```bash
cd apps/web-platform/infra && \
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply -replace=terraform_data.disk_monitor_install
```

**Important:** Export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` separately for the R2 backend (per AGENTS.md -- the name transformer renames them to `TF_VAR_*` which the backend ignores).

Verify post-apply:

- `terraform plan` shows no changes
- SSH verify: `systemctl is-active disk-monitor.timer` returns "active"
- SSH verify: `grep RESEND_API_KEY /etc/default/disk-monitor` shows the key
- SSH verify: `grep -c DISCORD /etc/default/disk-monitor` returns 0
- End-to-end verify: trigger `bash /usr/local/bin/disk-monitor.sh` on the server (if disk usage is above 80%) or temporarily lower `WARN_THRESHOLD` in the script, run it, and confirm an email arrives at `ops@jikigai.com`

## References

- Issue: #1595
- Prior migration: #1420 (GH Actions Discord-to-email migration)
- Composite action pattern: `.github/actions/notify-ops-email/action.yml`
- Resend API docs: `https://resend.com/docs/api-reference/emails/send-email`
- Terraform learning: `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md`
- Doppler config: `prd_terraform` contains both `DISCORD_OPS_WEBHOOK_URL` and `RESEND_API_KEY`

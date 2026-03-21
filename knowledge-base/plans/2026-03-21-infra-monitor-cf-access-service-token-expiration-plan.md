---
title: "infra: monitor Cloudflare Access service token expiration"
type: feat
date: 2026-03-21
semver: patch
---

# infra: monitor Cloudflare Access service token expiration

## Overview

PR #971 created a Cloudflare Access service token (`github-actions-deploy`) that gates deploy webhook access through the Cloudflare Tunnel. Service tokens default to 8760h (1 year) and expire silently -- deploys fail with a 403 from Cloudflare Access with no indication that the token expired. This plan adds proactive expiration monitoring and documents the rotation procedure.

Closes #974. Follow-up from #967.

## Problem Statement

The `cloudflare_zero_trust_access_service_token.deploy` resource in `apps/web-platform/infra/tunnel.tf` creates a token with a 1-year lifetime (expires ~2027-03-21). When this token expires:

1. GitHub Actions deploy workflow (`web-platform-release.yml`) sends `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers
2. Cloudflare Access rejects the request with HTTP 403
3. The deploy step reports "Deploy webhook failed (HTTP 403)" -- indistinguishable from other 403 causes (Bot Fight Mode, misconfigured policy, etc.)
4. No alert fires unless explicitly configured

The issue requests two things:
- **Monitoring:** Alert before the token expires
- **Documentation:** Rotation procedure for when renewal is needed

## Proposed Solution

Two complementary approaches, both automatable via Terraform and GitHub Actions:

### 1. Terraform-managed Cloudflare notification policy

Add a `cloudflare_notification_policy` resource with `alert_type = "expiring_service_token_alert"` to `apps/web-platform/infra/tunnel.tf`. Cloudflare sends this alert one week before expiry. This is the primary monitoring mechanism -- zero ongoing CI cost, runs on Cloudflare's infrastructure.

### 2. GitHub Actions workflow as backup monitor

Create `scheduled-cf-token-expiry-check.yml` modeled on `scheduled-linkedin-token-check.yml`. This workflow:
- Reads the token's `expires_at` from Terraform state (via `terraform output`) or the Cloudflare API
- Calculates days remaining
- Creates a GitHub issue when the token is within 30 days of expiry
- Deduplicates with existing open issues
- Runs weekly on Monday mornings

This provides defense-in-depth: if the Cloudflare notification is missed (email spam filter, notification misconfiguration), the GitHub issue surfaces in the team's primary work tracker.

### 3. Rotation runbook in knowledge-base

Document the rotation procedure as a learning in `knowledge-base/learnings/` so it's discoverable by agents in future sessions.

## Technical Approach

### Phase 1: Terraform notification policy (`tunnel.tf`)

Add to `apps/web-platform/infra/tunnel.tf`:

```hcl
# Alert one week before the deploy service token expires.
# Cloudflare sends expiring_service_token_alert 7 days pre-expiry.
resource "cloudflare_notification_policy" "service_token_expiry" {
  account_id  = var.cf_account_id
  name        = "Deploy service token expiring"
  description = "Alert when github-actions-deploy service token approaches expiry"
  alert_type  = "expiring_service_token_alert"
  enabled     = true

  email_integration {
    id = var.cf_notification_email
  }
}
```

Add `cf_notification_email` to `variables.tf`:

```hcl
variable "cf_notification_email" {
  description = "Email address for Cloudflare notification policies"
  type        = string
}
```

Store the email in Doppler under `prd_terraform` config with name `CF_NOTIFICATION_EMAIL`, which the `--name-transformer tf-var` flag will convert to `TF_VAR_cf_notification_email`.

### Phase 2: GitHub Actions backup workflow (`.github/workflows/scheduled-cf-token-expiry-check.yml`)

```yaml
# Backup monitor: check CF Access service token expiry via Cloudflare API.
# Primary alert is the Terraform-managed cloudflare_notification_policy.
# This workflow catches cases where the CF notification is missed.
#
# Security: CLOUDFLARE_API_TOKEN from repository secrets (not user-controlled).

name: "Scheduled: CF Token Expiry Check"

on:
  workflow_dispatch:
  schedule:
    - cron: '0 9 * * 1'  # Monday 09:00 UTC
```

The workflow will:
1. Call the Cloudflare API to list service tokens: `GET /accounts/<account_id>/access/service_tokens`
2. Parse the `expires_at` field for the `github-actions-deploy` token
3. Calculate days remaining
4. If <= 30 days: create/comment on a GitHub issue with rotation instructions
5. If > 30 days and a stale issue exists: close it with a "token is valid" comment

Required secrets: `CF_API_TOKEN_READ` (a read-only Cloudflare API token with Access:Read scope -- separate from the Terraform token to follow least privilege), `CF_ACCOUNT_ID`.

### Phase 3: Rotation runbook

Create `knowledge-base/learnings/2026-03-21-cloudflare-service-token-rotation.md` documenting:

1. **Refresh (extend expiry):** Terraform `duration` attribute change + `terraform apply` extends the expiry without regenerating credentials. No secret rotation needed.
2. **Rotate (new credentials):** `terraform taint cloudflare_zero_trust_access_service_token.deploy && terraform apply` destroys and recreates the token with new `client_id` and `client_secret`. Then update GitHub secrets:
   ```bash
   terraform output -raw access_service_token_client_id | gh secret set CF_ACCESS_CLIENT_ID
   terraform output -raw access_service_token_client_secret | gh secret set CF_ACCESS_CLIENT_SECRET
   ```
3. **Verify:** Trigger a test deploy via `gh workflow run web-platform-release.yml` and confirm HTTP 200.

## Non-Goals

- **Automatic rotation:** Rotating the token regenerates `client_id` and `client_secret`, requiring GitHub secret updates. Automating this end-to-end (Terraform apply + GitHub secret update) introduces complexity and blast radius that isn't justified for a yearly event.
- **Token duration change:** The default 8760h (1 year) is reasonable. Shorter durations increase operational burden without proportional security benefit for a machine-to-machine token scoped to a single Access policy.
- **telegram-bridge service token:** That app doesn't use Cloudflare Tunnel/Access. Only `web-platform` has this dependency.
- **Cloudflare API token monitoring:** The `cf_api_token` used by Terraform is a separate concern. It doesn't expire the same way (API tokens have their own lifecycle). If needed, that's a separate issue.

## Acceptance Criteria

- [ ] `cloudflare_notification_policy.service_token_expiry` resource exists in `apps/web-platform/infra/tunnel.tf`
- [ ] `cf_notification_email` variable added to `apps/web-platform/infra/variables.tf` with Doppler value
- [ ] `terraform plan` shows the notification policy will be created (no errors)
- [ ] `scheduled-cf-token-expiry-check.yml` workflow exists and passes lint
- [ ] Workflow creates a GitHub issue when token is within 30 days of expiry
- [ ] Workflow deduplicates issues (doesn't create a second if one is open)
- [ ] Workflow closes stale issues when token is refreshed
- [ ] Rotation runbook exists in `knowledge-base/learnings/`
- [ ] `terraform apply` succeeds (notification policy created)

## Test Scenarios

- Given the service token expires in 25 days, when the scheduled workflow runs, then a GitHub issue is created with the title "[Action Required] Cloudflare deploy service token expiring" and body containing rotation instructions
- Given an open expiry issue exists and the token has been refreshed (60+ days remaining), when the workflow runs, then the issue is closed with a "token is valid" comment
- Given an open expiry issue exists and the token is still within 30 days of expiry, when the workflow runs, then a comment is added to the existing issue (no duplicate issue created)
- Given the Cloudflare API is unreachable, when the workflow runs, then it exits with a warning annotation (not a failure) to avoid noisy CI alerts
- Given `terraform plan` is run with the new notification policy, when the plan output is reviewed, then exactly one `cloudflare_notification_policy` resource is shown as "will be created"

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| `expiring_service_token_alert` alert type may not filter to a specific token | Cloudflare docs say "None" for filters -- the alert fires for ALL service tokens in the account. Acceptable: only one token exists. |
| CF API token in GitHub secrets may lack Access:Read scope | Use the existing `CF_API_TOKEN` or create a dedicated read-only token. Verify scope before workflow runs. |
| Email notification goes to spam | GitHub Actions backup workflow creates an issue in the repo -- the primary work tracker. |
| `previous_client_secret_expires_at` grace period not documented | During rotation, update GitHub secrets immediately after `terraform apply`. The old secret stops working once tainted and destroyed. |

## References

- Existing service token resource: [`apps/web-platform/infra/tunnel.tf:54-57`](apps/web-platform/infra/tunnel.tf)
- Deploy workflow using the token: [`.github/workflows/web-platform-release.yml:49-76`](.github/workflows/web-platform-release.yml)
- Pattern reference for scheduled token checks: [`.github/workflows/scheduled-linkedin-token-check.yml`](.github/workflows/scheduled-linkedin-token-check.yml)
- Cloudflare notification types: [Terraform `cloudflare_notification_policy`](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/notification_policy)
- Cloudflare service token docs: [Service tokens](https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/)
- Parent issue: #974
- Originating PR: #971 / #967

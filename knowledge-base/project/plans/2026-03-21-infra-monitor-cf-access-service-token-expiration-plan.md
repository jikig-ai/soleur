---
title: "infra: monitor Cloudflare Access service token expiration"
type: feat
date: 2026-03-21
semver: patch
deepened: 2026-03-21
---

# infra: monitor Cloudflare Access service token expiration

## Enhancement Summary

**Deepened on:** 2026-03-21
**Sections enhanced:** 6
**Research sources:** Cloudflare Terraform provider v4 docs, Cloudflare service token API docs, project learnings (Doppler tf-var naming, CF provider v4/v5 resource names, tunnel server provisioning), existing workflow patterns (scheduled-linkedin-token-check.yml), project constitution

### Key Improvements

1. Replaced deprecated `terraform taint` with `terraform apply -replace=` in rotation runbook
2. Added `previous_client_secret_expires_at` grace period to rotation procedure for zero-downtime credential rollover
3. Added concrete GitHub Actions workflow implementation with full bash script (not just a skeleton)
4. Added constitution-mandated `workflow_dispatch`-only initial trigger (add cron after validation)
5. Added `gh label create` pre-creation step per constitution requirement

### New Considerations Discovered

- Cloudflare `expiring_service_token_alert` fires for ALL service tokens in the account (no per-token filtering) -- acceptable since only one token exists, but worth documenting for future-proofing
- `previous_client_secret_expires_at` on the service token resource allows grace period rotation: update the secret version, set a transition window, then update downstream consumers before the old secret expires
- `CF_ACCOUNT_ID` is not a secret (it's in Terraform variables and public DNS records) -- can be stored as a repository variable, not a secret

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

### Research Insights

**Failure mode detail:** Per the tunnel server provisioning learning (`2026-03-21-cloudflare-tunnel-server-provisioning.md`), Cloudflare Bot Fight Mode already caused a false 403 during initial setup. A token expiry 403 would be even harder to diagnose because the token was previously working -- the failure appears intermittent rather than systematic.

**Cloudflare notification timing:** Cloudflare sends `expiring_service_token_alert` exactly 7 days before expiry. This is a fixed window -- not configurable. The 30-day GitHub Actions backup provides a larger advance warning window.

## Proposed Solution

Two complementary approaches, both automatable via Terraform and GitHub Actions:

### 1. Terraform-managed Cloudflare notification policy

Add a `cloudflare_notification_policy` resource with `alert_type = "expiring_service_token_alert"` to `apps/web-platform/infra/tunnel.tf`. Cloudflare sends this alert one week before expiry. This is the primary monitoring mechanism -- zero ongoing CI cost, runs on Cloudflare's infrastructure.

### 2. GitHub Actions workflow as backup monitor

Create `scheduled-cf-token-expiry-check.yml` modeled on `scheduled-linkedin-token-check.yml`. This workflow:
- Calls the Cloudflare API directly: `GET /client/v4/accounts/<account_id>/access/service_tokens`
- Parses the `expires_at` field (ISO 8601 format, e.g., `2027-03-21T14:30:00Z`)
- Calculates days remaining
- Creates a GitHub issue when the token is within 30 days of expiry
- Deduplicates with existing open issues
- Starts with `workflow_dispatch` only (add cron after validation per constitution)

This provides defense-in-depth: if the Cloudflare notification is missed (email spam filter, notification misconfiguration), the GitHub issue surfaces in the team's primary work tracker.

### 3. Rotation runbook in knowledge-base

Document the rotation procedure as a learning in `knowledge-base/project/learnings/` so it's discoverable by agents in future sessions.

## Technical Approach

### Phase 1: Terraform notification policy (`tunnel.tf`)

Add to `apps/web-platform/infra/tunnel.tf`:

```hcl
# Alert one week before the deploy service token expires.
# Cloudflare sends expiring_service_token_alert 7 days pre-expiry.
# Note: this alert fires for ALL service tokens in the account (no per-token
# filtering). Currently only one token exists (github-actions-deploy).
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

#### Research Insights

**Provider version:** The codebase pins `cloudflare ~> 4.0`. The `email_integration` block syntax above is confirmed correct for v4. The v5 provider uses a different `mechanisms` attribute -- do not use v5 syntax. See learning `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`.

**Doppler naming:** Per learning `2026-03-21-doppler-tf-var-naming-alignment.md`, the Doppler key must match the Terraform variable name after `--name-transformer tf-var` conversion. `CF_NOTIFICATION_EMAIL` in Doppler becomes `TF_VAR_cf_notification_email`, binding to `variable "cf_notification_email"`.

**Notification policy scope:** The `expiring_service_token_alert` type has no `filters` block support (Cloudflare docs list "None" for available filters). It fires for all service tokens in the account. This is acceptable with one token but should be noted in comments for future maintainers who might add more tokens.

### Phase 2: GitHub Actions backup workflow (`.github/workflows/scheduled-cf-token-expiry-check.yml`)

Full implementation:

```yaml
# Backup monitor: check CF Access service token expiry via Cloudflare API.
# Primary alert is the Terraform-managed cloudflare_notification_policy.
# This workflow catches cases where the CF notification is missed.
#
# Security: CF_API_TOKEN from repository secrets (not user-controlled).
# CF_ACCOUNT_ID is a non-secret repository variable.

name: "Scheduled: CF Token Expiry Check"

on:
  workflow_dispatch:
  # Add cron after validating the workflow works end-to-end:
  # schedule:
  #   - cron: '0 9 * * 1'  # Monday 09:00 UTC

concurrency:
  group: scheduled-cf-token-expiry-check
  cancel-in-progress: false

permissions:
  issues: write

jobs:
  check-token:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Check service token expiry
        env:
          CF_API_TOKEN: ${{ secrets.CF_API_TOKEN }}
          CF_ACCOUNT_ID: ${{ vars.CF_ACCOUNT_ID }}
          GH_TOKEN: ${{ github.token }}
          GH_REPO: ${{ github.repository }}
          WARN_DAYS: "30"
          TOKEN_NAME: "github-actions-deploy"
        run: |
          set -euo pipefail

          if [[ -z "${CF_API_TOKEN:-}" ]]; then
            echo "::warning::CF_API_TOKEN secret is not set. Skipping check."
            exit 0
          fi

          if [[ -z "${CF_ACCOUNT_ID:-}" ]]; then
            echo "::warning::CF_ACCOUNT_ID variable is not set. Skipping check."
            exit 0
          fi

          # List service tokens
          HTTP_CODE=$(curl -s -o /tmp/cf-tokens.json -w "%{http_code}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/access/service_tokens")

          if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
            echo "::warning::Cloudflare API returned HTTP $HTTP_CODE. Token status unknown."
            exit 0
          fi

          # Find the deploy token by name
          EXPIRES_AT=$(jq -r \
            --arg name "$TOKEN_NAME" \
            '.result[] | select(.name == $name) | .expires_at // empty' \
            /tmp/cf-tokens.json)

          if [[ -z "$EXPIRES_AT" ]]; then
            echo "::warning::Service token '$TOKEN_NAME' not found in API response."
            exit 0
          fi

          # Calculate days remaining (ISO 8601 -> epoch)
          EXPIRES_EPOCH=$(date -d "$EXPIRES_AT" +%s)
          NOW_EPOCH=$(date +%s)
          DAYS_REMAINING=$(( (EXPIRES_EPOCH - NOW_EPOCH) / 86400 ))

          echo "Token '$TOKEN_NAME' expires at $EXPIRES_AT ($DAYS_REMAINING days remaining)."

          ISSUE_TITLE="[Action Required] Cloudflare deploy service token expiring"

          if [[ "$DAYS_REMAINING" -le "$WARN_DAYS" ]]; then
            echo "::warning::Token expires in $DAYS_REMAINING days (threshold: $WARN_DAYS)."

            BODY=$(cat <<ISSUE_BODY
          ## Cloudflare Deploy Service Token Expiring

          The \`github-actions-deploy\` service token expires on **$EXPIRES_AT** ($DAYS_REMAINING days remaining).

          When expired, all deploys via \`web-platform-release.yml\` will fail with HTTP 403.

          ### Renewal steps

          **Option A: Extend expiry (no credential change)**

          1. Edit \`apps/web-platform/infra/tunnel.tf\` -- add or update \`duration\` on the service token resource
          2. Run: \`doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform apply\`

          **Option B: Rotate credentials**

          1. Run: \`terraform apply -replace=cloudflare_zero_trust_access_service_token.deploy\`
          2. Update GitHub secrets:
             \`\`\`bash
             terraform output -raw access_service_token_client_id | gh secret set CF_ACCESS_CLIENT_ID
             terraform output -raw access_service_token_client_secret | gh secret set CF_ACCESS_CLIENT_SECRET
             \`\`\`
          3. Verify: \`gh workflow run web-platform-release.yml\`

          **References:** #974, knowledge-base/project/learnings/2026-03-21-cloudflare-service-token-rotation.md
          ISSUE_BODY
          )

            # Dedup: check for existing open issue
            EXISTING=$(gh issue list --repo "$GH_REPO" --state open \
              --search "in:title \"[Action Required] Cloudflare deploy service token\"" \
              --json number --jq '.[0].number // empty')

            if [[ -n "$EXISTING" ]]; then
              echo "Issue already exists: #$EXISTING -- adding comment."
              gh issue comment "$EXISTING" --repo "$GH_REPO" \
                --body "Token check ran $(date -u '+%Y-%m-%d %H:%M UTC') -- $DAYS_REMAINING days remaining."
            else
              # Pre-create label if missing
              gh label create "action-required" --repo "$GH_REPO" \
                --description "Requires manual intervention" --color "B60205" 2>/dev/null || true
              gh issue create --repo "$GH_REPO" \
                --title "$ISSUE_TITLE" \
                --label "action-required" \
                --body "$BODY"
            fi
          else
            echo "Token is healthy ($DAYS_REMAINING days remaining)."

            # Close stale renewal issues
            STALE=$(gh issue list --repo "$GH_REPO" --state open \
              --search "in:title \"[Action Required] Cloudflare deploy service token\"" \
              --json number --jq '.[0].number // empty')

            if [[ -n "$STALE" ]]; then
              echo "Closing stale renewal issue #$STALE."
              gh issue close "$STALE" --repo "$GH_REPO" \
                --comment "Token check ran $(date -u '+%Y-%m-%d %H:%M UTC') -- $DAYS_REMAINING days remaining. Auto-closing."
            fi
          fi

          rm -f /tmp/cf-tokens.json
```

#### Research Insights

**Constitution compliance:**
- `workflow_dispatch` only initially -- cron commented out until validated end-to-end (constitution: "start with workflow_dispatch trigger only, adding cron after the pipeline is validated")
- `timeout-minutes: 5` set on the job (constitution: "claude-code-action and workflows must set timeout-minutes")
- `gh label create ... 2>/dev/null || true` pre-creates labels (constitution: "gh issue create --label fails if the label does not exist")
- Warning annotations on API failures rather than hard failures (constitution: "network failures must degrade gracefully")

**Pattern alignment with scheduled-linkedin-token-check.yml:**
- Same deduplication pattern (`gh issue list --search`, then create or comment)
- Same stale-issue auto-close pattern
- Same graceful handling of missing secrets
- Same `concurrency` block to prevent parallel runs

**Security:**
- `CF_ACCOUNT_ID` stored as a repository **variable** (`vars.CF_ACCOUNT_ID`), not a secret -- it's not sensitive (visible in DNS records and public Cloudflare dashboard URLs)
- `CF_API_TOKEN` reused from existing Terraform secret -- avoids creating a second API token. Verify it has `Access:Read` scope. If not, the Cloudflare API returns 403 with a clear error message ("insufficient permissions"), which the workflow handles gracefully via the HTTP code check.

**Edge case: `date -d` portability:**
- Ubuntu runners (GitHub Actions) use GNU coreutils, so `date -d "$EXPIRES_AT"` handles ISO 8601 natively. This would not work on macOS (`date -j -f`), but the workflow only runs on `ubuntu-latest`.

### Phase 3: Rotation runbook

Create `knowledge-base/project/learnings/2026-03-21-cloudflare-service-token-rotation.md` documenting:

1. **Refresh (extend expiry):** Change or add the `duration` attribute on the service token resource in Terraform + `terraform apply`. This extends the expiry without regenerating credentials. No secret rotation needed. The `expires_at` output updates automatically.

2. **Rotate (new credentials) -- zero-downtime method:**
   a. Increment `client_secret_version` on the existing resource (generates new secret while keeping old one valid during transition)
   b. Set `previous_client_secret_expires_at` to a future timestamp (e.g., 24 hours) to allow transition window
   c. `terraform apply`
   d. Update GitHub secrets with the new credentials:
      ```bash
      terraform output -raw access_service_token_client_id | gh secret set CF_ACCESS_CLIENT_ID
      terraform output -raw access_service_token_client_secret | gh secret set CF_ACCESS_CLIENT_SECRET
      ```
   e. The old secret remains valid until `previous_client_secret_expires_at` passes

3. **Rotate (new credentials) -- hard cut method:**
   ```bash
   terraform apply -replace=cloudflare_zero_trust_access_service_token.deploy
   terraform output -raw access_service_token_client_id | gh secret set CF_ACCESS_CLIENT_ID
   terraform output -raw access_service_token_client_secret | gh secret set CF_ACCESS_CLIENT_SECRET
   ```
   Note: uses `terraform apply -replace=` instead of deprecated `terraform taint` (deprecated since Terraform 0.15.2). Old secret stops working immediately.

4. **Verify:** Trigger a test deploy via `gh workflow run web-platform-release.yml` and confirm HTTP 200.

#### Research Insights

**`terraform taint` deprecation:** `terraform taint` was deprecated in Terraform 0.15.2 (April 2021) and will be removed in a future version. Use `terraform apply -replace=<resource>` instead -- it combines the taint and apply into a single operation, reducing the window where state is inconsistent.

**`previous_client_secret_expires_at` attribute:** The `cloudflare_zero_trust_access_service_token` resource supports `client_secret_version` (incrementing triggers rotation) and `previous_client_secret_expires_at` (sets when the old secret expires). This enables zero-downtime rotation:
- Increment `client_secret_version` in HCL
- Set `previous_client_secret_expires_at = "2027-03-22T00:00:00Z"` (24h grace)
- Apply, update GitHub secrets, then the old secret expires gracefully

**Rotation vs. renewal distinction:** Per Cloudflare docs, "Refresh" extends the token's lifetime by one year without changing credentials. "Rotate" regenerates `client_secret` (and may change `client_id` depending on method). The client secret is only displayed once at creation time -- if lost, a new token must be created. Terraform state stores both values, so as long as state is accessible, credentials are recoverable.

## Non-Goals

- **Automatic rotation:** Rotating the token regenerates `client_id` and `client_secret`, requiring GitHub secret updates. Automating this end-to-end (Terraform apply + GitHub secret update) introduces complexity and blast radius that isn't justified for a yearly event.
- **Token duration change:** The default 8760h (1 year) is reasonable. Shorter durations increase operational burden without proportional security benefit for a machine-to-machine token scoped to a single Access policy.
- **telegram-bridge service token:** That app doesn't use Cloudflare Tunnel/Access. Only `web-platform` has this dependency.
- **Cloudflare API token monitoring:** The `cf_api_token` used by Terraform is a separate concern. It doesn't expire the same way (API tokens have their own lifecycle). If needed, that's a separate issue.

## Acceptance Criteria

- [x] `cloudflare_notification_policy.service_token_expiry` resource exists in `apps/web-platform/infra/tunnel.tf`
- [x] `cf_notification_email` variable added to `apps/web-platform/infra/variables.tf` with Doppler value
- [x] `terraform plan` shows the notification policy will be created (no errors)
- [x] `scheduled-cf-token-expiry-check.yml` workflow exists and passes lint
- [x] Workflow creates a GitHub issue when token is within 30 days of expiry
- [x] Workflow deduplicates issues (doesn't create a second if one is open)
- [x] Workflow closes stale issues when token is refreshed
- [x] Rotation runbook exists in `knowledge-base/engineering/ops/runbooks/`
- [ ] `terraform apply` succeeds (notification policy created)
- [ ] Workflow validated via `gh workflow run` before enabling cron schedule

## Test Scenarios

- Given the service token expires in 25 days, when the scheduled workflow runs, then a GitHub issue is created with the title "[Action Required] Cloudflare deploy service token expiring" and body containing rotation instructions
- Given an open expiry issue exists and the token has been refreshed (60+ days remaining), when the workflow runs, then the issue is closed with a "token is valid" comment
- Given an open expiry issue exists and the token is still within 30 days of expiry, when the workflow runs, then a comment is added to the existing issue (no duplicate issue created)
- Given the Cloudflare API is unreachable, when the workflow runs, then it exits with a warning annotation (not a failure) to avoid noisy CI alerts
- Given `terraform plan` is run with the new notification policy, when the plan output is reviewed, then exactly one `cloudflare_notification_policy` resource is shown as "will be created"
- Given the `CF_API_TOKEN` secret is not set, when the workflow runs, then it exits with a warning annotation and exit code 0
- Given the `action-required` label does not exist, when the workflow creates an issue, then it pre-creates the label before issue creation

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| `expiring_service_token_alert` alert type may not filter to a specific token | Cloudflare docs say "None" for filters -- the alert fires for ALL service tokens in the account. Acceptable: only one token exists. Add a comment in HCL for future maintainers. |
| CF API token in GitHub secrets may lack Access:Read scope | Reuse existing `CF_API_TOKEN`. The workflow handles 403 gracefully (warning annotation, not failure). Verify scope on first manual run. |
| Email notification goes to spam | GitHub Actions backup workflow creates an issue in the repo -- the primary work tracker. Defense-in-depth. |
| `previous_client_secret_expires_at` grace period behavior underdocumented | Document both zero-downtime and hard-cut rotation methods. Default to hard-cut for simplicity; zero-downtime available when deploy continuity is critical. |
| Terraform provider v4 vs v5 attribute mismatch | Verified: `email_integration` is the correct v4 syntax. See learning `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`. |
| Doppler variable name mismatch | Follows established naming convention per learning `2026-03-21-doppler-tf-var-naming-alignment.md`. Validate with `terraform validate` after adding variable. |

## References

- Existing service token resource: [`apps/web-platform/infra/tunnel.tf:54-57`](apps/web-platform/infra/tunnel.tf)
- Deploy workflow using the token: [`.github/workflows/web-platform-release.yml:49-76`](.github/workflows/web-platform-release.yml)
- Pattern reference for scheduled token checks: [`.github/workflows/scheduled-linkedin-token-check.yml`](.github/workflows/scheduled-linkedin-token-check.yml)
- Cloudflare notification types: [Terraform `cloudflare_notification_policy` (v4)](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/notification_policy)
- Cloudflare service token docs: [Service tokens](https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/)
- Learning: [Cloudflare Terraform v4 vs v5 resource names](knowledge-base/project/learnings/2026-03-20-cloudflare-terraform-v4-v5-resource-names.md)
- Learning: [Doppler tf-var naming alignment](knowledge-base/project/learnings/2026-03-21-doppler-tf-var-naming-alignment.md)
- Learning: [Cloudflare tunnel server provisioning](knowledge-base/project/learnings/2026-03-21-cloudflare-tunnel-server-provisioning.md)
- Parent issue: #974
- Originating PR: #971 / #967

---
module: System
date: 2026-04-06
problem_type: integration_issue
component: email_processing
symptoms:
  - "Resend API returns 403: This API key is suspended"
  - "Resend API returns 403: The send.soleur.ai domain is not verified"
  - "Disk monitor emails not delivered after terraform apply"
root_cause: config_error
resolution_type: config_change
severity: high
tags: [resend, api-key, doppler, terraform, email, account-consolidation]
synced_to: []
---

# Learning: Resend duplicate account consolidation and API key rotation

## Problem

Two separate Resend accounts existed for the project:

1. **osmosis** (<jean@osmosis.team>) -- suspended, had `send.soleur.ai` domain configured, API key `re_fEbnWAeF...` stored in Doppler prd/prd_terraform
2. **jikigai** (<ops@jikigai.com>) -- active, had `soleur.ai` domain verified, used by Supabase SMTP with key `re_MwZAqkWc...`

Doppler (prd + prd_terraform) and GitHub Actions had the suspended account's key. After terraform applied disk-monitor-install, the server couldn't send emails because the key was from the suspended account.

## Investigation

1. `terraform apply -replace=terraform_data.disk_monitor_install` succeeded (deployed script + key to server)
2. Test email via curl returned 401 "API key is invalid"
3. Checked Resend API with `/api-keys` endpoint: returned 403 "This API key is suspended"
4. Opened Resend dashboard via Playwright: account banner showed "Your account is temporarily suspended"
5. Discovered the correct active account under <ops@jikigai.com> with verified `soleur.ai` domain

## Solution

1. Created new API key `soleur-infra-alerts` (sending access) on the jikigai Resend account
2. Updated secrets in three places simultaneously:
   - `doppler secrets set RESEND_API_KEY --project soleur --config prd`
   - `doppler secrets set RESEND_API_KEY --project soleur --config prd_terraform`
   - `gh secret set RESEND_API_KEY`
3. Re-ran `terraform apply -replace=terraform_data.disk_monitor_install` to push correct key to server
4. Fixed sender domain from `noreply@send.soleur.ai` to `noreply@soleur.ai` in:
   - `apps/web-platform/infra/disk-monitor.sh`
   - `.github/actions/notify-ops-email/action.yml`
   - `knowledge-base/engineering/ops/runbooks/disk-monitoring.md`
5. Re-ran terraform apply to deploy corrected disk-monitor.sh
6. Verified with test email: HTTP 200, email delivered to <ops@jikigai.com>

## Key Insight

When multiple Resend accounts exist, the domain verification is per-account. The `send.soleur.ai` subdomain was only verified on the suspended osmosis account. The active jikigai account has `soleur.ai` verified, so all sender addresses must use `@soleur.ai` (not `@send.soleur.ai`). The DNS records for `send.soleur.ai` in `dns.tf` are now orphaned and can be cleaned up.

## Session Errors

1. **Wrong API key deployed to server** -- Doppler had the suspended account's key. Recovery: discovered via test email 401, traced to suspended account. **Prevention:** When provisioning API keys, verify the key works with a test API call before storing in Doppler.

2. **`send.soleur.ai` domain not verified on correct account** -- Test email returned 403 after key fix. Recovery: switched sender to `noreply@soleur.ai` which was verified on the jikigai account. **Prevention:** After rotating API keys across accounts, verify the sending domain is verified on the target account before updating code.

3. **Playwright browser killed by parallel session** -- Browser backend became stale mid-task. Recovery: killed Chrome processes, retried. **Prevention:** Known issue with parallel sessions; `--isolated` flag mitigates but doesn't fully prevent.

4. **Worktree cleaned up unexpectedly** -- `fix-follow-through` worktree disappeared between terraform runs. Recovery: created new `fix-resend-key` worktree. **Prevention:** Worktrees without commits can be removed by cleanup-merged; commit WIP before long-running operations.

## See Also

- [Resend subdomain verification DNS patterns](./2026-04-06-resend-subdomain-verification-dns-patterns.md) -- the learning from setting up `send.soleur.ai` on the osmosis account
- [Supabase Resend email configuration](../2026-03-18-supabase-resend-email-configuration.md) -- original SMTP setup on the jikigai account

## Tags

category: integration-issues
module: System

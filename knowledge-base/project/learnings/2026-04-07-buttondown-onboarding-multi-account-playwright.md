---
module: System
date: 2026-04-07
problem_type: integration_issue
component: service_object
symptoms:
  - "Google OAuth Playwright login landed on wrong Buttondown account (personal vs business)"
  - "Doppler auth token expired mid-session requiring manual re-authentication"
root_cause: config_error
resolution_type: config_change
severity: medium
tags: [buttondown, playwright, oauth, multi-account, doppler]
---

# Learning: Buttondown Multi-Account Confusion During Playwright Automation

## Problem

When automating Buttondown dashboard tasks via Playwright, Google OAuth login with `jean.deruelle@jikigai.com` landed on a personal Buttondown account (username: `deruelle`) instead of the Soleur Newsletter business account (username: `soleur`, email: `ops@jikigai.com`). The API key in Doppler was for the business account, creating a mismatch between API operations (correct account) and Playwright operations (wrong account).

## Solution

1. **Verify account identity before Playwright operations:** Query the API first to confirm which account the API key belongs to: `curl -s -H "Authorization: Token $KEY" https://api.buttondown.com/v1/newsletters | jq '.results[0] | {name, username, email_address}'`
2. **The Soleur Newsletter account uses `ops@jikigai.com`** — it was created with a different email than the founder's personal Google account
3. User manually logged into the correct account after the mismatch was caught

## Key Insight

When a SaaS service has multiple accounts under different emails, Playwright Google OAuth will use the first available Google account — not necessarily the one tied to the target service account. Always verify the logged-in account identity (via API or dashboard UI) before performing configuration operations. The API key acts as the source of truth for which account to target.

## Session Errors

1. **Doppler auth token expired mid-session** — Recovery: User ran `! doppler login -y` to re-authenticate. Prevention: Doppler personal tokens expire; check `doppler whoami` at session start if Doppler commands will be needed.
2. **Wrong Buttondown account via Google OAuth** — Recovery: Logged out, user manually logged into correct account. Prevention: Query the API for account identity before starting Playwright dashboard operations.
3. **Phantom worktree (buttondown-setup)** — Recovery: Ignored, created a new worktree with correct name. Prevention: Verify worktree creation with `git worktree list` immediately after creation.
4. **Playwright browser singleton lock** — Recovery: `pkill -f "chrome.*mcp-chrome"` to kill stale processes. Prevention: Always call `browser_close` before ending Playwright work; `--isolated` flag in `.mcp.json` mitigates but doesn't fully prevent.
5. **Terraform init -backend=false insufficient for plan/apply** — Recovery: Re-ran `terraform init` with R2 backend credentials. Prevention: When running `terraform plan` or `apply` (not just `validate`), always init with full backend credentials.

## See Also

- `knowledge-base/project/learnings/2026-02-26-cla-system-implementation-and-gdpr-compliance.md` — Similar "wrong account" pattern with GitHub gist creation

## Tags

category: integration-issues
module: System

---
module: System
date: 2026-04-03
problem_type: integration_issue
component: authentication
symptoms:
  - "GitHub OAuth consent screen shows raw Supabase URL (ifsccnjhymdmidffkzhl.supabase.co) as redirect destination"
  - "Exposes internal infrastructure URL to users during sign-in"
root_cause: config_error
resolution_type: config_change
severity: medium
tags: [supabase, custom-domain, oauth, github, google, dns, terraform, branding]
---

# Learning: Supabase Custom Domain Setup for Branded OAuth Callbacks

## Problem

The GitHub OAuth consent screen displayed `https://ifsccnjhymdmidffkzhl.supabase.co` as the redirect URL, exposing internal infrastructure to users and eroding trust during sign-in. The same issue affected Google OAuth.

## Solution

1. **Upgraded Supabase to Pro plan** ($25/mo) and enabled the Custom Domain add-on ($10/mo)
2. **Added DNS records in Terraform** (`apps/web-platform/infra/dns.tf`):
   - CNAME: `api.soleur.ai` -> `ifsccnjhymdmidffkzhl.supabase.co` (NOT proxied -- Supabase needs direct DNS for SSL)
   - TXT: `_acme-challenge.api.soleur.ai` with value from `supabase domains create` output
3. **Created and verified custom domain** via Supabase CLI (`supabase domains create`, `reverify`, `activate`)
4. **Updated OAuth provider callback URLs** BEFORE activating the custom domain (critical ordering)
5. **Updated Doppler** `NEXT_PUBLIC_SUPABASE_URL` to `https://api.soleur.ai`

## Key Insight

- **Supabase custom domains require Pro plan + separate add-on** -- enable the add-on via dashboard before running CLI commands
- **DNS requires TWO records** (CNAME + ACME challenge TXT), not just CNAME -- the TXT value is dynamic from `supabase domains create`
- **OAuth provider callbacks must be updated BEFORE domain activation** -- after activation, Supabase advertises the custom domain, and providers reject unknown callback URLs
- **CNAME must NOT be proxied** through Cloudflare -- Supabase needs direct DNS for SSL certificate verification
- **`uri_allow_list` is for redirect destinations, not callback sources** -- adding the API domain to `uri_allow_list` is unnecessary and widens the redirect surface
- **CSP auto-adapts** -- `lib/csp.ts` dynamically constructs `connect-src` from `NEXT_PUBLIC_SUPABASE_URL`, so no code changes needed
- **Backward compatibility confirmed** -- old Supabase project URL continues working after custom domain activation

## Session Errors

1. **Doppler project flag missing on Terraform apply** -- `doppler run -c prd_terraform` requires `-p soleur`. Recovery: added the flag. **Prevention:** Always use `-p soleur` with `doppler run` in Terraform contexts.

2. **Terraform init with wrong backend** -- `terraform init -backend=false` then `apply` needed `-reconfigure` for real backend. Recovery: re-ran init with correct flags. **Prevention:** When running targeted applies, always init with the real backend from the start.

3. **Terraform init SSO token expired** -- S3 backend init failed because AWS SSO token was stale. Recovery: passed R2 credentials from Doppler through env vars. **Prevention:** Use `doppler run` with explicit `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` export for R2 backend access.

4. **configure-auth.sh missing RESEND_API_KEY** -- Script requires all env vars even for partial updates. Recovery: used direct Supabase API call instead. **Prevention:** For targeted auth config changes, use the Supabase Management API directly rather than the full configure-auth.sh script.

5. **Unnecessary api.soleur.ai in uri_allow_list** -- Plan prescribed adding the API domain to redirect allow list. Recovery: security review caught it; removed the entry. **Prevention:** Understand that `uri_allow_list` controls `redirectTo` destinations, not OAuth callback sources.

6. **Git worktree bare repo conflict** -- `git commit` failed after `cd` into infra dir changed context. Recovery: used explicit `GIT_DIR`/`GIT_WORK_TREE` env vars. **Prevention:** Always `cd` back to the worktree root before git operations, or use `git -C <worktree-path>`.

7. **Supabase custom domain add-on not enabled** -- CLI returned 400 because the add-on needs enabling via dashboard first. Recovery: enabled via Playwright MCP in dashboard. **Prevention:** Enable the Custom Domain add-on in the Supabase dashboard before running `supabase domains create`.

## Tags

category: integration-issues
module: authentication

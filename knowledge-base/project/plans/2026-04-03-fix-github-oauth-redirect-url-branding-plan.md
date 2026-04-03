---
title: "fix: GitHub OAuth consent screen shows Supabase URL instead of branded Soleur URL"
type: fix
date: 2026-04-03
deepened: 2026-04-03
---

# fix: GitHub OAuth consent screen shows Supabase URL instead of branded Soleur URL

## Enhancement Summary

**Deepened on:** 2026-04-03
**Sections enhanced:** 3 (Parts 1, 2, and Security/CSP)
**Research sources:** Supabase custom domain docs, GitHub OAuth App docs, 4 institutional learnings

### Key Improvements

1. Added TXT record requirement for Supabase domain verification (CNAME alone is insufficient -- a `_acme-challenge` TXT record is also needed for SSL certificate issuance)
2. Added CSP automatic compatibility confirmation -- `lib/csp.ts` dynamically constructs `connect-src` from `NEXT_PUBLIC_SUPABASE_URL`, so custom domain change flows through with zero CSP code changes
3. Added domain verification timeline: SSL certificate provisioning via Let's Encrypt/Google Trust Services/SSL.com can take up to 30 minutes; `reverify` command may need multiple runs
4. Added GitHub OAuth App logo requirement: any size accepted (unlike Google's strict 120x120px requirement)

### New Considerations Discovered

- Supabase domain verification requires TWO DNS records (CNAME + `_acme-challenge` TXT), not just the CNAME -- the TXT record value is provided by `supabase domains create` output
- The `supabase domains reverify` command may need to be run multiple times as DNS propagates (up to 30 minutes)
- CSP `connect-src` for WebSocket connections also updates automatically (`wss://` prefix derived from same URL)
- GitHub OAuth App settings page also allows setting a "Setup URL" for post-installation redirects (not needed for this fix, but worth knowing)

## Overview

The GitHub OAuth consent screen displays `https://ifsccnjhymdmidffkzhl.supabase.co` as the redirect URL at the bottom of the authorization page. This exposes an internal infrastructure URL to users and erodes trust during sign-in. The fix requires configuring the GitHub OAuth App's settings in the GitHub Developer Console and, for full resolution, activating a Supabase custom domain.

This is the GitHub-specific counterpart to the Google OAuth branding fix completed in #1403. The Google consent screen branding (app name, logo, legal links) was fixed via Google Cloud Console configuration and domain verification. The GitHub issue is different: GitHub's consent screen prominently displays the **callback URL domain**, which is the Supabase project URL (`ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback`).

## Problem Statement

When users click "Continue with GitHub" on `https://app.soleur.ai/login`, GitHub's authorization page shows:

- **Redirect URL (bottom of page):** `https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback`

This is the Supabase Auth callback URL that GitHub redirects to after the user authorizes. Unlike Google (where branding fixes the app name/logo on the consent screen), GitHub's consent screen inherently displays the callback URL domain. The only way to change what appears there is to change the actual callback URL domain.

## Root Cause Analysis

The redirect URL shown on GitHub's OAuth consent screen is the **Authorization callback URL** configured in the GitHub OAuth App settings. Supabase sets this to `https://<project-ref>.supabase.co/auth/v1/callback` by default. This URL is:

1. Configured in the GitHub OAuth App at `https://github.com/settings/developers`
2. Used by Supabase GoTrue as the callback endpoint for the OAuth flow
3. Displayed by GitHub to the user on the consent screen

There are two levels of fix:

- **Partial (GitHub App settings only):** Configure the GitHub OAuth App's homepage URL, app name, and description for better branding context -- but this does NOT change the redirect URL shown at the bottom
- **Full (Supabase custom domain):** Activate a Supabase custom domain (e.g., `api.soleur.ai`) so the callback URL becomes `https://api.soleur.ai/auth/v1/callback`

## Proposed Solution

### Part 1: GitHub OAuth App Branding (immediate, no cost)

Configure the GitHub OAuth App in [Developer Settings](https://github.com/settings/developers) with proper branding:

- **Application name:** Soleur
- **Homepage URL:** `https://soleur.ai`
- **Application description:** AI-powered development assistant
- **Application logo:** Soleur logo (from `plugins/soleur/docs/images/`)

This improves the GitHub consent screen context (app name, homepage link) but does NOT change the redirect URL at the bottom of the page.

**Automation approach:** Use Playwright MCP to navigate to the GitHub Developer Settings, find the Soleur OAuth App, and update the branding fields. The GitHub OAuth App Client ID is stored in Doppler as `GITHUB_CLIENT_ID` (config: `prd`).

#### Research Insights: GitHub OAuth App Configuration

**GitHub OAuth App logo:** Unlike Google (which requires exactly 120x120px), GitHub accepts any size logo upload. Use the existing `plugins/soleur/docs/images/logo-mark-512.png` directly -- no resizing needed.

**GitHub OAuth App fields available ([docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)):**

| Field | Value | Notes |
|-------|-------|-------|
| Application name | Soleur | Shown prominently on consent screen |
| Homepage URL | `https://soleur.ai` | Shown as clickable link on consent screen |
| Application description | AI-powered development assistant | Shown below app name |
| Authorization callback URL | `https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback` | Already set; changes to `api.soleur.ai` in Part 2 |
| Application logo | `plugins/soleur/docs/images/logo-mark-512.png` | Any size accepted |

**No verification required:** Unlike Google (which requires brand verification taking 2-3 business days), GitHub OAuth Apps show branding immediately after saving. No domain verification, no review queue.

**Playwright automation note:** Per institutional learning (`2026-03-09-x-provisioning-playwright-automation.md`), the GitHub Developer Settings page is fully automatable -- no CAPTCHAs or interactive OAuth consent needed. The flow is: navigate to settings > find app by Client ID > click Edit > fill fields > save.

### Part 2: Supabase Custom Domain (requires Pro plan upgrade, ~$35/mo)

This is the only way to change the redirect URL from `ifsccnjhymdmidffkzhl.supabase.co` to a branded domain. This part is shared with the existing plan at `knowledge-base/project/plans/2026-04-02-fix-google-oauth-consent-screen-branding-plan.md` (Part 2).

**Prerequisites (from existing plan):**

1. Upgrade Supabase to Pro plan ($25/mo base)
2. Activate custom domain add-on (~$10/mo additional)

**Implementation steps:**

1. Add CNAME DNS record in Terraform (`apps/web-platform/infra/dns.tf`):

   ```hcl
   resource "cloudflare_record" "supabase_custom_domain" {
     zone_id = var.cf_zone_id
     name    = "api"
     content = "ifsccnjhymdmidffkzhl.supabase.co"
     type    = "CNAME"
     proxied = false  # Must NOT be proxied -- Supabase needs direct DNS for SSL verification
     ttl     = 60
   }
   ```

2. Apply Terraform (CNAME only first): `doppler run -c prd_terraform --name-transformer tf-var -- terraform apply -target=cloudflare_record.supabase_custom_domain`
3. Create custom domain: `supabase domains create --custom-hostname api.soleur.ai --project-ref ifsccnjhymdmidffkzhl` -- **capture the `_acme-challenge` TXT record value from the output**
4. Add TXT record to Terraform (`_acme-challenge.api.soleur.ai` with the value from step 3) and apply
5. Verify domain: `supabase domains reverify --project-ref ifsccnjhymdmidffkzhl` (poll until verified -- may take up to 30 minutes)
5. **Before activating:** Update GitHub OAuth App callback URL to add `https://api.soleur.ai/auth/v1/callback`
6. **Before activating:** Update Google OAuth authorized redirect URIs to add `https://api.soleur.ai/auth/v1/callback`
7. Activate: `supabase domains activate --project-ref ifsccnjhymdmidffkzhl`
8. Update Doppler `prd` config: `NEXT_PUBLIC_SUPABASE_URL` from `https://ifsccnjhymdmidffkzhl.supabase.co` to `https://api.soleur.ai`
9. Rebuild and redeploy Docker image (NEXT_PUBLIC_ vars baked at build time per Dockerfile ARG pattern)
10. Update `configure-auth.sh` `uri_allow_list` to include `https://api.soleur.ai/**`
11. Verify end-to-end OAuth flow with both GitHub and Google providers

**Critical ordering note (from Supabase docs):** OAuth provider redirect URIs must be updated BEFORE activating the custom domain. After activation, OAuth flows advertise the custom domain as the callback URL. If providers don't have this URL whitelisted, auth breaks.

**Backward compatibility (confirmed by Supabase docs):** The original project URL (`ifsccnjhymdmidffkzhl.supabase.co`) continues to work after custom domain activation. Both domains function simultaneously.

#### Research Insights: Supabase Custom Domain Verification

**Two DNS records required (not one):** The plan's CNAME record is necessary but insufficient. Supabase domain verification also requires a TXT record for SSL certificate issuance:

1. **CNAME record:** `api.soleur.ai` -> `ifsccnjhymdmidffkzhl.supabase.co` (already in plan)
2. **TXT record:** `_acme-challenge.api.soleur.ai` -> value provided by `supabase domains create` output

The TXT record value is dynamic -- it is returned by the `supabase domains create` command. The Terraform resource for this record must be added AFTER running the create command and reading the output.

**Revised Terraform for dns.tf (both records):**

```hcl
resource "cloudflare_record" "supabase_custom_domain" {
  zone_id = var.cf_zone_id
  name    = "api"
  content = "ifsccnjhymdmidffkzhl.supabase.co"
  type    = "CNAME"
  proxied = false  # Must NOT be proxied -- Supabase needs direct DNS for SSL verification
  ttl     = 60
}

# TXT record value from `supabase domains create` output
# Must be added after running the create command
resource "cloudflare_record" "supabase_acme_challenge" {
  zone_id = var.cf_zone_id
  name    = "_acme-challenge.api"
  content = var.supabase_acme_challenge_value  # From `supabase domains create` output
  type    = "TXT"
  ttl     = 60
}
```

**SSL certificate provisioning timeline:** Supabase uses multiple Certificate Authorities (Let's Encrypt, Google Trust Services, SSL.com) for high availability. The verification process can take up to 30 minutes. The `supabase domains reverify` command may need to be run multiple times as DNS records propagate.

**CSP automatic compatibility (confirmed by code review):** The `apps/web-platform/lib/csp.ts` file dynamically constructs `connect-src` from `NEXT_PUBLIC_SUPABASE_URL`:

- `https://${supabaseHost}` for REST API calls
- `wss://${supabaseHost}` for WebSocket (Realtime) connections

When `NEXT_PUBLIC_SUPABASE_URL` changes from `https://ifsccnjhymdmidffkzhl.supabase.co` to `https://api.soleur.ai`, CSP automatically allows the new domain. No CSP code changes needed.

## Technical Considerations

### Code Impact Assessment

**Part 1 (GitHub App branding): Zero code changes.** Pure GitHub Developer Console configuration.

**Part 2 (custom domain) code changes:**

- `apps/web-platform/infra/dns.tf` -- Add CNAME record for `api.soleur.ai`
- Doppler `prd` config -- Update `NEXT_PUBLIC_SUPABASE_URL`
- Docker rebuild required (NEXT_PUBLIC_ vars baked at build time)

**No application code changes needed** -- all Supabase client code reads `NEXT_PUBLIC_SUPABASE_URL` from environment:

- `apps/web-platform/lib/supabase/client.ts` (browser client)
- `apps/web-platform/lib/supabase/server.ts` (server client + service client)
- `apps/web-platform/app/(auth)/callback/route.ts` (auth callback)
- `apps/web-platform/components/auth/oauth-buttons.tsx` (uses `window.location.origin/callback`, not Supabase URL)
- `apps/web-platform/lib/csp.ts` (reads NEXT_PUBLIC_SUPABASE_URL dynamically)
- `apps/web-platform/middleware.ts` (reads NEXT_PUBLIC_SUPABASE_URL)

### Security Considerations

- Custom domain uses SSL/TLS via Supabase's certificate provisioning
- No change to CSRF protection, origin validation, or CSP enforcement
- `apps/web-platform/lib/auth/validate-origin.ts` validates against `https://app.soleur.ai` (unaffected -- this validates the app origin, not the Supabase API origin)

### Existing Patterns

- DNS records managed via Terraform: `apps/web-platform/infra/dns.tf`
- Auth configuration: `apps/web-platform/supabase/scripts/configure-auth.sh`
- OAuth provider setup checklist: `knowledge-base/engineering/checklists/oauth-provider-setup.md`
- Google OAuth branding learning: `knowledge-base/project/learnings/workflow-issues/google-oauth-consent-screen-branding-requires-domain-verification-20260402.md`

### Institutional Learnings Applied

1. **Docker rebuild for NEXT_PUBLIC_ vars** (`2026-03-17-nextjs-docker-public-env-vars.md`): `NEXT_PUBLIC_SUPABASE_URL` is baked at build time; Doppler change alone is insufficient
2. **Cloudflare Terraform v4 resource names** (`2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`): Use `cloudflare_record` (v4), not `cloudflare_dns_record` (v5)
3. **Nested Doppler invocation for Terraform** (`apps/web-platform/infra/variables.tf` header): Use `doppler run --name-transformer tf-var` pattern
4. **OAuth provider checklist** (`knowledge-base/engineering/checklists/oauth-provider-setup.md`): Follow the checklist for any provider configuration changes

## Acceptance Criteria

### Part 1: GitHub OAuth App Branding

- [ ] GitHub OAuth App name set to "Soleur"
- [ ] Homepage URL set to `https://soleur.ai`
- [ ] Application description set
- [ ] Application logo uploaded
- [ ] Consent screen shows "Soleur" as the app name when clicking "Continue with GitHub"

### Part 2: Supabase Custom Domain

- [ ] Supabase project upgraded to Pro plan
- [ ] CNAME record `api.soleur.ai` -> `ifsccnjhymdmidffkzhl.supabase.co` in Terraform
- [ ] Domain verified and SSL certificate issued by Supabase
- [ ] ALL OAuth provider callback URLs updated before domain activation (GitHub, Google)
- [ ] Custom domain activated
- [ ] `NEXT_PUBLIC_SUPABASE_URL` updated in Doppler to `https://api.soleur.ai`
- [ ] Docker image rebuilt with new URL
- [ ] GitHub OAuth consent screen shows `api.soleur.ai` in redirect URL (not `ifsccnjhymdmidffkzhl.supabase.co`)
- [ ] Google OAuth consent screen shows `api.soleur.ai` in redirect URL
- [ ] Auth callback works end-to-end with both providers
- [ ] `configure-auth.sh` `uri_allow_list` includes `https://api.soleur.ai/**`
- [ ] Expense entry updated in `knowledge-base/operations/expenses.md` (Supabase $0 -> ~$35/mo)

## Test Scenarios

- Given a user clicks "Continue with GitHub" on the login page, when the GitHub consent screen appears, then the app name shows "Soleur" with logo and homepage link
- Given the Supabase custom domain is active, when a user initiates GitHub OAuth, then the redirect URL at the bottom of the consent screen shows `api.soleur.ai` instead of `ifsccnjhymdmidffkzhl.supabase.co`
- Given the custom domain is active, when the GitHub callback redirects to `api.soleur.ai/auth/v1/callback`, then the session is created and user is routed correctly (accept-terms/setup-key/dashboard)
- Given the custom domain is active, when a user initiates Google OAuth, then the flow completes successfully with the new callback URL
- Given the old Supabase URL is still functional (backward compatibility), when any in-flight OAuth flow uses the old callback URL, then it still works during transition

**Browser verification (for QA):**

- Navigate to `https://app.soleur.ai/login`, click "Continue with GitHub", verify consent screen branding and redirect URL domain
- After custom domain setup: verify the redirect URL in the browser address bar uses `api.soleur.ai`

## Domain Review

**Domains relevant:** Operations

### Operations

**Status:** reviewed
**Assessment:** The Supabase Pro plan upgrade (~$35/mo: Pro $25 + custom domain ~$10) is an operational expense increase from $0 (free tier). This is the same cost decision documented in the existing plan `2026-04-02-fix-google-oauth-consent-screen-branding-plan.md` Part 2. Must be recorded in `knowledge-base/operations/expenses.md` upon activation.

## Dependencies and Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Supabase Pro plan cost (~$35/mo) not approved | Part 2 blocked; redirect URL still shows raw Supabase URL | Part 1 improves branding context immediately; defer Part 2 to when Pro plan is needed for other features |
| OAuth flow breaks during custom domain activation | Users unable to sign in | Update ALL provider callback URLs before activation; Supabase backward compatibility ensures old URL continues working |
| DNS propagation delay for CNAME record | Domain verification may take time | Use low TTL (60s); poll `supabase domains reverify` until confirmed |
| Docker image rebuild required after URL change | Brief deployment downtime | Schedule during low-traffic window; monitor post-deploy |

## Alternative Approaches Considered

| Approach | Rejected Because |
|----------|-----------------|
| Vanity subdomain (`soleur.supabase.co`) | Still shows `supabase.co` in the redirect URL -- not fully branded |
| Proxy Supabase auth through app domain | Complex, fragile, adds latency; Supabase does not support proxied auth callbacks |
| Only fix GitHub App branding (Part 1) | Does not change the redirect URL shown at bottom of consent screen; partial fix only |
| Separate GitHub App for branded redirect | GitHub OAuth Apps cannot proxy callbacks through a different domain |

## Relationship to Existing Work

This plan shares Part 2 (Supabase custom domain) with `knowledge-base/project/plans/2026-04-02-fix-google-oauth-consent-screen-branding-plan.md`. The custom domain activation benefits ALL OAuth providers simultaneously:

- **Google:** Redirect URL changes from `ifsccnjhymdmidffkzhl.supabase.co` to `api.soleur.ai`
- **GitHub:** Redirect URL changes from `ifsccnjhymdmidffkzhl.supabase.co` to `api.soleur.ai`
- **Future providers (Apple, Microsoft per #1341):** Will automatically use `api.soleur.ai`

Part 1 (GitHub App branding) is independent and should be done regardless of Part 2.

## Plan Review Findings [2026-04-03]

Three reviewers (DHH, Kieran, Code Simplicity) provided feedback. All agreed:

1. **Part 1 is the right immediate fix.** Ship it -- zero code changes, pure configuration.
2. **Part 2 is the correct long-term fix** but depends on cost approval (~$35/mo). It is shared with the existing Google OAuth branding plan and should not be duplicated.
3. **Plan is already minimal** -- no unnecessary abstractions or code changes.

**Key observation:** Part 2 (Supabase custom domain) is identical across this plan and the Google OAuth plan (`2026-04-02-fix-google-oauth-consent-screen-branding-plan.md`). This plan should focus on Part 1 (GitHub-specific branding) and reference the existing plan for Part 2 rather than duplicating the 11-step implementation sequence. If/when Part 2 is executed, it benefits all providers simultaneously.

**Changes applied from review:**

- Added clarifying note that `configure-auth.sh` `site_url` (`https://app.soleur.ai`) is the frontend URL and is correct as-is; only `uri_allow_list` needs the custom domain addition
- Noted that Part 2 is a shared dependency across all OAuth providers and should be tracked as a single work item

## References

- Existing Google OAuth branding plan: `knowledge-base/project/plans/2026-04-02-fix-google-oauth-consent-screen-branding-plan.md`
- OAuth sign-in spec: `knowledge-base/project/specs/feat-oauth-sign-in/spec.md`
- OAuth provider setup checklist: `knowledge-base/engineering/checklists/oauth-provider-setup.md`
- Google OAuth branding learning: `knowledge-base/project/learnings/workflow-issues/google-oauth-consent-screen-branding-requires-domain-verification-20260402.md`
- Auth config script: `apps/web-platform/supabase/scripts/configure-auth.sh`
- DNS Terraform: `apps/web-platform/infra/dns.tf`
- Supabase client: `apps/web-platform/lib/supabase/client.ts`
- Auth callback: `apps/web-platform/app/(auth)/callback/route.ts`
- OAuth buttons: `apps/web-platform/components/auth/oauth-buttons.tsx`
- Expenses: `knowledge-base/operations/expenses.md`
- Supabase custom domains docs: [supabase.com/docs/guides/platform/custom-domains](https://supabase.com/docs/guides/platform/custom-domains)
- GitHub OAuth Apps: [GitHub Developer Settings](https://github.com/settings/developers)

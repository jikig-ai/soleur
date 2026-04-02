---
title: "fix: Google OAuth consent screen branding and redirect URL"
type: fix
date: 2026-04-02
---

# fix: Google OAuth consent screen branding and redirect URL

## Overview

The Google OAuth consent screen displays "Sign in to ifsccnjhymdmidffkzhl.supabase.co" instead of "soleur.ai". Two root causes: (1) the Google Cloud OAuth consent screen was never configured with app branding (name, logo, domain, privacy/ToS URLs), and (2) the Supabase auth redirect URL uses the raw project URL because no custom domain or vanity subdomain is configured.

This is a follow-up to the OAuth sign-in implementation (#1211) where "Custom branding of provider consent screens" was explicitly listed as a Non-Goal in `knowledge-base/project/specs/feat-oauth-sign-in/spec.md`. The learning in `knowledge-base/project/learnings/2026-03-30-pkce-magic-link-same-browser-context.md` documents that OAuth providers were configured via Playwright MCP but branding was not addressed.

## Problem Statement

When users click "Continue with Google" on the Soleur login page, the Google consent screen shows:

- **App name:** The raw Supabase project ref or default
- **Redirect URL domain:** `ifsccnjhymdmidffkzhl.supabase.co`
- **No logo, no privacy policy link, no ToS link**

This erodes user trust and looks unprofessional. Users see an unfamiliar domain and may hesitate to authorize.

## Proposed Solution

Two-part fix with different dependency chains:

### Part 1: Google OAuth Consent Screen Branding (immediate, no cost)

Configure the Google Cloud Console OAuth consent screen with proper branding:

- **App name:** Soleur
- **App logo:** Soleur logo (from `plugins/soleur/docs/images/` or brand assets)
- **Application home page:** `https://soleur.ai`
- **Authorized domains:** `soleur.ai`
- **Privacy policy URL:** `https://soleur.ai/pages/legal/privacy-policy.html`
- **Terms of service URL:** `https://soleur.ai/pages/legal/terms-and-conditions.html`

This immediately improves the consent screen to show "Soleur" instead of the cryptic project ref.

**Automation approach:** Use Playwright MCP to navigate to Google Cloud Console > APIs & Services > OAuth consent screen and configure these fields. The Google Cloud project number is `972366012527` (extracted from the client ID `972366012527-drkik8tidmfidprooi8kguqmdjcguik6.apps.googleusercontent.com`). If the consent screen requires Google verification for external publishing (which requires domain verification), drive up to that point and hand off to the user for the verification step only.

**Verification status check:** Before configuring branding, check the current OAuth app publishing status (testing vs production) and verification state. If the app is unverified in production mode, Google shows a scary "This app isn't verified" warning. If in testing mode, only test users can sign in. Document the current state and submit for verification if needed (verification can take weeks).

### Part 2: Supabase Custom Domain (requires plan upgrade)

**Blocker discovered during research:** Both Supabase custom domains and vanity subdomains require the **Pro plan** ($25/mo). The Supabase project `ifsccnjhymdmidffkzhl` is currently on the **free tier** (confirmed via `knowledge-base/operations/expenses.md` and API response: "upgrade your plan to access this feature").

**Decision required:** Upgrade to Supabase Pro ($25/mo) to enable a custom domain. Two options:

| Option | Domain | Cost | Complexity |
|--------|--------|------|-----------|
| Vanity subdomain | `soleur.supabase.co` | $25/mo (Pro plan) | Low -- CLI command only |
| Custom domain | `api.soleur.ai` (or `auth.soleur.ai`) | $25/mo (Pro plan) | Medium -- CNAME + TXT DNS records + SSL verification |

**Recommended:** Custom domain (`api.soleur.ai`) because it fully brands the auth redirect URL under `soleur.ai`. Vanity subdomain still shows `supabase.co`.

**If custom domain is chosen, implementation steps:**

1. Upgrade Supabase to Pro plan via dashboard (Playwright MCP automation up to payment step, then manual payment)
2. Add CNAME DNS record in Terraform (`apps/web-platform/infra/dns.tf`): `api.soleur.ai` -> `ifsccnjhymdmidffkzhl.supabase.co`
3. Add TXT record for domain verification (provided by Supabase after CNAME creation)
4. Run `supabase domains create --custom-hostname api.soleur.ai --project-ref ifsccnjhymdmidffkzhl`
5. Run `supabase domains reverify --project-ref ifsccnjhymdmidffkzhl` until verified
6. Update `NEXT_PUBLIC_SUPABASE_URL` in Doppler `prd` config from `https://ifsccnjhymdmidffkzhl.supabase.co` to `https://api.soleur.ai`
7. Rebuild and redeploy Docker image (NEXT_PUBLIC_ vars are baked at build time per `.env.example`)
8. Update `configure-auth.sh` `uri_allow_list` if needed
9. Update ALL OAuth providers' authorized redirect URIs to use `api.soleur.ai` (Google and GitHub currently enabled; Apple and Microsoft tracked in #1341)
10. Verify Supabase custom domain auto-updates the auth callback URL used during OAuth flows, or manually update via Management API

### Part 3: OAuth Setup Checklist (documentation/workflow improvement)

Add an OAuth provider setup checklist to prevent branding gaps when adding future providers. Two deliverables:

1. **Checklist document:** `knowledge-base/engineering/checklists/oauth-provider-setup.md` covering:
   - Provider developer console setup (app name, logo, domains)
   - Consent screen branding configuration
   - Privacy policy and ToS URL configuration
   - Redirect URI configuration
   - Credential storage in Doppler
   - Supabase provider enablement via `configure-auth.sh`
   - Post-setup verification (test sign-in flow end-to-end)

~~2. **Enhancement to `configure-auth.sh`:** Removed per review -- the script runs rarely and a checklist document is sufficient. Adding programmatic consent screen verification would be fragile (no simple API) and YAGNI.~~

## Technical Considerations

### Code Impact Assessment

**No code changes required for Part 1.** The Google OAuth consent screen branding is purely a Google Cloud Console configuration.

**Part 2 code changes (if custom domain):**

- `apps/web-platform/infra/dns.tf` -- Add CNAME record for `api.soleur.ai`
- Doppler `prd` config -- Update `NEXT_PUBLIC_SUPABASE_URL`
- Docker rebuild required (NEXT_PUBLIC_ vars baked at build time)
- `apps/web-platform/lib/csp.ts` -- No change needed (reads NEXT_PUBLIC_SUPABASE_URL dynamically)
- `apps/web-platform/lib/supabase/client.ts` -- No change needed (reads NEXT_PUBLIC_SUPABASE_URL)
- `apps/web-platform/lib/supabase/server.ts` -- No change needed (reads NEXT_PUBLIC_SUPABASE_URL)
- `apps/web-platform/middleware.ts` -- No change needed (reads NEXT_PUBLIC_SUPABASE_URL)
- `apps/web-platform/app/(auth)/callback/route.ts` -- No change needed
- `apps/web-platform/components/auth/oauth-buttons.tsx` -- No change needed (uses `window.location.origin/callback`, not Supabase URL)

**Part 3 code changes:**

- New file: `knowledge-base/engineering/checklists/oauth-provider-setup.md`

### Security Considerations

- Supabase custom domain uses SSL/TLS via Supabase's certificate provisioning (Let's Encrypt / Google Trust Services)
- No change to CSRF protection, origin validation, or CSP enforcement
- Google OAuth consent screen verification may be required for production apps with >100 users

### Existing Patterns

- DNS records managed via Terraform in `apps/web-platform/infra/dns.tf`
- Auth configuration script in `apps/web-platform/supabase/scripts/configure-auth.sh`
- Origin validation in `apps/web-platform/lib/auth/validate-origin.ts` (allows `https://app.soleur.ai`)
- Learnings about OAuth configuration gaps in `knowledge-base/project/learnings/2026-03-30-pkce-magic-link-same-browser-context.md`

## Acceptance Criteria

### Part 1: Google OAuth Consent Screen

- [ ] Google OAuth consent screen shows "Soleur" as app name
- [ ] Consent screen displays Soleur logo
- [ ] Privacy policy link points to `https://soleur.ai/pages/legal/privacy-policy.html`
- [ ] Terms of service link points to `https://soleur.ai/pages/legal/terms-and-conditions.html`
- [ ] Authorized domains include `soleur.ai`
- [ ] Application home page set to `https://soleur.ai`
- [ ] OAuth app publishing status checked and verification submitted if needed

### Part 2: Supabase Custom Domain (conditional on plan upgrade)

- [ ] Supabase project upgraded to Pro plan
- [ ] CNAME record `api.soleur.ai` -> `ifsccnjhymdmidffkzhl.supabase.co` in Terraform
- [ ] Domain verified and SSL certificate issued
- [ ] `NEXT_PUBLIC_SUPABASE_URL` updated in Doppler to `https://api.soleur.ai`
- [ ] Docker image rebuilt with new URL
- [ ] Auth callback works end-to-end with new domain
- [ ] ALL OAuth provider redirect URIs updated (Google, GitHub; Apple/Microsoft per #1341)
- [ ] Supabase auth callback URL verified or updated for custom domain
- [ ] Expense entry updated in `knowledge-base/operations/expenses.md` ($0 -> $25/mo)

### Part 3: OAuth Setup Checklist

- [ ] Checklist document created at `knowledge-base/engineering/checklists/oauth-provider-setup.md`
- [ ] Covers all 4 current providers (Google, Apple, GitHub, Microsoft)
- [ ] Includes consent screen branding as a required step
- [ ] Includes post-setup verification steps with provider console URLs

## Test Scenarios

- Given a user clicks "Continue with Google" on the login page, when the Google consent screen appears, then it shows "Soleur" as the app name with logo and legal links
- Given the Supabase custom domain is configured (Part 2), when a user initiates OAuth, then the redirect URL uses `api.soleur.ai` instead of `ifsccnjhymdmidffkzhl.supabase.co`
- Given the custom domain is active, when the callback route exchanges the code, then the session is created successfully
- Given `configure-auth.sh` is run for a new provider, when it completes, then it outputs a branding verification checklist

**Browser verification (for QA):**

- Navigate to `https://app.soleur.ai/login`, click "Continue with Google", verify consent screen branding
- After custom domain setup: verify the redirect URL in the browser address bar uses `api.soleur.ai`

## Domain Review

**Domains relevant:** Operations, Legal

### Operations

**Status:** reviewed
**Assessment:** The Supabase Pro plan upgrade ($25/mo) is an operational expense that must be recorded in `knowledge-base/operations/expenses.md`. The current entry shows $0 free-tier. This is the first paid Supabase expense. The upgrade decision should factor into the monthly cloud spend budget.

### Legal

**Status:** reviewed
**Assessment:** No new legal implications. Privacy policy and ToS URLs are already published and will be linked from the consent screen. The Google OAuth consent screen verification process may require domain verification, which is an administrative step, not a legal one. No changes to data processing or user consent flows.

## Dependencies and Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Google consent screen verification required for >100 users | Delays branding visibility to unverified state | Submit for verification early; branding still shows for <100 users |
| Supabase Pro plan cost ($25/mo) may not be approved | Part 2 blocked; consent screen still shows raw URL | Part 1 fixes app name/logo immediately; defer Part 2 |
| DNS propagation delay for custom domain | Temporary auth downtime if URL switched before propagation | Use Supabase `domains reverify` to confirm before switching URL |
| Docker image rebuild required | Brief deployment downtime | Schedule during low-traffic window |

## Alternative Approaches Considered

| Approach | Rejected Because |
|----------|-----------------|
| Vanity subdomain (`soleur.supabase.co`) | Still shows `supabase.co` in the redirect URL -- not fully branded |
| Proxy Supabase auth through app domain | Complex, fragile, adds latency, and Supabase doesn't support it |
| Do nothing (just fix consent screen name) | Redirect URL still shows cryptic `ifsccnjhymdmidffkzhl.supabase.co` |

## Plan Review Findings [Updated 2026-04-02]

Three reviewers (DHH, Kieran, Code Simplicity) provided feedback. All agreed:

1. **Part 1 is the right fix.** Ship immediately -- zero code changes, high impact.
2. **Part 2 should be deferred** unless Supabase Pro is needed for other reasons. The redirect URL is a minor trust signal compared to the consent screen app name.
3. **Part 3 simplified** to just the checklist document. Dropped `configure-auth.sh` enhancement (YAGNI -- script runs rarely, checklist is sufficient).

**Changes applied from review:**

- Added Google OAuth app verification status check to Part 1
- Changed Part 2 step 9 to cover ALL OAuth providers' redirect URIs (not just Google)
- Added Part 2 step 10 to verify Supabase custom domain auto-updates auth callback URLs
- Removed `configure-auth.sh` enhancement from Part 3
- Added verification status acceptance criterion to Part 1

## References

- OAuth sign-in spec: `knowledge-base/project/specs/feat-oauth-sign-in/spec.md` (Non-Goals: "Custom branding of provider consent screens")
- PKCE/OAuth learning: `knowledge-base/project/learnings/2026-03-30-pkce-magic-link-same-browser-context.md`
- Auth config script: `apps/web-platform/supabase/scripts/configure-auth.sh`
- DNS Terraform: `apps/web-platform/infra/dns.tf`
- CSP config: `apps/web-platform/lib/csp.ts`
- Supabase client: `apps/web-platform/lib/supabase/client.ts`
- Auth callback: `apps/web-platform/app/(auth)/callback/route.ts`
- OAuth buttons: `apps/web-platform/components/auth/oauth-buttons.tsx`
- Expenses: `knowledge-base/operations/expenses.md` (Supabase free tier entry)
- Supabase custom domains docs: [supabase.com/docs/guides/platform/custom-domains](https://supabase.com/docs/guides/platform/custom-domains)
- Google OAuth consent screen: [Google Cloud Console APIs & Services](https://console.cloud.google.com/apis/credentials/consent)

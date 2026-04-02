---
title: "fix: Google OAuth consent screen branding and redirect URL"
type: fix
date: 2026-04-02
deepened: 2026-04-02
---

# fix: Google OAuth consent screen branding and redirect URL

## Enhancement Summary

**Deepened on:** 2026-04-02
**Sections enhanced:** 3 (Parts 1, 2, 3)
**Research sources:** Google OAuth docs, Supabase custom domains docs, Supabase pricing, 4 institutional learnings

### Key Improvements

1. Added exact Google logo requirements (120x120px, square, JPG/PNG/BMP, under 1MB) and brand verification timeline (2-3 business days)
2. Corrected Supabase custom domain pricing: Pro plan ($25/mo) PLUS custom domain add-on (~$10/mo billed hourly) = ~$35/mo total
3. Added critical migration ordering: OAuth providers must be updated BEFORE domain activation
4. Added backward compatibility finding: old Supabase URL continues to work after custom domain activation

### New Considerations Discovered

- Google brand verification is separate from app verification -- brand verification takes 2-3 days, app verification can take weeks
- Supabase custom domain is billed by the hour as a separate add-on, not included in Pro plan base price
- Existing Supabase project URL remains functional after custom domain activation (no forced cutover)
- Only subdomains supported for Supabase custom domains, not root domains

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

#### Research Insights: Google OAuth Consent Screen

**Logo requirements ([Google Cloud docs](https://support.google.com/cloud/answer/15549049)):**

- Size: 120x120px (square) for best display
- Format: JPG, PNG, or BMP
- Max file size: 1MB
- The existing `plugins/soleur/docs/images/logo-mark-512.png` must be resized to 120x120px before upload

**Brand verification vs app verification -- two separate processes:**

- **Brand verification** (app name + logo visible on consent screen): Takes 2-3 business days. Required for any external-user app that wants its name and logo to appear. Without it, users see a generic consent screen.
- **App verification** (remove "unverified app" warning): Required for apps requesting sensitive or restricted scopes, or for apps with >100 users. Can take weeks. Soleur only requests `email` and `profile` scopes (non-sensitive), so app verification may not be required.

**Playwright automation pattern:** Per institutional learning (`2026-03-09-x-provisioning-playwright-automation.md`), use Playwright MCP to automate mechanical steps (navigation, form filling, file uploads) and pause for human input only on security-sensitive steps. The Google Cloud Console consent screen configuration is entirely mechanical -- no passwords or verification codes needed -- so full automation is feasible.

**Scopes assessment:** Soleur requests only `openid`, `email`, and `profile` (default Supabase Google provider scopes). These are non-sensitive scopes per [Google's OAuth 2.0 policies](https://developers.google.com/identity/protocols/oauth2/policies), meaning:

- No security assessment required
- No restricted scope justification
- Brand verification alone is sufficient

### Part 2: Supabase Custom Domain (requires plan upgrade)

**Blocker discovered during research:** Both Supabase custom domains and vanity subdomains require the **Pro plan** ($25/mo). The Supabase project `ifsccnjhymdmidffkzhl` is currently on the **free tier** (confirmed via `knowledge-base/operations/expenses.md` and API response: "upgrade your plan to access this feature").

**Decision required:** Upgrade to Supabase Pro ($25/mo) to enable a custom domain. Two options:

~~Original cost estimate table superseded by corrected pricing above.~~

**Recommended:** Custom domain (`api.soleur.ai`) because it fully brands the auth redirect URL under `soleur.ai`. Vanity subdomain still shows `supabase.co`.

**Pricing correction (from research):** Custom domains are a separate **paid add-on** billed hourly on top of the Pro plan base price. Total estimated cost: ~$35/mo (Pro $25 + custom domain ~$10). This is higher than the original $25/mo estimate.

| Option | Domain | Base Plan | Add-on | Total/mo | Complexity |
|--------|--------|-----------|--------|----------|-----------|
| Vanity subdomain | `soleur.supabase.co` | $25 (Pro) | $0 | $25 | Low -- CLI only |
| Custom domain | `api.soleur.ai` | $25 (Pro) | ~$10 | ~$35 | Medium -- DNS + verification |

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

#### Research Insights: Supabase Custom Domain Migration

**Backward compatibility confirmed ([Supabase docs](https://supabase.com/docs/guides/platform/custom-domains)):**
The original Supabase project URL (`ifsccnjhymdmidffkzhl.supabase.co`) **continues to work** after custom domain activation. Both domains function simultaneously. No forced cutover means zero-downtime migration.

**Critical migration ordering:** OAuth provider redirect URIs must be updated **BEFORE** activating the custom domain. After activation, OAuth flows advertise the custom domain as the callback URL (`https://api.soleur.ai/auth/v1/callback`). If providers don't have this URL whitelisted, auth breaks.

**Correct step order (revised):**

1. Create DNS records (CNAME + TXT)
2. Run `supabase domains create` and `reverify`
3. **BEFORE activating:** Update Google OAuth authorized redirect URIs to add `https://api.soleur.ai/auth/v1/callback`
4. **BEFORE activating:** Update GitHub OAuth callback URL to add `https://api.soleur.ai/auth/v1/callback`
5. Run `supabase domains activate`
6. Update Doppler `NEXT_PUBLIC_SUPABASE_URL` and rebuild Docker image
7. Verify both old and new URLs work during transition

**Subdomain-only constraint:** Supabase custom domains only support subdomains (e.g., `api.soleur.ai`), not root domains (e.g., `soleur.ai`). The proposed `api.soleur.ai` is correct.

**Terraform resource name:** Per institutional learning (`2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`), the Cloudflare provider is pinned at `~> 4.0`. Use `cloudflare_record` (v4 name), not `cloudflare_dns_record` (v5 name).

**CNAME record format for `dns.tf`:**

```hcl
resource "cloudflare_record" "supabase_custom_domain" {
  zone_id = var.cf_zone_id
  name    = "api"
  content = "ifsccnjhymdmidffkzhl.supabase.co"
  type    = "CNAME"
  proxied = false  # Must NOT be proxied -- Supabase needs direct DNS resolution for SSL verification
  ttl     = 60     # Low TTL for faster propagation during setup
}
```

**Docker rebuild note:** Per institutional learning (`2026-03-17-nextjs-docker-public-env-vars.md`), `NEXT_PUBLIC_SUPABASE_URL` is baked into the client-side JavaScript bundle at build time via `ARG` directives in the Dockerfile. Changing the Doppler secret alone is insufficient -- the Docker image MUST be rebuilt with the new URL passed as a build arg. The CI workflow already has the build-arg pattern in place.

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

#### Research Insights: OAuth Provider Checklist Content

**Per-provider consent screen branding requirements (for the checklist document):**

| Provider | Console URL | Logo Spec | Branding Fields |
|----------|------------|-----------|----------------|
| Google | [Cloud Console](https://console.cloud.google.com/apis/credentials/consent) | 120x120px, JPG/PNG/BMP, <1MB | App name, logo, home page, authorized domains, privacy policy, ToS |
| Apple | [Developer Portal](https://developer.apple.com/account/resources/identifiers/) | N/A (uses Apple UI) | App name, return URLs, domain verification |
| GitHub | [Developer Settings](https://github.com/settings/developers) | Logo upload (any size) | App name, homepage URL, callback URL, description |
| Microsoft | [Entra Admin Center](https://entra.microsoft.com/) | Logo (square, PNG, <=36KB) | App name, logo, publisher domain, privacy statement URL, ToS URL |

**Key checklist items from this session's learnings:**

- Tests that mock `signInWithOAuth()` cannot catch configuration gaps (from `2026-03-30-pkce-magic-link-same-browser-context.md`) -- checklist must include a live end-to-end sign-in test as the final verification step
- Supabase Management API `smtp_port` must be a string, not integer (from `2026-03-18-supabase-resend-email-configuration.md`) -- checklist should note type-sensitive API fields
- OAuth provider redirect URIs must be updated before Supabase custom domain activation -- checklist must enforce ordering

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

- [x] Google OAuth consent screen shows "Soleur" as app name
- [x] Consent screen displays Soleur logo
- [x] Privacy policy link points to `https://soleur.ai/pages/legal/privacy-policy.html`
- [x] Terms of service link points to `https://soleur.ai/pages/legal/terms-and-conditions.html`
- [x] Authorized domains include `soleur.ai`
- [x] Application home page set to `https://soleur.ai`
- [x] OAuth app publishing status checked — published to production. Brand verification blocked on domain ownership (#1403) and homepage privacy link (#1404)

### Part 2: Supabase Custom Domain (conditional on plan upgrade)

- [ ] Supabase project upgraded to Pro plan
- [ ] CNAME record `api.soleur.ai` -> `ifsccnjhymdmidffkzhl.supabase.co` in Terraform
- [ ] Domain verified and SSL certificate issued
- [ ] `NEXT_PUBLIC_SUPABASE_URL` updated in Doppler to `https://api.soleur.ai`
- [ ] Docker image rebuilt with new URL
- [ ] Auth callback works end-to-end with new domain
- [ ] ALL OAuth provider redirect URIs updated (Google, GitHub; Apple/Microsoft per #1341)
- [ ] Supabase auth callback URL verified or updated for custom domain
- [ ] Expense entry updated in `knowledge-base/operations/expenses.md` ($0 -> ~$35/mo: Pro $25 + custom domain ~$10)

### Part 3: OAuth Setup Checklist

- [x] Checklist document created at `knowledge-base/engineering/checklists/oauth-provider-setup.md`
- [x] Covers all 4 current providers (Google, Apple, GitHub, Microsoft)
- [x] Includes consent screen branding as a required step
- [x] Includes post-setup verification steps with provider console URLs

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
| Supabase total cost (~$35/mo: Pro $25 + custom domain ~$10) may not be approved | Part 2 blocked; consent screen still shows raw URL | Part 1 fixes app name/logo immediately; defer Part 2. Vanity subdomain ($25/mo, no add-on) is a cheaper fallback |
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

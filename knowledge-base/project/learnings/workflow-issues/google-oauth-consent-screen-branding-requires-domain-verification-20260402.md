---
module: System
date: 2026-04-02
problem_type: workflow_issue
component: tooling
symptoms:
  - "Google OAuth consent screen shows raw Supabase URL instead of app name"
  - "Brand verification fails with domain not registered and missing privacy link"
root_cause: incomplete_setup
resolution_type: workflow_improvement
severity: medium
tags: [oauth, google-cloud, consent-screen, dns, terraform, playwright]
---

# Google OAuth Consent Screen Branding Requires Multi-Step Verification

## Problem

When users signed in to Soleur via Google OAuth, the consent screen displayed "Sign in to ifsccnjhymdmidffkzhl.supabase.co" instead of "Soleur". The original OAuth sign-in implementation (#1211) explicitly listed consent screen branding as a non-goal, creating a trust gap for users.

## Root Cause

Three separate configurations were missing:

1. **Google Cloud Console branding** — App name, logo, homepage, privacy/ToS URLs, and authorized domains were not configured in the OAuth consent screen settings
2. **Domain ownership verification** — `soleur.ai` was not verified in Google Search Console, which Google requires before showing branded consent screens
3. **Homepage privacy link** — Google's brand verification crawler checks that the homepage visibly links to the privacy policy

## Solution

### Part 1: Google Cloud Console Configuration (Playwright MCP)

Navigated to Google Cloud Console > Auth Platform > Branding and configured:

- App name: "Soleur"
- Logo: 120x120px PNG (resized from 512px source via Pillow)
- Homepage: `https://soleur.ai`
- Privacy policy: `https://soleur.ai/pages/legal/privacy-policy.html`
- Terms of service: `https://soleur.ai/pages/legal/terms-and-conditions.html`
- Authorized domain: `soleur.ai` (added alongside existing `ifsccnjhymdmidffkzhl.supabase.co`)
- Publishing status: Changed from "Testing" to "In production"

### Part 2: Domain Verification (Terraform + Search Console)

1. Added DNS TXT record via Terraform in `apps/web-platform/infra/dns.tf`:

   ```hcl
   resource "cloudflare_record" "google_site_verification" {
     zone_id = var.cf_zone_id
     name    = "@"
     content = "google-site-verification=..."
     type    = "TXT"
     ttl     = 1
   }
   ```

2. Applied with `terraform apply -target=cloudflare_record.google_site_verification`
3. Verified in Google Search Console — "Ownership verified" confirmed

### Part 3: Homepage Privacy Link

Added Privacy Policy and Terms of Service links to `plugins/soleur/docs/_data/site.json` footerLinks array.

## Key Insight

Google OAuth consent screen branding is not just a single configuration — it requires a chain of three verifications (console branding, domain ownership, homepage crawl). Each step has different prerequisites and timelines. The brand verification specifically crawls the homepage looking for a privacy policy link, which means the docs site must be deployed before verification can complete.

## Prevention

- Use the OAuth provider setup checklist at `knowledge-base/engineering/checklists/oauth-provider-setup.md` when adding any OAuth provider
- Always configure consent screen branding as part of the initial OAuth setup, not as a follow-up
- For Google specifically: verify domain ownership in Search Console and ensure homepage has visible legal links before submitting brand verification

## Session Errors

1. **gcloud auth expired** — `gcloud projects list` returned `invalid_grant`. Recovery: Logged in via Playwright browser. **Prevention:** Check `gcloud auth list` status before attempting API calls; use Playwright to re-auth if expired.

2. **Playwright MCP file path restriction** — Logo file at `/tmp/` was outside allowed roots. Recovery: Copied file to `.playwright-mcp/` directory. **Prevention:** Always save files to repo-accessible paths when they'll be used by MCP tools. The allowed root is the repo root, not `/tmp/`.

3. **Cloudflare auto-verification popup crashed browser** — Google Search Console's Cloudflare auto-verification opened a new tab that crashed the Playwright browser context. Recovery: Killed Chrome, restarted, used "Any DNS provider" manual flow instead. **Prevention:** When Search Console offers auto-verification via Cloudflare, prefer "Any DNS provider" to get the TXT record value manually — the popup flow opens external OAuth that Playwright can't control.

4. **Terraform nested Doppler invocation** — First `terraform plan` failed because `TF_VAR_*` prefixes weren't set. Recovery: Used the nested `doppler run --name-transformer tf-var` pattern documented in `variables.tf` comments. **Prevention:** The nested Doppler pattern is documented in `apps/web-platform/infra/variables.tf` lines 1-13. Read the file header before running terraform commands.

5. **Brand verification failed on first attempt** — Domain not verified + no privacy link. Recovery: Added DNS TXT record and footer links. **Prevention:** Complete all three verification prerequisites (console config, domain verification, homepage legal links) before submitting for brand verification.

## Cross-References

- OAuth sign-in spec: `knowledge-base/project/specs/feat-oauth-sign-in/spec.md`
- PKCE learning: `knowledge-base/project/learnings/2026-03-30-pkce-magic-link-same-browser-context.md`
- Playwright automation learning: `knowledge-base/project/learnings/2026-03-09-x-provisioning-playwright-automation.md`
- OAuth setup checklist: `knowledge-base/engineering/checklists/oauth-provider-setup.md`
- GitHub issues: #1403 (domain verification - closed), #1404 (homepage privacy link)

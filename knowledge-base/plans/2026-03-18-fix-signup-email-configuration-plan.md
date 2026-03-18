---
title: "fix: Configure signup email for app.soleur.ai"
type: fix
date: 2026-03-18
---

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 7
**Research sources used:** Supabase docs (Context7), Resend docs, web search (email deliverability best practices), codebase analysis

### Key Improvements
1. Concrete Resend SMTP credentials (host: `smtp.resend.com`, port: `465`, user: `resend`, password: API key) -- no more placeholders
2. Corrected email template to use `{{ .ConfirmationURL }}` (correct for PKCE flow with `exchangeCodeForSession`) rather than `{{ .RedirectTo }}` which would break the auth flow
3. Added all Supabase Management API field names for programmatic email template updates (`mailer_templates_magic_link_content`, `mailer_subjects_magic_link`, etc.)
4. Added Resend-specific DNS record values (SPF: `include:amazonses.com`, DKIM: provided by Resend dashboard)
5. Added email HTML best practices: preheader text, MSO conditionals for Outlook, fallback font stack
6. Added edge case: email prefetching by corporate security scanners consuming magic links before users click them
7. Added Supabase Management API automation script for all three configuration changes in a single `curl` call

### New Considerations Discovered
- The app uses PKCE flow (`exchangeCodeForSession` in callback) -- `{{ .ConfirmationURL }}` is the correct template variable, not `{{ .RedirectTo }}`
- Resend has a native Supabase integration (one-click setup from Resend dashboard) that auto-configures SMTP
- Supabase default magic link expiry is 24 hours, but Resend recommends 1 hour for security
- Corporate email security scanners (Barracuda, Mimecast, Microsoft ATP) can prefetch and consume magic links -- consider adding OTP code as fallback in the email template
- Existing SPF/DKIM/DMARC records on `soleur.ai` must be checked before adding new ones to avoid conflicts

---

# fix: Configure signup email for app.soleur.ai

## Overview

The signup/login magic link emails sent by Supabase Auth have three problems: they come from a Supabase-owned domain instead of `soleur.ai`, they use the default Supabase template with no Soleur branding, and the confirmation link redirects to `localhost:3000` instead of `https://app.soleur.ai`. All three stem from Supabase project configuration, not application code bugs.

## Problem Statement

When a user signs up at `app.soleur.ai`, they receive a magic link email that:

1. **Wrong sender domain** -- From address is `noreply@mail.supabase.io` (or similar Supabase domain) instead of something like `noreply@soleur.ai`. This hurts deliverability and looks unprofessional.
2. **No branding** -- The email body uses Supabase's default template (plain text with Supabase branding). No Soleur logo, colors, or copy.
3. **Broken redirect** -- The magic link URL points to `http://localhost:3000/...` instead of `https://app.soleur.ai/...`, making the link non-functional for real users.

Tracked in: #678 (priority/p1-high)

## Root Cause Analysis

### Issue 1: Wrong sender domain

Supabase projects default to Supabase's built-in SMTP relay. Emails are sent from a `@supabase.io` address. To send from `@soleur.ai`, a custom SMTP provider must be configured via the Supabase dashboard (Authentication > SMTP Settings) or the Management API.

### Issue 2: No branding

Supabase provides default email templates for magic link, signup confirmation, password reset, etc. These are editable in the Supabase dashboard under Authentication > Email Templates. The current project uses the out-of-the-box templates with no customization.

### Issue 3: Redirect to localhost

The Supabase project's **Site URL** (Authentication > URL Configuration) is likely still set to `http://localhost:3000` from initial development. The default email template uses `{{ .ConfirmationURL }}` which internally constructs the redirect URL based on the Site URL. When `{{ .ConfirmationURL }}` resolves, it uses the Site URL as the base for where users land after auth verification. Additionally, `https://app.soleur.ai` may not be in the **Redirect URLs** allowed list, which would cause Supabase to fall back to the Site URL.

The client-side code (`apps/web-platform/app/(auth)/signup/page.tsx:21` and `apps/web-platform/app/(auth)/login/page.tsx:21`) correctly uses `window.location.origin` for the `emailRedirectTo` option -- no code change is needed there.

### Research Insights

**PKCE Flow Confirmation:** The app uses PKCE auth flow, confirmed by `exchangeCodeForSession(code)` in `apps/web-platform/app/(auth)/callback/route.ts:11`. The callback expects a `code` query parameter. This means `{{ .ConfirmationURL }}` is the correct template variable -- it generates a URL that goes through Supabase's verification server, which then redirects to the app's callback with `?code=...` for PKCE exchange. Using `{{ .RedirectTo }}` or manual `{{ .TokenHash }}` construction would break this flow.

**Supabase email template variables available:**
- `{{ .ConfirmationURL }}` -- Pre-built URL with auth verification (correct for PKCE flow)
- `{{ .SiteURL }}` -- The Site URL from project config
- `{{ .RedirectTo }}` -- The redirect URL passed from client code
- `{{ .Token }}` -- OTP code (6-digit)
- `{{ .TokenHash }}` -- Hashed token for server-side verification
- `{{ .Email }}` -- User's email address

## Proposed Solution

Three configuration changes in the Supabase dashboard, plus email template HTML files committed to the repo for maintainability.

### 1. Configure Custom SMTP via Resend

**Provider: [Resend](https://resend.com)** -- chosen for: native Supabase integration, simple API-key-based auth, good deliverability, custom domain support, generous free tier (100 emails/day).

**Resend SMTP credentials:**
- **Host:** `smtp.resend.com`
- **Port:** `465` (SSL/TLS). If connection issues arise, try `587` (STARTTLS).
- **Username:** `resend`
- **Password:** Resend API key (starts with `re_`)
- **Sender email:** `noreply@soleur.ai`
- **Sender name:** `Soleur`

**Setup steps:**

1. Create Resend account at https://resend.com (or use existing account)
2. Add `soleur.ai` as a sending domain in Resend dashboard
3. Resend will provide DNS records (SPF, DKIM) -- collect these for Phase 2
4. Generate an API key in Resend dashboard -- this becomes the SMTP password
5. Configure in Supabase via Management API:

```bash
export SUPABASE_ACCESS_TOKEN="<your-access-token>"  # From https://supabase.com/dashboard/account/tokens
export PROJECT_REF="<your-project-ref>"              # From project URL: supabase.com/dashboard/project/<ref>

curl -X PATCH "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "external_email_enabled": true,
    "smtp_admin_email": "noreply@soleur.ai",
    "smtp_host": "smtp.resend.com",
    "smtp_port": 465,
    "smtp_user": "resend",
    "smtp_pass": "<resend-api-key>",
    "smtp_sender_name": "Soleur"
  }'
```

**Alternative:** Resend offers a one-click Supabase integration from their dashboard (https://resend.com/supabase) that auto-configures SMTP settings without manual credential entry.

### Research Insights: SMTP Configuration

**Best Practices:**
- Use a dedicated API key for Supabase SMTP (not your main Resend API key) so it can be rotated independently
- Set up a subdomain like `mail.soleur.ai` as the sending domain rather than the root `soleur.ai` to isolate email reputation from the main domain
- Resend provides webhook events for bounces and complaints -- consider configuring these for monitoring

**Edge Cases:**
- Some corporate firewalls block port 465. Port 587 with STARTTLS is more universally accepted.
- Resend rate limits: Free tier is 100 emails/day, 10/second. For production, the Pro plan ($20/month) provides 50,000 emails/month.
- If Resend goes down, Supabase falls back to its built-in SMTP. This is actually desirable for auth emails -- users can still sign in, just from a different sender domain.

### 2. Fix Site URL and Redirect URLs (Supabase Dashboard)

- **Site URL**: Change from `http://localhost:3000` to `https://app.soleur.ai` in Authentication > URL Configuration.
- **Redirect URLs**: Add `https://app.soleur.ai/**` to the allowed redirect URLs list. Keep `http://localhost:3000/**` for local development.

**Via Management API:**

```bash
curl -X PATCH "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "site_url": "https://app.soleur.ai",
    "uri_allow_list": "http://localhost:3000/**,https://app.soleur.ai/**"
  }'
```

### Research Insights: Redirect Configuration

**Best Practices:**
- Use wildcard patterns (`/**`) in redirect URLs to cover all paths, not just specific routes
- The `site_url` is the **default** redirect when no `redirectTo` is passed from client code. Setting it to the production URL is correct.
- For staging environments, add the staging URL to `uri_allow_list` as well

**Edge Cases:**
- If `uri_allow_list` does not include the production URL, Supabase silently falls back to `site_url`. Since we're fixing `site_url` to be production, this fallback is actually correct behavior now.
- The `window.location.origin` approach in the client code resolves correctly in both dev (`http://localhost:3000`) and production (`https://app.soleur.ai`), so no client code changes needed.

### 3. Customize Email Templates (Supabase Dashboard)

Update the Magic Link email template in Authentication > Email Templates to use Soleur branding. The template uses `{{ .ConfirmationURL }}` which is the correct variable for the PKCE auth flow this app uses.

**All Supabase email template types to customize:**

| Template | Management API field (subject) | Management API field (content) |
|----------|-------------------------------|-------------------------------|
| Magic Link | `mailer_subjects_magic_link` | `mailer_templates_magic_link_content` |
| Confirmation | `mailer_subjects_confirmation` | `mailer_templates_confirmation_content` |
| Password Recovery | `mailer_subjects_recovery` | `mailer_templates_recovery_content` |
| Email Change | `mailer_subjects_email_change` | `mailer_templates_email_change_content` |
| Invite | `mailer_subjects_invite` | `mailer_templates_invite_content` |

**Priority:** Magic Link is the only template used currently (OTP-based auth). Customize it first, then optionally customize others.

Template file to commit for version control: `apps/web-platform/supabase/templates/magic-link.html`

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="color-scheme" content="dark">
  <meta name="supported-color-schemes" content="dark">
  <!--[if mso]>
  <style>table,td{font-family:Arial,Helvetica,sans-serif !important;}</style>
  <![endif]-->
</head>
<body style="margin:0;padding:0;background-color:#0a0a0a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;">Sign in to your Soleur account</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#0a0a0a;padding:40px 20px;">
    <tr>
      <td align="center">
        <table role="presentation" width="400" cellpadding="0" cellspacing="0" style="background-color:#171717;border-radius:12px;padding:40px;max-width:400px;width:100%;">
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <h1 style="color:#ffffff;font-size:20px;font-weight:600;margin:0;letter-spacing:-0.02em;">Soleur</h1>
            </td>
          </tr>
          <tr>
            <td style="color:#a3a3a3;font-size:14px;line-height:1.6;padding-bottom:24px;text-align:center;">
              Click the button below to sign in to your Soleur account.
            </td>
          </tr>
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <a href="{{ .ConfirmationURL }}"
                 style="display:inline-block;background-color:#ffffff;color:#000000;font-size:14px;font-weight:500;text-decoration:none;padding:12px 32px;border-radius:8px;mso-padding-alt:12px 32px;">
                Sign in to Soleur
              </a>
            </td>
          </tr>
          <tr>
            <td style="color:#525252;font-size:12px;line-height:1.5;text-align:center;padding-bottom:16px;">
              This link expires in 24 hours. If you didn't request this email, you can safely ignore it.
            </td>
          </tr>
          <tr>
            <td style="border-top:1px solid #262626;padding-top:16px;color:#404040;font-size:11px;line-height:1.4;text-align:center;">
              Soleur &mdash; AI domain leaders for your business<br>
              <a href="https://soleur.ai" style="color:#525252;text-decoration:none;">soleur.ai</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
```

### Research Insights: Email Template

**Best Practices:**
- Use `role="presentation"` on layout tables for accessibility (screen readers skip them)
- Include a preheader (hidden `<div>`) for email preview text in inbox list views
- Add `<!--[if mso]>` conditionals for Outlook desktop client compatibility
- Use `mso-padding-alt` on CTA buttons for correct padding in Outlook
- Set `max-width` with `width:100%` for responsive behavior on mobile
- Add `meta color-scheme: dark` to prevent forced light mode in Apple Mail and other dark-mode-aware clients
- Include a footer with company name and website link (CAN-SPAM compliance, even for transactional emails)

**Performance Considerations:**
- Keep email HTML under 100KB to avoid Gmail clipping
- Inline all CSS (no `<style>` blocks) for maximum email client compatibility
- Avoid images where possible -- text-based emails have higher deliverability and load faster

**Edge Cases:**
- **Email prefetching by corporate security scanners** (Barracuda, Mimecast, Microsoft ATP): These systems follow links in emails to scan for malware, which can consume one-time magic links before the user clicks. Supabase handles this by using a verification endpoint that requires a proper browser redirect chain (not a simple GET request), which mitigates most prefetch scanners. However, consider adding the OTP code as a secondary option: `<p style="...">Or enter this code: {{ .Token }}</p>`. This requires updating the signup/login pages to accept OTP code input.
- **Gmail image proxy**: Gmail proxies all images through its servers. If adding a Soleur logo image later, host it on a reliable CDN and use HTTPS.
- **Dark mode inversion**: Some email clients invert colors in dark mode. The template already uses a dark theme, which prevents unexpected inversions.

### 4. DNS Records for Email Authentication (Cloudflare via Terraform)

Add SPF, DKIM, and DMARC DNS records to `apps/web-platform/infra/dns.tf` to authorize Resend for `soleur.ai`.

**Pre-check:** Before adding records, verify no existing SPF/DKIM/DMARC records exist on `soleur.ai`:

```bash
dig TXT soleur.ai +short        # Check for existing SPF
dig TXT _dmarc.soleur.ai +short # Check for existing DMARC
```

If an SPF record exists, merge the Resend include into the existing record rather than creating a duplicate (multiple SPF records cause failures).

**Resend-specific DNS records** (exact values provided by Resend dashboard after domain verification):

```hcl
# SPF record -- authorizes Resend (which uses Amazon SES) to send on behalf of soleur.ai
# NOTE: If an SPF record already exists, merge "include:amazonses.com" into it
resource "cloudflare_record" "spf" {
  zone_id = var.cloudflare_zone_id
  name    = "soleur.ai"
  content = "v=spf1 include:amazonses.com ~all"
  type    = "TXT"
  ttl     = 3600
}

# DKIM records -- Resend provides 3 CNAME records for DKIM
# The exact names and values come from the Resend dashboard after adding soleur.ai
resource "cloudflare_record" "dkim1" {
  zone_id = var.cloudflare_zone_id
  name    = "resend._domainkey"
  content = "<value-from-resend-dashboard>"
  type    = "CNAME"
  ttl     = 3600
}

# Additional DKIM records may be required -- check Resend dashboard

# DMARC record
resource "cloudflare_record" "dmarc" {
  zone_id = var.cloudflare_zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@soleur.ai; pct=100"
  type    = "TXT"
  ttl     = 3600
}
```

### Research Insights: DNS & Deliverability

**Best Practices:**
- Use `~all` (soft fail) instead of `-all` (hard fail) in SPF during initial setup. Switch to `-all` after confirming everything works.
- DMARC `pct=100` means 100% of failing messages are subject to the policy. Start with `p=none` and `pct=100` for monitoring, then escalate to `p=quarantine` after confirming no legitimate emails fail.
- Set up a `rua` (reporting) address to receive DMARC aggregate reports. Use a service like DMARCian or Postmark's DMARC monitoring to parse these.
- Resend uses Amazon SES under the hood, so the SPF include is `amazonses.com`, not a Resend-specific domain.

**Edge Cases:**
- **Existing SPF record conflict**: If `soleur.ai` already has an SPF record (e.g., from Google Workspace for company email), adding a second SPF record will cause both to fail. DNS allows only one SPF record per domain. Merge includes into a single record: `v=spf1 include:_spf.google.com include:amazonses.com ~all`.
- **Cloudflare proxied records**: TXT records cannot be proxied by Cloudflare (they're always DNS-only). No `proxied` attribute needed.
- **DKIM as CNAME vs TXT**: Resend uses CNAME records for DKIM (delegating to their infrastructure), not TXT records with raw keys. This allows Resend to rotate keys without requiring DNS changes.

### 5. Combined Management API Script (All Configuration in One Call)

All three Supabase configuration changes can be applied in a single API call:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Required environment variables:
# SUPABASE_ACCESS_TOKEN -- from https://supabase.com/dashboard/account/tokens
# PROJECT_REF           -- from project URL
# RESEND_API_KEY        -- from Resend dashboard

SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:?Missing SUPABASE_ACCESS_TOKEN}"
PROJECT_REF="${PROJECT_REF:?Missing PROJECT_REF}"
RESEND_API_KEY="${RESEND_API_KEY:?Missing RESEND_API_KEY}"

# Read email template from file
MAGIC_LINK_TEMPLATE=$(cat apps/web-platform/supabase/templates/magic-link.html)

curl -X PATCH "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg template "$MAGIC_LINK_TEMPLATE" \
    --arg smtp_pass "$RESEND_API_KEY" \
    '{
      "site_url": "https://app.soleur.ai",
      "uri_allow_list": "http://localhost:3000/**,https://app.soleur.ai/**",
      "external_email_enabled": true,
      "smtp_admin_email": "noreply@soleur.ai",
      "smtp_host": "smtp.resend.com",
      "smtp_port": 465,
      "smtp_user": "resend",
      "smtp_pass": $smtp_pass,
      "smtp_sender_name": "Soleur",
      "mailer_subjects_magic_link": "Sign in to Soleur",
      "mailer_templates_magic_link_content": $template
    }'
  )"

echo "Supabase auth config updated successfully."
```

## Acceptance Criteria

- [ ] Magic link emails are sent from `noreply@soleur.ai` (or similar `@soleur.ai` address)
- [ ] Magic link emails display Soleur branding (dark theme, branded copy, footer)
- [ ] Clicking the magic link redirects to `https://app.soleur.ai/callback` (not localhost)
- [ ] Auth callback completes successfully (user lands on dashboard or setup-key page)
- [ ] SPF, DKIM, and DMARC DNS records pass validation (check via `dig` or mail-tester.com)
- [ ] Local development still works with `http://localhost:3000` redirect
- [ ] Email template HTML is committed to the repo at `apps/web-platform/supabase/templates/magic-link.html` for version control
- [ ] Login page magic link emails also work correctly (same flow as signup)
- [ ] Email renders correctly in Gmail, Apple Mail, and Outlook (major email clients)

## Test Scenarios

- Given a new user at `app.soleur.ai`, when they enter their email and click "Sign up with magic link", then they receive an email from `noreply@soleur.ai` with Soleur-branded content within 30 seconds
- Given a user clicks the magic link in the email, when the link is followed, then they are redirected to `https://app.soleur.ai/callback` and the PKCE code exchange completes successfully
- Given a developer running locally on `localhost:3000`, when they sign up, then the magic link still redirects to `http://localhost:3000/callback` (verified by `window.location.origin` in the `emailRedirectTo` option)
- Given the email is checked with mail-tester.com, when SPF/DKIM/DMARC are evaluated, then all pass with a score of 9+/10
- Given an existing user at `app.soleur.ai`, when they use the login page magic link, then the same branded email and correct redirect behavior applies
- Given the email is opened in Gmail on mobile, when the dark mode is enabled, then the template renders correctly without color inversions
- Given a user whose corporate email scanner prefetches links, when the magic link is followed after prefetch, then the PKCE flow still works (Supabase verification endpoint requires full browser redirect chain)

## Context

### Relevant Files

- `apps/web-platform/app/(auth)/signup/page.tsx:21` -- `signInWithOtp` call with `emailRedirectTo: window.location.origin + '/callback'`
- `apps/web-platform/app/(auth)/login/page.tsx:21` -- Same OTP flow as signup
- `apps/web-platform/app/(auth)/callback/route.ts:11` -- PKCE callback using `exchangeCodeForSession(code)`
- `apps/web-platform/lib/supabase/client.ts` -- Browser Supabase client (uses `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`)
- `apps/web-platform/lib/supabase/server.ts` -- Server Supabase client with service role
- `apps/web-platform/middleware.ts` -- Auth middleware, public paths include `/callback`
- `apps/web-platform/infra/dns.tf` -- Cloudflare DNS records (needs SPF/DKIM/DMARC additions)
- `apps/web-platform/infra/variables.tf` -- Terraform variables (has `app_domain = "app.soleur.ai"`)
- `apps/web-platform/infra/main.tf` -- Terraform providers (Hetzner + Cloudflare)
- `.github/workflows/build-web-platform.yml` -- CI/CD pipeline, Docker build with Supabase env vars

### Key Observations

- The client code is correct -- `emailRedirectTo: window.location.origin + '/callback'` resolves correctly in production. The issue is the Supabase project config, not the app code.
- No `supabase/config.toml` exists -- Supabase is fully managed via the hosted dashboard.
- Cloudflare is already the DNS provider (Terraform managed), making DNS record additions straightforward.
- The Supabase Management API can automate all SMTP, URL, and template configuration via a single `curl` call.
- The app uses PKCE auth flow (`exchangeCodeForSession` in callback), so `{{ .ConfirmationURL }}` is the correct email template variable.
- Resend has a native Supabase integration that can auto-configure SMTP without manual credential entry.

### Implementation Approach

This is primarily a configuration task, not a code change. The work splits into:

1. **Resend account setup** (domain verification, API key generation) -- automatable via Resend API or Playwright
2. **DNS records** (SPF, DKIM, DMARC) -- Terraform in `dns.tf`, applied with `terraform apply`
3. **Supabase configuration** (Site URL, redirect URLs, SMTP settings, email template) -- single Management API call
4. **Email template** (HTML file committed to repo) -- code change
5. **Verification** (send test email, check headers, verify redirect, test email client rendering)

## References

- GitHub Issue: #678
- [Supabase Auth SMTP docs](https://supabase.com/docs/guides/auth/auth-smtp)
- [Supabase Email Templates docs](https://supabase.com/docs/guides/auth/auth-email-templates)
- [Supabase Redirect URLs docs](https://supabase.com/docs/guides/auth/concepts/redirect-urls)
- [Supabase PKCE Flow docs](https://supabase.com/docs/guides/auth/sessions/pkce-flow)
- [Resend + Supabase SMTP setup](https://resend.com/docs/send-with-supabase-smtp)
- [Resend native Supabase integration](https://resend.com/supabase)
- [Resend domain verification](https://resend.com/docs/send-with-supabase-smtp)
- Supabase Management API: `PATCH /v1/projects/$PROJECT_REF/config/auth`

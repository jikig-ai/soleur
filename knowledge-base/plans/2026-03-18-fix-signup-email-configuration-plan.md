---
title: "fix: Configure signup email for app.soleur.ai"
type: fix
date: 2026-03-18
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

The Supabase project's **Site URL** (Authentication > URL Configuration) is likely still set to `http://localhost:3000` from initial development. The default email template uses `{{ .SiteURL }}` to construct the confirmation link. Even though the client code passes `emailRedirectTo: window.location.origin + '/callback'`, the email template's `{{ .SiteURL }}` takes precedence in the default template. Additionally, `https://app.soleur.ai` may not be in the **Redirect URLs** allowed list, which would cause Supabase to fall back to the Site URL.

The client-side code (`apps/web-platform/app/(auth)/signup/page.tsx:21` and `apps/web-platform/app/(auth)/login/page.tsx:21`) correctly uses `window.location.origin` for the `emailRedirectTo` option -- no code change is needed there.

## Proposed Solution

Three configuration changes in the Supabase dashboard, plus one email template HTML file committed to the repo for maintainability:

### 1. Configure Custom SMTP (`apps/web-platform/supabase/` or Supabase Dashboard)

Choose an email provider and configure it in Supabase:

- **Recommended provider**: Resend (simple setup, good deliverability, supports custom domains). Alternatives: Postmark, Amazon SES, Mailgun.
- **Configuration**: Supabase Dashboard > Project Settings > Authentication > SMTP Settings, or via Management API:

```bash
curl -X PATCH "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "external_email_enabled": true,
    "smtp_admin_email": "noreply@soleur.ai",
    "smtp_host": "<provider-smtp-host>",
    "smtp_port": 587,
    "smtp_user": "<smtp-user>",
    "smtp_pass": "<smtp-password>",
    "smtp_sender_name": "Soleur"
  }'
```

- **DNS**: Add SPF, DKIM, and DMARC records for `soleur.ai` in Cloudflare to authorize the SMTP provider. This ensures emails from `noreply@soleur.ai` are not flagged as spam.

### 2. Fix Site URL and Redirect URLs (Supabase Dashboard)

- **Site URL**: Change from `http://localhost:3000` to `https://app.soleur.ai` in Authentication > URL Configuration.
- **Redirect URLs**: Add `https://app.soleur.ai/**` to the allowed redirect URLs list. Keep `http://localhost:3000/**` for local development.

### 3. Customize Email Templates (Supabase Dashboard)

Update the Magic Link email template in Authentication > Email Templates to use Soleur branding. The template should:

- Use `{{ .RedirectTo }}` instead of `{{ .SiteURL }}` so the client-specified redirect is honored
- Include Soleur logo and brand colors (dark theme matching the app)
- Have clear copy explaining the magic link

Template file to commit for version control: `apps/web-platform/supabase/templates/magic-link.html`

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0;padding:0;background-color:#0a0a0a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0a0a0a;padding:40px 20px;">
    <tr>
      <td align="center">
        <table width="400" cellpadding="0" cellspacing="0" style="background-color:#171717;border-radius:12px;padding:40px;">
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <h1 style="color:#ffffff;font-size:20px;font-weight:600;margin:0;">Soleur</h1>
            </td>
          </tr>
          <tr>
            <td style="color:#a3a3a3;font-size:14px;line-height:1.6;padding-bottom:24px;">
              Click the button below to sign in to your Soleur account. This link expires in 24 hours.
            </td>
          </tr>
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <a href="{{ .ConfirmationURL }}"
                 style="display:inline-block;background-color:#ffffff;color:#000000;font-size:14px;font-weight:500;text-decoration:none;padding:12px 24px;border-radius:8px;">
                Sign in to Soleur
              </a>
            </td>
          </tr>
          <tr>
            <td style="color:#525252;font-size:12px;line-height:1.5;">
              If you didn't request this email, you can safely ignore it.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
```

### 4. DNS Records for Email Authentication (Cloudflare via Terraform)

Add SPF, DKIM, and DMARC DNS records to `apps/web-platform/infra/dns.tf` to authorize the chosen SMTP provider for `soleur.ai`. The exact records depend on the provider chosen (Resend, Postmark, etc.).

Example additions to `apps/web-platform/infra/dns.tf`:

```hcl
resource "cloudflare_record" "spf" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = "v=spf1 include:<provider-spf-domain> -all"
  type    = "TXT"
  ttl     = 3600
}

resource "cloudflare_record" "dkim" {
  zone_id = var.cloudflare_zone_id
  name    = "<provider-dkim-selector>._domainkey"
  content = "<provider-dkim-value>"
  type    = "TXT"
  ttl     = 3600
}

resource "cloudflare_record" "dmarc" {
  zone_id = var.cloudflare_zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=quarantine; rua=mailto:dmarc@soleur.ai"
  type    = "TXT"
  ttl     = 3600
}
```

## Acceptance Criteria

- [ ] Magic link emails are sent from `noreply@soleur.ai` (or similar `@soleur.ai` address)
- [ ] Magic link emails display Soleur branding (logo, dark theme, branded copy)
- [ ] Clicking the magic link redirects to `https://app.soleur.ai/callback` (not localhost)
- [ ] SPF, DKIM, and DMARC DNS records pass validation (check via `dig` or mail-tester.com)
- [ ] Local development still works with `http://localhost:3000` redirect
- [ ] Email template HTML is committed to the repo at `apps/web-platform/supabase/templates/magic-link.html` for version control
- [ ] Login page magic link emails also work correctly (same flow as signup)

## Test Scenarios

- Given a new user at `app.soleur.ai`, when they enter their email and click "Sign up with magic link", then they receive an email from `noreply@soleur.ai` with Soleur-branded content
- Given a user clicks the magic link in the email, when the link is followed, then they are redirected to `https://app.soleur.ai/callback` and authenticated successfully
- Given a developer running locally on `localhost:3000`, when they sign up, then the magic link still redirects to `http://localhost:3000/callback`
- Given the email is checked with mail-tester.com, when SPF/DKIM/DMARC are evaluated, then all pass with a score of 9+/10
- Given an existing user at `app.soleur.ai`, when they use the login page magic link, then the same branded email and correct redirect behavior applies

## Context

### Relevant Files

- `apps/web-platform/app/(auth)/signup/page.tsx` -- Signup page, calls `signInWithOtp` with `emailRedirectTo`
- `apps/web-platform/app/(auth)/login/page.tsx` -- Login page, same OTP flow
- `apps/web-platform/app/(auth)/callback/route.ts` -- Auth callback handler, exchanges code for session
- `apps/web-platform/lib/supabase/client.ts` -- Browser Supabase client
- `apps/web-platform/lib/supabase/server.ts` -- Server Supabase client
- `apps/web-platform/infra/dns.tf` -- Cloudflare DNS records (needs SPF/DKIM/DMARC additions)
- `apps/web-platform/infra/variables.tf` -- Terraform variables (has `app_domain = "app.soleur.ai"`)
- `.github/workflows/build-web-platform.yml` -- CI/CD pipeline

### Key Observations

- The client code is correct -- `emailRedirectTo: window.location.origin + '/callback'` resolves correctly in production. The issue is the Supabase project config, not the app code.
- No `supabase/config.toml` exists -- Supabase is fully managed via the hosted dashboard.
- Cloudflare is already the DNS provider (Terraform managed), making DNS record additions straightforward.
- The Supabase Management API can automate SMTP and URL configuration via `curl` or Playwright if dashboard access tokens are available.

### Implementation Approach

This is primarily a configuration task, not a code change. The work splits into:

1. **SMTP provider setup** (account creation, API key, domain verification) -- may require Playwright for provider signup
2. **Supabase dashboard configuration** (Site URL, redirect URLs, SMTP settings, email template) -- automatable via Management API
3. **DNS records** (SPF, DKIM, DMARC) -- Terraform in `dns.tf`
4. **Email template** (HTML file committed to repo) -- code change
5. **Verification** (send test email, check headers, verify redirect)

## References

- GitHub Issue: #678
- Supabase Auth SMTP docs: https://supabase.com/docs/guides/auth/auth-smtp
- Supabase Email Templates docs: https://supabase.com/docs/guides/auth/auth-email-templates
- Supabase Redirect URLs docs: https://supabase.com/docs/guides/auth/concepts/redirect-urls
- Supabase Management API: `PATCH /v1/projects/$PROJECT_REF/config/auth`

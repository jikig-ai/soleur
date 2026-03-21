---
title: "Supabase signup email configuration requires SMTP, DNS, and API-level changes -- not code"
date: 2026-03-18
category: infrastructure
tags: [supabase, resend, smtp, dns, email, terraform, cloudflare, auth, pkce]
module: apps/web-platform/infra/
---

# Learning: Supabase signup email configuration requires SMTP, DNS, and API-level changes -- not code

## Problem

GitHub issue #678 -- Signup emails from app.soleur.ai had three distinct failures:

1. **Wrong sender domain.** Emails were sent from Supabase's default domain (e.g., `noreply@mail.supabase.io`) instead of `soleur.ai`.
2. **No branding.** The email body used Supabase's generic template with no Soleur visual identity.
3. **Broken magic link.** The confirmation URL redirected to `localhost:3000` instead of `https://app.soleur.ai`, making signup impossible in production.

All three symptoms traced to a single root cause: the Supabase project was still running on development defaults. Site URL was `http://localhost:3000`, no custom SMTP provider was configured, and the default email templates had never been replaced.

## Solution

Five changes, none of which involved application code:

1. **SMTP provider (Resend).** Configured Resend as the custom SMTP sender via Supabase's auth settings. Connection details: `smtp.resend.com:465`, TLS enabled, API key as password. This moved the sender address from Supabase's domain to `noreply@soleur.ai`.

2. **Branded email template.** Created a custom HTML email template using Supabase's `{{ .ConfirmationURL }}` template variable, which is required for PKCE auth flow. The template includes Soleur branding and renders the magic link as a styled button.

3. **Site URL and redirects.** Updated the Supabase project's Site URL from `http://localhost:3000` to `https://app.soleur.ai` and added `https://app.soleur.ai/**` to the redirect allow list. This fixed the magic link destination.

4. **DNS records (Terraform + Cloudflare).** Added SPF, DKIM, DMARC, and MX records to the `soleur.ai` zone via Terraform to establish email authentication. These records prevent signup emails from landing in spam.

5. **Configuration script.** Created `configure-auth.sh` to apply all auth settings via the Supabase Management API, making the configuration reproducible across environments without manual dashboard interaction.

The client-side code (`emailRedirectTo: window.location.origin`) was already correct and required no changes.

## Key Insight

Supabase auth email configuration is an infrastructure/ops task, not a code task. The three visible symptoms (wrong sender, no branding, broken redirect) all stemmed from project-level settings accessible only through the Supabase dashboard or Management API. The application code was already written correctly -- it used `window.location.origin` for redirects, which resolves correctly in any environment. The fix was entirely in the project configuration and DNS layer.

This is a common pattern with managed auth services: the client SDK provides the right abstractions, but the project must be configured to match the production environment. Development defaults that work locally (localhost URLs, built-in SMTP) silently break in production without any code-level errors.

**Rule of thumb:** When auth emails misbehave in production but work in development, check project-level configuration (site URL, SMTP, templates) before investigating application code.

## Session Errors

1. **Supabase Management API rejects integer smtp_port.** The API expects `smtp_port` as a string value (`"465"`) not an integer (`465`). The request body passed `"smtp_port": 465` and received a validation error. This is undocumented -- the API schema does not indicate the field is string-typed. Fix: wrap the port number in quotes in the JSON payload.

2. **Resend DKIM record type mismatch.** The implementation plan assumed Resend would provide DKIM verification as a CNAME record (common with other providers like SendGrid). Resend actually provides DKIM as a TXT record containing the public key directly. The Terraform DNS configuration had to be updated from `type = "CNAME"` to `type = "TXT"` with the raw key value.

3. **Cloudflare domain-connect auto-configure failed silently.** Attempted to use Cloudflare's domain-connect feature to auto-configure DNS records for Resend. The API call returned success but no records were created. No error message or diagnostic information was provided. Fallback: configured all DNS records explicitly via Terraform, which succeeded on the first attempt. This reinforces the AGENTS.md rule to use Terraform for DNS provisioning rather than vendor-specific automation features.

## Tags

category: infrastructure
module: apps/web-platform/infra/

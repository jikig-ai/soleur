---
module: System
date: 2026-04-06
problem_type: integration_issue
component: email_processing
symptoms:
  - "Resend API returns 403: The soleur.ai domain is not verified"
  - "Resend API returns 403: The send.soleur.ai domain is not verified"
  - "Resend domain verification stuck in pending state"
root_cause: config_error
resolution_type: config_change
severity: medium
tags: [resend, dns, dkim, spf, cloudflare, terraform, email, domain-verification]
synced_to: []
---

# Learning: Resend subdomain verification requires non-obvious DNS record naming

## Problem

When migrating GitHub Actions workflow notifications from Discord to email via Resend HTTP API, the `soleur.ai` root domain was already registered in another Resend account. Creating `send.soleur.ai` as a new sending domain required DNS records with non-obvious naming patterns that caused verification delays.

## Solution

Three DNS records were required for `send.soleur.ai` domain verification in Resend:

1. **DKIM TXT** at `resend._domainkey.send` (resolves to `resend._domainkey.send.soleur.ai`) -- unique public key per Resend domain
2. **SPF TXT** at `send.send` (resolves to `send.send.soleur.ai`) -- Resend's bounce subdomain pattern
3. **MX** at `send.send` (resolves to `send.send.soleur.ai`) -- Resend's bounce subdomain, priority 10

The `send.send` naming is Resend's convention for bounce handling on subdomain-based sending domains. The SPF/MX records for the bounce subdomain are separate from any existing `send.soleur.ai` records.

**Terraform resources added to `apps/web-platform/infra/dns.tf`:**

```hcl
resource "cloudflare_record" "dkim_resend_send" {
  zone_id = var.cf_zone_id
  name    = "resend._domainkey.send"
  content = "p=MIGfMA0GCSqGSIb3DQEB..."
  type    = "TXT"
  ttl     = 1
}

resource "cloudflare_record" "spf_send_send" {
  zone_id = var.cf_zone_id
  name    = "send.send"
  content = "v=spf1 include:amazonses.com ~all"
  type    = "TXT"
  ttl     = 1
}

resource "cloudflare_record" "mx_send_send" {
  zone_id  = var.cf_zone_id
  name     = "send.send"
  content  = "feedback-smtp.eu-west-1.amazonses.com"
  type     = "MX"
  priority = 10
  ttl      = 1
}
```

## Key Insight

When Resend verifies a subdomain like `send.soleur.ai`, the DKIM record goes where you expect (`resend._domainkey.send.soleur.ai`), but the SPF and MX records go to a *bounce subdomain* (`send.send.soleur.ai`). This is Resend's convention for envelope sender isolation. The Resend dashboard shows these as `send.send` in the Name column, which looks like a display bug but is actually correct. Always copy the exact record names from the Resend dashboard rather than inferring them from the sending domain.

Additionally, if a root domain (`soleur.ai`) is claimed by another Resend account, you cannot add it to a new account. Use a subdomain (`send.soleur.ai`) instead -- this is actually best practice for email sending as it isolates sender reputation.

## Session Errors

**Resend API key not in Doppler despite plan assuming "already provisioned"**

- **Recovery:** Created key via Playwright MCP on Resend dashboard, stored in Doppler prd, set as GitHub secret
- **Prevention:** During plan phase, verify secrets exist in Doppler rather than trusting documentation claims about existing infrastructure

**Security hook warning blocked first workflow edit**

- **Recovery:** Re-submitted the edit (hook is advisory)
- **Prevention:** Expected behavior for GitHub Actions workflow edits; no change needed

**Initial SPF/MX records at wrong subdomain level**

- **Recovery:** Added `send.send` records after discovering Resend's bounce subdomain pattern
- **Prevention:** Always copy exact DNS record names from Resend's verification dashboard before adding to Terraform

## Prevention

- When adding a Resend sending domain, always check the dashboard for exact DNS record names -- do not infer them from the domain name
- The Resend bounce subdomain pattern (`send.<domain>`) creates DNS names that look wrong but are correct
- Verify domain verification status in the Resend dashboard before testing email sends
- Use `dig +short TXT <record>` and `dig +short MX <record>` to confirm DNS propagation before triggering verification

## Related Issues

- See also: [supabase-resend-email-configuration](../2026-03-18-supabase-resend-email-configuration.md) -- Original Resend SMTP setup for Supabase auth emails
- GitHub issue: #1420 -- Parent issue for notification routing
- GitHub issue: #1595 -- Deferred: migrate disk-monitor.sh from Discord to email

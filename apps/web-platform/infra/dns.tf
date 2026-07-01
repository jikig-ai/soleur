resource "cloudflare_record" "app" {
  zone_id = var.cf_zone_id
  name    = "app"
  content = hcloud_server.web["web-1"].ipv4_address
  type    = "A"
  proxied = true
  ttl     = 1 # Auto when proxied
}

# Deploy webhook endpoint routed through Cloudflare Tunnel (see #749).
# Protected by CF Access service token + HMAC signature validation.
resource "cloudflare_record" "deploy" {
  zone_id = var.cf_zone_id
  name    = "deploy"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.web.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# SSH ingress for CI runner via Cloudflare Tunnel (see #4177).
# Protected by CF Access service token; CI runs `cloudflared access tcp`
# to bridge runner→host through this hostname.
resource "cloudflare_record" "ssh" {
  zone_id = var.cf_zone_id
  name    = "ssh"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.web.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# Email authentication records for Resend SMTP (sends via Amazon SES, eu-west-1)

resource "cloudflare_record" "dkim_resend" {
  zone_id = var.cf_zone_id
  name    = "resend._domainkey"
  content = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDOftt0CO6q9Jyccw6ny9j6Nk5scYRFxubRtQix7QFaUmTtBpvT6A6yn5va1VMM+f6SrU6rKqmERhCcsMfCWE/GOgg7HiOhC5MOmSaEXL5QxcQxIVNBhgMG4EH/B/DL+dzYXoj8qN5k50PCnD2AyrwlYuId7hkKj8QajGtogcMDLwIDAQAB"
  type    = "TXT"
  ttl     = 1
}

resource "cloudflare_record" "spf_send" {
  zone_id = var.cf_zone_id
  name    = "send"
  content = "v=spf1 include:amazonses.com ~all"
  type    = "TXT"
  ttl     = 1
}

resource "cloudflare_record" "mx_send" {
  zone_id  = var.cf_zone_id
  name     = "send"
  content  = "feedback-smtp.eu-west-1.amazonses.com"
  type     = "MX"
  priority = 10
  ttl      = 1
}

# DNS records for send.soleur.ai subdomain (Resend HTTP API — ops notifications)
resource "cloudflare_record" "dkim_resend_send" {
  zone_id = var.cf_zone_id
  name    = "resend._domainkey.send"
  content = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC+EB1JLvPe+4RhVmheTK4jzPX22+fpYACUnrjws2hOJzzCOMLh1QhqBc5KrSHvyJpRsrvuYKVJguyliwLoY9NMARrdMQb0J7kayw7Ia2U5h1V3B+dP2OBi8WApYNUrkIlW4fY7OHRGEXk+J8als23Rx7cDhnZRwp0+LokLaXvT2wIDAQAB"
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

# DNS records for inbound.soleur.ai subdomain (Resend Inbound — operator email
# triage, #5103, ADR-055). This is a DEDICATED Resend domain, distinct from the
# apex soleur.ai (Proton) and send.soleur.ai (Resend outbound). Resend receiving
# is domain-scoped, so the Receiving MX lands on inbound.soleur.ai — NEVER the
# apex — keeping the operator's Proton apex mail untouched. Proton Sieve forwards
# ops@soleur.ai → <addr>@inbound.soleur.ai; mail to inbound.soleur.ai is received
# by Resend, which fires the email.received webhook. Values minted by the
# pre-merge bootstrap run (resend-inbound-bootstrap.sh) 2026-06-11.
resource "cloudflare_record" "dkim_resend_inbound" {
  zone_id = var.cf_zone_id
  name    = "resend._domainkey.inbound"
  content = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCy1ZgdHIVsVsFSdqNBTBZkUIhvXSDFee/BRBpLyUcQZjstW/0M6y8ZEp81siNH1J+NT+gvSacyEHpc3DZLanXswnJ5h1ooBpjjvajxROqfoYc2GjMKtCbN+3CWuISj6GArG8fxoNE/OoSgsc58lrYyTK8UsTPskTE5c2fDF4FzPQIDAQAB"
  type    = "TXT"
  ttl     = 1
}

resource "cloudflare_record" "spf_send_inbound" {
  zone_id = var.cf_zone_id
  name    = "send.inbound"
  content = "v=spf1 include:amazonses.com ~all"
  type    = "TXT"
  ttl     = 1
}

resource "cloudflare_record" "mx_send_inbound" {
  zone_id  = var.cf_zone_id
  name     = "send.inbound"
  content  = "feedback-smtp.eu-west-1.amazonses.com"
  type     = "MX"
  priority = 10
  ttl      = 1
}

# Receiving MX — the load-bearing inbound record. Mail to inbound.soleur.ai is
# routed to Amazon SES (eu-west-1) which Resend receives. Apex Proton MX is
# untouched (this is a subdomain record).
resource "cloudflare_record" "mx_receiving_inbound" {
  zone_id  = var.cf_zone_id
  name     = "inbound"
  content  = "inbound-smtp.eu-west-1.amazonaws.com"
  type     = "MX"
  priority = 10
  ttl      = 1
}

# Multi-rua: aggregate reports fan out to (1) the apex Proton mailbox and
# (2) the free Postmark DMARC aggregator, which turns reports into a
# human-readable weekly failure digest (#3012, brainstorm 2026-06-02).
# Policy is UNCHANGED — only the rua list is extended. Do NOT adopt
# Postmark's suggested "p=none" record; that would downgrade enforcement.
resource "cloudflare_record" "dmarc" {
  zone_id = var.cf_zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=reject; rua=mailto:dmarc-reports@soleur.ai,mailto:re+yyggnc2ymkj@dmarc.postmarkapp.com; pct=100"
  type    = "TXT"
  ttl     = 1
}

# Supabase custom domain -- branded API endpoint for OAuth callbacks and client connections.
# Must NOT be proxied: Supabase needs direct DNS for SSL certificate verification.
resource "cloudflare_record" "supabase_custom_domain" {
  zone_id = var.cf_zone_id
  name    = "api"
  content = "ifsccnjhymdmidffkzhl.supabase.co"
  type    = "CNAME"
  proxied = false
  ttl     = 60
}

# ACME challenge for Supabase custom domain SSL certificate verification.
# Value from `supabase domains create` output.
resource "cloudflare_record" "supabase_acme_challenge" {
  zone_id = var.cf_zone_id
  name    = "_acme-challenge.api"
  content = "UQm8-KEXBYA17JfJvT_3STiqv4T-ti6VimNwAxkErFo"
  type    = "TXT"
  ttl     = 60
}

# SPF for root domain -- @soleur.ai mailboxes send via Proton Mail.
# Sending subdomain send.soleur.ai (Resend/SES) has its own SPF record.
# Softfail (~all) per Proton's recommended widening; tighten to -all once
# deliverability is observed clean across all major receivers.
resource "cloudflare_record" "spf_root" {
  zone_id = var.cf_zone_id
  name    = "soleur.ai"
  content = "v=spf1 include:_spf.protonmail.ch ~all"
  type    = "TXT"
  ttl     = 1
}

# Google Search Console domain verification (required for OAuth consent screen branding, see #1398)
resource "cloudflare_record" "google_site_verification" {
  zone_id = var.cf_zone_id
  name    = "soleur.ai" # Use FQDN, not "@" -- CF API normalizes @ to FQDN, causing perpetual drift
  content = "google-site-verification=zbo0JKaBz4mZwUq9sv_gXtmw5RmiN6dw_O8bqK2nq6s"
  type    = "TXT"
  ttl     = 1
}

# ProtonMail domain ownership verification (apex TXT). Required to enable
# Proton Mail on soleur.ai.
resource "cloudflare_record" "protonmail_verification" {
  zone_id = var.cf_zone_id
  name    = "soleur.ai" # Use FQDN, not "@" -- CF API normalizes @ to FQDN, causing perpetual drift
  content = "protonmail-verification=669dab6390579ccb6db592dca20dbd199bacce2d"
  type    = "TXT"
  ttl     = 1
}

# ProtonMail receiving (apex MX). Primary + secondary as published by Proton.
# Apex SPF widened above to include _spf.protonmail.ch for sending.
resource "cloudflare_record" "protonmail_mx_primary" {
  zone_id  = var.cf_zone_id
  name     = "soleur.ai" # Use FQDN, not "@" -- CF API normalizes @ to FQDN, causing perpetual drift
  content  = "mail.protonmail.ch"
  type     = "MX"
  priority = 10
  ttl      = 1
}

resource "cloudflare_record" "protonmail_mx_secondary" {
  zone_id  = var.cf_zone_id
  name     = "soleur.ai" # Use FQDN, not "@" -- CF API normalizes @ to FQDN, causing perpetual drift
  content  = "mailsec.protonmail.ch"
  type     = "MX"
  priority = 20
  ttl      = 1
}

# ProtonMail DKIM signing -- three CNAMEs per Proton's per-domain key rotation
# scheme. Targets are issued once per domain in Proton's admin panel; do not
# regenerate without coordinating with Proton support.
# Not proxied -- DKIM signature lookups must hit Proton's authoritative NS
# directly so receivers can resolve the published public key.
resource "cloudflare_record" "protonmail_dkim_1" {
  zone_id = var.cf_zone_id
  name    = "protonmail._domainkey"
  content = "protonmail.domainkey.d76oa5imuaqfja4roobbqhui6tif2utb6kzwbzuxr7u34wiq3yxza.domains.proton.ch"
  type    = "CNAME"
  proxied = false
  ttl     = 1
}

resource "cloudflare_record" "protonmail_dkim_2" {
  zone_id = var.cf_zone_id
  name    = "protonmail2._domainkey"
  content = "protonmail2.domainkey.d76oa5imuaqfja4roobbqhui6tif2utb6kzwbzuxr7u34wiq3yxza.domains.proton.ch"
  type    = "CNAME"
  proxied = false
  ttl     = 1
}

resource "cloudflare_record" "protonmail_dkim_3" {
  zone_id = var.cf_zone_id
  name    = "protonmail3._domainkey"
  content = "protonmail3.domainkey.d76oa5imuaqfja4roobbqhui6tif2utb6kzwbzuxr7u34wiq3yxza.domains.proton.ch"
  type    = "CNAME"
  proxied = false
  ttl     = 1
}

# GitHub Pages -- docs site (soleur.ai apex + www redirect)
# These records were previously created via dashboard; imported to Terraform for IaC governance.
#
# www→apex canonicalizer contract (#4584, spun out of #4577):
#   The live `www.soleur.ai → 301 → soleur.ai` redirect (host- and
#   path-preserving) is GitHub-Pages-owned — it is NOT a Cloudflare Redirect
#   Rule or Page Rule. There is no cloudflare_page_rule / cloudflare_list /
#   http_request_redirect resource anywhere in this repo. GitHub Pages auto-301s
#   every non-primary alias to the primary custom domain configured by the
#   repo-tracked file `plugins/soleur/docs/CNAME = "soleur.ai"` (the apex).
#   The www 301 response carries Fastly/GitHub origin headers
#   (via: 1.1 varnish, x-fastly-request-id, x-github-request-id).
#
#   The managed substrate that makes this work is exactly two facts below:
#     - `cloudflare_record.github_pages` — apex A-records → GitHub Pages IPs, proxied.
#     - `cloudflare_record.www`          — www CNAME → jikig-ai.github.io, proxied.
#   Flip `docs/CNAME` to www, or repoint either record off GitHub Pages, and the
#   canonical direction inverts/breaks. Pure TF resource-drift sees the records
#   but neither the CNAME file nor the semantic contract, so
#   `www-apex-canonicalizer.test.sh` asserts all three together at CI time.
#   Runtime drift of the 301 is guarded by sentry_uptime_monitor.soleur_www.
resource "cloudflare_record" "github_pages" {
  for_each = toset([
    "185.199.108.153",
    "185.199.109.153",
    "185.199.110.153",
    "185.199.111.153",
  ])

  zone_id = var.cf_zone_id
  name    = "soleur.ai"
  content = each.value
  type    = "A"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "www" {
  zone_id = var.cf_zone_id
  name    = "www"
  content = "jikig-ai.github.io"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "github_pages_challenge" {
  zone_id = var.cf_zone_id
  name    = "_github-pages-challenge-jikig-ai"
  content = "8fcc2ac37a5abcac6cd2c71556053f"
  type    = "TXT"
  ttl     = 1
}

# Buttondown managed sending domain -- NS delegation for mail.soleur.ai
# Buttondown manages DKIM/SPF/MX records within this subdomain automatically.
resource "cloudflare_record" "buttondown_ns1" {
  zone_id = var.cf_zone_id
  name    = "mail"
  content = "ns1.onbuttondown.com"
  type    = "NS"
  ttl     = 1
}

resource "cloudflare_record" "buttondown_ns2" {
  zone_id = var.cf_zone_id
  name    = "mail"
  content = "ns2.onbuttondown.com"
  type    = "NS"
  ttl     = 1
}

# DNSSEC for soleur.ai -- chain of trust via DS record at .ai registry.
# Cloudflare Registrar auto-propagates DS records via CDS/CDNSKEY scanning.
# Status transitions: disabled -> pending -> active (1-2 days for registry propagation).
# Status is computed-only in provider v4.x (not configurable).
# Verify: dig soleur.ai DS @8.8.8.8 +short
resource "cloudflare_zone_dnssec" "soleur_ai" {
  zone_id = var.cf_zone_id
}

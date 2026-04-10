resource "cloudflare_record" "app" {
  zone_id = var.cf_zone_id
  name    = "app"
  content = hcloud_server.web.ipv4_address
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

resource "cloudflare_record" "dmarc" {
  zone_id = var.cf_zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@soleur.ai; pct=100"
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

# Google Search Console domain verification (required for OAuth consent screen branding, see #1398)
resource "cloudflare_record" "google_site_verification" {
  zone_id = var.cf_zone_id
  name    = "soleur.ai" # Use FQDN, not "@" -- CF API normalizes @ to FQDN, causing perpetual drift
  content = "google-site-verification=zbo0JKaBz4mZwUq9sv_gXtmw5RmiN6dw_O8bqK2nq6s"
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
#
# The lifecycle block prevents perpetual drift during the pending -> active
# transition. The API returns "pending" while the DS record propagates to the
# .ai registry, but our desired state is "active". Without ignore_changes,
# every terraform plan would show a diff. Remove the lifecycle block once
# status reaches "active" (verify via: dig soleur.ai DS @8.8.8.8 +short).
resource "cloudflare_zone_dnssec" "soleur_ai" {
  zone_id = var.cf_zone_id
}

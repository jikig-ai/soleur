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

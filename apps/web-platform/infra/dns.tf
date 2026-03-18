resource "cloudflare_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = "app"
  content = hcloud_server.web.ipv4_address
  type    = "A"
  proxied = true
  ttl     = 1 # Auto when proxied
}

# Email authentication records for Resend SMTP (sends via Amazon SES, eu-west-1)

resource "cloudflare_record" "dkim_resend" {
  zone_id = var.cloudflare_zone_id
  name    = "resend._domainkey"
  content = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDOftt0CO6q9Jyccw6ny9j6Nk5scYRFxubRtQix7QFaUmTtBpvT6A6yn5va1VMM+f6SrU6rKqmERhCcsMfCWE/GOgg7HiOhC5MOmSaEXL5QxcQxIVNBhgMG4EH/B/DL+dzYXoj8qN5k50PCnD2AyrwlYuId7hkKj8QajGtogcMDLwIDAQAB"
  type    = "TXT"
  ttl     = 1
}

resource "cloudflare_record" "spf_send" {
  zone_id = var.cloudflare_zone_id
  name    = "send"
  content = "v=spf1 include:amazonses.com ~all"
  type    = "TXT"
  ttl     = 1
}

resource "cloudflare_record" "mx_send" {
  zone_id = var.cloudflare_zone_id
  name    = "send"
  content = "feedback-smtp.eu-west-1.amazonses.com"
  type    = "MX"
  priority = 10
  ttl     = 1
}

resource "cloudflare_record" "dmarc" {
  zone_id = var.cloudflare_zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=none;"
  type    = "TXT"
  ttl     = 1
}

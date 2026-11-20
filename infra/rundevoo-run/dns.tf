# Safe-by-default DNS posture for the parked rundevoo.run zone (phase 1 of
# #12971; the product shape is deferred to #12972). The apex must not send
# email, so the zone declares that unambiguously rather than leaving the
# spoofing surface implicit.

# RFC 7505 null MX — declares the apex accepts no mail. `content = "."` is the
# literal null-MX target (verified against the local 4.52.7 provider schema
# before authoring — provider docs drift, see
# knowledge-base/project/learnings/integration-issues/2026-04-10-context7-terraform-provider-version-mismatch.md).
resource "cloudflare_record" "null_mx" {
  zone_id  = cloudflare_zone.rundevoo_run.id
  name     = "rundevoo.run" # Use FQDN, not "@" -- CF API normalizes @ to FQDN, causing perpetual drift
  content  = "."
  type     = "MX"
  priority = 0
  ttl      = 1
  proxied  = false
}

# Deny-all SPF — no host may send mail as @rundevoo.run.
resource "cloudflare_record" "spf_deny_all" {
  zone_id = cloudflare_zone.rundevoo_run.id
  name    = "rundevoo.run" # Use FQDN, not "@" -- CF API normalizes @ to FQDN, causing perpetual drift
  content = "v=spf1 -all"
  type    = "TXT"
  ttl     = 1
  proxied = false
}

# DMARC p=reject — receivers drop mail claiming @rundevoo.run. No rua: the
# domain sends nothing, so aggregate reports carry no signal worth the
# address's upkeep.
resource "cloudflare_record" "dmarc_reject" {
  zone_id = cloudflare_zone.rundevoo_run.id
  name    = "_dmarc.rundevoo.run" # literal FQDN form, same normalization trap
  content = "v=DMARC1; p=reject"
  type    = "TXT"
  ttl     = 1
  proxied = false
}

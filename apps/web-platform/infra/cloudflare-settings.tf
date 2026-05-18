# Cloudflare zone-level security settings managed via Terraform.
#
# HSTS must match the origin value defined in
# apps/web-platform/lib/security-headers.ts (max-age=63072000, 2 years).
# The edge previously rewrote origin HSTS down to 1 year via dashboard
# configuration, breaking preload-list eligibility (min 63072000).
# See #2527.
#
# Uses cloudflare_zone_settings_override from the v4 provider. This PATCHes
# zone settings in place and takes ownership of the dashboard value on first
# apply (no import needed). v5 migration splits this into per-setting
# resources and is out of scope here.

resource "cloudflare_zone_settings_override" "soleur_ai" {
  provider = cloudflare.zone_settings
  zone_id  = var.cf_zone_id

  settings {
    security_header {
      enabled            = true
      max_age            = 63072000
      include_subdomains = true
      preload            = true
      nosniff            = true
    }

    # 2026-05-18 incident remediation: Cloudflare's zone-level
    # Always Use HTTPS toggle force-redirected the Let's Encrypt
    # HTTP-01 challenge at /.well-known/acme-challenge/* to HTTPS
    # before GitHub Pages could serve the validator token, breaking
    # cert renewal. Edge-level HTTPS upgrade with an ACME-path
    # exception is now inlined as Rule 10 of
    # `cloudflare_ruleset.seo_page_redirects` (seo-rulesets.tf) —
    # CF only allows one user-defined ruleset per (zone, phase) and
    # `skip` action is not valid on http_request_dynamic_redirect
    # (CF API error 20016), so the ACME bypass is expressed as a
    # negative-match clause in Rule 10's expression rather than as
    # a separate skip rule. This toggle MUST stay "off"; if re-enabled,
    # the next ACME renewal (every ~60 days) fails again. See
    # knowledge-base/operations/domains.md.
    always_use_https = "off"
  }
}

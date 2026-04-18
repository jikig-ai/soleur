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
  }
}

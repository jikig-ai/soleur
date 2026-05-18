# Edge-level HTTPS upgrade for soleur.ai apex and www, with an explicit
# exception for /.well-known/acme-challenge/* so GitHub Pages can complete
# Let's Encrypt HTTP-01 challenges.
#
# Background (2026-05-18 incident): GitHub Pages cert for soleur.ai expired
# 2026-05-17. ACME renewal failed with bad_authz because Cloudflare's
# zone-level "Always Use HTTPS" force-redirected the
# /.well-known/acme-challenge/* validator request to HTTPS before
# GitHub Pages' acme-challenge listener (HTTP-only) could respond.
# Site returned Cloudflare 526 (Invalid SSL certificate at origin).
#
# Fix: turn the zone-level toggle OFF (codified in IaC at
# cloudflare-settings.tf `cloudflare_zone_settings_override.soleur_ai` via
# `always_use_https = "off"` — v4 provider supports this directly,
# confirmed via Context7 against the v5-migration guide on main, no v5
# migration required) AND replace it with this path-aware ruleset.
#
# Operator: see knowledge-base/operations/domains.md for the apply
# runbook and post-apply verification curls.
#
# Provider alias `cloudflare.rulesets` is defined in main.tf, bound to
# var.cf_api_token_rulesets. Token scope (variables.tf:69) already
# includes Single Redirect Rules:Edit + Transform Rules:Edit on the
# http_request_dynamic_redirect phase — no token change required.

resource "cloudflare_ruleset" "acme_aware_https_upgrade" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "ACME-aware HTTPS upgrade (soleur.ai apex + www)"
  description = "301 HTTP->HTTPS for every path EXCEPT /.well-known/acme-challenge/* so Let's Encrypt HTTP-01 can renew the GitHub Pages cert. See 2026-05-18 PIR."
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  # Rule 1: skip this ruleset entirely for ACME challenge paths on plain
  # HTTP. MUST sit before Rule 2 — Cloudflare evaluates rules top-down
  # within a ruleset and `skip` with ruleset = "current" short-circuits
  # the remainder.
  rules {
    action      = "skip"
    description = "Allow plain HTTP for /.well-known/acme-challenge/* (Let's Encrypt HTTP-01)"
    enabled     = true
    expression  = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"} and starts_with(http.request.uri.path, \"/.well-known/acme-challenge/\") and not ssl)"
    action_parameters {
      ruleset = "current"
    }
  }

  # Rule 2: 301 every other plain-HTTP request to HTTPS, preserving path
  # and query string. `target_url.expression` is the dynamic form (vs.
  # static target_url.value); requires Transform Rules:Edit in the token
  # scope (already granted, see variables.tf:69). preserve_query_string
  # is load-bearing for UTM-tagged campaign links.
  rules {
    action      = "redirect"
    description = "Force HTTPS on soleur.ai apex + www (all paths except ACME challenge)"
    enabled     = true
    expression  = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"} and not ssl)"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = true
        target_url {
          expression = "concat(\"https://\", http.host, http.request.uri.path)"
        }
      }
    }
  }
}

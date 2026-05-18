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
# Provider alias `cloudflare.rulesets` is defined in main.tf (lines
# ~50-59), bound to var.cf_api_token_rulesets. Token scope
# (variables.tf:69) already includes Single Redirect Rules:Edit +
# Transform Rules:Edit on the http_request_dynamic_redirect phase —
# no token change required.

# Sibling-ruleset ordering note: `seo-rulesets.tf` also declares a
# `cloudflare_ruleset` on the same `http_request_dynamic_redirect` phase.
# Today the SEO ruleset uses path equality (`http.request.uri.path eq
# "/pages/<x>.html"`), so no SEO rule overlaps `/.well-known/acme-challenge/*`.
# If future SEO rules adopt `starts_with` or wildcard path matching, verify
# they cannot match the ACME path BEFORE Rule 1 here runs — otherwise the
# ACME exception would silently regress depending on phase evaluation order
# (which is not pinned in IaC; see follow-up issue tracker).

resource "cloudflare_ruleset" "acme_aware_https_upgrade" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "ACME-aware HTTPS upgrade (soleur.ai zone)"
  description = "301 HTTP->HTTPS for every path EXCEPT /.well-known/acme-challenge/* on apex + www so Let's Encrypt HTTP-01 can renew the GitHub Pages cert. See 2026-05-18 PIR."
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  # Rule 1: skip this ruleset entirely for ACME challenge paths on plain
  # HTTP. Host-scoped to apex + www because only GitHub Pages (which
  # serves those two hosts) uses LE HTTP-01 origin-cert renewal — other
  # subdomains use Cloudflare-managed edge certs that do not need a
  # plain-HTTP carve-out. MUST sit before Rule 2 — Cloudflare evaluates
  # rules top-down within a ruleset and `skip` with ruleset = "current"
  # short-circuits the remainder.
  rules {
    action      = "skip"
    description = "Allow plain HTTP for /.well-known/acme-challenge/* on apex + www (Let's Encrypt HTTP-01)"
    enabled     = true
    expression  = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"} and starts_with(http.request.uri.path, \"/.well-known/acme-challenge/\") and not ssl)"

    # logging { enabled = true } mirrors the pattern in bot-allowlist.tf
    # for skip actions — Cloudflare auto-enables logging on skip rules
    # and declaring it here prevents the provider from planning a
    # replacement on every run.
    logging {
      enabled = true
    }

    action_parameters {
      ruleset = "current"
    }
  }

  # Rule 2: 301 every other plain-HTTP request to HTTPS, preserving path
  # and query string. The expression matches ANY plain-HTTP request to
  # the zone (`not ssl`) — restoring the zone-wide HTTPS-upgrade behavior
  # that the disabled `always_use_https` toggle used to provide, with
  # only the ACME path on apex + www (Rule 1) carved out.
  # `target_url.expression` is the dynamic form (vs. static
  # target_url.value); requires Transform Rules:Edit in the token scope
  # (already granted, see variables.tf:69). preserve_query_string is
  # load-bearing for UTM-tagged campaign links.
  rules {
    action      = "redirect"
    description = "Force HTTPS on the soleur.ai zone (all hosts, all paths except ACME challenge on apex + www)"
    enabled     = true
    expression  = "(not ssl)"
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

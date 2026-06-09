# Cloudflare Bulk Redirects — legacy /pages/legal/<slug>.html → clean /legal/<slug>/ 301s.
#
# Why a separate file / separate product (not more rules in seo-rulesets.tf):
#   The 9 legacy legal-page redirects were DEFERRED in seo-rulesets.tf (see the
#   comment at seo-rulesets.tf:59-66). Cloudflare Free-tier zones cap the
#   `http_request_dynamic_redirect` phase at 10 rules, and that ruleset's 10
#   slots are fully consumed (8 page redirects + 1 terms rename + 1 load-bearing
#   HTTPS catch-all that protects cross-subdomain credentials and ACME renewal —
#   it cannot be evicted, PR #3974). `regex_replace()` consolidation would need
#   Business/WAF Advanced (paid). Bulk Redirects is a SEPARATE Free-tier product
#   on a DIFFERENT phase (`http_request_redirect`, account-level) with its own
#   quota — so these 9 legal slugs land here with zero contention on the zone
#   ruleset and zero paid upgrade.
#
# Root cause being fixed: without an edge 301 these URLs are served the HTTP-200
# meta-refresh fallback (plugins/soleur/docs/page-redirects.njk), which Google
# Search Console classifies as "Crawled - currently not indexed" (GSC drilldown
# 2026-06-09). A deterministic 301 moves them out of that bucket. The same stubs
# also carry `<meta name="robots" content="noindex">` now as a defensive interim.
#
# Provider/token scope: this resource is ACCOUNT-level (account_id, not zone_id) —
# the only account-scoped Cloudflare ruleset in the repo. The `cloudflare.rulesets`
# alias's token (var.cf_api_token_rulesets) is currently ZONE-scoped only
# (Cache/WAF/Single-Redirect/Transform on soleur.ai). Bulk Redirects additionally
# require account-level `Account Rulesets:Edit` + `Account Filter Lists:Edit`. The
# token MUST be widened before apply succeeds — flagged BLOCKING in the PR body.
# There is no Terraform-managed path for CF API-token permission grants.
#
# Provider is pinned cloudflare/cloudflare 4.52.7 (~> 4.0) — ALL HCL below uses v4
# BLOCK syntax (`item { value { redirect { ... } } }`, `action_parameters { from_list {} }`).
# context7 / registry `latest` show v5 (`items = [{...}]` attribute-set) — do NOT copy.
# `terraform validate` is the catch for v4-vs-v5 schema drift.
#
# See:
#   - knowledge-base/project/plans/2026-06-09-fix-gsc-legal-page-redirects-plan.md
#   - issue #3297 (GSC indexing fixes feature), #3328 (meta-refresh source deletion follow-up)
#   - apps/web-platform/infra/seo-rulesets.tf:59-66 (the deferral this resolves)
#   - apps/web-platform/infra/tunnel.tf (account_id-scoped resource precedent)

resource "cloudflare_list" "legal_redirects" {
  provider    = cloudflare.rulesets
  account_id  = var.cf_account_id
  name        = "legal_redirects" # referenced by name from the ruleset's from_list
  kind        = "redirect"
  description = "Legacy /pages/legal/*.html -> clean /legal/<slug>/ 301s. See plan 2026-06-09, #3297, #3328."

  # Apex, host-less source_url (Bulk Redirects strips the scheme from the request
  # URL before matching). include_subdomains = "enabled" (v4 string enum, NOT a
  # bool — provider schema: type=string) so legacy www.soleur.ai deep
  # links collapse to the apex target in a single hop. 10 pairs: 9 legal slugs
  # (clean-slug == source-slug) + the terms-of-service -> terms-and-conditions rename alias.

  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/privacy-policy.html"
        target_url            = "https://soleur.ai/legal/privacy-policy/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/cookie-policy.html"
        target_url            = "https://soleur.ai/legal/cookie-policy/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/gdpr-policy.html"
        target_url            = "https://soleur.ai/legal/gdpr-policy/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/acceptable-use-policy.html"
        target_url            = "https://soleur.ai/legal/acceptable-use-policy/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/data-protection-disclosure.html"
        target_url            = "https://soleur.ai/legal/data-protection-disclosure/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/individual-cla.html"
        target_url            = "https://soleur.ai/legal/individual-cla/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/corporate-cla.html"
        target_url            = "https://soleur.ai/legal/corporate-cla/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/disclaimer.html"
        target_url            = "https://soleur.ai/legal/disclaimer/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/terms-and-conditions.html"
        target_url            = "https://soleur.ai/legal/terms-and-conditions/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
  # Rename alias: terms-of-service has no source page; legacy slug -> terms-and-conditions.
  item {
    value {
      redirect {
        source_url            = "soleur.ai/pages/legal/terms-of-service.html"
        target_url            = "https://soleur.ai/legal/terms-and-conditions/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
}

resource "cloudflare_ruleset" "bulk_redirects" {
  provider    = cloudflare.rulesets
  account_id  = var.cf_account_id # ACCOUNT-level (not zone_id) — the novel axis vs every other ruleset in the repo
  name        = "Legal page bulk redirects"
  description = "Account http_request_redirect ruleset bound to the legal_redirects list. See plan 2026-06-09, #3297."
  kind        = "root"
  phase       = "http_request_redirect"

  rules {
    action      = "redirect"
    description = "301 legacy /pages/legal/*.html via the legal_redirects bulk list"
    enabled     = true
    expression  = "http.request.full_uri in $legal_redirects"

    action_parameters {
      from_list {
        name = "legal_redirects"
        key  = "http.request.full_uri"
      }
    }
  }
}

# Cloudflare Bulk Redirects — legacy /pages/legal/<slug>.html → clean /legal/<slug>/ 301s
# (plus the orphaned blog reslug; 12 exact pairs total, see the list below).
#
# Why a separate file / separate product (not more rules in seo-rulesets.tf):
#   The 9 legacy legal-page redirects were DEFERRED in seo-rulesets.tf (see the
#   2026-06-09 note there). Cloudflare Free-tier zones cap the
#   `http_request_dynamic_redirect` phase at 10 rules, and that ruleset's 10
#   slots are fully consumed (8 page redirects + 1 terms rename + 1 load-bearing
#   HTTPS catch-all that protects cross-subdomain credentials and ACME renewal —
#   it cannot be evicted, PR #3974). `regex_replace()` consolidation would need
#   Business/WAF Advanced (paid). Bulk Redirects is a SEPARATE Free-tier product
#   on a DIFFERENT phase (`http_request_redirect`, account-level) with its own
#   quota — so these redirects land here with zero contention on the zone
#   ruleset and zero paid upgrade.
#
# Execution order (verified vs CF docs 2026-06-09, rules/url-forwarding/):
#   Single Redirects (zone `http_request_dynamic_redirect`) evaluate BEFORE
#   Bulk Redirects (`http_request_redirect`) — "the product executed first
#   will apply". The two rule sets are disjoint except terms-of-service (see
#   the item-level note). Plain-HTTP entries take 2 hops (zone Rule 10 HTTPS
#   catch-all first, then this list on the https re-request); HTTPS entries —
#   apex or any subdomain — are a single hop.
#
# Root cause being fixed: without an edge 301 these URLs are served the HTTP-200
# meta-refresh fallback (plugins/soleur/docs/page-redirects.njk), which Google
# Search Console classifies as "Crawled - currently not indexed" (GSC drilldown
# 2026-06-09). A deterministic 301 moves them out of that bucket. The same stubs
# also carry `<meta name="robots" content="noindex">` now as a defensive interim.
#
# Provider/token scope: this resource is ACCOUNT-level (account_id, not zone_id) —
# the only account-scoped Cloudflare ruleset in the repo. Bulk Redirects require
# account-level `Account Rulesets:Edit` + `Account Filter Lists:Edit`, which the
# `cloudflare.rulesets` token GAINED via the #5092 widen; the "token is currently
# ZONE-scoped only / MUST be widened before apply" note that stood here was
# falsified by that widen and has been removed.
#
# The authoritative permission set is the `cf_api_token_rulesets` description in
# variables.tf (the scope ledger) — do not re-enumerate it here. There is no
# Terraform-managed path for CF API-token permission grants; see ADR-130 for the
# widen-vs-mint decision test and the mandatory retained-scope probe set.
#
# Provider is pinned cloudflare/cloudflare 4.52.7 (~> 4.0) — ALL HCL below uses v4
# BLOCK syntax (`item { value { redirect { ... } } }`, `action_parameters { from_list {} }`).
# context7 / registry `latest` show v5 (`items = [{...}]` attribute-set) — do NOT copy.
# `terraform validate` is the catch for v4-vs-v5 schema drift.
#
# See:
#   - the 2026-06-09 fix-gsc-legal-page-redirects plan (archived under
#     knowledge-base/project/plans/archive/)
#   - issue #3367 (the canonical Bulk Redirects refactor tracker this implements)
#   - issue #3297 (GSC indexing fixes feature), #3328 (meta-refresh source deletion follow-up)
#   - apps/web-platform/infra/seo-rulesets.tf (the 2026-06-09 note — the deferral this resolves)
#   - apps/web-platform/infra/tunnel.tf (account_id-scoped resource precedent)

resource "cloudflare_list" "legal_redirects" {
  provider    = cloudflare.rulesets
  account_id  = var.cf_account_id
  name        = "legal_redirects" # referenced by name from the ruleset's from_list
  kind        = "redirect"
  description = "Legacy /pages/legal/*.html -> /legal/<slug>/ 301s + blog reslug. See plan 2026-06-09, #3367, #3297, #3328."

  # Apex, host-less source_url (scheme-less sources match both http and https).
  # include_subdomains = "enabled" (v4 string enum, NOT a bool — provider
  # schema: type=string) so legacy www.soleur.ai deep links collapse to the
  # apex target. CAVEAT: this matches EVERY proxied subdomain (app, deploy,
  # ssh, ...), not just www — verified safe today (no subdomain serves these
  # exact paths; api.soleur.ai is unproxied), but a future subdomain that
  # legitimately serves one of these paths would be hijacked by this
  # account-level rule. preserve_query_string = "enabled" deliberately
  # diverges from the zone redirects' `false`: these are SEO 301s where
  # dropping campaign params (?utm_*) on the hop loses attribution; targets
  # are static pages with no query-reflection surface.
  # 12 pairs: 9 legal slugs (clean-slug == source-slug) + the terms-of-service
  # -> terms-and-conditions rename alias + 2 shapes of the blog reslug.

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
  # NOTE: deliberately duplicates zone Rule 9 (seo-rulesets.tf "terms-of-service"
  # rule). Single Redirects evaluate BEFORE Bulk Redirects, so on apex+www the
  # zone rule wins (and drops the query string); this entry remains live only
  # for other subdomains via include_subdomains. Identical target on both
  # surfaces — if one ever changes, change the other. Retiring zone Rule 9 to
  # free a slot is a candidate follow-up once the bulk apply is verified (#3367).
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
  # Blog reslug: its zone rule was evicted 2026-05-18 to make room for the
  # HTTPS catch-all (seo-rulesets.tf "2026-05-18" note) and it has had NO edge
  # 301 since — the same GSC crawled-not-indexed class this file fixes. Two
  # shapes because Bulk Redirects match full_uri EXACTLY: the directory URL
  # and the explicit index.html are distinct keys.
  item {
    value {
      redirect {
        source_url            = "soleur.ai/blog/what-is-company-as-a-service/"
        target_url            = "https://soleur.ai/company-as-a-service/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
  item {
    value {
      redirect {
        source_url            = "soleur.ai/blog/what-is-company-as-a-service/index.html"
        target_url            = "https://soleur.ai/company-as-a-service/"
        status_code           = 301
        include_subdomains    = "enabled"
        preserve_query_string = "enabled"
      }
    }
  }
}

# Naming: no `seo_` prefix (vs sibling zone rulesets seo_page_redirects /
# seo_response_headers) because this is THE single account-level
# http_request_redirect phase owner — future non-SEO bulk lists would attach
# additional rules here rather than new rulesets. The list keeps its original
# `legal_redirects` name even though it now also carries the blog reslug:
# renaming a list ripples through the rule expression, the workflow -target
# allow-list, and the live CF object for zero behavioral gain.
resource "cloudflare_ruleset" "bulk_redirects" {
  provider    = cloudflare.rulesets
  account_id  = var.cf_account_id # ACCOUNT-level (not zone_id) — the novel axis vs every other ruleset in the repo
  name        = "Legacy URL bulk redirects"
  description = "Account http_request_redirect ruleset bound to the legal_redirects list. See plan 2026-06-09, #3367, #3297."
  kind        = "root"
  phase       = "http_request_redirect"

  rules {
    action      = "redirect"
    description = "301 legacy URLs (/pages/legal/*.html + blog reslug) via the legal_redirects bulk list"
    enabled     = true
    expression  = "http.request.full_uri in $legal_redirects"

    action_parameters {
      from_list {
        # Resource reference (not a string literal) so Terraform has a graph
        # edge: the list MUST exist before the ruleset that binds it, or the
        # CF API rejects the rule on first apply (nondeterministic ordering
        # failure that would masquerade as the token-scope failure documented
        # in the header). The `$legal_redirects` in `expression` above must
        # stay literal — only this binding creates the dependency.
        name = cloudflare_list.legal_redirects.name
        key  = "http.request.full_uri"
      }
    }
  }
}

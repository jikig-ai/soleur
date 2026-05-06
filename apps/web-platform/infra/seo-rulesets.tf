# SEO and indexing-hygiene rulesets at the Cloudflare edge.
#
# Provider alias `cloudflare.rulesets` is defined in main.tf (lines ~50-71),
# bound to var.cf_api_token_rulesets. Existing siblings on the same alias:
# cloudflare_ruleset.cache_shared_binaries (cache.tf), allowlist_ai_crawlers
# (bot-allowlist.tf). Token scope expanded to include Single Redirect
# Rules:Edit + Transform Rules:Edit (see variables.tf). Both run BEFORE origin fetch, so they apply regardless of
# what GitHub Pages emits — the legacy meta-refresh templates at
# plugins/soleur/docs/page-redirects.njk + _data/pageRedirects.js can be
# deleted in a follow-up PR once these 301s are verified live.
#
# Background: Google Search Console (snapshot 2026-05-05) flagged 29 pages on
# soleur.ai across five Critical-Indexing categories. Two systemic root causes:
#   (A) Apex/www canonical mismatch — _data/site.json declared apex while
#       Cloudflare 301s every apex URL to www. Fixed in Phase 1 of the plan.
#   (B) Meta-refresh redirect template — Google classifies these soft signals
#       non-deterministically across "Page with redirect", "Crawled - not
#       indexed", and "Alternate page with proper canonical tag" buckets.
#       HTTP 301 at the edge is deterministic.
# Plus subdomain hardening on api.soleur.ai (Supabase REST root) and
# deploy.soleur.ai (Cloudflare Zero Trust Access surface) — discovered by
# Googlebot via Certificate Transparency log enumeration. A 403 is not
# equivalent to noindex; X-Robots-Tag is.
#
# See:
#   - issue #3297 (the GSC fixes feature)
#   - knowledge-base/project/plans/2026-05-05-feat-gsc-indexing-fixes-plan.md
#   - knowledge-base/project/learnings/2026-05-05-gsc-indexing-triage-patterns.md
#   - knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md
#     (verify Transform Rule fires on the CF Access challenge response)

# ── Vector 2: Single Redirects (HTTP 301 at edge) ────────────────────────────
#
# Replaces meta-refresh template _data/pageRedirects.js.
#
# This phase (`http_request_dynamic_redirect`) runs before origin fetch, so
# the 301 is served whether GitHub Pages still emits the legacy HTML files or
# not. Source-template deletion is tracked in follow-up issue #3328.
#
# Free-tier Cloudflare zones cap dynamic-redirect rules at 10 per phase. The
# initial 19-rule rollout (one rule per source path) hit that limit on first
# apply — see `knowledge-base/project/learnings/2026-05-06-cf-free-tier-rule-limits.md`.
# This ruleset consolidates the 19 source paths into 4 rules using
# `regex_replace()` in `target_url.expression`. Rule ORDER matters: the
# dynamic-redirect phase short-circuits on first match, so the
# `terms-of-service` rename rule must precede the generic `/pages/legal/*`
# regex rule (otherwise the regex would route /pages/legal/terms-of-service.html
# to /legal/terms-of-service/, a 404 — the slug was renamed to terms-and-conditions).
resource "cloudflare_ruleset" "seo_page_redirects" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "Legacy /pages/*.html → clean URLs (HTTP 301)"
  description = "Edge 301s replacing _data/pageRedirects.js. See issue #3297."
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  # Rule 1: terms-of-service slug rename — MUST come before Rule 3 below.
  # The legacy slug terms-of-service was renamed to terms-and-conditions; if
  # the generic /pages/legal/* regex (Rule 3) matched first, it would 301 to
  # /legal/terms-of-service/ which is a 404.
  rules {
    action      = "redirect"
    description = "Redirect /pages/legal/terms-of-service.html → /legal/terms-and-conditions/ (renamed slug)"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal/terms-of-service.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/legal/terms-and-conditions/"
        }
      }
    }
  }

  # Rule 2: top-level /pages/<slug>.html → /<slug>/.
  # Match anchors are `^/pages/[^/]+\.html$` so single-segment paths only —
  # /pages/legal/cookie-policy.html (depth 2) is intentionally NOT matched
  # here; Rule 3 handles it. /pages/legal.html (depth 1) IS matched here and
  # correctly routes to /legal/.
  # Covers: agents, skills, vision, community, getting-started, legal,
  #         pricing, changelog (8 source paths).
  rules {
    action      = "redirect"
    description = "Redirect /pages/<slug>.html → /<slug>/ (regex-consolidated, 8 source paths)"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path matches \"^/pages/[^/]+\\.html$\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          expression = "concat(\"https://www.soleur.ai\", regex_replace(http.request.uri.path, \"^/pages/([^/]+)\\.html$\", \"/$${1}/\"))"
        }
      }
    }
  }

  # Rule 3: /pages/legal/<slug>.html → /legal/<slug>/ (depth 2, regex).
  # The terms-of-service rename is excluded by Rule 1 firing first.
  # Covers: privacy-policy, terms-and-conditions, cookie-policy, gdpr-policy,
  #         acceptable-use-policy, data-protection-disclosure, individual-cla,
  #         corporate-cla, disclaimer (9 source paths).
  rules {
    action      = "redirect"
    description = "Redirect /pages/legal/<slug>.html → /legal/<slug>/ (regex-consolidated, 9 source paths)"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path matches \"^/pages/legal/[^/]+\\.html$\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          expression = "concat(\"https://www.soleur.ai/legal\", regex_replace(http.request.uri.path, \"^/pages/legal/([^/]+)\\.html$\", \"/$${1}/\"))"
        }
      }
    }
  }

  # Rule 4: blog content reslug.
  # Specific path; not part of the /pages/* pattern.
  rules {
    action      = "redirect"
    description = "Redirect /blog/what-is-company-as-a-service/index.html → /company-as-a-service/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/blog/what-is-company-as-a-service/index.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/company-as-a-service/"
        }
      }
    }
  }
}

# ── Vectors 3 + 4: Response-header X-Robots-Tag injection ─────────────────────
#
# Three rules, all in the http_response_headers_transform phase:
#   1. api.soleur.ai/*  → noindex, nofollow  (Supabase REST root)
#   2. deploy.soleur.ai/* → noindex, nofollow  (CF Access challenge surface)
#   3. www.soleur.ai/blog/feed.xml → noindex  (RSS feed)
#
# Why X-Robots-Tag and not robots.txt: a 403 is not equivalent to a noindex.
# Google still records the URL's existence and may surface it in search
# results without a snippet. X-Robots-Tag is the authoritative indexing
# control; per-subdomain robots.txt would be redundant belt-and-suspenders.
#
# IMPORTANT (deploy.soleur.ai): this hostname sits behind
# `cloudflare_zero_trust_access_application.deploy` (tunnel.tf). The default
# response IS the CF Access challenge HTML/403. Verify the Transform Rule
# fires on that challenge response, not just the origin response. If the
# Access policy intercepts before the response_headers_transform phase, this
# rule is silently a no-op — the post-merge curl verification is the
# load-bearing check (see plan Phase 4 step 6).
resource "cloudflare_ruleset" "seo_response_headers" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "X-Robots-Tag on subdomains + RSS feed"
  description = "Defense-in-depth noindex for non-public subdomains + RSS. See issue #3297."
  kind        = "zone"
  phase       = "http_response_headers_transform"

  rules {
    action      = "rewrite"
    description = "X-Robots-Tag: noindex, nofollow on api.soleur.ai GET responses"
    enabled     = true
    # Scoped to GET only — Soleur app users hit api.soleur.ai for Supabase
    # REST/Auth via POST/PATCH/DELETE/OPTIONS. Only GET responses can be
    # indexed by search engines. Trims one header byte off every write
    # request and removes any chance of header injection on CORS preflight
    # responses (X-Robots-Tag is not CORS-relevant, but defense in depth
    # narrows the surface — see #3297 user-impact-reviewer triage).
    expression = "(http.host eq \"api.soleur.ai\" and http.request.method eq \"GET\")"
    action_parameters {
      headers {
        name      = "X-Robots-Tag"
        operation = "set"
        value     = "noindex, nofollow"
      }
    }
  }

  rules {
    action      = "rewrite"
    description = "X-Robots-Tag: noindex, nofollow on deploy.soleur.ai/*"
    enabled     = true
    expression  = "(http.host eq \"deploy.soleur.ai\")"
    action_parameters {
      headers {
        name      = "X-Robots-Tag"
        operation = "set"
        value     = "noindex, nofollow"
      }
    }
  }

  rules {
    action      = "rewrite"
    description = "X-Robots-Tag: noindex on www.soleur.ai RSS feed"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/blog/feed.xml\")"
    action_parameters {
      headers {
        name      = "X-Robots-Tag"
        operation = "set"
        value     = "noindex"
      }
    }
  }
}

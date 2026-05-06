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
# Cloudflare Free-tier zones cap dynamic-redirect rules at 10 per phase,
# and `regex_replace()` in `target_url.expression` requires Business or WAF
# Advanced (cannot be used to consolidate). Both constraints discovered
# post-merge during PR #3296 apply.
#
# This ruleset declares 10 explicit rules (the Free-tier cap), prioritized:
#   - 8 top-level `/pages/<slug>.html → /<slug>/` redirects (high-traffic pages)
#   - 1 `terms-of-service → terms-and-conditions` slug rename (load-bearing —
#     the only entry with a confirmed GSC 404 bucket entry pre-fix)
#   - 1 `/blog/what-is-company-as-a-service/index.html → /company-as-a-service/` reslug
#
# Deferred to follow-up: 9 individual `/pages/legal/<slug>.html → /legal/<slug>/`
# redirects (privacy, cookie, gdpr, AUP, data-protection, individual-cla,
# corporate-cla, disclaimer, terms-and-conditions). These paths return 404
# until a Bulk Redirects refactor lands (account-scoped `cloudflare_list` of
# type "redirect" + `cloudflare_ruleset` with phase `http_request_redirect`).
# Google will recrawl from the sitemap and drop them from the redirect-bucket
# cluster — acceptable transitional state since the canonical `/legal/<slug>/`
# paths ARE in the sitemap and indexed.
resource "cloudflare_ruleset" "seo_page_redirects" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "Legacy /pages/*.html → clean URLs (HTTP 301)"
  description = "Edge 301s replacing _data/pageRedirects.js. See issue #3297."
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules {
    action      = "redirect"
    description = "Redirect /pages/agents.html → /agents/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/agents.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/agents/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/skills.html → /skills/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/skills.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/skills/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/vision.html → /vision/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/vision.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/vision/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/community.html → /community/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/community.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/community/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/getting-started.html → /getting-started/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/getting-started.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/getting-started/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/legal.html → /legal/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/legal/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/pricing.html → /pricing/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/pricing.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/pricing/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/changelog.html → /changelog/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/changelog.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/changelog/"
        }
      }
    }
  }

  # NEW: missing entry in legacy _data/pageRedirects.js — caused the 1× 404
  # in the GSC report (legal slug renamed but redirect not added).
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
#
# NOTE: the api.soleur.ai rule below is currently a no-op (DNS-only CNAME
# bypasses CF edge). See per-rule comment for diagnosis and tracker #3379.
resource "cloudflare_ruleset" "seo_response_headers" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "X-Robots-Tag on subdomains + RSS feed"
  description = "Defense-in-depth noindex for non-public subdomains + RSS. See issue #3297."
  kind        = "zone"
  phase       = "http_response_headers_transform"

  # ── Currently a no-op (verified 2026-05-06) ────────────────────────────────
  #
  # `api.soleur.ai` is a DNS-only CNAME → `ifsccnjhymdmidffkzhl.supabase.co`
  # (Supabase Custom Domain). Cloudflare Transform Rules declared on the
  # `soleur.ai` zone only fire on traffic that transits soleur.ai's CF edge
  # (proxied / orange-cloud records). DNS-only CNAMEs bypass the edge entirely,
  # so this Transform Rule never sees the request.
  #
  # Per Cloudflare: "Rules features require that your domain (or subdomain)
  # has its DNS records proxied through Cloudflare"
  # (https://developers.cloudflare.com/rules/).
  #
  # Evidence (2026-05-06):
  #   $ curl -sI -X GET https://api.soleur.ai/
  #   HTTP/2 404 — no x-robots-tag header in response.
  # Compare deploy.soleur.ai (also on this ruleset, but proxied) — its rule
  # fires correctly: x-robots-tag: noindex, nofollow confirmed live.
  #
  # Why retained: if `api.soleur.ai` is ever proxied through soleur.ai's edge
  # (orange-cloud record + Supabase Origin Certificate at the edge), this rule
  # fires automatically without further code changes. Removing it would make
  # that future flip more error-prone (silent re-exposure window).
  #
  # Re-evaluation criteria (tracker: #3379):
  #   1. Supabase Custom Domains adds a response-header-injection feature
  #      (eliminates the need for an edge rule entirely), OR
  #   2. operator chooses to proxy api.soleur.ai through soleur.ai's edge.
  #
  # Practical risk: low. `api.soleur.ai` returns 401/404/403 on every
  # authenticated path under Googlebot's anonymous identity — there is no
  # body content for Google to index. X-Robots-Tag was defense-in-depth
  # against URL-existence-recording (the "Crawled - not indexed" GSC bucket).
  rules {
    action      = "rewrite"
    description = "X-Robots-Tag: noindex, nofollow on api.soleur.ai GET responses (no-op until proxied — see #3379)"
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

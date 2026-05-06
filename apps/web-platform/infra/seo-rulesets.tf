# SEO and indexing-hygiene rulesets at the Cloudflare edge.
#
# Two rulesets, both bound to the existing cf_api_token_rulesets token (scope
# expanded to include Single Redirect Rules:Edit + Transform Rules:Edit; see
# variables.tf). Both run BEFORE origin fetch, so they apply regardless of
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
# not. Deletion of the source templates is a follow-up PR (see Phase 5 of the
# plan).
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

  rules {
    action      = "redirect"
    description = "Redirect /pages/legal/privacy-policy.html → /legal/privacy-policy/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal/privacy-policy.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/legal/privacy-policy/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/legal/terms-and-conditions.html → /legal/terms-and-conditions/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal/terms-and-conditions.html\")"
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
    description = "Redirect /pages/legal/cookie-policy.html → /legal/cookie-policy/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal/cookie-policy.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/legal/cookie-policy/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/legal/gdpr-policy.html → /legal/gdpr-policy/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal/gdpr-policy.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/legal/gdpr-policy/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/legal/acceptable-use-policy.html → /legal/acceptable-use-policy/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal/acceptable-use-policy.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/legal/acceptable-use-policy/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/legal/data-protection-disclosure.html → /legal/data-protection-disclosure/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal/data-protection-disclosure.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/legal/data-protection-disclosure/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/legal/individual-cla.html → /legal/individual-cla/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal/individual-cla.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/legal/individual-cla/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/legal/corporate-cla.html → /legal/corporate-cla/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal/corporate-cla.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/legal/corporate-cla/"
        }
      }
    }
  }

  rules {
    action      = "redirect"
    description = "Redirect /pages/legal/disclaimer.html → /legal/disclaimer/"
    enabled     = true
    expression  = "(http.host eq \"www.soleur.ai\" and http.request.uri.path eq \"/pages/legal/disclaimer.html\")"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = false
        target_url {
          value = "https://www.soleur.ai/legal/disclaimer/"
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
resource "cloudflare_ruleset" "seo_response_headers" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "X-Robots-Tag on subdomains + RSS feed"
  description = "Defense-in-depth noindex for non-public subdomains + RSS. See issue #3297."
  kind        = "zone"
  phase       = "http_response_headers_transform"

  rules {
    action      = "rewrite"
    description = "X-Robots-Tag: noindex, nofollow on api.soleur.ai/*"
    enabled     = true
    expression  = "(http.host eq \"api.soleur.ai\")"
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

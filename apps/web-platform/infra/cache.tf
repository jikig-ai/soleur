# Cloudflare cache rules for web-platform endpoints.
#
# Default Cloudflare behavior does not cache dynamic paths like
# `/api/shared/<opaque-token>` regardless of the origin's Cache-Control —
# the cache-eligibility heuristic keys off URL path extension and static-
# asset signals. This ruleset opts `/api/shared/*` into edge caching and
# has Cloudflare respect the origin `Cache-Control` the app emits (see
# `apps/web-platform/server/kb-binary-response.ts` CACHE_CONTROL_BY_SCOPE
# for the `public, max-age=60, s-maxage=300, …` policy).
#
# Without this rule, the `s-maxage=300` directive is decorative and the
# origin serves every shared-PDF byte on every view. With it, a viral
# shared PDF fans out from the edge and origin bandwidth stays flat.
resource "cloudflare_ruleset" "cache_shared_binaries" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "Edge-cache /api/shared/* per origin Cache-Control"
  description = "Opt dynamic share-token binaries into edge caching; honor origin Cache-Control directives (s-maxage, stale-while-revalidate, must-revalidate). See issue #2329."
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules {
    action      = "set_cache_settings"
    description = "Respect origin Cache-Control for shared KB binaries"
    enabled     = true
    expression  = "(starts_with(http.request.uri.path, \"/api/shared/\"))"

    action_parameters {
      cache = true

      edge_ttl {
        mode = "respect_origin"
      }

      browser_ttl {
        mode = "respect_origin"
      }
    }
  }
}

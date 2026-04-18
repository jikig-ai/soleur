---
title: Cloudflare default-bypasses dynamic paths regardless of Cache-Control
date: 2026-04-18
category: integration-issues
module: apps/web-platform/infra
tags: [cloudflare, cache-control, terraform, cache-rules]
pr: 2532
issue: 2329
---

# Cloudflare default-bypasses dynamic paths regardless of Cache-Control

## Problem

PR #2532 shipped a scope-aware `Cache-Control: public, max-age=60, s-maxage=300, stale-while-revalidate=3600, must-revalidate` on `/api/shared/[token]` binary responses, expecting Cloudflare to absorb viral-share traffic at the edge. The PR plan listed this as a non-goal:

> "No Cloudflare Page Rules / cache-rule config changes in this PR — default Cloudflare behavior honors `public, max-age=…` with standard Cache-Control, which is what this change emits."

That claim was **wrong**. Cloudflare's default cache eligibility keys off URL path extension (`.pdf`, `.png`, etc.) and static-asset heuristics, not the `Cache-Control` header. An opaque dynamic path like `/api/shared/<token>` is bypassed regardless of `public, s-maxage=300`. The application-layer change would have been a no-op at the edge.

## Solution

Add a Terraform `cloudflare_ruleset` (`http_request_cache_settings` phase) that opts the path into edge caching and respects the origin's `Cache-Control`:

```hcl
resource "cloudflare_ruleset" "cache_shared_binaries" {
  zone_id = var.cf_zone_id
  name    = "Edge-cache /api/shared/* per origin Cache-Control"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules {
    action     = "set_cache_settings"
    expression = "(starts_with(http.request.uri.path, \"/api/shared/\"))"
    enabled    = true

    action_parameters {
      cache = true
      edge_ttl    { mode = "respect_origin" }
      browser_ttl { mode = "respect_origin" }
    }
  }
}
```

`respect_origin` defers to `Cache-Control` for every directive (`s-maxage`, `stale-while-revalidate`, `must-revalidate`), so the policy lives in code (`kb-binary-response.ts`) not in the CF dashboard. File lives at `apps/web-platform/infra/cache.tf`.

## Key Insight

**Application-layer cache headers are necessary but not sufficient for dynamic paths on Cloudflare.** For any opaque/dynamic URL (tokens, IDs, RPC endpoints), assume `Cache-Control` is decorative until a cache-eligibility rule exists. The default-eligibility heuristic silently swallows the feature otherwise — with no error, no warning, just flat origin load. The `CF-Cache-Status: DYNAMIC` response header is the diagnostic: it means "Cloudflare chose not to cache this, regardless of what you asked for."

## Prevention

- **For any Cache-Control work targeting dynamic paths, pair the application PR with Terraform cache-rule work in the same PR.** Do not defer infra work as a follow-up — the feature is not live without it.
- **Verify with `curl -I <url> | grep CF-Cache-Status` post-deploy.** `HIT`/`MISS` means the rule took effect; `DYNAMIC` or `BYPASS` means Cloudflare is ignoring your headers.
- **Plan's "non-goals" section should not make vendor-behavior claims without citing docs.** This session's plan asserted CF default caching behavior without verification and the claim made it through deepen-plan review. Architecture agent caught it.

## Session Errors

**Plan non-goal claim was unverified and wrong** — The plan (line 101) stated CF would honor `public, max-age=…` by default. Architecture review proved this incorrect. Recovery: added `cache.tf` with `cloudflare_ruleset` in the review-fix commit. **Prevention:** plan/deepen-plan skills should flag vendor-behavior claims in non-goals sections without doc citations, and reviewers should verify them against provider docs rather than accept plan assertions.

**Initial scope-out reflex rejected by second-reviewer** — Attempted to scope-out the Terraform ruleset as architectural-pivot/contested-design. The `code-simplicity-reviewer` DISSENTED correctly: same top-level directory (`apps/web-platform/infra/` matches the criterion's literal text), the architect named one concrete fix (not multiple independent alternatives). Recovery: flipped to fix-inline. **Prevention:** the existing `rf-review-finding-default-fix-inline` rule and dissent gate already cover this. Reinforces that scope-out should be rare and the criteria are not loopholes.

## Tags

category: integration-issues
module: cloudflare

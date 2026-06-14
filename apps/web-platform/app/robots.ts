import type { MetadataRoute } from "next";

// app.soleur.ai is the product surface, not a marketing site: login-gated
// dashboards plus token-gated invite/share routes (/invite/[token],
// /shared/[token]) — none of which should ever enter a search index. The
// public, indexable marketing content lives on the apex docs site (soleur.ai).
//
// De-indexing strategy (changed 2026-06-14 — GSC "Indexed, though blocked by
// robots.txt" on https://app.soleur.ai/): we deliberately ALLOW crawling here.
// The load-bearing de-index mechanism is the host-wide
// `X-Robots-Tag: noindex, nofollow` edge header set by the Cloudflare Transform
// Rule in `apps/web-platform/infra/seo-rulesets.tf`
// (cloudflare_ruleset.seo_response_headers), which fires on EVERY response
// including the bare-URL 307→/login and the token routes.
//
// A blanket `Disallow: /` was the PRIOR mechanism and it backfired: robots.txt
// blocks *crawling* but not *indexing*. Google indexed the bare URL anyway and
// the crawl-block then PREVENTED Googlebot from ever fetching the page to see a
// noindex directive — so the URL could never be removed. Per Google's documented
// removal method, a page must be crawlable AND carry noindex to be dropped from
// the index; hence `allow: "/"` here paired with the edge noindex header. The
// token routes are now protected by that global header, not by a crawl block
// (the old block never protected them from indexing-if-crawled in the first
// place — it only recorded their URLs without a snippet).
export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
    },
  };
}

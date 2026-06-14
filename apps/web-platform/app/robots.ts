import type { MetadataRoute } from "next";

// app.soleur.ai is the login-gated product surface (dashboards + token-gated
// /invite/[token], /shared/[token]); none of it should ever be indexed. The
// public, indexable marketing content lives on the apex docs site (soleur.ai).
//
// We deliberately ALLOW crawling. The load-bearing de-index mechanism is the
// host-wide `X-Robots-Tag: noindex, nofollow` edge header set by the Cloudflare
// Transform Rule in `apps/web-platform/infra/seo-rulesets.tf`
// (cloudflare_ruleset.seo_response_headers) — see that file for the full
// robots.txt-vs-noindex rationale. Do NOT re-add `Disallow: /`: the prior
// blanket block caused the GSC "Indexed, though blocked by robots.txt" report
// (it blocked crawling, which prevented Googlebot from ever seeing the noindex
// that would remove the URL). Crawl-allow is required so the header is seen;
// token routes are protected by that global header, not by a crawl block.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
    },
  };
}

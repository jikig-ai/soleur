import type { MetadataRoute } from "next";

// app.soleur.ai is the product surface, not a marketing site: login-gated
// dashboards plus token-gated invite/share routes (/invite/[token],
// /shared/[token]) — none of which should ever enter a search index (a
// tokenised URL is both useless and a leak surface if indexed). A host-wide
// Disallow: / is the correct default here, not a /login,/signup carve-out
// (that would leave /dashboard/* and the token routes crawlable). The public,
// indexable marketing content lives on the apex docs site (soleur.ai).
export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      disallow: "/",
    },
  };
}

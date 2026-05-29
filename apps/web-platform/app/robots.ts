import type { MetadataRoute } from "next";

// app.soleur.ai is the logged-in product surface, not a marketing site. Every
// route is either an auth funnel page or a behind-login dashboard view, so
// there is nothing here we want in a search index. Disallow the whole host to
// keep app pages (e.g. /login, /signup) out of Search Console coverage — the
// public, indexable marketing content lives on the apex docs site (soleur.ai).
export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      disallow: "/",
    },
  };
}

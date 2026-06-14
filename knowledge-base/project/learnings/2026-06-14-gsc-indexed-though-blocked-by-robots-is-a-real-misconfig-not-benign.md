# Learning: GSC "Indexed, though blocked by robots.txt" is a REAL misconfig (robots.txt can't de-index) — the opposite disposition from the benign www-canonical class

## Problem

The operator forwarded three Google Search Console coverage reports in one session.
Two were **"Alternate page with proper canonical tag"** / duplicate-canonical reports
on `soleur.ai` (the marketing/docs site) — benign by construction (Google's
variant memory of www/`?ref=`/`.html` URLs that correctly 3xx-redirect to the apex
canonical; the only action is operator-side VALIDATE FIX + wait). See
[[2026-06-12-gsc-duplicate-canonical-on-www-variant-is-benign-consolidation]].

The third report — **"Indexed, though blocked by robots.txt"** on
`https://app.soleur.ai/` (the login-gated Next.js product host) — looks superficially
similar ("GSC flagged a URL we don't want indexed") but is the **opposite
disposition: a real misconfiguration that requires a code change**, not a benign
wait.

## Solution

**The discriminator: read what GSC is actually telling you about the mechanism.**

- "Alternate page with proper canonical tag" / "Duplicate, Google chose different
  canonical" = Google FOUND a noindex/canonical signal and acted on it correctly →
  **benign**, verify-live-then-VALIDATE-FIX.
- "Indexed, though blocked by robots.txt" = Google indexed a URL it was **forbidden
  to crawl**, so it could never see a noindex → **the block is actively preventing
  the fix**. robots.txt `Disallow` blocks *crawling*, not *indexing*; a discovered
  URL gets indexed URL-only and the crawl-block stops Googlebot from ever fetching
  the page to read a `noindex`.

**Google's documented removal method:** a page must be **crawlable AND carry
`noindex`** to be dropped from the index. So the fix is counter-intuitive — you
*remove* the robots.txt block and *add* a noindex:

1. `app/robots.ts`: blanket `disallow: "/"` → `allow: "/"` so Googlebot can fetch
   the page and see the directive.
2. Add a host-wide `X-Robots-Tag: noindex, nofollow` response header.

**Mechanism choice — edge Transform Rule beats origin `headers()`** for a host
whose bare URL is a middleware redirect. The repo already had
`cloudflare_ruleset.seo_response_headers` (`apps/web-platform/infra/seo-rulesets.tf`)
noindexing `deploy.`/`api.` subdomains, CI-guarded by
`test/seo-rulesets-noindex.test.ts` and auto-applied by `apply-web-platform-infra.yml`.
A new host-only rule `(http.host eq "app.soleur.ai")` fires at the edge on **every**
response — including the bare-URL 307→/login that GSC actually crawled — which
Next.js `headers()` does NOT reliably cover for middleware-generated redirects
(the `/robots.txt`-shadowing precedent). `app.soleur.ai` must be proxied
(`dns.tf cloudflare_record.app proxied = true`) for the edge rule to fire; the
dormant `api.soleur.ai` rule (DNS-only CNAME, #3379) is the cautionary no-op.

**Strictly safer than the old block:** the prior `robots.ts` comment feared the
token routes (`/invite/[token]`, `/shared/[token]`) were "a leak surface if
indexed" — but robots.txt is exactly what *allows* a leaked token URL to be
indexed URL-only. A global `noindex, nofollow` header guarantees they are never
indexed even if crawled, which the block never did.

## Key Insight

A GSC coverage report is not a uniform "benign variant-memory" class. Split it by
the **stated mechanism**:
- variant correctly redirects/canonicalizes → benign, wait.
- **a crawl-block is preventing a needed noindex → real, fix it** (crawl-allow +
  `X-Robots-Tag: noindex`).

robots.txt is never an indexing control and never a security control — it only
asks compliant bots not to crawl. To keep a host OUT of the index you need a
`noindex` directive on a crawlable page, not a `Disallow`.

## Tags
category: seo
module: apps/web-platform
related: [[2026-06-12-gsc-duplicate-canonical-on-www-variant-is-benign-consolidation]], [[2026-05-29-nextjs-metadata-routes-need-public-paths-allowlist]]

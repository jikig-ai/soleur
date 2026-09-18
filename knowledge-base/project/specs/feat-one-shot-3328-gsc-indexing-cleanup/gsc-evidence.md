# GSC "Why pages aren't indexed" evidence — pulled 2026-09-18

Source: Google Search Console, `sc-domain:soleur.ai` property, Indexing → Pages,
per-bucket drilldowns pulled live via Playwright (data as of GSC "Last update:
9/14/26"). Every URL below was then re-verified live with `curl -sIL -A Googlebot`.

76 not indexed / 52 indexed / 7 reason buckets (+1 empty "Duplicate without
user-selected canonical", validation Passed).

## Bucket 1 — Page with redirect (45) — VERDICT: benign

All 45 URLs verified live: every one 301→200 to the correct apex canonical.
Composition:

- Host/scheme canonicalization: `http://soleur.ai/`, `http://www.soleur.ai/`,
  `https://www.soleur.ai/` → `https://soleur.ai/` (301, single hop for https).
- ~35 `https://www.soleur.ai/<path>` variants (blog posts, /legal/*, top-level
  pages) — all 301 → apex equivalents, all landing 200.
- Legacy `/pages/*.html`: `pages/community.html`, `pages/pricing.html`,
  `pages/vision.html`, `pages/agents.html`, `pages/index.html`,
  `pages/legal/privacy-policy.html` (apex+www variants) — all 301 → clean URLs.
  Served by Cloudflare edge 301s (seo-bulk-redirects.tf / seo-rulesets.tf), NOT
  the meta-refresh stubs — edge rule wins first.

No action needed. GSC keeps historical entries in this bucket ~forever; entries
are correct-by-design.

## Bucket 2 — Alternate page with proper canonical tag (7) — VERDICT: benign

- `https://soleur.ai/?ref=peerlist`, `https://www.soleur.ai/?ref=peerlist` —
  param variants, canonical → `/`. Working as intended.
- `https://soleur.ai/index.html` — 301 → `/`.
- `https://soleur.ai/blog/?q={search_term_string}` — literal OpenSearch-style
  placeholder URL Google crawled from somewhere external; NOT present in repo
  markup (grep-verified: no `search_term_string`/opensearch in docs or
  web-platform sources; `/opensearch.xml` 404s). Serves 200, canonical → `/blog/`.
- `https://soleur.ai/blog/soleur-vs-devin/?utm_source=linkedin-company&...` —
  UTM variant, canonical consolidates.
- `https://www.soleur.ai/blog/case-study-competitive-intelligence/` — www variant.
- `https://www.soleur.ai/blog/what-is-company-as-a-service/` — reslugg'd post,
  301 → `/company-as-a-service/`.

No action needed (canonical consolidation working).

## Bucket 3 — Excluded by 'noindex' tag (6) — VERDICT: 5 intentional + 1 actionable

- `https://app.soleur.ai/`, `http://app.soleur.ai/`, `https://app.soleur.ai/login`,
  `https://app.soleur.ai/login?error=auth_failed`, `https://app.soleur.ai/callback`
  — app auth surfaces; noindex is CORRECT and intentional.
- `https://soleur.ai/blog/2026-03-24-vibe-coding-vs-agentic-engineering/?utm_...`
  — **ACTIONABLE**: serves HTTP 200 meta-refresh stub (`blog/redirects.njk`
  template, generated from `_data/blogRedirects.js`), not an edge 301. This is
  the open #3328 scope: migrate blogRedirects to Cloudflare edge 301s and delete
  the meta-refresh machinery. Also note the stub's canonical is RELATIVE
  (`/blog/vibe-coding-vs-agentic-engineering/`).

## Bucket 4 — Not found 404 (4) — VERDICT: mostly stale/benign

- `https://api.soleur.ai/` — live 404 JSON (CT-log-enumerated subdomain).
  Honest 404; `deploy.soleur.ai` already sends `X-Robots-Tag: noindex, nofollow`
  but api.soleur.ai does NOT — candidate for the same header (minor defense).
- `https://soleur.ai/cdn-cgi/l/email-protection`,
  `https://www.soleur.ai/cdn-cgi/l/email-protection` — Cloudflare email-obfuscation
  decode endpoints; 404 for bots by design. Prior plan
  `knowledge-base/project/plans/2026-07-20-fix-gsc-404-cdn-cgi-email-protection-plan.md`.
- `https://soleur.ai/pages/legal/terms-of-service.html` — STALE: last crawled
  Apr 7, now 301 → `/legal/terms-and-conditions/` (verified).

## Bucket 5 — Blocked 403 (2) — VERDICT: benign (defense already deployed)

- `https://deploy.soleur.ai/hooks/deploy-status`, `http://deploy.soleur.ai/` —
  admin/deploy surface, correctly 403, AND already sends
  `X-Robots-Tag: noindex, nofollow` (verified live). Per
  `learnings/2026-05-05-gsc-indexing-triage-patterns.md` Insight 3 this is the
  recommended defense-in-depth — done.

## Bucket 6 — Crawled - currently not indexed (11) — VERDICT: mixed

Genuinely-live pages Google crawled but declined to index:

- `https://soleur.ai/blog/soleur-vs-polsia/` (Jun 26)
- `https://soleur.ai/blog/why-most-agentic-tools-plateau/` (Jun 20)
- `https://soleur.ai/blog/ai-agents-for-solo-founders/` (Jun 13)
- `https://soleur.ai/legal/gdpr-policy/` (Sep 10)
- `https://soleur.ai/legal/data-protection-disclosure/` (Sep 4)

Stale/variants (no action):

- `https://www.soleur.ai/blog/billion-dollar-solo-founder-stack/` — www variant.
- `https://www.soleur.ai/pages/changelog.html`, `.../cookie-policy.html`,
  `/pages/agents.html`, `/pages/vision.html` — legacy .html, now 301 (Apr crawl).
- `https://www.soleur.ai/blog/feed.xml` — RSS feed; non-HTML, fine to skip.

For the 3 blog posts + 2 legal pages: per learning
`2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking` the
remediation is internal-link equity (links from high-traffic pages). Related
open issues: #8143/#8144 (homepage/nav pass zero links to 9-10 pillar/cluster
pages) — same root cause class. All 5 are in the sitemap and return 200 with
correct self-canonicals.

## Bucket 7 — Duplicate, Google chose different canonical (1) — VERDICT: stale

- `https://www.soleur.ai/company-as-a-service/` (May 7 crawl) — www variant;
  validation already "Passed".

## Indexed baseline check

All 60 sitemap `<loc>` URLs verified: HTTP 200, self-canonical, no noindex.
robots.txt = `Allow: /` + sitemap ref. Sitemap is clean.

## Actionable work items (evidence-backed)

1. **#3328 (OPEN)**: migrate `plugins/soleur/docs/_data/blogRedirects.js`
   (23 date-prefixed slugs → canonical, computed at build time from
   `plugins/soleur/docs/blog/*.md` filenames) to Cloudflare edge 301s —
   the Bulk Redirects list in `apps/web-platform/infra/seo-bulk-redirects.tf`
   is the proven pattern (zone `http_request_dynamic_redirect` quota is FULL:
   10/10; Bulk Redirects is a separate account-level product). Then delete the
   meta-refresh machinery: `docs/page-redirects.njk`, `docs/_data/pageRedirects.js`
   (all 19 entries verified covered by live edge 301s),
   `docs/blog/redirects.njk`, `docs/_data/blogRedirects.js`; update
   `docs/scripts/validate-blog-links.sh` and the meta-refresh-skip block in
   `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`.
   #3328 re-evaluation pre-conditions verified met: PR #3296 merged,
   edge 301s live ≥7 days (since ~June), curl suite green on 5+ legacy URLs.
2. **Internal-link equity** for the 3 non-indexed blog posts (+ optionally the
   2 legal pages) — content-side fix, no infra.
3. **Optional minor**: `X-Robots-Tag: noindex` header for `api.soleur.ai`
   (parity with deploy.soleur.ai) — Terraform transform rule if one exists.

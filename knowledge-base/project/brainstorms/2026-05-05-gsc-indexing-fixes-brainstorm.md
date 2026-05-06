---
title: GSC critical indexing fixes
status: ready-for-plan
date: 2026-05-05
brand_critical: true
brand_survival_threshold: single-user incident
related_pr: "#3296"
---

# GSC Critical Indexing Fixes — Brainstorm

## User-Brand Impact

- **Artifact at risk:** soleur.ai public discoverability surface (sitemap, canonical
  set, indexed pages) and any private/staging path inadvertently exposed to Googlebot.
- **Vector:** (1) Trust breach if a non-public URL gets indexed and a prospective
  user finds it via Google. (2) Credential / private path exposure if the 403
  cluster URL is a path that should never have been crawlable.
- **Threshold:** `single-user incident`. Confirmed concrete:
  `http://deploy.soleur.ai/` was discovered by Googlebot and is the **1× 403 entry**
  in the report — an admin/deployment surface that was reachable enough for Google
  to fingerprint. Any future regression that flips its auth from 403 → 200 (config
  drift, accidental routing) would be brand-fatal in one impression.

## Input Data — Confirmed URL Set

Source: GSC `Page indexing` (operator-shared screenshots, 2026-05-05).

### Page with redirect — 20 (10 visible)

```
https://soleur.ai/blog/                                 May 1
https://soleur.ai/blog/soleur-vs-cursor/                Apr 30
https://soleur.ai/changelog/                            Apr 30
http://soleur.ai/                                       Apr 30
https://soleur.ai/                                      Apr 30
https://soleur.ai/pricing/                              Apr 30
https://www.soleur.ai/pages/vision.html                 Apr 29  ← META-REFRESH PAGE
https://soleur.ai/blog/soleur-vs-anthropic-cowork/      Apr 29
https://soleur.ai/vision/                               Apr 28
https://soleur.ai/skills/                               Apr 26
```

### Not found (404) — 2

```
https://api.soleur.ai/                                  May 1   ← SUBDOMAIN ROOT
https://soleur.ai/pages/legal/terms-of-service.html     Apr 7   ← STALE OLD-PATH
```

### Alternate page with proper canonical tag — 2

```
https://www.soleur.ai/index.html                        Apr 29
https://www.soleur.ai/?ref=peerlist                     Apr 18
```

### Blocked due to access forbidden (403) — 1

```
http://deploy.soleur.ai/                                May 1   ← ADMIN SUBDOMAIN
```

### Crawled - currently not indexed — 4

```
https://www.soleur.ai/pages/changelog.html              Apr 20  ← META-REFRESH PAGE
https://www.soleur.ai/pages/legal/cookie-policy.html    Apr 13  ← META-REFRESH PAGE
https://www.soleur.ai/pages/agents.html                 Apr 4   ← META-REFRESH PAGE
https://www.soleur.ai/blog/feed.xml                     Mar 27  ← RSS FEED
```

## Live Verification (2026-05-05)

| URL | HTTP | Notes |
|---|---|---|
| `https://soleur.ai/` | 301 → `https://www.soleur.ai/` | Cloudflare apex→www |
| `https://www.soleur.ai/` | 200 | Canonical alive |
| `https://www.soleur.ai/pages/agents.html` | **200** | Body has `<meta http-equiv="refresh">` + `<link rel="canonical" href="/agents/">` |
| `https://www.soleur.ai/pages/vision.html` | **200** | Same meta-refresh pattern |
| `https://www.soleur.ai/pages/legal/terms-of-service.html` | **404** | Not in `pageRedirects.js` (renamed to `terms-and-conditions.html`) |
| `https://api.soleur.ai/` | 404 (JSON) | API service responding, root has no handler |
| `https://deploy.soleur.ai/` | **403** | Cloudflare-fronted; auth-walled admin surface |
| `https://www.soleur.ai/blog/feed.xml` | 200 (XML) | Atom feed |

## Two Root Causes

### Root cause A — Apex/www canonical mismatch (~18 redirects)

- `plugins/soleur/docs/_data/site.json` declares `url: "https://soleur.ai"` (apex).
- `plugins/soleur/docs/sitemap.njk` interpolates `site.url` into every `<loc>`.
- `plugins/soleur/docs/robots.txt` references `https://soleur.ai/sitemap.xml`.
- Cloudflare 301s every apex URL to `https://www.soleur.ai/...`.
- → 18 of the 20 redirect-bucket entries are apex variants of legitimate sitemap pages.

### Root cause B — Meta-refresh-only legacy redirect strategy

- `plugins/soleur/docs/page-redirects.njk` emits HTML pages with
  `<meta http-equiv="refresh" content="0;url=...">` + `<link rel="canonical">`.
- Driven by `_data/pageRedirects.js` (18 entries; missing `terms-of-service.html`).
- These resolve as **HTTP 200** with redirect-y body content. Google classifies them
  inconsistently:
  - 1 entry → "Page with redirect" (`vision.html`)
  - 3 entries → "Crawled - currently not indexed" (`agents.html`, `changelog.html`, `cookie-policy.html`)
  - 1 entry → "Alternate page with proper canonical tag" (`index.html`)
- Plus the missing entry `terms-of-service.html` → 404 (the table doesn't include it
  because the page was renamed to `terms-and-conditions.html` but Google still
  remembers the old slug).
- Meta-refresh + canonical is a "soft signal" — Google's behavior is non-deterministic
  vs HTTP 301 which is canonical and final.

### Independent: subdomain leaks (api.soleur.ai, deploy.soleur.ai)

These are not rooted in either A or B. They are DNS records that Cloudflare has
exposed to public crawlers:

- `api.soleur.ai/` returns 404 JSON. Service exists, root has no handler.
- `deploy.soleur.ai/` returns 403. **Admin surface.** Discovery vector unknown
  — likely Cloudflare's public DNS records since both subdomains are proxied. Even
  with auth, having Google enumerate this in search results is brand-negative.

## What We're Building

A 3-vector fix that maps to the three root causes plus a noindex pass for the RSS feed:

### Vector 1 — Switch canonical hostname to www

- Change `plugins/soleur/docs/_data/site.json` → `url: "https://www.soleur.ai"`.
- Change `plugins/soleur/docs/robots.txt` → `Sitemap: https://www.soleur.ai/sitemap.xml`.
- Sitemap auto-regenerates with www URLs on next build.
- Resubmit sitemap in GSC after deploy.
- **Expected result:** 18 of the 20 redirect-bucket entries resolve once Google
  re-fetches the sitemap.

### Vector 2 — Replace meta-refresh with HTTP 301

Constraint: the docs site is published statically (GitHub Pages or similar — the
`x-github-request-id` header in earlier curl output suggests GH Pages). GH Pages
has no `_headers` / `_redirects`. **Two viable HTTP 301 placements:**

(2a) **Cloudflare Bulk Redirects (Terraform)** — declare a Cloudflare Ruleset
mapping each old `/pages/*.html` path to the new clean URL. 301 served at edge,
no Eleventy template needed. Per AGENTS.md `hr-all-infrastructure-provisioning-servers`,
this lands in a Terraform root with R2 backend.

(2b) **Migrate the docs site to Cloudflare Pages** (which supports `_redirects`
file with HTTP 301 semantics) and remove `page-redirects.njk` / `pageRedirects.js`.

**Recommended:** 2a — narrower diff, keeps GH Pages deployment intact, and the
existing Cloudflare proxy already terminates the request. Deletes `page-redirects.njk`
and `pageRedirects.js` once 2a is in place.

Vector 2 must include the missing `terms-of-service.html` → `terms-and-conditions/`
mapping (or a delete-and-410 if the doc was retired).

### Vector 3 — Block subdomain leaks

For `api.soleur.ai`:
- Serve `X-Robots-Tag: noindex, nofollow` on all responses.
- Serve `robots.txt` at `https://api.soleur.ai/robots.txt` with `Disallow: /`.
- Optional: redirect root to docs site `/api/` page (if planned) or 410 Gone.

For `deploy.soleur.ai`:
- Same robots disallow + `X-Robots-Tag: noindex, nofollow` (defense in depth — even
  behind 403, Google should not display this URL in results).
- Audit Cloudflare WAF: is this subdomain proxied (`Orange cloud`) when it could be
  DNS-only or removed entirely from public DNS? Per CLO/security lens: if this is
  an internal-only deployment dashboard, prefer Cloudflare Zero Trust or a private
  Tunnel over a public 403.
- **Investigate discovery vector:** check `git grep deploy.soleur.ai` across the
  repo for any accidental public link, and check Cloudflare's CT-log scrubbing
  setting (subdomain transparency-log enumeration is the most likely vector).

### Vector 4 — Noindex the RSS feed

- Either remove `/blog/feed.xml` from the sitemap if it's auto-included, or add
  `<meta name="robots" content="noindex">` equivalent for non-HTML resources via
  `X-Robots-Tag: noindex` header (Cloudflare Transform Rule, scoped to `*.xml`).

### Verification & GSC re-validation

After deploy:
- Use GSC URL Inspection on representative URLs from each bucket.
- Click "Validate fix" on each Critical issue category.
- Monitor Chart.csv equivalent over 7-14 days to confirm not-indexed count trends down.

## Why This Approach (Trade-offs)

| Alternative | Why not |
|---|---|
| Keep apex canonical, redirect www→apex instead | Requires Cloudflare DNS flip; more disruptive; OG/Discord embeds may break short-term |
| Keep meta-refresh, just add `terms-of-service.html` entry | Doesn't fix the 4 "crawled-not-indexed" entries that are also meta-refresh casualties |
| Just remove `pageRedirects.js` entirely (orphan old URLs) | Breaks external backlinks (peerlist, etc.); 404s the residual long tail |
| Ignore the 403 (it's "just" admin) | User-brand-critical: even a 403 is information leak; Google enumerating admin subdomains is a discoverability surface |

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Canonical hostname = `https://www.soleur.ai` | Live infra already 301s to www; aligns build with deploy |
| D2 | Old `/pages/*.html` redirects move to Cloudflare 301 (vector 2a) | Deterministic vs meta-refresh; serves at edge; deletes 2 files of build complexity |
| D3 | Subdomain leak fix uses robots.txt + `X-Robots-Tag` header (defense in depth, not just 403) | 403 is not noindex; Google can still display URL in results without snippet |
| D4 | `feed.xml` gets `X-Robots-Tag: noindex` via Cloudflare rule | Eleventy can't set headers; same edge layer as D2 |
| D5 | Cloudflare changes go through Terraform per `hr-all-infrastructure-provisioning-servers` | New Terraform root needs R2 backend per `hr-every-new-terraform-root-must-include-an` |

## Non-Goals

- Migrating the docs site off GitHub Pages (vector 2b deferred).
- Re-architecting the URL structure of `soleur.ai` (e.g., flattening `/blog/*` paths).
- Implementing AI-engine optimization (AEO) tags — separate scope, see `soleur:seo-aeo` skill.
- Rewriting `soleur.ai/blog/feed.xml` content; only marking it noindex.

## Open Questions

1. **Discovery vector for `deploy.soleur.ai`:** is it linked from any public surface,
   or strictly DNS/CT-log enumeration? (CLO/security concern for the report-back.)
2. **What is `api.soleur.ai` for?** Is there a planned public landing page, or
   should the subdomain be removed from public DNS / Zero-Trust-protected?
3. **Is GitHub Pages still the right substrate** given we now want HTTP 301s?
   (Defer to vector 2a; revisit only if Cloudflare Bulk Redirects volume grows past
   the free-tier ceiling.)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
(skipped formal leader spawn given strong root-cause clarity from local discovery;
relevant lenses summarized below from the operator framing.)

### Marketing (CMO lens)

**Summary:** Indexing degradation is direct organic-discovery loss. The redirect cluster
(20 of 29) is the single highest-leverage fix in the marketing surface. Vector 1
recovers the bulk of indexed inventory in one config change; vector 2 stabilizes the
long tail of legacy URLs against the meta-refresh non-determinism.

### Product (CPO lens)

**Summary:** No product-feature scope; this is publishing-surface hygiene. CPO sign-off
warranted only for vector 3 (subdomain leak) where threat model intersects with the
brand's "what does a prospect see when they Google us" experience.

### Legal (CLO lens)

**Summary:** Vector 3 (deploy.soleur.ai 403, robots disallow + noindex) is the
load-bearing CLO concern. A 403 is not a noindex — Google can still surface the URL
text in results. CLO sign-off required on the chosen mitigation (Zero Trust vs
robots.txt vs DNS-private). Not a privacy-policy revision; no PII at risk in the
current 403 response.

### Engineering (CTO lens)

**Summary:** Vector 2a (Cloudflare Bulk Redirects via Terraform) introduces a new
Terraform root or extends an existing one. Per AGENTS.md hard rules, must include
R2 remote backend. Touch points: `plugins/soleur/docs/_data/site.json`,
`plugins/soleur/docs/robots.txt`, deletion of `page-redirects.njk` + `pageRedirects.js`,
new `infra/cloudflare/` (or extension of existing) Terraform module. No app-layer
code change.

## Capability Gaps

- No existing Cloudflare Terraform root manages `soleur.ai` DNS/redirects (verified
  via `find . -maxdepth 4 -name "*.tf"`); plan must establish one or extend
  `apps/web-platform/infra/` if its Cloudflare zone is the same account.
- No `X-Robots-Tag` header strategy exists for the docs site. Plan must establish a
  Cloudflare Transform Rule and document it.

## Resume Prompt

```text
Resume /soleur:plan for feat-seo-gsc-indexing-fixes. Brainstorm:
knowledge-base/project/brainstorms/2026-05-05-gsc-indexing-fixes-brainstorm.md.
Branch: feat-seo-gsc-indexing-fixes. Worktree: .worktrees/feat-seo-gsc-indexing-fixes/.
PR: #3296. Brand-survival threshold: single-user incident.

Plan should cover four vectors:
1. Switch site.json url + robots.txt sitemap to www.soleur.ai
2. Replace meta-refresh page-redirects.njk with Cloudflare Bulk Redirects (Terraform,
   R2 backend); add missing terms-of-service.html entry; delete page-redirects.njk
   and pageRedirects.js
3. Block api.soleur.ai and deploy.soleur.ai from indexing (robots.txt + X-Robots-Tag)
   and audit deploy.soleur.ai discovery vector
4. X-Robots-Tag: noindex on /blog/feed.xml via Cloudflare Transform Rule

Plus GSC re-validation post-deploy. Honor hr-all-infrastructure-provisioning-servers
and hr-every-new-terraform-root-must-include-an.
```

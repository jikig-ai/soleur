# Feature: GSC critical indexing fixes for soleur.ai

## Problem Statement

Google Search Console reports 29 pages flagged across 5 critical-indexing categories
on soleur.ai (snapshot 2026-05-05). Indexed-vs-not-indexed ratio is degrading
month-over-month (3:2 in March, 18:29 in May). Two systemic root causes plus a
user-brand-critical subdomain leak account for nearly all flagged URLs.

**User-brand vector:** `http://deploy.soleur.ai/` is in the GSC report as the 1× 403
entry — Googlebot has discovered and fingerprinted an admin/deployment subdomain.
A 403 is not a noindex; the URL can still appear in search results.

## Goals

- Drive GSC "Page with redirect" bucket from 20 → ≤2 (only the unavoidable apex
  HTTP→HTTPS upgrade).
- Drive GSC "Not found (404)" bucket from 2 → 0.
- Drive GSC "Crawled - currently not indexed" bucket from 4 → 0 (or only the RSS
  feed if intentionally noindexed).
- Block `api.soleur.ai` and `deploy.soleur.ai` from search indexing with defense in
  depth (`X-Robots-Tag` + per-subdomain `robots.txt`).
- Recover indexed-page count trend toward parity with sitemap entries.
- All four GSC critical-issue categories submitted for validation post-deploy.

## Non-Goals

- Migrating the docs site off GitHub Pages onto Cloudflare Pages or another host.
- Rewriting the URL structure of `soleur.ai` (e.g., flattening blog paths).
- AI-engine optimization (AEO) tags — separate scope, see `soleur:seo-aeo`.
- Rewriting `soleur.ai/blog/feed.xml` content — only marking it `noindex`.
- Removing `api.soleur.ai` from DNS (out of scope; leave routing decisions to the
  team responsible for the API service).

## Functional Requirements

### FR1: Sitemap and canonical hostname use www

Sitemap at both `https://soleur.ai/sitemap.xml` and `https://www.soleur.ai/sitemap.xml`
serves URLs in the form `https://www.soleur.ai/<path>`. `robots.txt` references the
www sitemap. `<link rel="canonical">` on every rendered page points to the www
variant.

### FR2: Old `/pages/*.html` URLs return HTTP 301

Every entry in the previous `_data/pageRedirects.js` table — plus the previously
missing `pages/legal/terms-of-service.html` → `legal/terms-and-conditions/` mapping
— resolves to an HTTP 301 response with a `Location` header pointing to the new
canonical URL. No HTML body, no meta-refresh.

### FR3: Subdomain leak surfaces are explicitly noindexed

`https://api.soleur.ai/*` and `https://deploy.soleur.ai/*` responses include
`X-Robots-Tag: noindex, nofollow` regardless of HTTP status. Each subdomain serves
a `robots.txt` with `User-agent: *\nDisallow: /`. The discovery vector for
`deploy.soleur.ai` is documented in the brainstorm follow-up.

### FR4: RSS feed is noindexed

`https://www.soleur.ai/blog/feed.xml` (and any other `.xml` non-sitemap feed under
`www.soleur.ai/blog/`) responds with `X-Robots-Tag: noindex`.

### FR5: GSC re-validation submitted

After deploy, all 5 critical-issue categories in GSC have "Validate fix" clicked,
with URL Inspection sample-checks confirming the new HTTP behavior.

## Technical Requirements

### TR1: Build-time changes

- `plugins/soleur/docs/_data/site.json`: `url` → `https://www.soleur.ai`.
- `plugins/soleur/docs/robots.txt`: `Sitemap:` line → `https://www.soleur.ai/sitemap.xml`.
- Delete `plugins/soleur/docs/page-redirects.njk`.
- Delete `plugins/soleur/docs/_data/pageRedirects.js`.

### TR2: Cloudflare Bulk Redirects (Terraform)

- New Terraform root (or extension of existing Cloudflare-zone root) declaring
  Cloudflare Single Redirects / Bulk Redirects for the legacy
  `/pages/*.html` → clean-URL set, plus the missing `terms-of-service.html` entry.
- R2 remote backend (bucket `soleur-terraform-state`, key
  `soleur-ai-edge/terraform.tfstate` or analogous) per
  `hr-every-new-terraform-root-must-include-an`.
- All Cloudflare resource changes flow through Terraform (no API/UI edits) per
  `hr-all-infrastructure-provisioning-servers`.

### TR3: Cloudflare Transform Rules for headers

- Rule 1: scoped to host `api.soleur.ai`, set response header
  `X-Robots-Tag: noindex, nofollow`.
- Rule 2: scoped to host `deploy.soleur.ai`, same header.
- Rule 3: scoped to path `*.xml` on `www.soleur.ai`, set response header
  `X-Robots-Tag: noindex`.
- Rule 4 (or static origin): serve `User-agent: *\nDisallow: /` at
  `/robots.txt` for `api.soleur.ai` and `deploy.soleur.ai` hostnames.

### TR4: Discovery-vector audit and documentation

- Run `git grep "deploy.soleur.ai"` and `git grep "api.soleur.ai"` to confirm no
  public link exposure.
- Check Cloudflare DNS settings for "Subdomain transparency-log scrubbing" or
  equivalent.
- Document findings in `knowledge-base/engineering/ops/runbooks/` or as a
  follow-up issue.

### TR5: Verification suite

- `curl -sI https://www.soleur.ai/pages/agents.html` returns HTTP 301.
- `curl -sI https://www.soleur.ai/pages/legal/terms-of-service.html` returns HTTP 301.
- `curl -sI https://deploy.soleur.ai/` includes `x-robots-tag: noindex, nofollow`.
- `curl -sI https://api.soleur.ai/` includes `x-robots-tag: noindex, nofollow`.
- `curl -s https://deploy.soleur.ai/robots.txt` and `https://api.soleur.ai/robots.txt`
  return `User-agent: *\nDisallow: /`.
- `curl -sI https://www.soleur.ai/blog/feed.xml` includes `x-robots-tag: noindex`.
- `curl -s https://www.soleur.ai/sitemap.xml | grep -c "https://www.soleur.ai"` is
  the same as the sitemap entry count.
- `curl -s https://www.soleur.ai/sitemap.xml | grep -c "https://soleur.ai"` is 0
  (no apex URLs in sitemap).

### TR6: User-impact gates

Per `hr-weigh-every-decision-against-target-user-impact`, the plan and PR carry
`Brand-survival threshold: single-user incident`. The plan skill's Phase 2.6 must
preserve the User-Brand Impact section from the brainstorm. The PR must request
`user-impact-reviewer` and CLO sign-off on vector 3 before merge.

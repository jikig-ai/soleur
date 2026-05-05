---
title: GSC critical indexing fixes
status: paused-awaiting-url-exports
date: 2026-05-05
brand_critical: true
brand_survival_threshold: single-user incident
related_pr: "#3296"
---

# GSC Critical Indexing Fixes — Brainstorm (PAUSED)

## Status

Paused at Phase 1.1. Awaiting per-issue URL exports from Google Search Console (the
operator-supplied CSV in `~/Downloads/soleur.ai-Coverage-2026-05-05/Critical issues.csv`
is aggregate-only — categories and counts but no URLs). Resume when URL exports
land in the same folder.

## User-Brand Impact

- **Artifact at risk:** soleur.ai public discoverability surface (sitemap, canonical
  set, indexed pages) and any private/staging path inadvertently exposed to
  Googlebot.
- **Vector:** (1) Trust breach if a non-public URL gets indexed and a prospective
  user finds it via Google. (2) Credential / private path exposure if the 403 cluster
  or one of the redirect-cluster URLs is a path that should never have been
  crawlable in the first place.
- **Threshold:** `single-user incident`. One prospect seeing a leaked private/staging
  path in Google search would be brand-damaging. Plan inherits this threshold per
  AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Input Snapshot (2026-05-05)

Source: `~/Downloads/soleur.ai-Coverage-2026-05-05/`

| Reason | Source | Pages |
|---|---|---|
| Page with redirect | Website | 20 |
| Not found (404) | Website | 2 |
| Alternate page with proper canonical tag | Website | 2 |
| Blocked due to access forbidden (403) | Website | 1 |
| Crawled - currently not indexed | Google systems | 4 |

`Chart.csv` trend (2026-03-02 → 2026-05-01): not-indexed grew 3 → 29; indexed grew
2 → 18. Discovery ratio is degrading — pages are entering the sitemap faster than
Google is promoting them.

`Non-critical issues.csv` is empty (no warnings).

## What We Already Know (Local Discovery)

### 1. Hostname mismatch — likely root cause for the 20-page redirect cluster

- `plugins/soleur/docs/_data/site.json`: `url: "https://soleur.ai"` (apex).
- `plugins/soleur/docs/sitemap.njk` emits `<loc>{{ site.url }}{{ entry.url }}</loc>`,
  so all 43 sitemap URLs use the apex hostname.
- `plugins/soleur/docs/robots.txt`: `Sitemap: https://soleur.ai/sitemap.xml` (apex).
- Live: `curl -sI https://soleur.ai/<path>` → HTTP 301, `Location: https://www.soleur.ai/<path>`
  served by Cloudflare. Verified for `/`, `/pricing/`, `/agents/`, `/getting-started/`, `/blog/`.
- Live: `https://www.soleur.ai/` → HTTP 200.

Result: Googlebot fetches every sitemap URL at apex, gets a 301 to www, and the
apex variant is bucketed as "Page with redirect" — uncountably the source of
the 20 affected pages, modulo a small number of redirect-chain edge cases.

### 2. Other categories — hypotheses pending URL list

- **2 × 404:** likely stale entries in `plugins/soleur/docs/_data/pageRedirects.js` or
  `blogRedirects.js`, or blog slug renames. Need URLs to confirm.
- **2 × alternate-canonical:** typically expected behavior (Google chose a www
  canonical for an apex variant). Likely no action required.
- **1 × 403:** primary user-brand concern. Hypotheses:
  - Cloudflare `/cdn-cgi/*` path crawled by Googlebot (visible in our 301 response
    body — anti-bot challenge link is exposed).
  - A `/api/*` route or admin path that should be in `robots.txt` Disallow.
  - A genuinely private resource that should never have been linked from a public page.
- **4 × crawled-not-indexed:** Google-side quality signal — thin content or
  duplicate signals. Common for young sites. Lower priority unless a category
  spans high-priority pages.

### 3. Where fixes will land

Three candidate locations, scope depends on canonical decision:

- `plugins/soleur/docs/_data/site.json` — change `url`
- `plugins/soleur/docs/robots.txt` — change Sitemap line
- `plugins/soleur/docs/_data/pageRedirects.js`, `blogRedirects.js` — audit for stale
  targets
- Cloudflare DNS / Page Rules — flip apex↔www redirect direction OR add Disallow
  for `/cdn-cgi/*` (already implicitly handled by Cloudflare in most cases)
- `apps/web-platform/next.config.ts` — only relevant if the Next.js app contributes
  any indexable URLs (unlikely; needs verification)

## Working Hypothesis (To Be Validated With URL List)

Switch canonical hostname to `www.soleur.ai` in build config (option B):

1. Update `site.json.url` to `https://www.soleur.ai`
2. Update `robots.txt` sitemap URL to www
3. Re-deploy docs site → sitemap regenerated with www URLs → Google re-fetches → 20
   "redirect" pages move to indexed.
4. Audit `pageRedirects.js` / `blogRedirects.js` against the 404 URLs.
5. Investigate the 403 URL — is it a path that should be `Disallow`-ed in
   `robots.txt`? Is it a leak?
6. After fixes deploy, request validation of each issue category in GSC.

The alternative (option A: keep apex canonical, redirect www→apex) requires
infrastructure change (Cloudflare rule edit) and is more disruptive given current
infra already favors www.

## Open Questions (Pending URL Exports)

1. What are the 20 redirect URLs? (Confirm hypothesis: all apex variants of sitemap entries.)
2. What are the 2 × 404 URLs? (Map to redirect tables or removed posts.)
3. What is the 1 × 403 URL? (**Highest user-brand priority** — confirm not a leak.)
4. What are the 4 × crawled-not-indexed URLs? (Triage by content quality.)
5. What are the 2 × alternate-canonical URLs? (Likely no-op but verify.)

## Resume Instructions for the Operator

1. In Google Search Console, open each "Critical issues" reason row.
2. Click the row, then **Export → CSV** (or Google Sheets) to get the per-URL list.
3. Save each export to `~/Downloads/soleur.ai-Coverage-2026-05-05/` with descriptive
   filenames, e.g. `redirect-pages.csv`, `404-pages.csv`, `403-pages.csv`,
   `crawled-not-indexed-pages.csv`, `alternate-canonical-pages.csv`.
4. Resume the brainstorm with the prompt at the bottom of this document.

If GSC export is hitting a "data not available" wall, the alternative is the
Search Console API (`searchconsole.googleapis.com`) `urlInspection.index.inspect`
or a GSC sitemap re-submit + 24h wait. Brainstorm can also run on partial data
(403 URL alone is enough to start the leak audit).

## Resume Prompt

```text
Resume /soleur:brainstorm for feat-seo-gsc-indexing-fixes. Brainstorm doc:
knowledge-base/project/brainstorms/2026-05-05-gsc-indexing-fixes-brainstorm.md.
Branch: feat-seo-gsc-indexing-fixes. Worktree: .worktrees/feat-seo-gsc-indexing-fixes/.
PR: #3296. Status: paused awaiting URL exports in
~/Downloads/soleur.ai-Coverage-2026-05-05/. Continue from Phase 1.1 with the
per-URL data in hand.
```

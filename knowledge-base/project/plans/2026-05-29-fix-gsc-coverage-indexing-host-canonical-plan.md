---
title: "Fix Google Search Console coverage / indexing failures for soleur.ai docs"
type: fix
date: 2026-05-29
branch: feat-one-shot-gsc-coverage-indexing
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# 🐛 Fix Google Search Console "Why pages aren't indexed" coverage failures

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Research Reconciliation, AC12, Phase 1, Risks
**Verification:** live `curl` probes (2026-05-29), worktree Eleventy build, codebase greps

### Key Improvements (from deepen pass)
1. **Found a second, active www-canonicalizer:** `plugins/soleur/docs/_data/github.js:49-54` defines `APEX_RE = /https:\/\/soleur\.ai(?=$|[^a-zA-Z0-9.-])/g` and **rewrites apex → www** in GitHub release-note bodies rendered on `/changelog/`. The original plan's AC12 sweep mentioned the prose references generically; this is a *load-bearing logic* edit, not a string flip — the rewriter must be **deleted** (post-flip it would re-inject www links that 301). Promoted to Phase 1 + a dedicated AC.
2. **Quantified the AC12 sweep:** 24 `www.soleur.ai` references across 12 files (`robots.txt`, `eleventy.config.js`, `site.json`, `_data/github.js`, 7 legal docs, 1 blog post). Classified each below.
3. **Confirmed Next.js 15.5.18** (`apps/web-platform/package.json`) supports the `MetadataRoute.Robots` (`robots.ts`) API and `metadata.robots` — AC7/AC8 are implementable as written. No app `robots.ts`/`public/robots.txt` exists today (verify-the-negative pass confirmed).

### New Considerations Discovered
- The `APEX_RE` rewriter in `github.js` is the canonical evidence that the **whole www-canonicalization was a deliberate #3296 decision** based on the then-live apex→www direction. The flip must reverse this assumption everywhere it was encoded, not just in declarative host strings.
- The validator's canonical-host gate cannot catch a globally-consistent-but-wrong host — only the live redirect probe (AC13) can. This is the load-bearing post-deploy check.

## Overview

Google Search Console (domain property `sc-domain:soleur.ai`) reported a cluster of "Page with redirect", "Crawled - currently not indexed", "Not found (404)", and "Alternate page with proper canonical tag" coverage failures for the soleur.ai Eleventy docs site. The drilldown CSVs (digested in the feature description; archived at `/home/jean/Downloads/GoogleSearchConsoleFailed`) name legacy `/pages/*.html` URLs, `www.` host variants, `/blog/feed.xml`, the `api.soleur.ai`/`app.soleur.ai` subdomains, and `/legal/disclaimer/`.

The single dominant root cause is a **canonical-host inversion**: the docs site declares `https://www.soleur.ai` as its canonical host (in `site.json`, `robots.txt`, and the feed base), but the live infrastructure now serves the **bare apex** `https://soleur.ai` (200) and **301-redirects `www` → apex**. Every sitemap `<loc>`, every `<link rel="canonical">`, and the `robots.txt` Sitemap line therefore point at a host that 301-redirects — which is exactly the "Page with redirect" signal Google reports.

A prior fix (PR #3296 / #3297, brainstorm `2026-05-05-gsc-indexing-fixes-brainstorm.md`) standardized on `www` because at that time Cloudflare did `apex → www`. **The redirect direction has since flipped** (GitHub Pages now enforces the `CNAME` apex `soleur.ai`). The codebase is stale relative to live infra — this is the canonical directional-drift failure class (`2026-03-17-planning-direction-confirmation-required`).

This plan flips the canonical host to the bare apex, closes one remaining legacy redirect-stub gap (`terms-of-service.html` → 404), noindexes the app login page, and adds a robots policy for the app subdomain. GSC re-validation is operator-triggered (clicking "Validate Fix" in Search Console after deploy) — this is the only post-deploy step.

## Research Reconciliation — Spec vs. Codebase

The feature description was written from the GSC CSV drilldown (a snapshot of the *deployed* state). Several items it names have already been fixed in source by PRs #1851/#3296. The live re-probe (2026-05-29) and a worktree build separate already-fixed items from genuinely-open ones.

| Feature-description claim | Codebase / live reality (verified 2026-05-29) | Plan response |
|---|---|---|
| Sitemap lists legacy `/pages/*.html`, `/index.html` | **Already fixed.** Built `_site/sitemap.xml` (48 `<loc>`) contains zero `/pages/*.html`, `/index.html`, or `feed.xml`. Redirect stubs are `eleventyExcludeFromCollections: true`, so they never enter `collections.all`. | No sitemap-exclusion work needed. Add a regression guard test. |
| Sitemap lists bare `http://` and `www` variants | **Inverted, not as described.** Sitemap emits **only** `https://www.soleur.ai/...` (single host) — but that host now 301s to apex. The problem is the host *choice*, not mixed hosts. | Flip `site.url` apex; update validator semantics. |
| `/blog/feed.xml` is in the sitemap | **Already fixed.** Feed is plugin-generated (`eleventy-plugin-rss`), not a collection member; `.xml` fails the sitemap's `.html`/`/` filter. Not in built sitemap. | No exclusion work. The `<link rel="alternate" ... feed.xml>` in `base.njk:227` is a discovery hint, not a sitemap entry — keep it. |
| `/pages/legal/terms-of-service.html` returns 404 | **Confirmed open.** Live `curl` → 404. `pageRedirects.js` maps `terms-and-conditions.html` but the page was historically `terms-of-service.html`; Google indexed the old name, no stub exists. | Add the missing redirect entry (root cause #3). |
| `api.soleur.ai/` 404, `app.soleur.ai/login` duplicate-no-canonical | **Confirmed open.** `api.soleur.ai/` → 404; `app.soleur.ai/login` → 200 with **no** `robots`/canonical meta; no app robots.txt. These are separate properties (Next.js web-platform + API), not the docs site. | Noindex the app login + add app robots policy (root cause #4). `api`/`deploy` subdomains are Cloudflare/DNS surfaces — see Non-Goals. |
| `/legal/disclaimer/` crawled-not-indexed; needs internal link + sitemap + canonical | **Mostly already satisfied.** Disclaimer is linked from `legal.njk:90`, is in the built sitemap, and self-canonicalizes via `base.njk:7`. Its canonical currently points at the redirecting `www` host (subsumed by root cause #1). | The host flip fixes the canonical; no separate disclaimer work beyond confirming it post-flip. |
| "Alternate page with proper canonical tag" (15) | Benign per description. Caused/healthy because Google saw `www` (alternate) and apex (canonical) pairs — the host flip removes the `www` alternates over time. | No action; will resolve as a side effect. |

## User-Brand Impact

**If this lands broken, the user experiences:** a docs site whose sitemap/canonical point at a host that does not serve 200s, suppressing organic discoverability of soleur.ai (the public top-of-funnel). A wrong-direction flip (apex when infra wants www) would re-break every URL the same way.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this change touches only public marketing-site SEO metadata (host strings, redirect stubs, a `robots: index:false` flag on a login page). No personal data, auth, or money surfaces.

**Brand-survival threshold:** `aggregate pattern` — discoverability decay is a slow aggregate SEO signal, not a single-user incident. No per-PR CPO sign-off required; section present per gate.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `site.url` in `plugins/soleur/docs/_data/site.json` is `https://soleur.ai` (no `www.`). Verify: `grep '"url"' plugins/soleur/docs/_data/site.json` returns `"url": "https://soleur.ai"`.
- [ ] AC2 — `robots.txt` Sitemap line uses the apex. Verify: `grep -i sitemap plugins/soleur/docs/robots.txt` returns `Sitemap: https://soleur.ai/sitemap.xml`.
- [ ] AC3 — Feed `base` in `eleventy.config.js` is `https://soleur.ai/`. Verify: `grep 'base:' eleventy.config.js` returns `base: "https://soleur.ai/",`.
- [ ] AC4 — After `npx @11ty/eleventy` (run from worktree root), the built sitemap uses a single apex host and no `www`. Verify: `grep -oE 'https?://[^/<]+' _site/sitemap.xml | grep -v sitemaps.org | sort -u` returns exactly `https://soleur.ai`.
- [ ] AC5 — Built canonical tags use the apex. Verify: `grep -rh 'rel="canonical"' _site/index.html _site/pricing/index.html` shows `https://soleur.ai/...`, zero `www`.
- [ ] AC6 — `pageRedirects.js` contains an entry `{ from: "pages/legal/terms-of-service.html", to: "/legal/terms-and-conditions/" }`. After build, `_site/pages/legal/terms-of-service.html` exists and its meta-refresh + `<link rel="canonical">` both target `/legal/terms-and-conditions/`. Verify: `test -f _site/pages/legal/terms-of-service.html && grep -o 'url=/legal/terms-and-conditions/' _site/pages/legal/terms-of-service.html`.
- [ ] AC7 — App login page is noindexed. `apps/web-platform/app/(auth)/layout.tsx` metadata includes `robots: { index: false, follow: false }` (preserving the existing `referrer` policy). Verify: `grep -A3 'robots' "apps/web-platform/app/(auth)/layout.tsx"`.
- [ ] AC8 — App subdomain has a robots policy that disallows indexing of auth surfaces. A `apps/web-platform/app/robots.ts` (Next.js Route Handler) exists returning `Disallow: /` (or scoped to `/login`, `/signup`, `/dashboard`). Verify: `test -f apps/web-platform/app/robots.ts`.
- [ ] AC9 — SEO validator passes against the new build with the apex host. Verify: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` exits 0 and reports `single canonical host: https://soleur.ai`.
- [ ] AC10 — Regression guard: a test asserts the built sitemap excludes `/pages/`, `/index.html`, and `feed.xml`, and uses the apex host. (Extend existing docs test surface — see Files to Edit. If no JS test surface exists for `_site`, add a shell assertion to the deploy workflow's existing "Verify build output" step instead of a new test framework.)
- [ ] AC11 — `deploy-docs.yml` "Verify build output" step does not reference `www.soleur.ai` and its `test -f _site/pages/${page}.html` loop still passes (redirect stubs unaffected by the host flip). Verify: build + `bash` the step's commands locally.
- [ ] AC12 — All 24 `www.soleur.ai` references across 12 files are flipped to apex (or explicitly scoped-out per match). After the sweep, `grep -rn "www\.soleur\.ai" plugins/soleur/docs eleventy.config.js | grep -v node_modules` returns only deliberate exclusions. The 12 files (verified 2026-05-29): `robots.txt` (Phase 1), `eleventy.config.js` (Phase 1), `_data/site.json` (Phase 1), `_data/github.js` (Phase 1 — see AC15), and prose links in `pages/legal/{acceptable-use-policy,cookie-policy,data-protection-disclosure,disclaimer,gdpr-policy,privacy-policy,terms-and-conditions}.md` (7 files, 16 refs) + `blog/2026-04-30-best-claude-code-plugins-2026.md` (1 ref). Legal/blog prose links are operator-facing apex-canonical links — flip for consistency.
- [ ] AC15 — `plugins/soleur/docs/_data/github.js` no longer rewrites apex → www. The `APEX_RE` constant and its `.replace(APEX_RE, "https://www.soleur.ai")` call (lines 49–54) are **removed** (changelog bodies should keep their natural apex links). Verify: `grep -c "www.soleur.ai\|APEX_RE" plugins/soleur/docs/_data/github.js` returns 0. After build, `_site/changelog/index.html` contains zero `www.soleur.ai`.

### Post-merge (operator)

- [ ] AC13 — After the docs deploy completes (GitHub Pages), re-probe live: `curl -sI https://soleur.ai/sitemap.xml` → 200 and its `<loc>` hosts are apex. **Automation:** feasible via `gh run watch` on the deploy workflow + a `curl` assertion; bake into `/soleur:ship` post-merge verification rather than punting to operator.
- [ ] AC14 — Operator clicks **"Validate Fix"** in Google Search Console for each affected coverage category (Page with redirect, 404, Crawled-not-indexed). **Automation: not feasible** — GSC "Validate Fix" is behind interactive Google OAuth + a console-only button with no public API for validation triggering. This is the single genuinely operator-only step.

## Implementation Phases

Phases are ordered so the contract-defining host flip lands before downstream consumers (sitemap/canonical/validator) are re-verified.

### Phase 1 — Flip canonical host to bare apex (root cause #1)
- Edit `plugins/soleur/docs/_data/site.json`: `"url": "https://www.soleur.ai"` → `"url": "https://soleur.ai"`.
- Edit `plugins/soleur/docs/robots.txt`: `Sitemap: https://www.soleur.ai/sitemap.xml` → `Sitemap: https://soleur.ai/sitemap.xml`.
- Edit `eleventy.config.js`: feed `base: "https://www.soleur.ai/"` → `base: "https://soleur.ai/"`.
- **Edit `plugins/soleur/docs/_data/github.js`: remove the `APEX_RE` constant (line 49) and the `.replace(APEX_RE, "https://www.soleur.ai")` in the changelog map (line 54)** so release-note bodies retain their apex links. This is the active rewriter that inverts the canonical host in changelog content (AC15).
- Sweep the remaining prose `www.soleur.ai` references per AC12 (7 legal docs + 1 blog post). Read each file before editing; flip to apex.

### Phase 2 — Close legacy redirect-stub gap (root cause #3)
- Edit `plugins/soleur/docs/_data/pageRedirects.js`: add `{ from: "pages/legal/terms-of-service.html", to: "/legal/terms-and-conditions/" }`. (Audit the full GSC CSV legacy-path list against the existing map; add any other old-name stubs Google still indexes. The cited set — pricing/agents/vision/community/changelog/cookie-policy — already have stubs; only `terms-of-service.html` is missing.)

### Phase 3 — Noindex app login + app robots policy (root cause #4)
- Edit `apps/web-platform/app/(auth)/layout.tsx`: add `robots: { index: false, follow: false }` to the existing `metadata` export (keep `referrer`).
- Create `apps/web-platform/app/robots.ts` (Next.js Route Handler) returning a `MetadataRoute.Robots` that disallows crawling of the app surface (`Disallow: /` for the app subdomain — it is a logged-in product, not a marketing surface).
- Note: `api.soleur.ai` (404) and `deploy.soleur.ai` (403) are Cloudflare/DNS surfaces, not code we serve content for — see Non-Goals.

### Phase 4 — Regression guard + validator semantics
- Add the AC10 regression guard (sitemap excludes legacy paths + uses apex host) to the existing docs test surface or the deploy workflow's verify step.
- Review `validate-seo.sh`'s canonical-host gate: it asserts *internal* consistency (sitemap host == robots host) but not that the host is the live-200 host. Optionally tighten its comment (currently says "apex→www") to reflect the corrected www→apex direction so the next maintainer is not misled. (Comment-only; no logic change required since the gate passes for any single consistent host.)

### Phase 5 — Build + validate
- Run `npx @11ty/eleventy` from the worktree root.
- Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` and `validate-csp.sh _site`.
- Confirm AC4–AC9 mechanically.

## Files to Edit
- `plugins/soleur/docs/_data/site.json` — `url` apex flip
- `plugins/soleur/docs/robots.txt` — Sitemap line apex flip
- `eleventy.config.js` — feed `base` apex flip
- `plugins/soleur/docs/_data/github.js` — remove `APEX_RE` apex→www rewriter (lines 49, 54)
- `plugins/soleur/docs/_data/pageRedirects.js` — add `terms-of-service.html` stub
- `apps/web-platform/app/(auth)/layout.tsx` — add `robots: { index: false }`
- `.github/workflows/deploy-docs.yml` — (optional) add sitemap-host assertion to "Verify build output"; confirm no `www` reference
- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` — (optional) correct stale apex→www comment
- `plugins/soleur/docs/pages/legal/disclaimer.md` and any legal docs with `https://www.soleur.ai` prose links — flip per AC12

## Files to Create
- `apps/web-platform/app/robots.ts` — app-subdomain robots policy (Next.js Route Handler)
- (Test) regression guard for sitemap — location depends on existing docs test surface (see Test Strategy)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (74 open issues, 2026-05-29) — none reference `site.json`, `robots.txt`, `pageRedirects.js`, `sitemap.njk`, `(auth)/layout.tsx`, or `eleventy.config.js`.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — public marketing surface), Marketing (CMO — SEO/discoverability)

This is a docs-site SEO/infra fix. Engineering owns the Eleventy/Next.js implementation. Marketing owns the discoverability outcome (organic funnel). Product owns the public marketing surface coherence. No new user-facing page or flow is created — the app login page already exists; we only add a `robots` flag. **Product/UX Gate tier: NONE** — no new component file under `components/**/*.tsx` or `app/**/page.tsx` is created (`robots.ts` is a metadata route handler, not a page). Domain leaders will be consulted at deepen-plan if escalated; the change is mechanical config.

## Observability

```yaml
liveness_signal:
  what: GitHub Pages deploy of docs + Vercel/host deploy of web-platform; sitemap.xml reachable at apex
  cadence: on push to main touching plugins/soleur/docs/** or eleventy.config.js
  alert_target: deploy-docs.yml job status (GitHub Actions) — fails closed if build or validate-seo.sh fails
  configured_in: .github/workflows/deploy-docs.yml
error_reporting:
  destination: GitHub Actions workflow run logs (deploy-docs.yml "Validate SEO" + "Verify build output" steps)
  fail_loud: yes — validate-seo.sh exits non-zero on host inconsistency; workflow fails and blocks deploy
failure_modes:
  - mode: Host flipped wrong direction (apex when infra wants www again)
    detection: post-deploy curl probe of https://soleur.ai/ vs https://www.soleur.ai/ redirect direction (AC13)
    alert_route: /soleur:ship post-merge verification curl assertion
  - mode: Legacy redirect stub still 404s
    detection: curl https://soleur.ai/pages/legal/terms-of-service.html → expect 200 meta-refresh
    alert_route: post-merge curl in ship verification
  - mode: App login still indexable
    detection: curl https://app.soleur.ai/login | grep noindex
    alert_route: post-merge curl in ship verification
logs:
  where: GitHub Actions run logs for deploy-docs.yml
  retention: GitHub default (90 days)
discoverability_test:
  command: "npx @11ty/eleventy && bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site && curl -sI https://soleur.ai/sitemap.xml"
  expected_output: "validate-seo.sh exits 0 reporting 'single canonical host: https://soleur.ai'; curl returns HTTP 200"
```

## Test Strategy

- **Build verification** (deterministic, no network): `npx @11ty/eleventy` from worktree root → grep built `_site/sitemap.xml` and `_site/**/index.html` for apex-only hosts (AC4, AC5).
- **Validator**: `validate-seo.sh _site` must pass with the apex host (AC9). This is the canonical enumerator — no new test framework needed for the SEO checks.
- **Regression guard** (AC10): before adding a new test framework, check the existing docs test surface. `plugins/soleur/test/` uses `bun test` (per AGENTS plugin checklist: `bun test plugins/soleur/test/components.test.ts`). If a `_site`-asserting test fits there, extend it; otherwise add a shell assertion to `deploy-docs.yml`'s existing "Verify build output" step (no new dependency). Do NOT introduce a new test runner.
- **Live probes** (post-merge only, operator/ship): `curl -sI` against apex, www, legacy stub, app login (AC13). Pin `--max-time` on every curl.

## Non-Goals / Out of Scope
- **`api.soleur.ai` (404) and `deploy.soleur.ai` (403):** these are Cloudflare/DNS-fronted subdomains, not content the docs or web-platform repos serve. Stopping them from appearing in the domain-property coverage is a Cloudflare WAF/robots concern at the subdomain edge, not an Eleventy/Next.js code change. **Deferral:** file a tracking issue (Cloudflare `_redirects`/`robots` or a `X-Robots-Tag: noindex` response header at the api/deploy edge) — labels `domain/engineering`, `chore`, `priority/p3-low`. Re-evaluate when the subdomains carry real content.
- **Cloudflare redirect-rule changes:** the www→apex 301 is already correct (apex is canonical). No infra change needed; we align the code to live infra, not the reverse.
- **GSC API automation of "Validate Fix":** no public API; operator-only (AC14).

## Research Insights

**Live verification (2026-05-29, `curl --max-time`):**
- `https://soleur.ai/` → `HTTP/2 200` (canonical, alive)
- `https://www.soleur.ai/` → `HTTP/2 301 location: https://soleur.ai/` (www redirects to apex)
- `https://soleur.ai/pages/legal/terms-of-service.html` → `HTTP/2 404` (missing redirect stub)
- `https://app.soleur.ai/login` → `HTTP/2 200`, no `robots`/canonical meta (indexable)
- `https://api.soleur.ai/` → `HTTP/2 404`; `https://deploy.soleur.ai/` → `HTTP/2 403`

**Directional drift (root cause provenance):** The prior fix (PR #3296/#3297, brainstorm `knowledge-base/project/brainstorms/2026-05-05-gsc-indexing-fixes-brainstorm.md` line 77) recorded `https://soleur.ai/ → 301 → https://www.soleur.ai/ | Cloudflare apex→www`. Today the direction is **inverted** (`www → apex`), because GitHub Pages enforces the `CNAME` apex (`plugins/soleur/docs/CNAME` = `soleur.ai`). The codebase standardized on www and is now stale vs. live infra — the canonical directional-confirmation failure class (`knowledge-base/project/learnings/2026-03-17-planning-direction-confirmation-required.md`). The fix flips the code to match live infra; the infra (www→apex 301) is already correct and needs no change.

**Built-sitemap audit (worktree `npx @11ty/eleventy`):** 48 `<loc>` entries, single host `https://www.soleur.ai`, zero `/pages/*.html`, zero `/index.html`, zero `feed.xml`. The legacy-URL-in-sitemap items from the GSC CSV are already fixed in source (PRs #1851/#3296); the host is the only remaining sitemap defect.

**Next.js robots API (verified `apps/web-platform/package.json` → `next@^15.5.18`):** `robots.ts` exporting `MetadataRoute.Robots` and `metadata.robots = { index: false }` are both stable in Next 15. Reference: Next.js App Router metadata docs (`robots.ts` file convention, `metadata.robots` field).

**SEO validator semantics (`plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh:62-88`):** the `#3297` canonical-host gate asserts sitemap host == robots host (internal consistency) — it currently PASSES on the wrong www host. The gate's inline comment still claims `apex→www`; correct it to `www→apex` so the next maintainer is not misled.

## Risks & Mitigations
- **Risk: redirect direction flips back to apex→www.** If Cloudflare/GitHub Pages config changes again, this fix re-breaks. *Mitigation:* AC13 post-deploy probe asserts direction; the validator + regression guard make the host an explicit, testable contract. Cite live evidence in PR body (`www → apex 301` confirmed 2026-05-29).
- **Risk: third-party JSON-LD `sameAs`/contact links hardcode `www`.** *Mitigation:* AC12 sweep with per-match decision.
- **Risk: app `robots.ts` over-blocks a public marketing route on the app subdomain.** *Mitigation:* app subdomain is logged-in product only; `Disallow: /` is correct. Confirm no public landing pages live on `app.` before merge.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- The SEO validator's canonical-host gate checks sitemap↔robots *internal* consistency, NOT that the host is the live-200 host. It passed for the wrong (www) host because both sitemap and robots agreed on www. The only safe verification of "right host" is the live `curl` redirect probe (AC13) — the build-time validator cannot catch a globally-consistent-but-wrong host choice.
- Redirect stubs are **meta-refresh** (`<meta http-equiv="refresh">`), not server 301s — GitHub Pages cannot emit 301s for arbitrary paths. Google treats `content="0;url=..."` instant meta-refresh as a redirect signal (acceptable), but it is weaker than a 301. This is an accepted constraint of GitHub Pages hosting, not a bug to fix here.
- When flipping `site.url`, the `og:url`, `og:image`, twitter image, and all JSON-LD `url`/`@id` fields in `base.njk` derive from `site.url` automatically — the single `site.json` edit propagates. Do NOT hand-edit `base.njk` host strings.

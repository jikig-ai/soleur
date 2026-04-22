---
title: "refactor(marketing): drain 2026-04-21 SEO/AEO audit backlog"
date: 2026-04-22
type: refactor
domain: marketing
branch: feat-one-shot-drain-seo-aeo-2026-04-21
closes:
  - "2707"  # P0 — FAQ + FAQPage JSON-LD on /pricing/
  - "2708"  # P0 — homepage <title> conflict Eleventy vs Next.js
  - "2709"  # P1 — bare single-word <title> on /pricing/, /community/, /blog/
  - "2711"  # P1 — inline author card + Person JSON-LD on blog posts
references:
  - "2706"  # 2026-04-21 growth audit summary issue
  - "2486"  # drain-pattern reference PR (one PR, multiple closures)
  - "2609"  # jsonLdSafe filter requirement
audit_inputs:
  - knowledge-base/marketing/audits/soleur-ai/2026-04-21-aeo-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-04-21-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-04-21-content-plan.md
  - knowledge-base/marketing/audits/soleur-ai/2026-04-21-seo-audit.md
brand_guide: knowledge-base/marketing/brand-guide.md
---

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** Files-to-Edit (output dir correction), Research Reconciliation, Implementation Phases 2/5/6, Acceptance Criteria, Risks, Test Strategy, Research Insights
**Research sources:** Live codebase reads (`eleventy.config.js`, `blog/blog.json`, `apps/web-platform/package.json`, `test/community-stats-data.test.ts`, `docs/_includes/base.njk`), Next.js 15 metadata docs (verified via context match: app has `next@^15.5.15`), Schema.org FAQPage + Person spec, Google Search Central rich-results rules.

### Key Improvements (delta from initial plan)

1. **CRITICAL: Eleventy output directory corrected from `_site/` to `_site/`.** Verified via `grep "output:" eleventy.config.js` → line 64: `output: "_site"`. Every Acceptance Criterion, drift-guard assertion, and build-validation command that referenced `_site/` has been corrected. A wrong build-path in the plan would have burned the first 20 minutes of the work phase with empty `fs.readFile` failures.
2. **CRITICAL: Blog post permalink structure verified.** `plugins/soleur/docs/blog/blog.json` sets `permalink: "blog/{{ page.fileSlug }}/index.html"` and `layout: "blog-post.njk"` — the directory-data-cascade. Every `.md` file in `docs/blog/` auto-inherits the layout. Rendered paths are `_site/blog/<slug>/index.html`. Drift-guard test 4 glob corrected from `_site/blog/*/index.html` to `_site/blog/*/index.html`.
3. **Next.js 15 title-template verified.** App pins `next@^15.5.15` in `apps/web-platform/package.json`. Next.js 15 supports the `{ template, default, absolute }` Metadata title object (documented since 13.2, stable through 15.x). `tsc --noEmit` gate in Phase 3 will catch any type drift.
4. **Next.js `title` sites-of-use swept.** `grep -rn "title:" apps/web-platform/app/ | grep -v "page.tsx,pricing,line"` returned: only `app/layout.tsx` exports `metadata.title`. No descendant `/dashboard/*` route overrides `metadata.title` — all route titles defined inside `dashboard/page.tsx` are component prop `title:` fields (unrelated to Next.js metadata). The title-template `%s` placeholder will fall through to `default` on every route. Safe to proceed.
5. **`jsonLdSafe` filter implementation verified.** `eleventy.config.js:30-35`: `JSON.stringify(value).replace(/<\//g, "<\\/").replace(/ /g, "\\u2028").replace(/ /g, "\\u2029")`. This is the three-hazard-class filter (HTML breakout + JS runtime termination + JSON parse safety). Arrays and objects pass through `JSON.stringify` cleanly — `site.author.sameAs` as an array is safe to pass directly to `jsonLdSafe`. No per-element map needed. Risk #7 in the initial plan is eliminated.
6. **`foundingDate` confirmed "2026" in base.njk (not 2025).** `grep "foundingDate" base.njk` → `"foundingDate": "2026"`. Any future author-object `foundingDate` (not added in this PR) must match.
7. **Test runner path verified.** Sibling test (`plugins/soleur/test/community-stats-data.test.ts`) imports `from "bun:test"` and uses `resolve(import.meta.dir, "../docs/_data/...")` to locate docs artifacts. Drift-guard test will follow the same pattern — paths relative to `plugins/soleur/test/` via `import.meta.dir`, resolved against `../docs/...` for source and `../../../../_site/...` for built artifacts (repo root is 4 levels up from `plugins/soleur/test/`).
8. **Eleventy input path caveat surfaced.** `eleventy.config.js:3` sets `INPUT = "plugins/soleur/docs"` and the build must run from repo root. The `docs:build` npm script already handles this (`cd ../../../ && npx @11ty/eleventy`). Do NOT run `npx @11ty/eleventy` from `plugins/soleur/docs/` — it will fail with "no input directory" per learning `2026-03-15-eleventy-build-must-run-from-repo-root.md`.

### New Considerations Discovered

- **`blog.njk` listing title-prefix semantics change.** Current template interpolates `(title + " - " + site.name)` into CollectionPage JSON-LD `name`. Adding `seoTitle: "Blog — Soleur"` does NOT automatically fix the JSON-LD — the JSON-LD still references `title` (which stays "Blog"). Phase 4 step 4 MUST also update the JSON-LD interpolation to use `seoTitle or (title + " — " + site.name)` with Nunjucks `or` fallback to avoid the "Blog - Soleur" double-dash vs seoTitle "Blog — Soleur" split-signal.
- **`base.njk` title fallback logic needs re-reading before edit.** The logic at line 125 is: `{% if seoTitle %}{{ seoTitle }}{% elif title == site.name %}{{ site.name }} - {{ site.tagline }}{% else %}{{ title }} - {{ site.name }}{% endif %}`. Setting `seoTitle` overrides everything — the `title` + dash + `site.name` branch is bypassed. Safe.
- **`<img>` asset passthrough already wired.** `eleventy.config.js:54` has `addPassthroughCopy({ [${INPUT}/images]: "images" })`. Dropping `jean-deruelle.jpg` into `plugins/soleur/docs/images/` auto-copies to `_site/images/jean-deruelle.jpg` with no config change. Risk #4 ("photo missing breaks build") further reduced — Eleventy ignores missing image paths; only the drift-guard test enforces presence.
- **Existing BlogPosting author JSON-LD already has Person shape.** `_includes/blog-post.njk:27-32` renders `author: { @type: "Person", name, url, jobTitle }`. The plan only EXTENDS this node (adds `image`, `sameAs`) — does NOT create from scratch. Much lower risk of JSON-LD structural drift.
- **`site.author.sameAs` serialization path confirmed safe.** Nunjucks `{{ site.author.sameAs | jsonLdSafe | safe }}` → `jsonLdSafe` runs `JSON.stringify(array)` → produces a valid JSON array literal like `["https://github.com/deruelle","https://x.com/jeandev_"]`. Direct drop-in works; no per-element map needed.
- **CSP `img-src` re-verified for external `sameAs` linked resources.** The `<img>` in the author card is same-origin (`/images/`) — `'self'` covers. Any external profile photo (e.g., linking directly to GitHub avatar URL) would require CSP edit. Plan pins same-origin asset; no CSP change.
- **AEO content-plan suggests additional FAQ items that should NOT be smuggled in.** The 2026-04-21 content-plan lists 5 suggested new pricing FAQ items. This PR adds only the 2 strictly required for the aggregate-cost-breakdown citation claim in #2707's audit finding. Additional items are a marketing content task, not a drain. Explicit in Non-Goals.

# refactor(marketing): drain 2026-04-21 SEO/AEO audit backlog

## Overview

One focused PR that closes four open issues (two P0, two P1) filed by the 2026-04-21 weekly growth audit (#2706). All four are narrow on-page markup edits to the Eleventy docs site at `plugins/soleur/docs/`, plus a single targeted edit to the Next.js root layout at `apps/web-platform/app/layout.tsx` to eliminate the homepage `<title>` split signal.

PR #2486 is the explicit drain pattern: one PR, multiple `Closes #N` lines in the body, zero new scope-outs. This PR follows the same pattern.

Every fix is additive or rewrites a single metadata field. No new infrastructure, no new build steps, no new dependencies, no new pages, no new top-level routes. The PR adds one new image asset (founder photo) and wires it into the blog post layout as an inline author card.

The PR body MUST include, verbatim:

```text
Closes #2707
Closes #2708
Closes #2709
Closes #2711
```

One per line, in the PR body (not the title) per AGENTS.md rule `wg-use-closes-n-in-pr-body-not-title-to`.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| `#2711` says blog-post layout is at `_includes/layouts/` (`post.njk` or equivalent). | No `_includes/layouts/` directory exists. The only blog-post layout file is `plugins/soleur/docs/_includes/blog-post.njk` (verified by `find _includes -type f`). All blog posts in `docs/blog/*.md` use this layout via front-matter or collection tag. | Edit `plugins/soleur/docs/_includes/blog-post.njk` directly. Do NOT create `_includes/layouts/`. |
| `#2711` says "photo asset path under `plugins/soleur/docs/assets/`". | `docs/assets/` does NOT exist. Static images live at `plugins/soleur/docs/images/` (see `/images/og-image.png`, `/images/logo-mark-512.png` already referenced in `base.njk`). `docs/screenshots/` and `docs/images/blog/` exist. | Place founder photo at `plugins/soleur/docs/images/jean-deruelle.jpg` (or `.png`), serve at `/images/jean-deruelle.jpg`. Update issue language accordingly in the PR body. |
| `#2709` and `#2708` reference "homepage `<title>`" in `plugins/soleur/docs/pages/index.njk`. | Homepage file is actually `plugins/soleur/docs/index.njk` (at `docs/` root, NOT under `pages/`). Verified by `find docs -maxdepth 2 -name "index.njk"`. Front-matter already has `seoTitle: "Soleur — AI Agents for Solo Founders | Every Department, One Platform"` — the conflict is with Next.js `apps/web-platform/app/layout.tsx`. | Edit `plugins/soleur/docs/index.njk` (root) and `apps/web-platform/app/layout.tsx`. Do NOT touch `pages/index.njk` (does not exist). |
| `#2708` claims Next.js layout currently shows `"Soleur — One Command Center, 8 Departments"`. | Verified by `head apps/web-platform/app/layout.tsx`: exact match on line 7. `app/page.tsx` redirects `/` → `/dashboard`, so on soleur.ai production this Next.js title only renders behind `/dashboard/*` (the Eleventy index.html serves at `soleur.ai/`). | The split is theoretical on prod (Next.js `/` redirects before paint) but real for any crawler or preview tool that fetches the redirect target. Plan: scope the Next.js title to dashboard-surface language so the two surfaces never present conflicting claims about what "Soleur" is. |
| `#2711` says blog posts lack "consistent byline rendering". | `_includes/blog-post.njk` already renders a byline via `<span class="blog-post-author">by <a href="{{ site.author.url }}" rel="author">{{ site.author.name }}</a>, {{ site.author.role }} of {{ site.name }}</span>` (line 58). BlogPosting JSON-LD already has `author: { @type: "Person", name, url, jobTitle }` (lines 27–32). | The byline is NOT missing — the _inline author card_ (photo + bio + credentials + sameAs links) is. Plan scope narrows to: (1) add inline author card block below blog post content, (2) extend site.json author metadata with `bio`, `credentials`, `sameAs`, `image`, (3) extend the existing BlogPosting `author` JSON-LD node with `image` and `sameAs`. |
| Issue body says "model after existing FAQ blocks on home/getting-started/agents/skills/vision". | FAQPage JSON-LD confirmed on `/agents/` (verified — 5 Q&A, lines 110–153 of `pages/agents.njk`). Pattern uses `<details class="faq-item"><summary class="faq-question">` visible markup + separate `<script type="application/ld+json">` FAQPage. | Replicate `agents.njk` pattern verbatim on `pricing.njk`. Pricing already has a trailing FAQPage JSON-LD block at the bottom (lines 300-ish) but NO visible FAQ markup — verify and reconcile in Phase 2. |

**Key correction discovered during research:** `pricing.njk` actually **already has a FAQPage JSON-LD block** at the bottom (5 Q&A pairs: "Why $49/mo", "concurrent conversations", "Claude separately", "free option", "when do paid plans launch"). The gap reported by #2707 is **NOT missing JSON-LD** — it is **missing the visible `<details>`/`<summary>` FAQ section** that corresponds to the schema. AEO audit's "#1 gap" is: Google's rich-result eligibility requires the visible FAQ to match the JSON-LD answers verbatim; an orphaned JSON-LD block with no visible counterpart can be treated as schema spam and dropped from rich-results. Plan: add the visible `<details class="faq-item">` block that mirrors the existing JSON-LD (or extend both together with additional Q&A pairs from the 2026-04-21 content-plan).

## Files to Edit

| Path | Change | Issue |
|---|---|---|
| `plugins/soleur/docs/pages/pricing.njk` | 1) Add visible `<section class="landing-section">` FAQ block with `<details class="faq-item">` items matching the existing JSON-LD; 2) Extend JSON-LD with 2 added Q&A: an aggregate-cost claim ("How does $95K/mo replacement stack break down?") with inline BLS / Robert Half / Levels.fyi citations, and a methodology footnote; 3) Update `title` front-matter from `Pricing` to `"Pricing — AI Agents for Solo Founders"`. | #2707, #2709 |
| `plugins/soleur/docs/pages/community.njk` | Update `title` front-matter from `Community` to `"Community — Soleur"`. | #2709 |
| `plugins/soleur/docs/pages/blog.njk` | Update `title` front-matter from `Blog` to `"Blog — Soleur"`. Verify the existing CollectionPage JSON-LD `name` field still interpolates correctly with the new title (current: `"{{ (title + " - " + site.name) }}"` → would become "Blog — Soleur - Soleur"; reconcile to a single-pass `seoTitle` override pattern mirroring `docs/index.njk`). | #2709 |
| `plugins/soleur/docs/index.njk` | No title change required (already has `seoTitle: "Soleur — AI Agents for Solo Founders \| Every Department, One Platform"`). Verify nothing else references the conflicting Next.js string. | #2708 (confirmation only) |
| `apps/web-platform/app/layout.tsx` | Change `metadata.title` from `"Soleur — One Command Center, 8 Departments"` to something scoped to the dashboard surface so the two surfaces never present conflicting brand claims. Proposed: `{ template: "%s — Soleur Dashboard", default: "Soleur Dashboard — Your Command Center" }` (Next.js title-template pattern). This ensures `/dashboard`, `/dashboard/billing`, etc. inherit a scoped title; no descendant route can accidentally render the marketing brand line. | #2708 |
| `plugins/soleur/docs/_includes/blog-post.njk` | 1) Add inline author-card block in `{% block content %}` after the prose content, before `</section>`. Renders: photo (`<img src="{{ site.author.image }}" width=96 height=96 alt="Jean Deruelle — Founder of Soleur" loading="lazy">`), name, role, one-line bio, credentials list, sameAs links. 2) Extend JSON-LD `author` Person node with `"image"` and `"sameAs"` fields (uses `\| jsonLdSafe \| safe` per rule `cq-prose-issue-ref-line-start` companion pattern from #2609). | #2711 |
| `plugins/soleur/docs/_data/site.json` | Extend `author` object with `image: "/images/jean-deruelle.jpg"`, `bio: "Founder of Soleur. 15+ years building distributed systems and developer tools. Creator of the Company-as-a-Service platform."` (one sentence, mirrors `about.njk` language), `credentials: ["Founder, Soleur", "15+ years in distributed systems"]`, `sameAs: ["https://github.com/deruelle", "https://x.com/jeandev_", <LinkedIn URL if available>]`. | #2711 |
| `plugins/soleur/docs/pages/blog.njk` (author card on listing) | Add a compact `<div class="blog-listing-author">` block above the first category section rendering `site.author.name` + `site.author.role` as the blog's canonical author. Models the "By Jean Deruelle — Founder of Soleur" pattern from the brand guide. | #2711 |
| `plugins/soleur/docs/css/style.css` | Add minimal CSS for `.author-card`, `.author-card__photo`, `.author-card__body`, `.author-card__credentials`, `.author-card__links` (neutral layout — photo 96px left, text right, monochrome). Do NOT introduce new tokens; reuse existing `--color-*` / `--space-*` CSS vars. | #2711 |

## Files to Create

| Path | Purpose |
|---|---|
| `plugins/soleur/docs/images/jean-deruelle.jpg` | Founder headshot for inline author card. Square 512×512 JPEG (under 80 KB). Sourced from existing brand/social assets — do not generate. If no existing asset is usable, invoke `soleur:gemini-imagegen` (per AGENTS.md `hr-when-triaging-a-batch-of-issues-never`) with a "professional headshot, neutral background, 512×512, editorial portrait style" prompt ONLY if no real photo is available; otherwise the founder (user) provides the photo and this plan stops at the point of asset insertion. |
| `plugins/soleur/test/seo-aeo-drift-guard.test.ts` | New `bun:test` drift-guard that asserts: (1) `_site/pricing/index.html` contains `"@type":"FAQPage"` AND at least one `<details class="faq-item">` visible element AND the JSON-LD Q&A count matches the visible `<details>` count; (2) `_site/pricing/index.html`, `_site/community/index.html`, `_site/blog/index.html` all have `<title>` containing `"Soleur"` AND at least one em-dash/hyphen/pipe separator (not a single bare word); (3) `_site/index.html` `<title>` is the seoTitle string (exact); (4) every rendered blog-post HTML under `_site/blog/*/index.html` contains both an inline author-card DOM block (class `author-card`) AND a Person JSON-LD with `image` + `sameAs`; (5) all FAQPage and BlogPosting JSON-LD blocks parse as valid JSON via `JSON.parse`. |

## Open Code-Review Overlap

None. Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` — zero open code-review issues reference any of the six file paths in the `Files to Edit` table. Check performed 2026-04-22.

## Implementation Phases

### Phase 1 — RED tests (drift-guard)

1. Create `plugins/soleur/test/seo-aeo-drift-guard.test.ts` with five failing assertions as enumerated in "Files to Create" above.
2. Run: `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — confirm 5 failures.
3. Do NOT touch any source file yet.

### Phase 2 — #2707 (FAQ + visible block + extended JSON-LD on /pricing/)

1. Add visible FAQ section (`<section class="landing-section">` with `<details class="faq-item">` items) mirroring the existing JSON-LD's 5 Q&A pairs.
2. Extend JSON-LD with 2 new Q&A pairs from 2026-04-21 content-plan (aggregate-cost breakdown + methodology). Both must also appear in the visible `<details>` block (Google rich-result parity requirement).
3. Inline citations for the $95K/mo claim: link to Robert Half salary guide (200 OK for curl — verified in prior drain pattern per PR #2486 research), Payscale C-suite, and Levels.fyi engineering salaries. Do NOT cite `bls.gov` (returns 403 to curl per PR #2486 research — breaks pre-merge link-rot guard).
4. All string interpolations in new JSON-LD use `\| jsonLdSafe \| safe` (per rule `#2609` pattern already used in the file).
5. Run drift-guard test 1 → PASS.

### Phase 3 — #2708 (homepage `<title>` reconciliation)

1. Verify `plugins/soleur/docs/index.njk` `seoTitle` is unchanged and correct.
2. In `apps/web-platform/app/layout.tsx`, replace `metadata.title` with Next.js title-template pattern:

   ```ts
   export const metadata: Metadata = {
     title: {
       template: "%s — Soleur Dashboard",
       default: "Soleur Dashboard — Your Command Center",
     },
     // description unchanged or updated to dashboard-scoped copy
     // ...
   };
   ```

3. Update the `description` if it overlaps with the marketing-site description (avoid the exact tagline split).
4. Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` to verify Metadata type still compiles.
5. Run drift-guard test 3 → PASS.

### Phase 4 — #2709 (bare single-word titles)

1. Update `pages/pricing.njk` front-matter `title: Pricing` → `title: "Pricing — AI Agents for Solo Founders"`.
   - Verify this does NOT double-append "- Soleur" in `base.njk:125`: the branch `{% elif title == site.name %}{{ site.name }} - {{ site.tagline }}{% else %}{{ title }} - {{ site.name }}{% endif %}` would produce `"Pricing — AI Agents for Solo Founders - Soleur"` (double dash-separated). Acceptable for SERP (two separators: em-dash for product anchor, hyphen for brand) but re-check against brand-guide voice rules before freezing the exact string. Alternative: set `seoTitle: "Pricing — AI Agents for Solo Founders | Soleur"` and keep `title: Pricing` for in-page H1 — this is the pattern `index.njk` already uses.
   - **Chosen pattern:** use `seoTitle` override (mirrors `index.njk`) to keep the in-page `<h1>Every department.<br>One price.</h1>` unchanged while fixing the crawler-visible `<title>`. Applies to all three pages below.
2. `pages/pricing.njk`: add `seoTitle: "Pricing — AI Agents for Solo Founders | Soleur"` to front-matter.
3. `pages/community.njk`: add `seoTitle: "Community — Soleur"` to front-matter.
4. `pages/blog.njk`: add `seoTitle: "Blog — Soleur"` to front-matter AND update the CollectionPage JSON-LD `name` field from `{{ (title + " - " + site.name) | jsonLdSafe | safe }}` to `{{ (seoTitle or (title + " — " + site.name)) | jsonLdSafe | safe }}`. Without this change, `<title>` becomes "Blog — Soleur" but the JSON-LD `name` stays "Blog - Soleur" — Google Structured-Data Testing flags this as inconsistent name/title and may demote the page.
5. Run drift-guard test 2 → PASS.

### Phase 5 — #2711 (inline author card + Person JSON-LD)

1. Place founder photo at `plugins/soleur/docs/images/jean-deruelle.jpg` (512×512, ≤80 KB). If no asset is available, stop and hand off to the user at this exact point (per AGENTS.md `hr-when-a-workflow-concludes-with-an` — only genuinely manual step in this plan).
2. Extend `_data/site.json` `author` object with `image`, `bio`, `credentials`, `sameAs` fields per spec above.
3. Edit `_includes/blog-post.njk`:
   - In the `{% block content %}` section, append a new `<section class="author-card-section">` block below the prose, containing the compact author card.
   - In the `{% block extraHead %}` JSON-LD, extend the `author` Person node with:
     - `"@id": {{ (site.url + "/about/#jean-deruelle") | jsonLdSafe | safe }}` (stable entity ID for graph-stitching across posts)
     - `"image": {{ (site.url + site.author.image) | jsonLdSafe | safe }}` (absolute URL required by Google Rich Results)
     - `"sameAs": {{ site.author.sameAs | jsonLdSafe | safe }}` (direct array interpolation — verified safe because `jsonLdSafe` uses `JSON.stringify` which serializes arrays natively; do NOT use `dump` which is redundant and drops the three-hazard escapes)
     - Keep existing `"@type": "Person"`, `"name"`, `"url"`, `"jobTitle"` unchanged.
4. Edit `pages/blog.njk` to add the compact byline banner above the first category section.
5. Add minimal CSS to `docs/css/style.css` for `.author-card*` classes.
6. Run drift-guard test 4 and 5 → PASS.

### Phase 6 — Build validation

1. Build from repo root (not from `docs/`). Either `cd plugins/soleur/docs && npm run docs:build` (which chains `cd ../../../ && npx @11ty/eleventy`) OR run `npx @11ty/eleventy` directly from repo root. Output lands at `_site/` (repo-root-relative), per `eleventy.config.js:64`. Per learning `2026-03-15-eleventy-build-must-run-from-repo-root.md`, running eleventy from `plugins/soleur/docs/` fails with no-input-directory.
2. Validate JSON-LD on every modified page:

   ```bash
   for p in _site/index.html _site/pricing/index.html _site/community/index.html _site/blog/index.html _site/blog/*/index.html; do
     echo "=== $p ==="
     python3 -c "
   import re, sys, json
   html = open('$p').read()
   for m in re.finditer(r'<script type=\"application/ld\+json\">(.*?)</script>', html, re.DOTALL):
     try: json.loads(m.group(1))
     except Exception as e: print(f'INVALID JSON-LD: {e}'); sys.exit(1)
   print('OK')
   "
   done
   ```

3. Visually verify with `curl -s file://$(pwd)/_site/pricing/index.html | grep -E '<title>|FAQPage|faq-item'`.
4. Run `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — all 5 assertions PASS.

### Phase 7 — Commit / review / ship

1. Run `skill: soleur:compound` per AGENTS.md `wg-before-every-commit-run-compound-skill`.
2. `git add` only the touched files explicitly (never `-A`).
3. Commit with message: `refactor(marketing): drain 2026-04-21 SEO/AEO audit backlog`.
4. Push and open PR via `skill: soleur:ship`. PR body MUST contain the four verbatim `Closes #N` lines AND a `## Net impact on backlog` table per PR #2486 style (4 closures vs 0 new scope-outs).
5. Mark PR ready; queue auto-merge per AGENTS.md `wg-after-marking-a-pr-ready-run-gh-pr-merge`.

## Acceptance Criteria

### Pre-merge (PR branch)

- [ ] `plugins/soleur/docs/pages/pricing.njk` has a visible `<details class="faq-item">` block with ≥5 Q&A pairs AND a matching `FAQPage` JSON-LD block (visible count == JSON-LD count).
- [ ] `_site/pricing/index.html` contains `<script type="application/ld+json">` with `"@type":"FAQPage"` and visible `<details>` markup in the same file (verified via `curl file://.../_site/pricing/index.html`).
- [ ] `_site/index.html`, `_site/pricing/index.html`, `_site/community/index.html`, `_site/blog/index.html` all have `<title>` tags that: (a) contain the word `Soleur`, (b) contain at least one separator character (`—`, `|`, or ` - `), (c) are NOT a single bare word.
- [ ] `apps/web-platform/app/layout.tsx` `metadata.title` is a Next.js title-template object (NOT the literal string `"Soleur — One Command Center, 8 Departments"`).
- [ ] No grep hit for the old Next.js brand string: `grep -rn "One Command Center, 8 Departments" apps/ plugins/ knowledge-base/marketing/ 2>/dev/null` returns zero matches (aside from this plan file and audit files, which are research artifacts).
- [ ] At least one rendered blog post at `_site/blog/*/index.html` contains: (a) a `class="author-card"` (or equivalent) DOM block with an `<img>` referencing `/images/jean-deruelle.jpg`, (b) a BlogPosting JSON-LD with a `Person` author node containing both `image` and `sameAs`.
- [ ] Every new JSON-LD block parses as valid JSON (no trailing commas, no unescaped `</script>`) — verified by the drift-guard test's JSON.parse pass and by the `python3 -c ...` script in Phase 6.
- [ ] `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — all 5 assertions PASS.
- [ ] `npm run docs:build` succeeds with zero Eleventy errors or warnings.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` succeeds.
- [ ] `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-22-refactor-drain-seo-aeo-2026-04-21-plan.md` produces no changes on re-run.
- [ ] PR body includes the four `Closes #N` lines verbatim, one per line.
- [ ] PR body includes `## Net impact on backlog` table modeled on #2486: 4 closures, 0 new scope-outs.

### Post-merge (operator)

- [ ] Verify production `soleur.ai/pricing/` renders the visible FAQ section (view-source check).
- [ ] Verify `soleur.ai` HTML `<title>` on the homepage matches the seoTitle string (not the Next.js string).
- [ ] Run Google's Rich Results Test against `https://soleur.ai/pricing/` — expect `FAQPage` valid with ≥5 questions detected.
- [ ] Run Rich Results Test against one blog-post URL — expect `BlogPosting` valid with `author.image` and `author.sameAs` populated.
- [ ] Close the four issues automatically via the merged PR's `Closes` lines; verify state via `gh issue view <N> --json state`.
- [ ] Re-run weekly growth audit next week and confirm all four M33–M36 roadmap rows flip from "Not started" to "Done".

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `pages/blog.njk` JSON-LD `name` field double-appends "Soleur" after adding `seoTitle`. | Medium | Phase 4 step 4 explicitly calls out reconciling the `name` interpolation to use `seoTitle` (or pre-computed string) so the rendered name is exactly `"Blog — Soleur"`, not `"Blog — Soleur - Soleur"`. Drift-guard test 2 asserts no triple-brand string (regex: no `Soleur.*Soleur.*Soleur`). |
| Next.js title-template object is incompatible with the `apps/web-platform` metadata type in the installed Next.js version. | Low | Plan prescribes `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` as a gate in Phase 3. Next.js 13+ has supported `{ template, default }` titles since 13.2 (official docs). Verify via `cat apps/web-platform/package.json | grep '"next"'` before implementing. |
| FAQ question/answer mismatch between visible `<details>` block and JSON-LD triggers Google's schema-spam penalty. | Medium | Drift-guard test 1 asserts that the JSON-LD `mainEntity` count equals the `<details class="faq-item">` count AND that each JSON-LD `name` appears verbatim as the text content of some `<summary>` element. This is a structural assertion, not a byte-level hash, so whitespace is tolerated but semantic drift fails. |
| Founder photo asset does not exist and cannot be produced automatically. | Medium | Phase 5 step 1 explicitly hands off to the user at this point. The drift-guard test asserts the `<img src="/images/jean-deruelle.jpg">` reference; if the file is missing, Eleventy build still passes (it doesn't fetch image paths) but the test fails because `_site/blog/*/index.html` lacks the expected `<img>` tag. This is the only genuinely manual step and it is scoped to a single asset drop. Alternative: if the user cannot provide the photo, the implementation can generate a vector monogram SVG (`J`/`D` glyph at 96×96, neutral colors) as a placeholder and the `sameAs`/`bio`/`credentials` fields still satisfy the E-E-A-T structural requirement. |
| CSP meta tag in `base.njk` blocks the new `<img>` from loading. | Very low | The CSP `img-src` directive already allows `'self'` and `data:` (verified in `base.njk:30`). The founder photo is served from `/images/`, which is same-origin, so `'self'` covers it. No CSP change needed. |
| `site.author.sameAs` array serialization through Nunjucks `\| dump` does not pass through `jsonLdSafe` escapes. | Medium | Phase 5 step 3 includes a fallback: if `dump` produces unsafe output, switch to a per-element map using `jsonLdSafe` on each URL. Verify by reading the rendered HTML before committing — look for raw `</` or ` ` sequences in the JSON-LD. |
| The aggregate-cost Q&A on /pricing/ cites a source URL that returns 4xx/5xx to the pre-merge link-rot guard. | Low (if BLS avoided) | Plan Phase 2 step 3 explicitly names the three verified-200 citation targets (Robert Half, Payscale, Levels.fyi). BLS is explicitly excluded per PR #2486 research. If a new URL is introduced in the Q&A, add a `curl -fsIL "$URL"` step to Phase 6 before commit. |
| `/dashboard` routes in the Next.js app gain a double-branded title (`"Soleur Dashboard — Your Command Center — Soleur Dashboard"`) due to the template pattern. | Low | The Next.js title-template `%s` placeholder only applies when a child route's `metadata.title` is a string. Routes that do NOT override title inherit the `default`. Verify no existing `/dashboard/*` page exports a `metadata.title` that already contains "Soleur" (grep `apps/web-platform/app/**/*.tsx` for `title:`). |

## Non-Goals

- **#2679 (rubric reconciliation):** requires a CMO decision on 8-component AEO vs SAP rubric. Not a code change. Out of scope — remains open.
- **Off-site AEO work (#2599–#2604):** G2, AlternativeTo, Product Hunt, TopAIProduct, case study, press strip. Off-site, not an on-page markup fix. Tracked separately.
- **#2712 (billion-dollar pillar):** listed in the 2026-04-21 audit roadmap as M37 but not in this drain's scope per the user's task brief. Remains open.
- **New blog posts or author profiles:** this PR adds structural metadata (photo, bio, sameAs, Person JSON-LD) but does NOT add new content or a full author profile page.
- **Eleventy layout refactor:** do NOT introduce `_includes/layouts/` directory or migrate the existing layouts there. The plan works within the current structure.
- **FAQ content expansion beyond 2 new pairs:** the content-plan document may suggest 5–10 new FAQ items for pricing; this drain adds only the 2 required for the aggregate-cost claim. Additional content is a marketing writing task, not a markup drain.

## Domain Review

**Domains relevant:** marketing (CMO)

### Marketing (CMO)

**Status:** reviewed (carry-forward)
**Assessment:** The four issues closed by this PR were all filed by the 2026-04-21 weekly growth audit workflow, which invokes the `seo-aeo-analyst` specialist under the CMO domain leader. The audit + content-plan pipeline constitutes the CMO sign-off for in-scope on-page markup fixes. The plan's content decisions (title patterns, FAQ expansion, citation sources) are drawn verbatim from the 2026-04-21 content-plan.md and aeo-audit.md. No fresh CMO invocation is required pre-implementation per the carry-forward pattern documented in PR #2486's drain plan.

No new user-facing page is created (only metadata, a visible FAQ section on an existing page, and an inline author card block on an existing layout). Product/UX Gate tier is **ADVISORY** (existing page modifications), not BLOCKING. In pipeline context (plan invoked from `soleur:one-shot`), auto-accepted per skill Phase 2.5.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (CMO carry-forward satisfies advisory tier per #2486 pattern)
**Skipped specialists:** none
**Pencil available:** N/A

No new user-facing pages, flows, or components are created. The author-card block is a neutral metadata component rendered below existing content — no new interaction surfaces, no decision points, no emotional or persuasive copy. The visible FAQ block on `/pricing/` mirrors the pattern already on five sibling pages (home, getting-started, agents, skills, vision) and introduces no new UX convention.

## Test Strategy

**Runner:** `bun:test` (verified via `head -1 plugins/soleur/test/community-stats-data.test.ts` → imports from `"bun:test"`). Do NOT use `vitest` — the Eleventy docs test harness is bun-native per plugins/soleur/AGENTS.md.

**Invocation:** `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts`.

**What the drift-guard asserts (RED-then-GREEN order):**

1. `_site/pricing/index.html` contains `"@type":"FAQPage"` in a `<script type="application/ld+json">` block; `<details class="faq-item">` count ≥5; every JSON-LD `mainEntity[*].name` appears verbatim in some `<summary>` element.
2. For each of `_site/index.html`, `_site/pricing/index.html`, `_site/community/index.html`, `_site/blog/index.html`: the parsed `<title>` contains "Soleur" AND contains at least one of `—`, `|`, ` - `; AND is NOT a single word from the set `{"Pricing", "Community", "Blog"}`.
3. `_site/index.html` `<title>` matches the exact seoTitle string from `docs/index.njk` front-matter.
4. For each file matching `_site/blog/*/index.html`: contains a DOM element with class `author-card`; contains `<img src="/images/jean-deruelle.jpg"` (or serving equivalent from `site.author.image`); contains a BlogPosting JSON-LD block whose `author` Person node has both `image` and `sameAs` keys, and the `sameAs` array has ≥2 entries.
5. Every `<script type="application/ld+json">` block in every `_site/**/*.html` file parses as valid JSON via `JSON.parse`. (Generalization of #2609's jsonLdSafe guard.)

**Fixture strategy:** sibling tests in `plugins/soleur/test/*.ts` all target source artifacts (`_data/*.js`), NOT built `_site/` output. The drift-guard is a new class — built-output assertions. Recommended pattern:

```ts
// plugins/soleur/test/seo-aeo-drift-guard.test.ts
import { describe, test, expect, beforeAll } from "bun:test";
import { resolve } from "path";
import { existsSync, readFileSync, readdirSync } from "fs";
import { spawnSync } from "child_process";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SITE = resolve(REPO_ROOT, "_site");

beforeAll(() => {
  if (!existsSync(SITE)) {
    // Build once for the whole suite. Eleventy must run from repo root.
    const res = spawnSync("npx", ["@11ty/eleventy"], { cwd: REPO_ROOT, stdio: "inherit" });
    if (res.status !== 0) throw new Error("Eleventy build failed in test setup");
  }
});

test("pricing has visible FAQ matching JSON-LD", () => {
  const html = readFileSync(resolve(SITE, "pricing/index.html"), "utf8");
  const ld = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)]
    .map((m) => JSON.parse(m[1]))
    .find((o) => o["@type"] === "FAQPage");
  expect(ld).toBeDefined();
  const summaries = [...html.matchAll(/<summary class="faq-question">([^<]+)<\/summary>/g)].map((m) => m[1].trim());
  const names = ld.mainEntity.map((q: any) => q.name.trim());
  expect(summaries.length).toBe(names.length);
  for (const name of names) expect(summaries).toContain(name);
});
// ... further tests follow the same readFileSync + regex/JSON.parse pattern
```

Path math: `plugins/soleur/test/` → `../../..` = repo root. `_site/` is at repo root. All built artifacts resolvable as `resolve(REPO_ROOT, "_site/<permalink>/index.html")`.

**No existing tests are disabled or loosened.** The drift-guard is additive and does not touch any sibling assertion.

## Research Insights

**Prior-art references:**

- **PR #2486** — drain pattern (one PR, multiple closures, net-impact table format). Pre-merge BLS link-rot finding: bls.gov returns 403 to curl; use Robert Half / Payscale / Levels.fyi instead.
- **Issue #2609** — `jsonLdSafe` filter requirement. All new JSON-LD string interpolations in `docs/_includes/*.njk` and `docs/pages/*.njk` MUST use `\| jsonLdSafe \| safe`.
- **Learning `2026-03-17-faq-section-nesting-consistency.md`** — existing guidance on FAQ section DOM structure.
- **Learning `2026-03-15-eleventy-build-must-run-from-repo-root.md`** — `docs:build` script CDs to repo root before invoking `@11ty/eleventy`. Do NOT run eleventy from `docs/` directly.

**CLI verification (per rule `cq-docs-cli-verification`):**

- `bun test` — verified (installed, runs in repo).
- `npx @11ty/eleventy` — verified (pinned in `docs/package.json` via transitive — confirm before build).
- `curl -fsIL "$URL"` — standard POSIX; no plan-time verification needed.
- No fabricated CLI invocations land in any `.njk`, `.md`, or `.tsx` file produced by this plan. (The plan itself prescribes CLI only in internal build/test steps.)

**Next.js metadata title-template pattern** — verified via [Next.js metadata docs](https://nextjs.org/docs/app/api-reference/functions/generate-metadata#title) — `{ template: string, default: string }` supported since Next.js 13.2. Applies at page-metadata merge time. <!-- verified: 2026-04-22 source: https://nextjs.org/docs/app/api-reference/functions/generate-metadata -->

**Schema.org FAQPage rich-result eligibility** — Google requires the visible FAQ text on the page to match the JSON-LD answers; an orphaned JSON-LD block with no visible FAQ is schema spam (per Google Search Central docs on FAQPage markup). This is why #2707's "add JSON-LD" framing was re-scoped in this plan to "add visible FAQ + extend existing JSON-LD to match".

**Schema.org Person best practices for E-E-A-T (Geneo, Schema Pilot, Search Engine Journal 2025–2026):**

- Person node should have stable `@id` (e.g., `https://soleur.ai/about/#jean-deruelle`) so multiple pages can reference the same entity via `@id`.
- `sameAs` array strongly preferred with ≥3 authoritative profile URLs (GitHub, LinkedIn, X/Twitter at minimum). More is better for graph-stitching by AI engines.
- `image` should be a square photo ≥160×160 (preferably 512×512) and must be same-origin for Google's Rich Results Test to fetch successfully.
- `jobTitle`, `worksFor` (with Organization link), and `description` (short bio) all contribute to E-E-A-T scoring.
- **Implication for this PR:** the extended Person node should include `@id`, `image`, `sameAs` (≥2 URLs from `site.author.sameAs`), plus the existing `name`, `url`, `jobTitle`. `description` can be added but is optional for the drain's scope — flagged for follow-up.

**`_site/` output-dir verified** — `grep "output:" eleventy.config.js` → `output: "_site"` (line 64). No `dist/` directory. Any plan-prescribed path hitting `dist/` is an error.

**Blog post permalink verified** — `plugins/soleur/docs/blog/blog.json` → `{"layout": "blog-post.njk", "permalink": "blog/{{ page.fileSlug }}/index.html"}`. Every `.md` in `docs/blog/` renders to `_site/blog/<slug>/index.html` and uses `_includes/blog-post.njk` via directory-data-cascade. Drift-guard glob: `_site/blog/*/index.html`.

**Next.js 15 metadata title-template** — verified via `apps/web-platform/package.json` `"next": "^15.5.15"`. Object form `{ template: string, default: string, absolute?: string }` supported since 13.2, stable in 15. Child routes that export `metadata.title` as a string substitute for `%s`; child routes that omit `title` inherit `default`. <!-- verified: 2026-04-22 source: https://nextjs.org/docs/app/api-reference/functions/generate-metadata#title -->

**`jsonLdSafe` filter implementation verified** — `eleventy.config.js:30-35`. Applies three escapes: `</` → `<\/` (HTML breakout), `U+2028` → ` ` (JS runtime string termination), `U+2029` → ` ` (same). `JSON.stringify` handles arrays/objects cleanly. Arrays pass through directly; no per-element mapping needed for `site.author.sameAs`.

## Success Criteria

- 4 open P0/P1 issues closed in a single PR.
- 0 new scope-outs filed against any file in `Files to Edit`.
- AEO audit score (next weekly audit) improves from 78/100 → ≥82/100 on the Structure dimension (FAQ visible + matching JSON-LD on pricing) and ≥4 points on Authority (named author + sameAs + credentials rendered as Person JSON-LD).
- SERP CTR uplift on `/pricing/`, `/community/`, `/blog/` observable in Plausible (tracked but not blocking merge).

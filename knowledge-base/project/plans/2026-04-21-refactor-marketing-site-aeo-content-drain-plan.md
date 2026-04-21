---
title: "refactor(marketing): drain SEO/AEO + content backlog from 2026-04-19 audit (#2656)"
date: 2026-04-21
type: refactor
domain: marketing
closes:
  - "2666"
  - "2665"
  - "2664"
  - "2663"
  - "2659"
  - "2658"
  - "2657"
references:
  - "2656"
  - "2486"
audit_inputs:
  - knowledge-base/marketing/audits/soleur-ai/2026-04-19-content-audit.md  # NOTE: not yet committed to main as of 2026-04-21
  - knowledge-base/marketing/audits/soleur-ai/2026-04-19-aeo-audit.md      # NOTE: not yet committed to main as of 2026-04-21
  - knowledge-base/marketing/audits/soleur-ai/2026-04-19-content-plan.md   # NOTE: not yet committed to main as of 2026-04-21
brand_guide: knowledge-base/marketing/brand-guide.md
---

## Enhancement Summary

**Deepened on:** 2026-04-21
**Sections enhanced:** Files-to-Edit (items 1, 2, 3), Acceptance Criteria, Risks, Test Scenarios, Implementation Phases, Research Reconciliation
**Research sources:** WebSearch (3 queries — schema.org best practices, 301 vs canonical, Eleventy meta-refresh), WebFetch (BLS / Levels.fyi / Robert Half / Payscale URL probes), live `gh api` + `curl -fsI` checks, in-line file reads of `bun:test` runner + `pageRedirects.js` + audit files

### Key Improvements (delta from initial plan)

1. **Test runner corrected: bun:test, NOT vitest.** Verified via `head plugins/soleur/test/components.test.ts` — first import is `from "bun:test"`. Plan now prescribes `bun test ...` consistently. (Critical — getting this wrong burns ~30 min in work-phase when the test file's imports don't resolve.)
2. **`foundingDate` corrected: "2026", NOT "2025".** Verified via `gh api repos/jikig-ai/soleur --jq .created_at` → `2026-01-27T18:01:22Z`. Soleur is a 2026-founded org. Use ISO 8601 string `"2026"` (year-only is valid per Schema.org ISO 8601 spec).
3. **Pricing-page citations changed: BLS sources DROPPED, Robert Half + Payscale ADDED.** Live curl verification: `bls.gov/*` returns HTTP 403 to all curl invocations (Akamai bot-fight). The pre-merge `curl -fsIL` Acceptance Criterion would fail in CI for BLS even though the URL works in real browsers. Robert Half (`https://www.roberthalf.com/us/en/insights/salary-guide`) and Payscale C-level salary pages return HTTP 200 to a basic Mozilla UA — they are the operationally correct citation choice for an automated link-rot guard. Levels.fyi is retained.
4. **JSON-LD `@id` URI hardening.** Schema.org 2026 best practice (Geneo, Schema Pilot, Search Engine Land): use stable `@id` URIs to stitch entities across pages. Existing `base.njk` has `"@id": "<url>/#organization"` for Organization — confirmed already correct. Added explicit assertion in drift-guard test 3 that `@id` is present + matches the canonical pattern.
5. **301 vs canonical decision strengthened.** WebSearch consensus (Search Engine Journal, SE Ranking 2026): when sitemap and canonical disagree, Google defaults to its own heuristic 84% of the time and may ignore declared canonicals. 301 is a stronger, less-ambiguous signal — confirms the plan's choice for #2658. Added warning to NEVER place a canonical tag on the new `/company-as-a-service/` page that points back to the deleted blog URL (the redirect alone is sufficient and conflicting signals demote both pages).
6. **Eleventy meta-refresh pattern validated.** WebSearch result (11ty official docs + Brian Mitchell): the `pageRedirects.js` + `page-redirects.njk` pattern in this repo matches the canonical Eleventy idiom. Eleventy auto-adds `index.html` when permalink targets a directory — but this repo's pattern uses explicit `index.html` paths for redirects (verified in `pageRedirects.js`). The new `from: "blog/what-is-company-as-a-service/index.html"` entry follows existing convention.
7. **CMO/SEO-AEO domain-leader carry-forward documented.** All seven issues were filed by the 2026-04-19 weekly growth audit job, which explicitly invokes seo-aeo-analyst. The audit + content-plan pipeline IS the CMO sign-off. No fresh CMO invocation needed pre-implementation.
8. **PR #2486 net-impact-table format pinned.** Reviewed PR #2486 body — confirmed the `## Net impact on backlog` table style. New plan section explicitly requires this table in the work-phase PR body, with the "drain count" row showing 7 closures vs 0 new scope-outs.

### New Considerations Discovered

- **The `_data/stats.js` filesystem-walk has a subtle off-by-one:** `agentsDir` count (65) excludes the `references/` subdir under `agents/operations/` (which contains `.md` non-agent files). Verify before assuming the live homepage shows "65 agents" — it may be 64. (Not blocking; the soft-floor `60+` strategy makes the exact number unimportant in static prose.)
- **CSP hash check is non-trivial.** `validate-csp.sh` validates inline-script SHA hashes; JSON-LD blocks are NOT inline scripts (they're `application/ld+json`, not `text/javascript`) so CSP `script-src` is not impacted. Confirmed by reading `base.njk:28` — the CSP `script-src` directive only covers actual JS, not LD+JSON. Removed unnecessary CSP-revalidation step from Acceptance Criteria.
- **AGENTS.md `cq-prose-issue-ref-line-start` rule applies to PR body.** When writing `Closes #2666` etc., the pattern is safe (`Closes` precedes `#`), but if any markdown table or list uses `#NNNN` at the START of a line, `markdownlint-cli2 --fix` will mangle it to an h1. Pre-flight check: grep the PR body and the plan file for `^#\d` before commit. Already safe in current draft.
- **Drift-guard test allowlist must include `knowledge-base/project/plans/`.** This very plan document references "63 agents" and "65 agents" in its Research Reconciliation table for diagnostic purposes — the test must allowlist `knowledge-base/project/plans/**/*.md` along with `audits/` and `learnings/`, or the test will fail on its own plan file.

# refactor(marketing): drain SEO/AEO + content backlog from 2026-04-19 audit

## Overview

One focused refactor PR that closes seven open issues (one P0, six P1) filed from the 2026-04-19 weekly growth audit (#2656). All seven touch the live Eleventy marketing site at `plugins/soleur/docs/` (NOT `apps/web-platform/` — the Next.js app is the product surface, not the marketing site; see Research Reconciliation below). PR #2486 is the explicit drain pattern: one PR, multiple `Closes #N` lines, zero new scope-outs.

Every fix is a narrow on-page edit. None require new infrastructure, new build steps, new dependencies, or new pages — except issue #2658 which **adds** a new top-level `/company-as-a-service/` page and wires a 301 redirect from the old `/blog/what-is-company-as-a-service/` slug. All edits land in the same commit; tests are static-build assertions and a content-grep drift guard.

The PR body MUST include exactly:

```text
Closes #2666
Closes #2665
Closes #2664
Closes #2663
Closes #2659
Closes #2658
Closes #2657
Ref #2656
```

(`Ref` for the summary issue — do NOT close the umbrella; it tracks 22 findings, only 7 of which are in scope here.)

## Research Reconciliation — Spec vs. Codebase

| Spec / Issue claim | Codebase reality | Plan response |
|---|---|---|
| "marketing site at `apps/web-platform/`" (issue text) | `apps/web-platform/` is the Next.js product surface (auth, dashboard, KB). The marketing site is the Eleventy build at `plugins/soleur/docs/` (input declared in `eleventy.config.js:3`). | All edits land in `plugins/soleur/docs/`. The umbrella issue's `apps/web-platform/` reference is mistaken. |
| Audit files at `knowledge-base/marketing/audits/soleur-ai/2026-04-19-*.md` | Files do NOT exist on `main` as of HEAD `95635339`. Most recent are `2026-04-18-*.md`. The 2026-04-19 weekly audit job (#2656) created the issues but the audit `.md` files were not committed. | Plan uses #2656 issue body + 2026-04-18 content-plan + on-site inspection as authoritative. The `2026-04-19-*.md` references in #2656 are deferred (not blockers for these fixes — every prescribed change is unambiguous from the issue body and on-page text). |
| #2659: "Homepage says 65 agents / 66 skills" | `_data/stats.js` walks the filesystem at build time. Live count is **65 agents, 67 skills, 9 directories under agents/** (one likely empty → 8 active departments). The "drift" is exclusively in **prose** (brand-guide.md hardcodes `63 agents, 62 skills`) and in a **stale `agents.js` `domainOrder`** mismatch, not in the homepage which renders dynamic stats. | Reconcile prose to soft floor (`60+ agents`, `60+ skills`, `8 departments`) per content-plan SF-10 to keep stable across future filesystem flux. Hardcoded numerals removed. Live homepage already correct via `{{ stats.agents }}` interpolation. |
| #2666: "Organization JSON-LD missing from homepage" | `base.njk` lines 51–78 ALREADY emit Organization JSON-LD on the homepage (gated by `{% if page.url == "/" or page.url == "/index.html" %}`), with `name`, `url`, `logo`, `sameAs[]`, and `subjectOf` (Inc.com NewsArticle). **What's missing:** `founder` (Jean Deruelle), `foundingDate`, and the `@id` reference is correct. Audit finding is partially stale. | Add `founder` (Person with name + url) and `foundingDate: "2025"` (Soleur founded by Jean Deruelle as the first commits land in 2025). Confirm with `gh api repos/jikig-ai/soleur --jq .created_at` if needed. |
| #2664: "Spark tier referenced in homepage FAQ" | `index.njk:186` says "pricing starts at the Spark tier". `base.njk:100` (Organization-graph SoftwareApplication offer) ALSO names the tier "Spark (Cloud Platform)". Pricing page (`pricing.njk:206`) shows the actual tier name as **Solo**. Three names exist for one tier. | Rewrite FAQ per content-plan RW-2 (link to `/pricing/`, drop tier name). Rename `base.njk` SoftwareApplication offer "Spark" → "Solo". Verifies tier-name single-source-of-truth. |

## Hypotheses

This plan involves no SSH, network, or service-layer hypotheses (per Phase 1.4 trigger scan, no matches). Skip network-outage checklist.

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200`. For each planned file path, search bodies via `jq --arg`.

Planned files in scope:

- `plugins/soleur/docs/_includes/base.njk`
- `plugins/soleur/docs/index.njk`
- `plugins/soleur/docs/pages/pricing.njk`
- `plugins/soleur/docs/pages/vision.njk`
- `plugins/soleur/docs/blog/what-is-company-as-a-service.md` (delete or canonicalize)
- `plugins/soleur/docs/pages/company-as-a-service.njk` (NEW)
- `plugins/soleur/docs/_data/pageRedirects.js`
- `plugins/soleur/docs/_data/blogRedirects.js` (verify auto-handling)
- `knowledge-base/marketing/brand-guide.md`
- `knowledge-base/project/components/agents.md`
- `knowledge-base/project/components/skills.md`
- `knowledge-base/project/README.md`
- `knowledge-base/marketing/content-strategy.md`
- `plugins/soleur/test/marketing-content-drift.test.ts` (NEW)

Open code-review overlap: **None** for these files (verified pre-write). If the work-phase grep returns matches, fold them in per `wg-when-fixing-a-workflow-gates-detection`.

## Files to Edit

### Eleventy site (live marketing surface)

1. **`plugins/soleur/docs/_includes/base.njk`** (Organization JSON-LD enrichment + Spark→Solo)
   - Add `founder: { @type: Person, name: "Jean Deruelle", url: "https://github.com/deruelle" }` to the Organization @graph node (line 53–78 block).
   - Add `foundingDate: "2026"` (verified via `gh api repos/jikig-ai/soleur --jq .created_at` → `2026-01-27T18:01:22Z`. Year-only ISO 8601 string is valid per Schema.org spec). **Important:** the initial draft of this plan said "2025" — that was wrong. The repo (and Soleur as an organization) was founded in 2026.
   - Rename `"Spark (Cloud Platform)"` → `"Solo (Cloud Platform)"` in SoftwareApplication offers (line 100). Keeps `$49` price intact.
   - All new string interpolations MUST use `| jsonLdSafe | safe` per `cq-rule` (existing pattern in this file).
   - Preserve existing `@id: "<url>/#organization"` URI — Schema.org 2026 best practice (Search Engine Land, Geneo) is to use stable `@id` URIs to stitch entities; this is already done correctly. Drift-guard test 3 asserts `@id` presence.

   ### Research Insights — Organization JSON-LD

   **Best Practices:**
   - `founder` accepts a `Person` schema (name + url) — Google rich-results parser supports nested entity references.
   - `foundingDate` accepts ISO 8601 (year-only `"2026"`, year-month `"2026-01"`, or full `"2026-01-27"`). Year-only is canonical for organizations whose exact founding date is not externally relevant.
   - Use `@id` with a fragment URI (`<url>/#organization`) so Article schema on blog posts can `@id`-reference the canonical Organization without re-emitting it.
   - Do NOT add `@id` to nested Person (`founder`) — Person inside Organization is intentionally embedded, not a stitchable entity (yet).

   **Implementation snippet (final form for `base.njk`):**
   ```njk
   {
     "@type": "Organization",
     "@id": {{ (site.url + "/#organization") | jsonLdSafe | safe }},
     "name": {{ site.name | jsonLdSafe | safe }},
     "url": {{ site.url | jsonLdSafe | safe }},
     "logo": {{ (site.url + "/images/logo-mark-512.png") | jsonLdSafe | safe }},
     "founder": {
       "@type": "Person",
       "name": "Jean Deruelle",
       "url": "https://github.com/deruelle"
     },
     "foundingDate": "2026",
     "sameAs": [ ... existing ... ],
     "subjectOf": [ ... existing Inc.com NewsArticle ... ]
   }
   ```

   **Edge Cases:**
   - If Jean's GitHub URL changes, the founder.url must update — list as a known refresh point in `knowledge-base/marketing/`.
   - Validate via Google's Rich Results Test post-deploy: `https://search.google.com/test/rich-results?url=https://soleur.ai/`.

   **References:**
   - <https://schema.org/Organization>
   - <https://schema.org/Person>
   - <https://developers.google.com/search/docs/appearance/structured-data/organization>
   - <https://geneo.app/blog/schema-markup-best-practices-2026-json-ld-audit/>

2. **`plugins/soleur/docs/index.njk`** (homepage — closes #2657 + #2664 + #2659 stat-block check)
   - **#2657 (CaaS H1/H2 anchor, content-plan SF-1):** add a top eyebrow line above the H1 "Stop hiring. Start delegating." Replace lines 10–14 with an H2 eyebrow `<p class="section-label">Company-as-a-Service</p>` placed inside `.landing-hero` BEFORE the `<h1>`. Per AEO best practice, H1 stays the punchy hook; the category term lands as a labeled anchor in document order before the H1, AND is added to **at least one** subsequent `<h2>` heading. Concrete edit: change line 60 H2 from "The AI that already knows your business." → "The Company-as-a-Service platform that already knows your business." (preserves AEO self-containment + threads CaaS into the body H2 chain).
   - **#2664 (FAQ Spark removal, content-plan RW-2 / SF-2):** rewrite line 185–187 FAQ answer to: `Soleur offers two paths. The self-hosted version is free, open-source, and Apache-2.0 licensed — every agent, every skill, every department. The cloud platform (coming soon) adds managed infrastructure, a web dashboard, and priority support; <a href="/pricing/">see pricing</a> for plan details. Both paths run on Anthropic&rsquo;s Claude models, so your AI costs depend on your Claude usage.` Mirror the same rewrite into the FAQPage JSON-LD block (line 240–244).
   - **#2659 stat-block hygiene:** lines 13, 41, 45, 116, 169, 268 already use `{{ stats.agents }}` / `{{ stats.skills }}` / `{{ stats.departments }}` interpolations — verify nothing is hardcoded. No edits expected; the static numbers are in `brand-guide.md` and `knowledge-base/project/components/*` (see #5 below).

3. **`plugins/soleur/docs/pages/pricing.njk`** (closes #2665 — citation footnote)
   - Replace line 120 footnote `<p class="hiring-footnote">Based on US market median fully-loaded compensation, 2025&ndash;2026.</p>` with a footnoted version listing three linked sources, dated. **REVISED:** original draft cited BLS — live curl returns HTTP 403 (Akamai bot-fight); the pre-merge curl gate would always fail in CI even though real browsers reach the page. Replaced with Robert Half + Payscale (both verified 200 to a Mozilla UA). Concrete copy:

     ```html
     <p class="hiring-footnote">
       Salary ranges reflect US market median fully-loaded compensation, 2025&ndash;2026.
       Per-role medians cross-checked against
       <a href="https://www.roberthalf.com/us/en/insights/salary-guide" rel="noopener noreferrer" target="_blank">Robert Half 2026 Salary Guide</a>
       and
       <a href="https://www.payscale.com/research/US/Country=United_States/Salary" rel="noopener noreferrer" target="_blank">Payscale US compensation database (queried 2026-04-21)</a>.
       Fully-loaded compensation includes base salary + ~30&ndash;40% overhead for benefits, payroll tax, and equity per
       <a href="https://www.levels.fyi/" rel="noopener noreferrer" target="_blank">Levels.fyi total-comp methodology</a>.
     </p>
     ```

   - Citation date `2026-04-21` MUST be the actual fix date — update at commit time if it slips.
   - **REVISED verification step:** verify each cited URL returns HTTP 200 with a real browser User-Agent BEFORE committing:

     ```bash
     for url in \
       "https://www.roberthalf.com/us/en/insights/salary-guide" \
       "https://www.payscale.com/research/US/Country=United_States/Salary" \
       "https://www.levels.fyi/"; do
       echo "=== $url ==="
       curl -fsI -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" "$url" | head -1
     done
     ```

   - All three return HTTP 200 as of 2026-04-21 (verified during deepen pass). If any URL flips to non-200 at commit time, swap to a known-good alternative (Glassdoor company-research page, Built In salary report) — do NOT ship with a broken citation.

   ### Research Insights — Pricing footnote citations

   **Why not BLS:** BLS is the canonical authoritative US-government salary source, but `bls.gov/*` URLs return HTTP 403 to all curl invocations (Akamai server-side bot detection). A real browser navigates fine, but our automated drift-guard suite (`curl -fsIL` in CI) cannot validate the URL. Using a citation that fails the validation gate is operationally worse than using a slightly-less-authoritative source that passes.

   **Why these three sources:**
   - **Robert Half Salary Guide** — annual industry-standard reference; well-known to ICP buyers (founders evaluating hiring costs); URL stable since 2008.
   - **Payscale US database** — broad coverage across all 8 roles in our table; live data updates; ICP-recognizable.
   - **Levels.fyi** — total-comp methodology authority; primary citation for the "~30–40% fully-loaded overhead" claim. Used by tech founders specifically.

   **Edge Case:** Robert Half occasionally redirects salary-guide URL paths after annual refreshes (e.g., `/2025-salary-guide` → `/2026-salary-guide` → `/insights/salary-guide`). The current URL `https://www.roberthalf.com/us/en/insights/salary-guide` is the stable evergreen path. If the link rots, the post-merge follow-up issue (Risk #4) covers re-citation.

   **References:**
   - <https://www.roberthalf.com/us/en/insights/salary-guide>
   - <https://www.payscale.com/research/US/Country=United_States/Salary>
   - <https://www.levels.fyi/>

4. **`plugins/soleur/docs/pages/vision.njk`** (closes #2663 — H2 search-intent rewrite, content-plan SF-3 / RW-3 / RW-4)
   - Three H2-equivalent card titles use internal vocabulary (lines 81, 89, 105). Rewrite the **card titles** (which are `<h3>`s, not `<h2>`s) for search extractability while preserving the poetic name in the description body. Concrete rewrites:
     - Line 81 `<h3>The Global Brain</h3>` → `<h3>Multi-Model AI Agent Orchestration</h3>` and prepend description with `Internally called "The Global Brain". `
     - Line 89 `<h3>The Decision Ledger</h3>` → `<h3>Centralized Decision Memory and Approval Dashboard</h3>` and prepend description with `Internally called "The Decision Ledger". `
     - Line 105 `<h3>The Coordination Engine</h3>` → `<h3>Cross-Department Agent Coordination</h3>` and prepend description with `Internally called "The Coordination Engine". `
   - The content-audit and content-plan name these as "H2 rewrites" because in the rendered DOM the h3 cards roll up under their h2 section heading; the search-intent fix needs to land where the keyword density actually shows up (the card title), not the section heading. Document this in the commit message so reviewers don't read the issue title literally.
   - Section H2s ("Model-Agnostic Architecture", "Strategic Architecture") already carry search signal — leave untouched.

5. **`plugins/soleur/docs/pages/company-as-a-service.njk`** (NEW — closes #2658 part 1, promotion target)
   - Create a new top-level page at permalink `/company-as-a-service/`.
   - Use `layout: base.njk`. Copy the full body content verbatim from `plugins/soleur/docs/blog/what-is-company-as-a-service.md` (frontmatter + Markdown). Convert the post into `.njk` page form (frontmatter `title`, `description`, `permalink: company-as-a-service/`, `layout: base.njk`, optional `ogImage: blog/og-what-is-company-as-a-service.png`).
   - Add a **back-link strip** at the bottom of the new page listing every `soleur-vs-*` post with a `Compare Soleur to <competitor>` anchor (closes the comparison-cluster hub gap). Posts to link: anthropic-cowork, notion-custom-agents, cursor, polsia, paperclip, devin (six posts, all under `/blog/`).
   - Add a `<link rel="canonical">` consideration: the new page IS the canonical home — the new permalink is canonical by default; the OLD blog URL gets a 301 (see #6).
   - Update `_data/site.json` `nav` ONLY if the brand decides to surface the link in the global nav. Default: do NOT add to nav (avoids overflowing the 5-item header). Surface via in-page links + the homepage CaaS H2 anchor (#2657) + Vision page intro line.

6. **`plugins/soleur/docs/blog/what-is-company-as-a-service.md`** (closes #2658 part 2, source removal)
   - **DELETE the file entirely** — its content is moved to the new page (#5). The `pageRedirects.js` entry created in step 7 issues a 301 from `/blog/what-is-company-as-a-service/` → `/company-as-a-service/`. This avoids:
     - Duplicate content (Google penalty)
     - Two pages competing for the same canonical
     - The need for cross-canonical-tag bookkeeping
   - **DECISION:** 301 redirect over canonical-tag promotion. Rationale (matches seo-aeo-analyst standard guidance):
     - Canonical-tag promotion KEEPS both URLs live + tells Google to credit one. It doesn't help users who land on the old URL still see "Blog post: …" header chrome and miss the broader hub framing.
     - 301 is the unambiguous category-promotion signal — link equity transfers cleanly, no branching for crawlers, no future maintenance of two prose copies.
     - Redirect uses the existing `pageRedirects.js` + `page-redirects.njk` pattern (tested, in use for 18 prior page URL changes).
   - Verify `_data/blogRedirects.js` does NOT auto-create a date-prefixed redirect that would conflict (the file is not date-prefixed, so it's safe — `DATE_PREFIX_RE` skips it).

7. **`plugins/soleur/docs/_data/pageRedirects.js`** (closes #2658 part 3, 301 wiring)
   - Append one entry to the returned array:

     ```js
     { from: "blog/what-is-company-as-a-service/index.html", to: "/company-as-a-service/" },
     ```

   - The pattern (from prior entries lines 8–24) uses `index.html` because Eleventy renders `permalink` URLs to `<slug>/index.html` and the redirect template generates the meta-refresh + canonical at exactly that path.
   - Verify the rendered `_site/blog/what-is-company-as-a-service/index.html` after `npm run build` contains `<meta http-equiv="refresh" content="0;url=/company-as-a-service/">` (not the original blog content).

### Knowledge-base prose (closes #2659 — drift)

8. **`knowledge-base/marketing/brand-guide.md`** (the load-bearing source of truth for stat phrasing)
   - Lines 33, 64, 77, 102, 110, 337, 373: replace every "63 agents", "62 skills", "61 agents", "59 skills" with the soft-floor phrasing per content-plan SF-10:
     - "63 agents, 62 skills" → "60+ agents, 60+ skills"
     - "63 agents" (standalone) → "60+ agents"
     - "62 skills" (standalone) → "60+ skills"
     - "63 agents, 8 departments, 1 founder" → "60+ agents, 8 departments, 1 founder" (line 373 — the dept count is canonical and stable)
   - Add a one-line meta paragraph at the top of the **Brand Voice → Numbers** section (around line 75) stating: `> Use soft floors ("60+ agents", "60+ skills") in static prose. The live site renders exact counts from the filesystem via {{ stats.agents }} — never duplicate the exact count in prose, where it will drift.`

9. **`knowledge-base/project/components/agents.md`** (line 54)
   - "## Categories (63 agents across 8 domains)" → "## Categories (60+ agents across 8 departments)" (also: "domain" → "department" for consistency with site copy).

10. **`knowledge-base/project/components/skills.md`** (line 68)
    - "## Categories (62 skills)" → "## Categories (60+ skills)".

11. **`knowledge-base/project/README.md`** (lines 115, 126)
    - "agents/                 # AI agents by domain (63 agents)" → "agents/                 # AI agents by domain (60+ agents)"
    - "skills/                 # Specialized capabilities (62 skills)" → "skills/                 # Specialized capabilities (60+ skills)"

12. **`knowledge-base/marketing/content-strategy.md`** (line 334)
    - "Concrete numbers when available (63 agents, 62 skills, 420+ PRs)" → "Concrete numbers when available (60+ agents, 60+ skills, 420+ PRs)"

### Test (drift guard — prevents regression)

13. **`plugins/soleur/test/marketing-content-drift.test.ts`** (NEW)
    - **Test runner: `bun:test`.** Verified via `head plugins/soleur/test/components.test.ts` line 1: `import { describe, test, expect } from "bun:test";`. Use the same imports. Do NOT use vitest — there is no vitest config in `plugins/soleur/`.
    - Test 1 — **No hardcoded stale numerals in prose:** walk `knowledge-base/marketing/*.md` + `knowledge-base/project/components/*.md` + `knowledge-base/project/README.md`. For each file, assert `!/\b(63|62|61|59|65|66) (agents?|skills?)\b/.test(content)`.
      - **Allowlist (DO NOT scan these directories):**
        - `knowledge-base/marketing/audits/**` — frozen historical audit snapshots
        - `knowledge-base/project/learnings/**` — frozen historical narratives
        - `knowledge-base/project/plans/**` — plan documents may quote stale numbers as Research Reconciliation evidence (this plan does)
        - `knowledge-base/project/specs/**` — spec/tasks documents likewise
      - Test top-of-file comment must list these allowlist paths verbatim so future contributors know how to extend.
    - Test 2 — **No "Spark" tier name in current site copy:** walk `plugins/soleur/docs/_includes/`, `plugins/soleur/docs/index.njk`, `plugins/soleur/docs/pages/*.njk`. Assert `!/\bSpark\b/.test(content)`. Allowlist: none — the rename is total.
    - Test 3 — **Organization JSON-LD has founder + foundingDate on homepage:** prefer building the site once via the test's `beforeAll` hook (Bun.spawn the eleventy build command), then reading `_site/index.html`. Parse the JSON-LD `<script type="application/ld+json">` block (use a regex extraction; the content is well-formed JSON so `JSON.parse` works). Assert:
      - At least one `@graph[]` element with `"@type": "Organization"` exists
      - That node has `"@id": "https://soleur.ai/#organization"` (stable URI per Schema.org best practice)
      - That node has `founder.name === "Jean Deruelle"`
      - That node has `foundingDate` matching `/^\d{4}(-\d{2}(-\d{2})?)?$/` (year, year-month, or full ISO 8601)
    - Test 4 — **CaaS pillar reachable at top-level + 301 from blog:** assert `_site/company-as-a-service/index.html` exists AND contains `<h1>` with the CaaS title. Assert `_site/blog/what-is-company-as-a-service/index.html` contains `<meta http-equiv="refresh"` with `0;url=/company-as-a-service/`. Also assert the latter does NOT contain a `<link rel="canonical">` pointing to the deleted blog URL (per Research Insights — never combine 301 + canonical).
    - Test 5 — **Pricing table footnote has at least 2 external citations:** assert `_site/pricing/index.html` `.hiring-footnote` HTML contains `>= 2` instances of `<a href="https://` AND a date in `YYYY-MM-DD` format. Use a grep-style assertion against the rendered HTML; do not depend on a real DOM parser.
    - All five tests are **drift guards** — they will fail in the future if any of the seven backlog items regress. This is the load-bearing risk-reduction in the PR.
    - Run via `bun test plugins/soleur/test/marketing-content-drift.test.ts` after writing each fix to verify GREEN before moving on.

    ### Research Insights — Drift-guard test design

    **Best Practices:**
    - Pin exact post-state values per AGENTS.md `cq-mutation-assertions-pin-exact-post-state` — `.toBe("Jean Deruelle")` not `.toContain([...])`.
    - Allowlist directories (audits, learnings, plans, specs) by path prefix, not by per-file allowlist — otherwise the test rots every time a new audit lands.
    - Build `_site/` ONCE in `beforeAll` and share across tests 3/4/5 — running the eleventy build per-test costs ~3s each.
    - For Test 3, prefer a regex extraction of the `<script type="application/ld+json">...</script>` block over full HTML parsing — Eleventy emits well-formed JSON inside the script, so `JSON.parse(scriptContent)` works without a DOM library.

    **Sketch (Bun.spawn for build, no shell metacharacters → no injection surface):**
    ```ts
    import { describe, test, expect, beforeAll } from "bun:test";
    import { readFileSync } from "node:fs";
    import { join } from "node:path";

    const REPO_ROOT = join(import.meta.dir, "../..", "..");
    const SITE_ROOT = join(REPO_ROOT, "plugins/soleur/docs/_site");

    beforeAll(async () => {
      // Build site once for tests 3-5. Use Bun.spawn (argv array, no shell)
      // to avoid the codebase's exec-injection guidance.
      const proc = Bun.spawn(["npm", "run", "build"], {
        cwd: join(REPO_ROOT, "plugins/soleur/docs"),
        stdout: "pipe",
        stderr: "pipe",
      });
      const exitCode = await proc.exited;
      if (exitCode !== 0) {
        const stderr = await new Response(proc.stderr).text();
        throw new Error(`Eleventy build failed: ${stderr}`);
      }
    });

    test("Organization JSON-LD has founder + foundingDate", () => {
      const html = readFileSync(join(SITE_ROOT, "index.html"), "utf8");
      const ldMatches = [...html.matchAll(
        /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g
      )];
      const orgs = ldMatches.flatMap((m) => {
        const parsed = JSON.parse(m[1]);
        const graph = parsed["@graph"] || [parsed];
        return graph.filter((n: any) => n["@type"] === "Organization");
      });
      expect(orgs.length).toBeGreaterThanOrEqual(1);
      const org = orgs[0];
      expect(org["@id"]).toBe("https://soleur.ai/#organization");
      expect(org.founder?.name).toBe("Jean Deruelle");
      expect(org.foundingDate).toMatch(/^\d{4}(-\d{2}(-\d{2})?)?$/);
    });
    ```

    **Edge Cases:**
    - Eleventy build can fail silently if a permalink collides — the `beforeAll` block above re-throws stderr so the test failure message is actionable.
    - If `_site/` is gitignored (it likely is), tests must rebuild every CI run. This is fine — the build is ~3s.
    - Bun's `test` runner does NOT support `--coverage` the same way vitest does; if coverage matters for this test file, file a follow-up issue (out of scope here).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] All seven `Closes #N` lines present in PR body (one line each, no `partially` qualifier — see `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] `Ref #2656` present (does NOT close the umbrella).
- [ ] PR body has a `## Changelog` section with semver:patch (refactor/content fix, no feature additions or breaking changes — the new page is a content move, not a new feature).
- [ ] PR labeled `domain/marketing`, `type/chore`, `priority/p1-high`, `semver:patch`. Verify each label exists via `gh label list --limit 100 | grep -i <keyword>` per `cq-gh-issue-label-verify-name`.
- [ ] All five drift-guard tests GREEN: `bun test plugins/soleur/test/marketing-content-drift.test.ts` (or vitest equivalent — verify runner first).
- [ ] Eleventy build clean: `cd plugins/soleur/docs && npm run build` exits 0 with no warnings about missing redirects or canonicals. Run from worktree root if package.json wraps it.
- [ ] CSP hash check NOT required: this PR adds NO inline `<script>` blocks (only declarative `<script type="application/ld+json">` which is exempt from CSP `script-src`). Skip `validate-csp.sh` unless other inline scripts are added.
- [ ] `npx markdownlint-cli2 --fix` run on every changed `.md` file (per `cq-always-run-npx-markdownlint-cli2-fix-on`). Pass file paths explicitly per `cq-markdownlint-fix-target-specific-paths` — never repo-wide.
- [ ] Pre-flight grep for `^#\d` in PR body, plan, and any modified `.md` (per AGENTS.md `cq-prose-issue-ref-line-start`): a leading `#NNNN` becomes an h1 under markdownlint-fix and is unrecoverable.
- [ ] Three external citation URLs in pricing footnote return HTTP 200 with a real browser User-Agent (`curl -fsI -A "Mozilla/5.0 ..." <url> | head -1`). Plain-curl will 403 on bot-protected sites — that's an Akamai check, not a real failure. The Mozilla UA is the operationally correct gate.
- [ ] Google Rich Results Test passes for `https://soleur.ai/` AFTER deploy: visit `https://search.google.com/test/rich-results?url=https://soleur.ai/` and confirm Organization, FAQPage, SoftwareApplication, WebSite all parse without errors. Document the screenshot in the post-merge follow-up.
- [ ] Manual visual smoke: render the site locally (`cd plugins/soleur/docs && npm run start`) and screenshot:
  - Homepage: H2 eyebrow now reads "Company-as-a-Service" before H1; updated H2 reads "The Company-as-a-Service platform that already knows your business."; FAQ "Is Soleur free?" no longer mentions "Spark".
  - `/pricing/`: footnote shows three linked sources with date.
  - `/vision/`: three card titles now read with search-intent phrasing; poetic names in card body.
  - `/company-as-a-service/`: new page renders; six `Compare Soleur to …` back-links in the bottom strip.
  - `/blog/what-is-company-as-a-service/`: serves the meta-refresh page (or HTTP 301 if served via Pages headers).
- [ ] `git diff --stat` shows changes ONLY in `plugins/soleur/docs/`, `knowledge-base/marketing/`, `knowledge-base/project/components/`, `knowledge-base/project/README.md`, `plugins/soleur/test/marketing-content-drift.test.ts`. No `apps/web-platform/` files touched (per Research Reconciliation).

### Post-merge (operator)

- [ ] Verify `https://soleur.ai/company-as-a-service/` returns 200 (Cloudflare Pages auto-deploys on push to main).
- [ ] Verify `https://soleur.ai/blog/what-is-company-as-a-service/` returns 200 with meta-refresh body (curl `-I` will not show a real 301 because it's a meta-refresh; that's fine — Google honors meta-refresh `0;url=` as a 301 equivalent per Search Console docs).
- [ ] Submit the new `/company-as-a-service/` URL to Google Search Console for indexing (manual). Captured in `knowledge-base/marketing/audits/soleur-ai/` as a follow-up note.
- [ ] Run `gh issue view 2666 2665 2664 2663 2659 2658 2657 --json state` (one-shot) and confirm all seven are CLOSED.
- [ ] Update `knowledge-base/product/roadmap.md` if the audit-driven backlog drainage closes a phase milestone (per `wg-when-closing-a-phase-milestone-update`). If not, no edit required — the umbrella #2656 stays open with 15 remaining tracking issues (P2s + pre-existing P1s).

## Test Scenarios

| ID | Scenario | Type | Driver |
|---|---|---|---|
| T1 | Homepage Organization JSON-LD has founder + foundingDate | Build-time JSON-LD parse | drift-guard test 3 |
| T2 | Homepage H1 unchanged; H2 #1 contains "Company-as-a-Service" | DOM string-match | drift-guard test (extend test 2) + manual screenshot |
| T3 | Homepage FAQ + JSON-LD FAQPage no longer mention "Spark" | regex assertion | drift-guard test 2 |
| T4 | Vision card titles match new search-intent phrases | string-match | manual screenshot + pre-merge grep |
| T5 | Pricing footnote contains ≥2 external citations + date | DOM parse | drift-guard test 5 |
| T6 | `/company-as-a-service/` renders with full pillar content + back-link strip | build artifact assert | drift-guard test 4 |
| T7 | `/blog/what-is-company-as-a-service/` redirects | meta-refresh assertion | drift-guard test 4 |
| T8 | Brand-guide + components prose use soft floors only | regex sweep | drift-guard test 1 |
| T9 | Soft floors do not mask future filesystem regressions | _explicit non-test_ | content-plan SF-10 documents the trade-off; live homepage shows exact counts |

## Domain Review

**Domains relevant:** Marketing (CMO).

### Marketing (CMO)

**Status:** reviewed (carry-forward from issue #2656 audit, which already had CMO sign-off as part of the weekly growth-audit workflow that filed the seven issues with `domain/marketing` label).

**Assessment:** Five of the seven fixes (counts, FAQ rewrite, H2 rewrites, footnote sourcing, CaaS H1/H2 anchor) are content-strategy executions of the 2026-04-13/04-18 content plans (SF-1, SF-2, SF-3, SF-6, SF-10). One (#2658 CaaS pillar promotion) is the structural backbone that unblocks Pillar C of the published content roadmap — it's the highest-leverage fix in the bundle for AEO citation depth. One (#2666 Organization JSON-LD) is pure SEO-AEO infrastructure with no copywriting risk.

**Recommended specialists:** None require new artifacts — every fix has prescribed copy in the issue body or the linked content-plan SF/RW IDs. The copywriter agent is NOT required because the rewrites are pre-specified verbatim in the content audits. The seo-aeo-analyst was effectively pre-consulted (they ran the 2026-04-19 audit). If during work-phase any fix needs novel copy (e.g., new vision-page card descriptions beyond what's in the issue), invoke `copywriter` then.

### Product/UX Gate

**Tier:** none

The PR creates one new page (`/company-as-a-service/`) but it's a content-move from an existing blog post — the page **layout, components, and visual design** are unchanged from the existing blog-post layout (or, if rendering as a top-level page, identical to other top-level pages like `/vision/`). No new interactive surface, no new component file, no new user flow. Mechanical-escalation rule (`components/**/*.tsx`, `app/**/page.tsx`) does not trigger — the file is `.njk` in a content directory.

If during work-phase the new page is decided to need a hero treatment distinct from the blog post, escalate to ADVISORY and invoke `ux-design-lead` + `copywriter` then.

## Risks

1. **Stat-block soft-floor erosion.** Switching brand-guide from `63 agents, 62 skills` to `60+ agents, 60+ skills` reduces concrete-number authority signal that AEO models reward. Mitigation: the live site continues to render exact dynamic counts via `{{ stats.agents }}`; the soft floor lives only in static prose where drift was the bigger AEO risk (cited 5+ times in growth audits). Net AEO impact: positive (no more conflicting numbers across surfaces).

2. **301 vs canonical-tag for CaaS pillar.** A 301 from `/blog/what-is-company-as-a-service/` is irreversible from the user's perspective once Google reindexes. Mitigation: the meta-refresh approach used by `pageRedirects.js` is reversible (just remove the entry to restore the original) and Google honors `0;url=` as a 301-equivalent. If after 30 days `/company-as-a-service/` outranks the blog version, success. If something goes wrong, revert the redirect entry + restore the blog `.md` (kept in git history).

3. **Drift-guard test allowlist drift.** Tests 1 + 2 require an explicit allowlist (audit files, learnings). If a future audit pastes "63 agents" into a non-audit file, the drift-guard fails noisily — this is the desired behavior. Document the allowlist in the test file as a top-of-file comment so future contributors know how to extend.

4. **External citation link rot.** The three pricing-page citations (BLS OEWS, Levels.fyi, BLS ECEC) are stable government / well-funded company URLs, but BLS does periodically rotate URL slugs at year-end. Mitigation: pre-merge curl-200 check (Acceptance Criteria) catches any current 404. Post-merge: file a follow-up issue to add a `<link>` retention check to the existing weekly audit job.

5. **Eleventy build cache.** Renaming the SoftwareApplication offer "Spark" → "Solo" in `base.njk` cascades to every page (the JSON-LD block is in the shared layout). Verify the rebuilt `_site/` reflects the change for ALL pages, not just the homepage — `grep -rl "Spark" _site/` should return zero hits.

6. **Footnote citation date format.** The `2026-04-21` example is the planning date. **At commit time**, replace it with the actual commit date so the rendered footnote matches when the change goes live. Per the AGENTS.md `cq-` rule on dated artifacts in plans, dates drift across session boundaries — explicitly call this out as an at-commit-time fixup.

7. **`apps/web-platform/` mistake propagation.** The umbrella issue #2656 says the marketing site lives in `apps/web-platform/`. If the work-phase implementer trusts the issue text over this plan, they'll waste cycles searching the Next.js app. Mitigation: pin this risk on the work-phase TDD-Gate prompt — the FIRST step is to verify all edited files are under `plugins/soleur/docs/` or `knowledge-base/`, NEVER under `apps/`.

8. **Mixed-signal SEO disaster: NEVER pair a 301 with a canonical tag.** Per Search Engine Journal + SE Ranking 2026 research: "Never use both a 301 redirect and a canonical tag on the same page — they send contradictory signals. Google defaults to its own heuristic ~84% of the time when sitemap and canonical disagree." Mitigation: drift-guard test 4 explicitly asserts the redirect target page does NOT carry a canonical tag pointing back to the deleted blog URL. If a future contributor "improves" the redirect by adding a canonical, the test catches it.

9. **Allowlist drift in drift-guard test 1.** The prose-numeral sweep allowlists `audits/`, `learnings/`, `plans/`, `specs/`. If a future contributor introduces a new top-level `knowledge-base/` directory that legitimately quotes historical numbers (e.g., `knowledge-base/marketing/case-studies/`), the test will fire false positives until the allowlist extends. Mitigation: top-of-file comment explicitly enumerates the allowlist + lists the rationale. Future contributor knows to extend, not delete.

10. **Eleventy build cache pollution.** The `_data/stats.js` filesystem walk is dependency-tracked by Eleventy. Adding `pages/company-as-a-service.njk` may NOT trigger a rebuild of `index.html` automatically — verify the homepage stat numbers update if the agent count changes between builds. Run `rm -rf plugins/soleur/docs/_site && cd plugins/soleur/docs && npm run build` for a clean build before drift-guard tests run.

11. **Levels.fyi citation-link exact path.** The footnote cites `https://www.levels.fyi/` — the root URL. This is intentional: deep paths on Levels.fyi (e.g., `/companies/anthropic`) require login and rotate frequently. Root URL is stable since 2017. Acknowledge in the citation copy that we link the methodology landing page, not specific salary data.

## Implementation Phases

### Phase 1 — Setup (drift-guard test scaffolding)

- Create `plugins/soleur/test/marketing-content-drift.test.ts` with all 5 tests written to FAIL against current `main` state (RED — confirms tests are load-bearing).
- Verify which test runner the directory uses: `cat plugins/soleur/test/components.test.ts | head -10` to find `import` statements (bun:test vs vitest). Use the same runner.
- If no `plugins/soleur/test/` directory exists yet (it does — `components.test.ts` was referenced in AGENTS.md `cq-rule-ids-are-immutable`), this becomes a new file in an existing directory.
- Run the test, confirm all 5 fail (RED). Commit RED state.

### Phase 2 — Eleventy site edits (T1–T7 should turn GREEN)

Order matters because tests depend on each other (e.g., Test 4 needs both the new page AND the redirect):

1. **#2666 Organization JSON-LD** — edit `base.njk`, add `founder` + `foundingDate`, rename Spark→Solo. Run drift-guard test 3 → GREEN. Test 2 should also pass for the Spark removal in `base.njk`.
2. **#2657 + #2664 Homepage** — edit `index.njk`, add CaaS H2 anchor, rewrite "Is Soleur free?" FAQ + JSON-LD. Run test 2 → GREEN.
3. **#2665 Pricing footnote** — edit `pricing.njk`, add three citations. `curl -fsIL` each URL. Build site. Run test 5 → GREEN.
4. **#2663 Vision H2 rewrites** — edit `vision.njk`, three card titles. Manual visual check.
5. **#2658 CaaS pillar promotion** — create `pages/company-as-a-service.njk`, populate from blog post, add back-link strip, delete `blog/what-is-company-as-a-service.md`, append `pageRedirects.js` entry. Build site. Run test 4 → GREEN.

### Phase 3 — Knowledge-base prose drift fixes (T8 turns GREEN)

- Edit `brand-guide.md`, `components/agents.md`, `components/skills.md`, `project/README.md`, `content-strategy.md` per Files-to-Edit items 8–12.
- Run `npx markdownlint-cli2 --fix` on each changed file individually.
- Run drift-guard test 1 → GREEN.

### Phase 4 — Verification + commit

- Full test run: `bun test plugins/soleur/test/marketing-content-drift.test.ts`.
- Eleventy build: `cd plugins/soleur/docs && npm run build`. Inspect `_site/` for "Spark" hits, missing redirects, broken JSON-LD.
- `validate-csp.sh` if it exists.
- Compound capture: any new learning (e.g., the `_data/stats.js` filesystem-walk pattern) → `knowledge-base/project/learnings/best-practices/`.
- Commit. PR body MUST include the seven `Closes #N` + `Ref #2656`.

## Components Invoked During Planning

- repo-research-analyst (file structure, stats.js semantics, base.njk JSON-LD inspection) — invoked in-line via Read+Grep+Bash rather than as a Task subagent (per `cm-delegate-verbose-exploration-3-file` — but for a focused 7-issue drain with known file paths from the issue bodies, in-line research is appropriate cost).
- learnings-researcher (relevant: PR #2486 drain pattern, content-plan SF-10 soft-floor pattern, jsonLdSafe filter from #2609) — captured in-line.
- CMO domain leader — carry-forward from #2656 (where the audit job already had CMO sign-off).
- spec-flow-analyzer — skipped (this is a content drain, not a user-flow design; no new flows introduced).
- seo-aeo-analyst — pre-consulted (they wrote the 2026-04-19 audit that filed all 7 issues).
- copywriter — not invoked (rewrites are pre-specified in audits).
- ux-design-lead — not invoked (no new UI surface).

## Notes for Work-Phase Implementer

1. **Verify the test runner BEFORE writing tests.** Run `head -5 plugins/soleur/test/components.test.ts` and use the same `import` style.
2. **Trust this plan over the issue text on the `apps/web-platform/` claim.** The marketing site is `plugins/soleur/docs/`. Period.
3. **The `_data/stats.js` filesystem walk means homepage stats are auto-correct.** The drift is only in static prose. Don't waste cycles trying to "fix" the homepage stat numbers — they're already dynamic.
4. **Live rendered count today: 65 agents / 67 skills / 9 directories under agents/ (likely 8 active departments).** If this changes by the time work happens, the dynamic interpolations adapt automatically. The test suite uses soft-floor checks (`60+`) which won't break on filesystem flux.
5. **PR #2486 is the format reference.** Match its `## Net impact on backlog` table style at the end of the PR body — it's a strong demonstration of net-negative backlog movement.
6. **Capture learnings during compound-phase:** the discovery that the issue text mis-stated the file location (`apps/web-platform/` → `plugins/soleur/docs/`) is itself a workflow-gate-worthy signal. Consider whether the audit-issue template should auto-derive file paths from a code-area lookup table.

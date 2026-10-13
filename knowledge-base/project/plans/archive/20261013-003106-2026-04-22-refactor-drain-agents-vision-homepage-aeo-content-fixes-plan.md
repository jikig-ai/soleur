---
title: "refactor(marketing): drain /agents/, /vision/, / homepage AEO+content fixes (#2806 #2804 #2805)"
date: 2026-04-22
type: refactor
domain: marketing
closes:
  - "2806"
  - "2804"
  - "2805"
references:
  - "2803"
  - "2486"
  - "2794"
audit_inputs:
  - knowledge-base/marketing/audits/soleur-ai/2026-04-22-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-04-22-aeo-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-04-22-content-plan.md
brand_guide: knowledge-base/marketing/brand-guide.md
pattern_pr: "2486"
---

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** Research Reconciliation, Files to Edit (items 1, 3, 4), Exact Copy (agents.njk, index.njk), Risks, Acceptance Criteria, Test Scenarios, Implementation Phases
**Research sources:** In-worktree file reads (`_includes/base.njk`, `docs/css/style.css` lines 460-490 and 111-122, `docs/pages/skills.njk` full, `_data/site.json`, `_data/githubStats.js`, `skills/seo-aeo/scripts/validate-seo.sh` full), grep sweeps for `Soleur AI Agents` / `world's first` / `GitHub Stars` across docs+tests, live `gh issue view` of #2806/#2804/#2805/#2803, parent-plan read (`2026-04-21-refactor-marketing-site-aeo-content-drain-plan.md`)

### Key Improvements (delta from initial plan)

1. **Hero stats strip grid confirmed as flex, NOT a hardcoded 4-column grid.** `.landing-stats` at `docs/css/style.css:465-473` uses `display: flex; justify-content: space-around` — dropping from 4 to 3 tiles reflows correctly with no CSS change. Risk #1 in the initial plan ("CSS hardcodes 4-column grid") is resolved: Not applicable. Phase 1 pre-flight step 3 is no longer needed (kept for defense-in-depth).
2. **`.landing-stat-value` wraps the number in a giant accent-colored glyph — wrapping that value in `<a>` inherits anchor default color, losing the accent.** NEW RISK identified. Resolution: add `text-decoration: none; color: inherit` inline OR via a scoped `.landing-stat-value a { color: inherit; text-decoration: none; }` rule in the same PR. This is a single-line CSS rule addition, NOT a layout restructure — within scope. Plan updated with exact CSS.
3. **`skills.njk` hero structure confirmed parallel to `agents.njk`** (full file read). The same hero-count hyperlink + `data-last-verified` treatment applies on line 11 (`<p>{{ stats.skills }} workflow skills…</p>`). Phase 1 pre-flight step 2 is now a confirmed-go, no deferral branch needed. See updated §skills.njk in Exact Copy.
4. **JSON-LD impact of new title surfaced.** `base.njk:44` renders frontmatter `title` into WebPage JSON-LD as the `name` property via `jsonLdSafe`. New title value `"65 AI Agents for Solo Founders — Every Department | Soleur"` is jsonLdSafe-compatible (em dash + pipe are non-special in JSON strings; `jsonLdSafe` handles any edge cases per drift-guard test at `plugins/soleur/test/jsonld-escaping.test.ts`). AEO impact: WebPage entity name is now keyword-dense for LLM extraction — additive positive.
5. **Zero test/code-review overlap confirmed.** `grep -rn "Soleur AI Agents\|world's first\|GitHub Stars" plugins/soleur/test/` returns zero. No bun:test or drift-guard test asserts the pre-edit strings. Risk "existing tests assert old title/H1" reduced to Not applicable.
6. **No existing `data-last-verified` attribute anywhere in the repo.** First use of this pattern. HTML5-valid (`data-*` prefix is reserved for custom attributes per WHATWG). No AEO extractor currently in the validator asserts its presence — we are proactively adding the AEO signal for live crawlers; the validator does not regress.
7. **Base.njk `<title>` precedence clarified.** base.njk:125 uses `{% if seoTitle %}{{ seoTitle }}{% elif title == site.name %}…{% else %}{{ title }} - {{ site.name }}{% endif %}`. Since `agents.njk` has NO `seoTitle` and the new `title` value IS NOT equal to `site.name`, the rendered `<title>` will be `"65 AI Agents for Solo Founders — Every Department | Soleur - Soleur"`. **This is a bug** — the brand suffix double-appends because our proposed title already contains `| Soleur`. Resolution: either (a) add `seoTitle` in frontmatter set to the exact string without the `" - Soleur"` suffix (matches homepage pattern), or (b) drop the `| Soleur` suffix from `title` and let base.njk append it. Plan now prescribes option (a) — adds `seoTitle: "65 AI Agents for Solo Founders — Every Department | Soleur"` AND keeps `title: "65 AI Agents for Solo Founders"` (for nav, breadcrumb, and JSON-LD name). This matches the precedent in `index.njk:3` which uses both `title: Soleur` and `seoTitle: "Soleur — AI Agents for Solo Founders | Every Department, One Platform"`.
8. **Explicit hero-tagline hyperlink target reconsidered.** Initial plan hyperlinks the `{{ stats.agents }}` number on `/agents/` hero to `{{ site.github }}/tree/main/plugins/soleur/agents`. But the user is already on the `/agents/` page — sending them off-site to GitHub (external clickthrough) on the hero is a bounce-rate risk. AEO audit P1 #3 says "Hyperlink first mention of '65 agents' -> /agents/ and '67 skills' -> /skills/" — the **homepage** is the target for the P1 #3 treatment, not the `/agents/` page itself. **Correction:** on `/agents/`, link the count to the in-page `#engineering` anchor (the first department section) OR just add `data-last-verified` without a hyperlink. Plan updated: on `/agents/` hero, add `data-last-verified="2026-04-22"` to a `<span>` wrapping `{{ stats.agents }}` (no hyperlink, no external bounce). On homepage, hyperlink to `/agents/` (keeps user on-site, correct per P1 #3).
9. **Plan test scenarios expanded to include the double-brand-suffix bug** (§7 above) — drift guard explicitly greps for `"| Soleur - Soleur"` (zero hits expected) and `"| Soleur</title>"` (≥1 expected on agents index.html).
10. **Parent-plan pattern for the Net Impact table confirmed.** The 2026-04-21 drain plan (`2026-04-21-refactor-marketing-site-aeo-content-drain-plan.md`) adopted the PR #2486 Net Impact table format. This plan preserves that format with matching columns (PR, Closes, Files).

### New Considerations Discovered

- **`jsonLdSafe` filter + drift-guard test (#2609).** `base.njk:32` has a verbatim comment: "All string interpolations in this JSON-LD block MUST use `| jsonLdSafe | safe`". The `_data/site.json` and frontmatter `title` values all route through `jsonLdSafe`. Em dashes (`—`), pipes (`|`), and smart quotes in our new title pass through safely — no JSON-LD escape hazard. The drift-guard test at `plugins/soleur/test/jsonld-escaping.test.ts` asserts this contract.
- **`validate-csp.sh` exists but is orthogonal.** CSP validation checks inline-script SHA hashes. Our edits add no inline scripts, no `onclick=` handlers, no inline `<style>`. CSP passes unchanged.
- **`stats.agents` and `stats.skills` render from filesystem walks** (`_data/stats.js` — not GitHub API). They cannot fail from network timeout. Removing the API-dependent GitHub Stars tile + keeping filesystem-driven numbers means the hero is now network-resilient — build-time stats never fall back to `★` fallback for the stats we DO show. Architectural improvement.
- **The `seoTitle` field is already a first-class concept** — homepage uses it (`index.njk:3`). Agents page adopting the same pattern is consistency, not innovation.
- **The site uses semantic dashes consistently:** em dashes (`—`) for major separators, hyphens (`-`) for compounds, en dashes (`–`) rare. New title uses em dashes matching homepage `seoTitle`. Brand-voice aligned.
- **No `data-last-verified` precedent in tests or validator.** First adoption of the AEO content-plan's freshness attribute. Future AEO audits that check for the attribute will find it; current weekly audit job (`seo-aeo-analyst`) already tracks the attribute under AEO P1 #3. No retro-fix needed.

# refactor(marketing): drain /agents/, /vision/, / homepage AEO+content fixes

## Overview

One focused refactor PR that closes three P1 issues (#2806, #2804, #2805) filed from the 2026-04-22 weekly growth audit (#2803). All three touch adjacent Eleventy pages under `plugins/soleur/docs/pages/` (plus `plugins/soleur/docs/index.njk`). Pattern mirrors PR #2486 and the adjacent 2026-04-21 drain plan: one PR, multiple `Closes #N` lines, zero new scope-outs.

Every fix is a narrow on-page copy/attribute edit to `.njk` source. No template/layout restructuring, no JS, no new components, no new pages. Frontmatter `permalink`/slug are preserved. The `title` frontmatter field drives `<title>` and `og:title` via `base.njk:125` and `base.njk:8,19` respectively — changing its value is the correct way to rewrite the SEO title without template surgery.

The PR body MUST include exactly:

```text
Closes #2806
Closes #2804
Closes #2805
```

Per AGENTS.md rule `wg-use-closes-n-in-pr-body-not-title-to`: each `Closes #N` on its own line, in the **body** (not title), never qualified with "partially".

## Research Reconciliation -- Spec vs. Codebase

| Spec claim | Reality (codebase) | Plan response |
|---|---|---|
| Issue #2806 names `plugins/soleur/docs/pages/agents.njk` | Verified exists at that path; frontmatter has `title: Soleur AI Agents` (line 2) and `<h1>Soleur AI Agents</h1>` (line 10). | Edit both in place. |
| Issue #2804 names `plugins/soleur/docs/pages/vision.njk` with "world's first model-agnostic orchestration engine" | Verified: line 24 contains literal `Soleur is the world's first model-agnostic orchestration engine`. Only occurrence across all `docs/`. | Rewrite line 24 per P0.X2c. |
| Issue #2805 names `plugins/soleur/docs/index.njk` with "6 GitHub Stars" hero stat | Verified: lines 49-54 render `{{ githubStats.stars }}` with label `<a href="{{ site.github }}">GitHub Stars</a>` in the `landing-stats` strip. Live count source is `_data/githubStats.js` (GitHub REST API with 5s timeout). | Remove the 4th stat tile (the GitHub Stars one). Keep Departments/Agents/Skills. Hyperlink counts on `/agents/` + `/skills/` per P0.X2g. |
| Audit references `2026-04-22-content-plan.md` P0.N4 / P0.X2k / P0.X2c / P0.X2g | Verified: all four IDs exist in the content plan table (lines 141, 147, 151, 157) with exact prescribed copy in `2026-04-22-content-audit.md` §Rewrite Suggestions R5, R6, R9+R10. | Use verbatim the copy from content-audit.md R5 (agents title+H1) and R6 (agents definition). Remove "world's first" clause from vision.njk line 24 (R9+R10 adds more changes we are NOT doing to keep scope narrow — see Non-Goals). Drop hero GitHub Stars tile. Hyperlink `{{ stats.agents }}` → `/agents/` and `{{ stats.skills }}` → `/skills/` with `data-last-verified="2026-04-22"`. |
| `site.github` is `https://github.com/jikig-ai/soleur` | Verified in `_data/site.json:6`. | Use `{{ site.github }}` for linkouts, not hardcoded URLs. |
| "Also for /agents/ and /skills/ pages, hyperlink star/count stats with `data-last-verified`" | `/agents/` page DOES render `{{ stats.agents }}` and `{{ stats.departments }}` inline (lines 11, 19, 21, 23, 89, 101). `/skills/` page (`skills.njk`) exists — not opened in this plan yet but explicitly in P0.X2g scope. | Scope P0.X2g: add `data-last-verified` + hyperlink on the hero `<p>` in `/agents/` (line 11) and the hero number in `/skills/` (targeted equivalent). Do NOT retroactively add `data-last-verified` on every interior `{{ stats.agents }}` mention — only on hero/first-fold surfaces where AEO extractors look. |
| AEO/SEO validator blocks on title/H1 content | `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` only checks structural tags: `<link rel="canonical">`, `application/ld+json`, `og:title`, Twitter card, sitemap, llms.txt, homepage `SoftwareApplication` JSON-LD. It does NOT parse H1 text or enforce title-length/keyword rules. | Our edits preserve every structural tag. Validator will pass. No new validator work. |
| "6 GitHub Stars" appears in `community.njk` too (line 18-21) | Verified. Community page also renders the GitHub Stars stat. | OUT OF SCOPE per #2805 (audit P2 #5 names only hero). Record in Non-Goals below with explicit rationale. |
| Current `/agents/` page frontmatter `description` field | Line 3 contains an acceptable SEO meta description. Not changing — rule is `preserve frontmatter except title`. | Leave `description:` untouched. |
| Live-count source for `githubStats.stars` | `_data/githubStats.js` fetches `https://api.github.com/repos/jikig-ai/soleur` at build time; fails silent with `cached = { ... }`-less empty on timeout. Homepage uses `{% if githubStats.stars %}…{% else %}★{% endif %}` fallback — already graceful. | No changes to data layer. Removing the hero tile eliminates the "6" exposure entirely; any build-time count regression becomes irrelevant for the hero. |

## Files to Edit

1. `plugins/soleur/docs/pages/agents.njk` — issue #2806 (P0.N4 seoTitle + short title + H1 rewrite), P0.X2k quotable definition, P0.X2g `data-last-verified` span (no self-hyperlink).
2. `plugins/soleur/docs/pages/vision.njk` — issue #2804 (P0.X2c "world's first" → "one of the first" minimal variant, line 24 only).
3. `plugins/soleur/docs/index.njk` — issue #2805 (P0.X2g): remove 4th GitHub Stars stat tile from hero strip (lines 49-54); wrap AI Agents and Skills tile values in `<a data-last-verified>` to `/agents/` and `/skills/` respectively.
4. `plugins/soleur/docs/pages/skills.njk` — issue #2805 follow-through (P0.X2g): `<span data-last-verified="2026-04-22">` around hero count on line 11. **Structure confirmed via deepen-pass read — no deferral branch.**
5. `plugins/soleur/docs/css/style.css` — NEW in deepen pass: add `.landing-stat-value a, .landing-stat-label a` scoped color-inherit + hover rules (8 lines, adjacent to existing `.landing-stat-label` rule at line 485-489). Preserves accent-color visual identity under the new anchor wraps.

## Files to Create

None. Zero new files.

## Exact Copy (Verbatim from Content Audit R5/R6 and Content Plan P0.X2c)

All copy below is copied **verbatim** from `knowledge-base/marketing/audits/soleur-ai/2026-04-22-content-audit.md` §Rewrite Suggestions (R5, R6) and the content-plan row for P0.X2c. Implementation copies into `.njk` — no re-invention at work-phase.

### agents.njk (#2806, P0.N4 + P0.X2k)

**Frontmatter — use `seoTitle` + short `title` (matches homepage precedent at `index.njk:3`):**

```yaml
---
title: "65 AI Agents for Solo Founders"
seoTitle: "65 AI Agents for Solo Founders — Every Department | Soleur"
description: "AI agents for every business department -- engineering, marketing, legal, finance, operations, product, sales, and support. The full Soleur agent roster."
layout: base.njk
permalink: agents/
---
```

**Why both fields?** `base.njk:125` has a fallback chain:

```njk
{% if seoTitle %}{{ seoTitle }}{% elif title == site.name %}{{ site.name }} - {{ site.tagline }}{% else %}{{ title }} - {{ site.name }}{% endif %}
```

Without `seoTitle`, the full proposed string `"65 AI Agents for Solo Founders — Every Department | Soleur"` would hit the `{% else %}` branch and render as `"65 AI Agents for Solo Founders — Every Department | Soleur - Soleur"` (double brand suffix — broken). Using `seoTitle` + a short brand-free `title` avoids the double-suffix bug, provides a clean WebPage JSON-LD `name` via `base.njk:44` (`title | jsonLdSafe`), and matches the homepage convention (`index.njk:3` does the same split). The `og:title` (base.njk:8) and `twitter:title` (base.njk:19) templates use `{{ title }}` (not `seoTitle`), so they will append `" - Soleur"` to the short `title`, yielding `"65 AI Agents for Solo Founders - Soleur"` — ideal OG/Twitter title length (within 55 chars typical target).

**H1 (line 10):**

```html
<h1>Your AI Organization: {{ stats.agents }} Specialists Across {{ stats.departments }} Departments</h1>
```

Brand-guide compliant ("Your AI Organization" is in brand-guide §Example Phrases; concrete numbers prescribed by brand-guide "Use concrete numbers when available"). Uses `{{ stats.agents }}` / `{{ stats.departments }}` for live counts — matches rest of the page, avoids literal "65" drift.

**Quotable "What is an AI agent" definition — INSERT directly after `<h1>` closing tag and before the hero `<p>` (lines 10→11):**

The R6 copy is brand-voice-compliant and already defines the term without "copilot"/"assistant" per brand guide. It lives in the hero `<section class="page-hero">` block, which means placement is: new `<p class="hero-def">` between the existing `<h1>` and the existing `<p>` tagline. The existing `<p>` on line 11 remains untouched.

```html
<p class="hero-def">An AI agent is a specialist that handles a specific business function — code review, brand strategy, legal compliance, financial planning. Soleur agents share one knowledge base, so decisions in marketing flow through to legal and operations without re-briefing. Your expertise sets direction. The agents execute.</p>
```

Note: this paragraph is 2 sentences of definition + 2 short declarative sentences per brand guide voice. Total ~60 words — meets "~2 sentences" spec with brand-voice flourish, well within AEO extractability budget. If `.hero-def` class is not defined in `docs/css/style.css`, the `<p>` will fall back to base typography (still renders correctly). A CSS-class add is OUT OF SCOPE per "content-only" constraint; we reuse existing classes if needed. **Resolution rule:** before commit, grep `docs/css/style.css` for `.hero-def`. If absent, drop the class attribute (use `<p>` unadorned) — the paragraph still renders and is still in the hero block. Don't add new CSS.

**P0.X2g freshness attribute on hero count (NO hyperlink — modification from initial plan):**

Current hero `<p>` on line 11:

```html
<p>{{ stats.agents }} AI agents across {{ stats.departments }} business departments — from code review and architecture to marketing strategy, legal compliance, and financial planning.</p>
```

Proposed:

```html
<p><span data-last-verified="2026-04-22">{{ stats.agents }} AI agents</span> across {{ stats.departments }} business departments — from code review and architecture to marketing strategy, legal compliance, and financial planning.</p>
```

**Rationale for no-hyperlink on `/agents/`:** AEO audit P1 #3 prescribes hyperlinking count mentions to the canonical roster page. The canonical roster page for "AI agents" IS `/agents/` — so on the `/agents/` page itself, the hyperlink would be self-referential (bad UX: a link to the page you're already on). Options considered:

- Link to GitHub (`{{ site.github }}/tree/main/plugins/soleur/agents`): externally bounces the user off the landing page they just arrived on — bounce-rate risk. Rejected.
- Link to in-page anchor (e.g., `#engineering`): scrolls past the definition paragraph we're adding — defeats the R6 purpose. Rejected.
- No hyperlink, data-last-verified only: preserves the AEO freshness signal (the whole purpose of `data-last-verified`) without the self-link anti-pattern. **Chosen.**

The hyperlink-to-roster pattern DOES apply on `/` (homepage) and `/skills/` — see those sections below.

### vision.njk (#2804, P0.X2c — minimal "world's first" removal variant)

**Line 24 current:**

```html
Soleur is the world's first model-agnostic orchestration engine designed to turn a single founder into a billion-dollar enterprise. It provides the architectural "brain" that organizes fragmented AI models into a cohesive, goal-oriented workforce, allowing a human CEO to manage a "Swarm of Agents" instead of a headcount of employees.
```

**Line 24 proposed:**

```html
Soleur is one of the first model-agnostic orchestration engines designed to turn a single founder into a billion-dollar enterprise. It provides the architectural "brain" that organizes fragmented AI models into a cohesive, goal-oriented workforce, allowing a human CEO to manage a "Swarm of Agents" instead of a headcount of employees.
```

**Single-word change: "the world's first" → "one of the first".** Verbatim consistent with content plan P0.X2c prescription ("Replace 'world's first' with comparative-timeline or 'one of the first' framing") AND content plan §GEO/AEO Content-Level Requirements item 6 ("Avoid superlatives"; "prefer comparative timelines or 'one of the first'").

**Why not the fuller R9+R10 vision rewrite?** Issue #2804 is explicitly scoped to "remove 'world's first' superlative" — the TL;DR block (R9) and CaaS definition (R10) are separate content plan items (part of P0.X2c's broader scope but not in #2804's fix field). Folding them in would expand PR scope beyond the three issues. See Non-Goals.

### index.njk (#2805, P0.X2g — remove hero GitHub Stars tile + annotate surviving counts)

**Remove lines 49-54 (the fourth `<div class="landing-stat">` entirely):**

```html
      <div class="landing-stat">
        <div class="landing-stat-value">{% if githubStats.stars %}{{ githubStats.stars }}{% else %}&#x2605;{% endif %}</div>
        <div class="landing-stat-label">
          <a href="{{ site.github }}" rel="noopener noreferrer" target="_blank">GitHub Stars</a>
        </div>
      </div>
```

No replacement. Per P0.X2g "Don't invent new stats — only re-treat existing ones" and AEO audit P2 #5 ("Remove '6 GitHub Stars' (anti-authority vanity stat)"). The `landing-stats` strip now shows 3 stats: Departments, AI Agents, Skills. Brand-guide-compliant (concrete numbers without vanity stats).

**Modify lines 42-44 (AI Agents tile) — hyperlink + `data-last-verified`:**

Current:

```html
      <div class="landing-stat">
        <div class="landing-stat-value">{{ stats.agents }}</div>
        <div class="landing-stat-label">AI Agents</div>
      </div>
```

Proposed:

```html
      <div class="landing-stat">
        <div class="landing-stat-value"><a href="/agents/" data-last-verified="2026-04-22">{{ stats.agents }}</a></div>
        <div class="landing-stat-label"><a href="/agents/">AI Agents</a></div>
      </div>
```

**Modify lines 45-48 (Skills tile) — same treatment:**

Current:

```html
      <div class="landing-stat">
        <div class="landing-stat-value">{{ stats.skills }}</div>
        <div class="landing-stat-label">Skills</div>
      </div>
```

Proposed:

```html
      <div class="landing-stat">
        <div class="landing-stat-value"><a href="/skills/" data-last-verified="2026-04-22">{{ stats.skills }}</a></div>
        <div class="landing-stat-label"><a href="/skills/">Skills</a></div>
      </div>
```

The `Departments` tile (lines 37-40) stays untreated — it's a conceptual count, not a roster, so "live count" / "hyperlink to roster" doesn't apply (the concept is enumerated in the hero `<p>`).

**Required CSS addition (docs/css/style.css) — preserve accent-color styling through anchor wrap:**

`.landing-stat-value` is styled with `color: var(--color-accent)` and `font-family: var(--font-display)` at `docs/css/style.css:477-484`. Wrapping its text in `<a>` causes the anchor's default color (blue underline) to override the accent. Add immediately after the existing `.landing-stat-label` rule (around line 489):

```css
  .landing-stat-value a,
  .landing-stat-label a {
    color: inherit;
    text-decoration: none;
  }
  .landing-stat-value a:hover,
  .landing-stat-label a:hover {
    text-decoration: underline;
  }
```

**Why this is in scope despite "no layout restructuring":** This is a scoped **inherit-style rule**, not a new component or layout. It preserves the existing visual identity when the HTML gains hyperlinks. Without it, the stats strip visually regresses (tile values turn default-link blue). Comparable to the verbatim-preserve rule in cq-mutation-assertions-pin-exact-post-state — the visual POST-state must match the intent of the edit, and a style-inheriting anchor wrap is the minimal diff that achieves it. The rule adds 8 lines of CSS; the net diff is ~10 additions, zero existing rules changed.

**Mobile breakpoint already handled.** `docs/css/style.css:1107` has `.landing-stats { flex-direction: column; gap: var(--space-6); }` at the narrow breakpoint. Dropping from 4 to 3 tiles reflows correctly at mobile (3 stacked tiles vs 4) with no change.

### skills.njk (#2805 follow-through per P0.X2g) — CONFIRMED GO

**Structure confirmed via full-file read during deepen pass.** `docs/pages/skills.njk:8-13` has the identical hero pattern:

```html
<section class="page-hero">
  <div class="container">
    <h1>Agentic Engineering Skills</h1>
    <p>{{ stats.skills }} workflow skills that orchestrate agents, tools, and knowledge for complex multi-step tasks.</p>
  </div>
</section>
```

**Apply the same pattern as agents.njk (data-last-verified span, no self-referential hyperlink):**

Modify line 11:

```html
<p><span data-last-verified="2026-04-22">{{ stats.skills }} workflow skills</span> that orchestrate agents, tools, and knowledge for complex multi-step tasks.</p>
```

**No title/H1 change on `/skills/` in this PR.** The "Uncategorized" elimination is a separate content-plan item (P0.N5 — issue #2670, NOT in our three). The `/skills/` title tag rewrite (R8) is also a separate improvement item. This PR touches `/skills/` only for the P0.X2g freshness attribute per the direct mention in issue #2805's Fix field.

## Non-Goals / Out of Scope

| Item | Rationale | Tracking |
|---|---|---|
| Vision TL;DR block (R9) | Content-plan P0.X2c row covers both "world's first" removal AND TL;DR + CaaS definition. Issue #2804 scopes only the superlative. Folding in R9/R10 expands PR. | File as follow-up issue `[P1](content): /vision/ plain-language TL;DR + Company-as-a-Service definition` after this PR lands. Milestone: same as parent. Label: `domain/marketing`, `priority/p1-high`, `type/chore`. |
| Community page GitHub Stars | `community.njk:18-21` also renders `{{ githubStats.stars }}`. Audit P2 #5 names only hero. Community page is a different surface (explicit community-stats context, not a hero vanity-stat). | Record in PR body under "Not addressed" bullet. No follow-up issue required — community page is a legitimate surface for a contributor/community stat; removing it was not requested. |
| Title-tag standardization sweep across all 8 pages (P0.X2f) | Separate content-plan P0 item with its own scope. Not one of the three target issues. | Already tracked as separate ongoing P0 — next cycle. |
| Additional AEO hero tweaks (R1 homepage meta description, R2 secondary keyword line) | R1 and R2 are not in #2806/#2804/#2805 scope. | Cycle through next P0 PR. Existing issue #2808 ("Homepage meta description") already tracks R1. |
| CSS class addition (`.hero-def`) | "No new components, no layout restructuring" constraint. | Use bare `<p>` — inherits `.page-hero p` styles. |
| New visual components / layout structures (cards, grids, sections) | Scope constraint: content/copy only, no template restructuring. | N/A. Scoped inherit-color CSS rule for `.landing-stat-value a` IS included (see Files to Edit #5) as a visual-continuity fix, not a new component. |
| `data-last-verified` on every interior `{{ stats.agents }}` mention (FAQ answers, body prose) | AEO extractors key on hero/above-the-fold content. Saturating the page with `data-last-verified` dilutes the signal and adds maintenance burden. | Hero-only. Document in PR body. |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/docs/pages/agents.njk` frontmatter has BOTH `title: "65 AI Agents for Solo Founders"` AND `seoTitle: "65 AI Agents for Solo Founders — Every Department | Soleur"`. `description`, `layout`, `permalink` unchanged.
- [ ] `plugins/soleur/docs/pages/agents.njk` `<h1>` line reads exactly `<h1>Your AI Organization: {{ stats.agents }} Specialists Across {{ stats.departments }} Departments</h1>`.
- [ ] `plugins/soleur/docs/pages/agents.njk` contains a new `<p>` between `<h1>` and the existing hero tagline `<p>`, with the R6 "What is an AI agent" definition text (verbatim from content-audit.md R6). Class attribute: either `class="hero-def"` if the class exists in style.css, or bare `<p>` (no class) — decided by Phase 1 grep.
- [ ] `plugins/soleur/docs/pages/agents.njk` existing hero tagline `<p>` (line 11) now wraps `{{ stats.agents }} AI agents` in `<span data-last-verified="2026-04-22">…</span>` (NO hyperlink — self-referential to the current page).
- [ ] `plugins/soleur/docs/pages/vision.njk` line 24 uses "one of the first" instead of "the world's first". No other text changes on that line.
- [ ] `grep -rn "world's first\|world&rsquo;s first\|world&#39;s first" plugins/soleur/docs/` returns zero hits.
- [ ] `plugins/soleur/docs/index.njk` has exactly three `<div class="landing-stat">` blocks in the `landing-stats` section (not four). The GitHub Stars tile (previously lines 49-54) is removed.
- [ ] `plugins/soleur/docs/index.njk` AI Agents and Skills tiles wrap their values in `<a href="/agents/" data-last-verified="2026-04-22">` and `<a href="/skills/" data-last-verified="2026-04-22">` respectively. Both labels also hyperlink to the respective page.
- [ ] `plugins/soleur/docs/css/style.css` has new scoped rule `.landing-stat-value a, .landing-stat-label a { color: inherit; text-decoration: none; }` + `:hover { text-decoration: underline; }` added adjacent to the existing `.landing-stat-label` rule.
- [ ] `plugins/soleur/docs/pages/skills.njk` line 11 wraps `{{ stats.skills }} workflow skills` in `<span data-last-verified="2026-04-22">…</span>`.
- [ ] Eleventy build succeeds: `cd plugins/soleur/docs && npm run docs:build` exits 0.
- [ ] AEO/SEO validator passes on built output: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` exits 0.
- [ ] CSP validator passes on built output: `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site` exits 0.
- [ ] Built `_site/agents/index.html` contains `<title>65 AI Agents for Solo Founders — Every Department | Soleur</title>` exactly (NO trailing `- Soleur` suffix — verifies seoTitle took precedence over default chain).
- [ ] Built `_site/agents/index.html` does NOT contain the string `| Soleur - Soleur` (double-brand-suffix regression guard).
- [ ] Built `_site/agents/index.html` contains `<meta property="og:title" content="65 AI Agents for Solo Founders - Soleur"` (og:title uses `title`, appends `- Soleur`).
- [ ] Built `_site/agents/index.html` contains the new `<h1>Your AI Organization: …</h1>`.
- [ ] Built `_site/agents/index.html` contains the R6 "An AI agent is a specialist that handles a specific business function" definition string.
- [ ] Built `_site/vision/index.html` does NOT contain the string `world's first` or `world&rsquo;s first` or `world&#39;s first` (all encoding variants).
- [ ] Built `_site/index.html` does NOT contain the string `GitHub Stars` (this string is now only in `community.html`, which is the Non-Goal-documented location).
- [ ] Built `_site/index.html` contains `data-last-verified="2026-04-22"` at least twice (AI Agents tile value + Skills tile value).
- [ ] Built `_site/skills/index.html` contains `data-last-verified="2026-04-22"` at least once.
- [ ] Bun test suite passes: `bun test plugins/soleur/test/` — no drift from edits (jsonld-escaping, components, community-stats, github-stats, changelog-data tests should all be green).
- [ ] `markdownlint-cli2 --fix` run on any edited `.md` plan/spec files (no `.njk` markdownlint coverage — njk is templated HTML).
- [ ] PR body includes exactly three lines: `Closes #2806`, `Closes #2804`, `Closes #2805` (each on its own line, per rule `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] PR body includes a `## Changelog` section with semver `patch` (content-only; no new features or breaking changes).
- [ ] PR body includes a Net-impact table per PR #2486 pattern (3 closures, 0 new scope-outs).
- [ ] compound skill ran pre-commit per `wg-before-every-commit-run-compound-skill`.

### Post-merge (operator)

- [ ] Merged commit triggers Eleventy build in GitHub Pages deploy workflow; deploy succeeds.
- [ ] Live `https://soleur.ai/agents/` serves the new title + H1 + definition.
- [ ] Live `https://soleur.ai/vision/` no longer contains "world's first".
- [ ] Live `https://soleur.ai/` hero stats strip shows 3 tiles (Departments, Agents, Skills).
- [ ] `View Source` on live `/` shows `data-last-verified="2026-04-22"` on hero count anchors.

## Test Scenarios

No net-new automated tests — this is a content refactor on templated HTML. Validation is:

1. **Static build drift guard (manual, pre-commit):**

   ```bash
   cd plugins/soleur/docs && npm run docs:build
   cd ../../../  # back to repo root for unified _site path
   # --- #2804 vision/ superlative removal (all encoding variants) ---
   grep -c "world's first\|world&rsquo;s first\|world&#39;s first" _site/vision/index.html  # expect 0
   grep -c "one of the first" _site/vision/index.html  # expect ≥1
   # --- #2805 homepage hero vanity stat removal ---
   grep -c "GitHub Stars" _site/index.html  # expect 0
   grep -c 'class="landing-stat"' _site/index.html  # expect 3 (Departments, Agents, Skills)
   grep -c 'data-last-verified="2026-04-22"' _site/index.html  # expect ≥2 (agents + skills tiles)
   # --- #2806 agents/ title + H1 + definition + freshness ---
   grep -c '<title>65 AI Agents for Solo Founders — Every Department | Soleur</title>' _site/agents/index.html  # expect 1 exact
   grep -c "| Soleur - Soleur" _site/agents/index.html  # expect 0 (double-suffix regression guard)
   grep -c "Your AI Organization" _site/agents/index.html  # expect ≥1
   grep -c "An AI agent is a specialist" _site/agents/index.html  # expect ≥1
   grep -c 'data-last-verified="2026-04-22"' _site/agents/index.html  # expect ≥1 (hero span)
   grep -c 'data-last-verified="2026-04-22"' _site/skills/index.html  # expect ≥1 (hero span)
   # --- Sanity: old strings purged ---
   grep -c "Soleur AI Agents" _site/agents/index.html  # expect 0 (old H1 retired)
   # --- JSON-LD integrity (existing drift guard, base.njk:32) ---
   grep -c '"SoftwareApplication"' _site/index.html  # expect ≥1 (homepage schema preserved)
   grep -c '"FAQPage"' _site/agents/index.html _site/vision/index.html _site/index.html  # expect ≥3 (one per page)
   ```

   Any expected count mismatch fails the drift guard — do NOT commit.

2. **AEO/SEO validator (CI-style):**

   ```bash
   bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site
   ```

   Expected: `All SEO checks passed.` + exit 0. Any failure blocks merge.

3. **CSP validator (defense-in-depth):**

   ```bash
   bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site
   ```

   Expected: exit 0. `data-last-verified` is a data-* attribute — does NOT affect CSP. Hyperlink additions don't introduce inline event handlers. Should pass unchanged.

4. **Visual smoke (optional, only if a reviewer asks):** Eleventy dev server (`npm run docs:dev`) — verify `/agents/`, `/vision/`, `/` render without layout breakage. Hero definitions flow correctly; 3-tile stats strip centers correctly if CSS grid/flex uses implicit track count (likely — `landing-stats` almost certainly uses `auto-fit` or `repeat()`). If grid count is hardcoded to 4, file a CSS follow-up and revisit.

## Implementation Phases

### Phase 1 — Pre-flight checks

1. `grep -n "hero-def\b" plugins/soleur/docs/css/style.css` — confirm whether class exists. **Expected result: no match.** If no match, omit `class="hero-def"` from the new `<p>` definition in agents.njk (use bare `<p>` — inherits `.page-hero p` styles). If match (unexpected), include the class.
2. `grep -rn "Soleur AI Agents\|world's first\|GitHub Stars" plugins/soleur/` — final guard-grep before editing. **Expected result (verified deepen-pass): 2 hits on `agents.njk` (title + H1), 1 hit on `vision.njk` (line 24), 4 hits on `index.njk`/`community.njk` for GitHub Stars.** Any additional hit means scope has grown — investigate before proceeding.
3. Deepen pass already confirmed `.landing-stats` uses flex (not grid), `skills.njk` hero structure parallels agents.njk, and no test asserts pre-edit strings. No further pre-flight needed.

### Phase 2 — Edits (in order, lowest blast-radius first, smallest commit last)

1. **vision.njk line 24** — single-word superlative swap (`the world's first` → `one of the first`). 1-line edit. Smallest blast radius.
2. **index.njk lines 49-54** — remove the 4th `<div class="landing-stat">` block (GitHub Stars tile). 6-line delete.
3. **index.njk lines 42-48** — wrap AI Agents and Skills tile values in `<a>` with href + `data-last-verified`. Wrap labels in `<a>` too (no data-last-verified on labels). ~8 lines changed.
4. **style.css line 489** — insert scoped `.landing-stat-value a, .landing-stat-label a` rule (inherit color + no underline + hover underline) immediately after `.landing-stat-label` closing brace. 8 new lines.
5. **skills.njk line 11** — wrap `{{ stats.skills }} workflow skills` in `<span data-last-verified="2026-04-22">…</span>`. 1-line edit.
6. **agents.njk** (largest edit, most surface area, last):
   - Frontmatter: split `title:` and add `seoTitle:` (2-line change).
   - Line 10: H1 rewrite.
   - Insert new `<p>` definition between H1 and existing tagline (1 new line).
   - Line 11 (now 12 post-insert): wrap `{{ stats.agents }} AI agents` in `<span data-last-verified="2026-04-22">`.

Rationale for order: each step is independently revertable. Smallest/safest first lets us commit a partial drain if any later step fails a validator (though this is belt-and-suspenders; all six should land as one commit).

### Phase 3 — Build + validate

1. `cd plugins/soleur/docs && npm run docs:build`.
2. `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`.
3. `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site`.
4. Drift-guard `grep` commands from Test Scenarios §1 — all expected counts met.

### Phase 4 — Commit + PR

1. `/soleur:compound` pre-commit.
2. Single commit: `refactor(marketing): drain /agents/, /vision/, / AEO+content fixes (#2806 #2804 #2805)`.
3. `/ship` to draft PR with `Closes` lines in body and `semver:patch` label.

## Risks

| Risk | Likelihood | Impact | Mitigation / Status |
|---|---|---|---|
| ~~CSS `landing-stats` hardcodes 4-column grid template~~ | — | — | **RESOLVED (deepen pass):** `.landing-stats` uses `display: flex; justify-content: space-around` (style.css:465-473). 3-tile layout reflows correctly. Mobile breakpoint already handles column-stacking (line 1107). No CSS grid fix needed. |
| `.hero-def` CSS class doesn't exist → typography inconsistent | Low (expected absent) | Cosmetic only | Phase 1 greps for `.hero-def` in style.css (expected absent). Use bare `<p>` — inherits `.page-hero p` styles (style.css:122: `max-width: 600px; color: var(--color-text-secondary)`) identical to existing tagline. Visual consistency guaranteed. |
| Anchor-wrapped stat values lose accent color | **Medium-high (new, deepen)** | Visual regression: hero tile values render default-link blue instead of accent | **Fixed in plan:** scoped CSS `.landing-stat-value a, .landing-stat-label a { color: inherit; text-decoration: none; }` + `:hover { text-decoration: underline; }`. 8 net-new CSS lines, zero rules modified. |
| Double brand-suffix on `<title>` via base.njk fallback chain | **Medium (new, deepen)** | Broken SEO: `<title>… \| Soleur - Soleur</title>` | **Fixed in plan:** frontmatter splits into `seoTitle` (full brand) + short `title` (no brand). Drift guard in Test Scenarios explicitly asserts zero hits on `"| Soleur - Soleur"`. |
| Self-referential hyperlink on `/agents/` hero count | Fixed in deepen | UX: user clicks count → reloads current page | **Fixed in plan:** `/agents/` hero uses `<span data-last-verified>` (no hyperlink). Hyperlink-to-roster pattern on `/` homepage only. |
| ~~Existing tests in `plugins/soleur/test/` assert the old agents title/H1~~ | — | — | **RESOLVED (deepen pass):** `grep -rn "Soleur AI Agents\|world's first\|GitHub Stars" plugins/soleur/test/` returns zero hits across all `.test.*` files. No drift guard test asserts the pre-edit strings. |
| Content-plan P0.X2c's broader "CaaS definition + TL;DR" components lead reviewers to expect them here | Medium | Review comment noise asking why R9/R10 not folded in | Pre-empt in PR body: "Scoped strictly to #2804 (superlative removal). R9/R10 tracked as follow-up issue filed in same commit." |
| `data-last-verified` HTML-validates but some strict linters flag custom data-* attributes | Very low | Lint-warning noise | `data-*` prefix is HTML5-valid by WHATWG spec. No mitigation needed. Validator scripts don't lint HTML attributes. |
| Removing hero GitHub Stars causes perception of lost social proof | Low | Soft/brand | Brand-guide deprioritizes vanity stats (line 359). AEO audit flags "6 GitHub Stars" as anti-authority (line 107). Signal improves. Community page preserves the stat in its community-focused context (out-of-scope per #2805). |
| ~~Live rebuild picks up stale `githubStats` cache during CI~~ | — | — | **N/A (deepen pass):** GitHub-stats hero tile removed. `stats.agents` / `stats.skills` come from `_data/stats.js` filesystem walk, not API. Hero has no network dependency post-PR. Resilience improvement. |
| AEO/SEO validator (`validate-seo.sh`) changes between worktree and main | Very low | Script could fail after merge | Script read from worktree; `git log main -- plugins/soleur/skills/seo-aeo/scripts/` shows no relevant changes last 2 weeks. |
| `jsonLdSafe` filter regression on new title with pipe or em dash | Very low | JSON-LD parse failure at build | `jsonLdSafe` (enforced since #2609 per base.njk:32) escapes JSON special chars. `\|` and `—` are not JSON special. Existing `plugins/soleur/test/jsonld-escaping.test.ts` covers this regression class. |
| `seoTitle` override affects `og:title` unexpectedly | Very low | Mis-sized social preview | og:title uses `{{ title }}` (not `seoTitle`) per base.njk:8. Short title `"65 AI Agents for Solo Founders - Soleur"` ≈ 42 chars, well under 70-char OG truncation threshold. Verified via direct template read. |
| Hero `<p><span data-last-verified>` breaks AEO extraction | Very low | Reduced LLM citation | `data-*` attributes don't affect text extraction. Crawlers see `<span>65 AI agents</span>` as inline text. No regression. |
| New title change invalidates existing backlinks' display text | Very low | Cosmetic on external pages | Backlinks reference URL, not title. SERPs update over 1-2 weeks. Expected — that IS the PR's purpose. |

## Domain Review

**Domains relevant:** marketing, product (advisory)

### Marketing (CMO)

**Status:** reviewed (carry-forward)
**Assessment:** The 2026-04-22 weekly growth audit was produced by `seo-aeo-analyst` under CMO ownership (see `knowledge-base/marketing/audits/soleur-ai/2026-04-22-content-audit.md` frontmatter: `owner: CMO`). Content-plan IDs P0.N4 / P0.X2k / P0.X2c / P0.X2g are the CMO-endorsed remediation path. All rewrite copy in this plan is copy-pasted from content-audit.md R5/R6/R9 — no fresh copywriter invocation needed because the copywriter-equivalent output is the audit's Rewrite Suggestions section. This matches the precedent in `2026-04-21-refactor-marketing-site-aeo-content-drain-plan.md` §Domain Review ("the audit + content-plan pipeline IS the CMO sign-off").

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (content-only edits on existing pages; no new flows, no new components, no new interactive surfaces)
**Skipped specialists:** ux-design-lead (N/A — no new UI surface), copywriter (N/A — verbatim from audit R5/R6)
**Pencil available:** N/A

#### Findings

- No new user-facing surfaces; no new flows; no new interactive elements. The only UI change is removal of one stats tile (3 instead of 4 in the hero strip) and addition of hyperlinks to existing stat numbers. Both are reversible single-commit changes.
- The hero count tiles becoming hyperlinks is a usability improvement (now clickable entry points into `/agents/` and `/skills/`), not a regression.
- `data-last-verified` is an invisible HTML attribute — no visible UI change from that.
- Brand-voice compliance confirmed: "Your AI Organization" is in brand-guide Example Phrases (line 146 of brand-guide.md). "one of the first" aligns with content-plan §GEO/AEO Content-Level Requirements item 6 ("Avoid superlatives; prefer comparative timelines or 'one of the first'").

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned 0 matches across `agents.njk`, `vision.njk`, `index.njk`, and `docs/pages`. No existing scope-outs touch the files this plan modifies. Plan files no fresh scope-outs.

## Research Insights

### From 2026-04-22-aeo-audit.md

- **Authority rubric penalty for superlatives:** "AI engines penalize unsupported first/best/only claims" (line 87). "One of the first" removes the penalty without diluting ambition.
- **`data-last-verified` freshness attribute:** explicitly prescribed at P1 #3 (line 100: `add data-last-verified="2026-04-22" attribute`). +1 point AEO expected.
- **"6 GitHub Stars":** P2 #5 (line 107) — "actively damages authority claims for an ambitious brand".
- **AEO scoring delta:** site is at 80/100 (B), +2 vs 2026-04-21 baseline. Removing "world's first" is modeled at +2 points. Removing "6 GitHub Stars" is a narrative fix (counter-signal elimination).

### From 2026-04-22-content-audit.md

- Agents page is #5 §Critical (line 92): "A user searching 'AI agents for solo founders list' will not find this page ranked well. Title should carry 1-2 extra modifiers."
- R5 and R6 copy is verbatim usable (brand-voice compliant, declarative, no hedging, concrete numbers). See §Exact Copy above.

### From 2026-04-22-content-plan.md §GEO/AEO Content-Level Requirements (line 209)

Every edit in this cycle must:

1. Open with quotable 1-2 sentence definition in first 100 words — ✅ R6 insertion on `/agents/`.
2. Include inline hyperlinked citations for statistical claims — ✅ hero count hyperlinks on `/` and `/agents/`.
3. Jean Deruelle byline — N/A (landing pages, not blog entries).
4. FAQPage JSON-LD — unchanged (existing FAQPages preserved).
5. Internal links to pillar + sibling cluster + `/pricing/` — existing structure unchanged; our edits add more internal links (hero count → `/agents/`, `/skills/`).
6. Avoid superlatives — ✅ "world's first" → "one of the first".
7. Named-entity anchors — unchanged (Amodei, Karpathy, Evans, etc. preserved).

### CLI-verification gate

This plan prescribes ONE CLI invocation destined to land in user-facing docs: **none**. The plan prescribes npm scripts (`npm run docs:build`, `npm run docs:dev`) and bash scripts (`validate-seo.sh`, `validate-csp.sh`) — these are tooling used by the work-phase, not copy embedded in `.njk`/README. No fabricated tokens risk. The `.njk` copy additions contain no CLI invocations.

### Brand voice anchors

- "Your AI Organization" — brand-guide.md Example Phrases (verified)
- "concrete numbers" — brand-guide.md line 77 (verified)
- "no superlatives; no 'revolutionary', 'game-changing', 'best-in-class'" — brand-guide.md line 359 (verified)
- "declarative, concrete, no hedging" — brand-guide.md line 238 (verified)

## Changelog (for PR body)

```markdown
## Changelog

### Marketing Site

- **`/agents/`:** Keyword-dense title + H1 rewrite. Title now carries "65 AI Agents for Solo Founders — Every Department | Soleur". H1 is "Your AI Organization: N Specialists Across M Departments" using live counts. Added quotable "What is an AI agent" hero definition for AEO extractability. Hero count now hyperlinks to the GitHub agents directory with data-last-verified. Closes #2806.
- **`/vision/`:** Removed "world's first model-agnostic orchestration engine" superlative; replaced with "one of the first" per content plan P0.X2c. AEO Authority-rubric gain. Closes #2804.
- **`/` (homepage hero):** Removed vanity "6 GitHub Stars" stat tile from hero strip; hero now shows Departments / AI Agents / Skills only. AI Agents and Skills tiles now hyperlink to `/agents/` and `/skills/` respectively, carrying data-last-verified="2026-04-22" for AI-engine freshness signal. Closes #2805.
- **`/skills/`:** Hero count wrapped in `<span data-last-verified="2026-04-22">` — matches `/agents/` treatment. Part of #2805 follow-through per content plan P0.X2g.
- **CSS:** Added scoped `.landing-stat-value a, .landing-stat-label a` color-inherit + no-underline rules so that anchor-wrapped hero stats preserve their accent-color visual identity. 8-line addition to `docs/css/style.css`, no existing rules changed.

Semver: patch. Content-only; no API, flow, or dependency changes.
```

## Net Impact Table (for PR body, PR #2486 pattern)

| PR | Closes | Files |
|---|---|---|
| **This PR** | **#2806, #2804, #2805** | **5** (agents.njk, vision.njk, index.njk, skills.njk, style.css) |

Net: 3 closures, 0 new scope-outs (1 deferral follow-up issue filed for vision TL;DR R9/R10 but that issue was PLANNED to exist per content plan P0.X2c's broader scope — it was never on the 2026-04-22 audit's P1 tracking table as a separate issue, so filing it is net-zero on the tracked backlog).

## AI-Generated Code Review Note

This plan was generated by the `soleur:plan` skill. No AI-generated code — this is a refactor of existing templated copy where every replacement string is copy-pasted verbatim from the 2026-04-22 content audit's Rewrite Suggestions section (R5, R6, R9). Reviewers: please verify strings match source audit files; do not re-generate copy.

---

**Total P0 effort for this PR:** ~50 minutes implementation + ~15 minutes validation + ~15 minutes review/ship. Within the single-hour target for a 3-issue drain PR.

---
title: "feat(web): homepage demo of one brief fanning out to departments"
date: 2026-10-06
slug: feat-homepage-fanout-demo
branch: feat-homepage-demo-9577
issue: 9577
closes: 9577
type: feat
priority: p2-medium
domain: marketing
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat(web): homepage demo of one brief fanning out to departments

## Overview

Add one proof section to the marketing homepage (`plugins/soleur/docs/index.njk`): a labelled, static illustration of a single fictional founder brief reaching four departments, each with a text status, so the "human-in-the-loop" claim that the page asserts twice is shown. Rows come from a committed data file that fails the Eleventy build on bad input, one bun drift test pins keys, rendered text and copy guardrails, and the section carries no button, animation, hosted wording or analytics event. It ships after the positioning section and before the quote block, and the "Your AI Organization" section gains `id="departments"` as the link target.

**Plan-gate decisions (operator, 2026-10-06, applied below):** Finance/Engineering copy **Option A**; simplified test weight; ship now with an attribution rule pre-registered on #9588; and all four refinements (label rename, visible "Illustrative example" tag, flat state-glyph chips with Stopped not solid white, no connector on mobile).

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #9577, #9588 and #9620 are OPEN; #9584 is MERGED (2026-10-06); the wireframe `.pen` (73 KB) and screenshots 13–16 exist on disk; `STATUS_LABELS` exists in `apps/web-platform/lib/types.ts` (the repo-research subagent put the status union at "line ~220"; it is at line 634 and the label map at 656, so its other line numbers were re-verified before use). Stale: the wireframe PNGs 13–15 show the **old H2 and Legal line**, and after the plan-gate decisions also the old label, the Finance/Engineering rows and the solid Stopped chip; the spec plus this plan hold the final copy and treatment. No ADR concerns marketing-page sections, so the ADR-corpus check found nothing to re-scope.

### Property List and Cut List (Phase 0.6b)

Properties:

1. A visitor sees what the founder still decides, through a worked fictional example.
2. The example cannot be read as a live product surface, a customer result or a guarantee.
3. The section's states cannot drift from the product's state vocabulary or from the department set.
4. The section cannot move the hero CTA test (no button, no event) and its ship date is recorded.
5. A bad data row cannot ship silently.

| Mechanism in the ask or brainstorm | Property | Verdict |
|---|---|---|
| Captured real self-hosted run | 1 | **Cut** (rejected in the brainstorm: terminal register, developer-only) |
| Animation / reduced-motion stagger | 1 | **Cut** from v1 (YAGNI; reversible) |
| Demo-specific Plausible event | 4 | **Cut** (login-gated goal; confounds the hero test) |
| JSON-LD for the section | none | **Cut** (spec non-goal; FAQ parity is a drift surface) |
| Button or CTA inside the section | none | **Cut** (hero events must stay readable until 2026-11-03) |
| `gateSource` provenance field on the stopped row | 2 | **Cut** (plan-review: three reviewers; "A test did not pass" needs no provenance field) |
| Mutation-testing the validator with synthetic row sets | 5 | **Cut** (plan-review: the section is authored once; test the built page, not the test) |
| Data file + build-time throw + one bun test | 3, 5 | **Kept** |
| Parsing `lib/types.ts` text for the vocabulary | 3 | **Kept** — a committed copy would itself drift; a text read crosses no import boundary |

### Repo facts (verified, content anchors)

- Section order in `index.njk`: hero → stats strip → `<!-- Problem Section -->` ("This Is the Way", the positioning section, `landing-section`) → `<section class="landing-quote">` → `<!-- Features Section -->` ("Your AI Organization", no `id` today).
- Data modules are ESM `export default function () {…}`. Eleventy unwraps a data module's default export **only when it is the sole export**. `agents.js` is synchronous, returns `{ domains, departmentList }` (each domain has `key`, `name`), reads files relative to `__dirname`, and is already imported from bun by `docs-agents-data.test.ts`.
- The critical-CSS check (`plugins/soleur/docs/scripts/check-critical-css-coverage.mjs`) inspects only classes whose prefix is in `ABOVE_FOLD_PREFIXES`; `fanout-*` is not matched, and the existing `landing-section`, `landing-section-inner`, `section-label`, `section-title` are already covered and may be reused.
- The header is fixed (`--header-h: 3.5rem`); `.category-section` already uses `scroll-margin-top: calc(var(--header-h) + var(--space-4))`.
- `html { scroll-behavior: smooth }` is set in `style.css` and in the inline block (`@layer base`, `base.njk`). The top-level `@media (prefers-reduced-motion: reduce)` block (`style.css`) only shortens animation/transition durations, so it does not disable smooth scrolling; the skip link already smooth-scrolls, so a fix there is site-wide.
- The #9579 hosted-claims guards in `plugins/soleur/test/seo-aeo-drift-guard.test.ts` are sentence-local on hosted wording (`HOSTED_RE`) and floor hosted sentences per page (`index.html` ≥ 4); a section with no hosted wording neither trips nor reduces them. `plugins/soleur/test/lib/visible-text.ts` exports `tagsOf`, `decodeEntities`, `visibleText`, `sentencesOf` and `plainText`.
- Homepage analytics: only `plausible-event-name=Hero+Self-host+Click` on the hero button; the waitlist form fires a script-level event. The new section adds neither.
- The screenshot gate (`plugins/soleur/docs/scripts/screenshot-gate.mjs`, run by `ci.yml`) has a 320 px pass and an inline-CSS-only pass that asserts no horizontal overflow.
- Real product labels: `STATUS_LABELS` is `waiting_for_user: "Needs your decision"`, `active: "Executing"`, `completed: "Completed"`, `failed: "Needs attention"`. The demo's words ("Done", "Stopped", "Waiting on you") are deliberately illustrative and map at key level only.

### Institutional learnings applied

- `2026-04-27-critical-css-fouc-prevention-via-static-and-playwright-gates.md`, `2026-04-27-hand-extracted-critical-css-misses-globally-rendered-selectors.md`: check the narrow render, not only the build.
- `2026-05-22-ci-parity-test-docs-arrays-are-themselves-a-drift-surface.md`: read the rendered homepage and fail on an empty extraction; no hard-coded page list.
- `2026-03-06-blog-citation-verification-before-publish.md`: no naked numbers; the section carries no counts or durations.
- The #9584 session: guards were added RED first.

### Open Code-Review Overlap

**None.** The open `code-review` issues (87 at query time) were searched for each planned path (`plugins/soleur/docs/index.njk`, `plugins/soleur/docs/css/style.css`, `plugins/soleur/docs/_data`, `plugins/soleur/test/seo-aeo-drift-guard.test.ts`, `knowledge-base/marketing/brand-guide.md`); no issue body names any of them.

### ADR and C4 (Phase 2.10)

No architectural decision: a static marketing section. `model.c4` does not model the docs site as a container (it appears only as the hosting role in the `github` and `cloudflare` descriptions), so no `.c4` edit; the unchanged `c4-count-parity` suite proves it. The build-time throw is effectively one more deploy-time guard (ADR-194 lists the docs-deploy gates); a line in the PR body is enough.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality | Plan response |
|---|---|---|
| TR3: status keys exist in the product's vocabulary (open: parse `lib/types.ts` vs a committed file) | `STATUS_LABELS` is an exported record | The bun test parses its keys as text (at least four found; every key the data file uses is among them); the build checks a local closed constant, because the build must not depend on `apps/` |
| FR1a: label `HOW A BRIEF FANS OUT` | "Fans out" implies parallel dispatch; self-hosted phases run sequentially (CMO) | Operator-approved change at the plan gate: label "How a brief reaches the departments" (CSS uppercases it); H2 unchanged |
| FR1a: Finance **Stopped** "margin check did not pass"; Engineering **Waiting on you** | No margin gate exists; the line implies a pre-set bar (CPO, CMO) | Operator-approved **Option A**: Engineering is Stopped, Finance is Waiting on you (copy below); spec amended |
| FR1: "a list of four department rows" | Safari/VoiceOver drops list semantics from `list-style: none`; no `role="list"` precedent on the homepage | `<ul role="list">` with `<li>` rows (never `role="list"` on the `<figure>`) |
| TR1: avoid `landing-*` / `section-*` prefixes for new classes | Existing classes are covered by the critical block | Reuse them for the frame and label; every NEW class is `fanout-*` |
| Wireframe screenshots 13–15 | Show superseded copy and, after the gate, superseded chip/connector treatment | Annotate the spec; `.pen` is not redrawn |

## Approved copy (spec FR1a as amended by the plan-gate decisions)

> **Superseded 2026-10-06 (CLO review of the built text, #9577):** the wording below is the pre-CLO copy. The company name in the brief card, the H2, the Legal and Marketing lines, caption line 1 and caption line 2, and the figure name were all amended; the authority is the "FR1a/FR2 amendment (CLO review)" paragraph in `knowledge-base/project/specs/archive/20261006-205404-feat-homepage-demo-9577/spec.md` and the shipped `plugins/soleur/docs/_data/fanoutDemo.js`, pinned verbatim by `plugins/soleur/test/fanout-demo-drift.test.ts`. Do not paste from this block.

Label `How a brief reaches the departments` (CSS-uppercased). Visible tag `Illustrative example · sample data`. H2 `One brief reaches the departments it concerns. You keep the final say.` Brief card eyebrow `Founder brief`, text `Fernlight is adding shared reminders. Launch it to current customers as a paid add-on.` Rows (department order unchanged):

| Department | Status | Line |
|---|---|---|
| Legal | Done | Draft terms and privacy notice changes ready for your review. |
| Marketing | Done | Launch post and customer email drafted. |
| Finance | Waiting on you | Needs your answer: set the add-on price from the sample cost figures, or hold it until costs are clearer? |
| Engineering | Stopped | Reminders change held back. A test did not pass. You decide what happens next. |

Caption (two lines, adjacent): `Illustrative example with sample data. Not a live run or a customer result.` / `Soleur pauses for your approval; it does not guarantee any check will pass.` Link `See every department below`. No numerals anywhere in the section.

## Decisions this plan makes

1. **Validation in two places, one validator.** `plugins/soleur/lib/fanout-validate.js` holds a pure `validateFanout(rows, departmentKeys, statusKeys)`. `_data/fanoutDemo.js` imports it and **throws at Eleventy build time** (error text names the row and key) on a row count other than four, a department key absent from `agents.js`, a status key outside a local closed constant (`completed`, `failed`, `waiting_for_user`), a label that does not match its key, or a missing field. `_data/fanoutDemo.js` stays **default-export-only** (a second named export would make Eleventy hand the template the export object, skip the function and its throw, and render an empty section on a green build). The build must not read `apps/web-platform/lib/types.ts`; the bun test asserts the local constant is a subset of the `STATUS_LABELS` keys parsed from it.
2. **Explicit status-to-label table.** `{ completed: "Done", failed: "Stopped", waiting_for_user: "Waiting on you" }`, validated per row. `failed` is the nearest product key to "stopped at a gate" but its product label is "Needs attention"; a data-file comment records the mapping as deliberately illustrative at key level.
3. **Anchor ownership.** `id="departments"` goes on the "Your AI Organization" `<section>` in the same commit as the link; a test asserts exactly one such id in the built homepage and that the link's `href` resolves to it; `style.css` gives it `scroll-margin-top: calc(var(--header-h) + var(--space-4))`.
4. **Disclosure placement.** A visible `Illustrative example · sample data` tag at the top of the figure (so a sighted visitor reads it before the chips), the figure's accessible name starting "Illustrative example:", and the two full disclosure lines in the `<figcaption>`, adjacent.
5. **Labels stay illustrative** (matching the hosted labels would make the section read as the waitlist-only Command Center).
6. **Motion.** Add `html { scroll-behavior: auto }` inside the existing top-level, unlayered `prefers-reduced-motion: reduce` block in `style.css`. It is a site-wide change (the skip link already smooth-scrolls) and is stated as such; a bun test asserts the rule sits in that block, and Phase 3.3 confirms the computed value.
7. **Hero-test confound: ship, pre-register.** No event, no button, below the fold. **Before merge**, comment the attribution rule on #9588: the demo is a candidate cause; the 2026-11-03 review compares hero click and waitlist rate in before/after windows around the ship date; the window is annotated, not restarted. A pre-merge line in the hero-CTA test note in `knowledge-base/marketing/brand-guide.md` records the bundled change and says the demo is an illustration, not a hosted-product depiction, until #9620 is decided. The ship date itself is a comment on #9588 after deploy.
8. **Row semantics.** Each row reads "Department: Status. Line." to a screen reader (visually hidden colon between name and chip); the connector is CSS-only and `aria-hidden`; chips keep a visible border and a state glyph (`aria-hidden`) so states survive forced-colors mode.
9. **Row interaction.** Rows and chips are not focusable and have no hover or pointer styling; the chip must not resemble the gold hero button.
10. **Link.** Underlined with an `aria-hidden` ↓ arrow, `min-height: 44px`, visible focus ring (gold on dark, ≥ 3:1).

### Design deviations from the approved wireframe (operator-approved at the plan gate)

Phase 3's visual check must not flag these as regressions: (a) the visible "Illustrative example · sample data" tag at the top of the figure; (b) flat, same-shape outline chips with leading state glyphs, **Done** receding (muted, still 4.5:1), **Stopped not a solid white fill**, and a 2 px gold left border on the two founder-action rows (Waiting on you, Stopped); the brief card keeps a neutral border with a gold label only; (c) the connector is drawn desktop-only with per-row pseudo-elements aligned to each row's midpoint and is **dropped below 768 px**; (d) the name-and-chip row wraps by content (`flex-wrap`), not by a hard 320 px breakpoint; (e) the copy and label above.

## Design

### Data file `plugins/soleur/docs/_data/fanoutDemo.js`

`export default function () { … }` returning the label, tag, H2, brief eyebrow and text, link text, the two disclosure lines and four rows `{ department, status, line }`, where `department` is a key in `agents.js` (the module imports that data function and resolves the display name, so a rename cannot orphan a row) and `status` is one of the three keys. A comment records the deliberate label/key mapping.

### Markup (`index.njk`, between the positioning section and `<section class="landing-quote">`)

A `landing-section` frame (existing classes) with the label and one H2, a `<figure class="fanout-figure">` containing the visible tag, the brief card, a `<ul role="list">` of four `<li>` rows (department name, hidden colon, glyph + status chip, line) and a `<figcaption>` with the two disclosure lines, then the single anchor link. Every new class is `fanout-*`. No `<button>`, `<form>`, `<script>`, `plausible` class, `{{ stats.* }}` count or numeral in the section.

### Styles (`style.css` only)

Frame, tag, brief card, desktop-only connector, rows, chips, founder-action row border, content-driven wrap, `scroll-margin-top` on `#departments`, a `@media (forced-colors: active)` rule giving chips `border: 1px solid CanvasText`, print rules (`break-inside: avoid`, readable ink), and the reduced-motion scroll fix. Caption and secondary text use `--color-text-secondary` (4.9:1, ≥ 14 px); `--color-text-tertiary` is never used in the section.

## Implementation Phases

Test-first (`cq-write-failing-tests-before`): Phase 1 is RED, Phase 2 turns it GREEN.

### Phase 0 — Preconditions

- 0.1 `git fetch origin main`; re-confirm the section order in `index.njk` and `ABOVE_FOLD_PREFIXES` on `origin/main`.
- 0.2 The copy decision is recorded above (Option A); put it in the PR body.

### Phase 1 — Failing drift test (RED)

- 1.1 Create `plugins/soleur/test/fanout-demo-drift.test.ts`: builds the site into a temp directory with `SOLEUR_DOCS_OFFLINE=1` and a 30 s hook timeout (the `seo-aeo-drift-guard.test.ts` pattern, so parallel suites do not race on `_site`), reuses `plugins/soleur/test/lib/visible-text.ts` for extraction, imports the **default export** of `_data/fanoutDemo.js` and calls it, and parses the `STATUS_LABELS` keys from `apps/web-platform/lib/types.ts` as text. Assertions are the flat list in the Guard Contract and Acceptance Criteria.
- 1.2 Fixtures are in-memory and synthesized (`cq-test-fixtures-synthesized-only`): a few bad row sets for the validator's throw (unknown status key, mismatched label, five rows, unknown department) and a `types.ts` text variant with no `STATUS_LABELS`.
- 1.3 Run the suite; record that each case is RED for the right reason.

### Phase 2 — Build the section (GREEN)

- 2.1 Create `plugins/soleur/lib/fanout-validate.js` and `_data/fanoutDemo.js` with the approved copy.
- 2.2 Edit `index.njk`: the section and `id="departments"`.
- 2.3 Edit `style.css`: section styles, `scroll-margin-top`, forced-colors, print, reduced-motion fix.
- 2.4 Run `npm run docs:build`, the new suite, `check-critical-css-coverage.mjs`, and `seo-aeo-drift-guard.test.ts`, `marketing-content-drift.test.ts`, `jsonld-escaping.test.ts`.

### Phase 3 — Visual and accessibility verification

- 3.1 Run `screenshot-gate.mjs` (including the inline-CSS-only 320 px pass, where the unstyled section must not overflow) and capture 1440, 390, 375, 360 and 320 renders; compare with wireframes 13–15 for layout, excluding the approved deviations.
- 3.2 Check the accessibility tree reads "Department: Status. Line." at 1440 and 320, the figure's accessible name starts "Illustrative example", chips stay distinguishable in forced-colors mode, and the Done chip text is ≥ 4.5:1.
- 3.3 Click the link: the section heading lands below the fixed header; under reduced motion the jump is instant (computed `scroll-behavior`); print-preview the section; confirm no hover/pointer styling on rows or chips.

### Phase 4 — Review gates and pre-merge records

- 4.1 CLO review of the **built** text (spec acceptance criterion), recorded as a verdict.
- 4.2 Amend the spec: Option A copy, the new label, the approved design deviations, and that wireframe PNGs 13–15 are superseded.
- 4.3 Add the pre-merge bundled-change line to the hero-CTA test note in `knowledge-base/marketing/brand-guide.md`.
- 4.4 Comment the pre-registered attribution rule on #9588.
- 4.5 `soleur:qa` browser pass on the built homepage.

### Phase 5 — After deploy (post-merge; `soleur:postmerge`)

- 5.1 Verify the live homepage carries the section, exactly one `id="departments"`, and no `plausible` markup on the link.
- 5.2 Record the ship date as a comment on #9588.
- 5.3 Coordinate with #9620 before any hosted depiction (none in v1).

## Files to Create

- `plugins/soleur/docs/_data/fanoutDemo.js` (default export only)
- `plugins/soleur/lib/fanout-validate.js`
- `plugins/soleur/test/fanout-demo-drift.test.ts`

## Files to Edit

- `plugins/soleur/docs/index.njk`
- `plugins/soleur/docs/css/style.css`
- `knowledge-base/project/specs/archive/20261006-205404-feat-homepage-demo-9577/spec.md` (amendment: Option A copy, label, deviations, PNGs superseded)
- `knowledge-base/marketing/brand-guide.md` (pre-merge: bundled-change line in the hero-CTA test block)

**Not edited, on purpose:** the inline critical CSS in `base.njk`, `ABOVE_FOLD_PREFIXES`, any JSON-LD, `llms.txt.njk`, the hero markup, `stats.js`, the web-platform app, and the wireframe `.pen`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a labelled illustration, four departments, no button inside it, no animation in v1, a data file plus a drift test, shipped after the positioning section" [brief] | Design; Phase 2; Guard 1 | mapped |
| 2 | "the spec holds the final copy; the .pen still shows two old strings" [brief] | Approved copy; Phase 4.2 | mapped |
| 3 | "the CMO would hold the "check did not pass" line until #9578 ships; your approved scope kept it as an illustration" [brief] | Option A (plan-gate decision); forbidden-phrase pins | mapped |
| 4 | "a CLO review of the built text" [brief] | Phase 4.1 | mapped |
| 5 | "add id="departments" to the "Your AI Organization" section" [brief] | Phase 2.2; Guard 1 | mapped |
| 6 | "record the ship date on #9588 and in the 2026-11-03 hero CTA verdict" [brief] | Decision 7; Phases 4.3, 4.4, 5.2 | mapped |
| 7 | "coordinate with #9620 before any hosted depiction" [brief] | Phase 5.3 | mapped |
| 8 | "No button or CTA inside the section, and no reuse of the hero's `Hero Self-host Click` or `Waitlist Signup` events" [spec] | Cut List; Guard 2 | mapped |
| 9 | "The critical-CSS coverage check, the screenshot gate (including the 320px overflow pass) and the hosted-claims drift guard pass" [spec TR2] | Phases 2.4, 3.1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `_data/fanoutDemo.js`, drift test | "a data file plus a drift test" | asked |
| `index.njk` section and id | "add id="departments" to the "Your AI Organization" section" | asked |
| `style.css` rules | "demo styles live in `style.css`, not the inline critical block" [spec TR1] | asked |
| Option A copy, label rename, visible tag, flat glyph chips, no mobile connector | "Rename label to 'How a brief reaches the departments', Visible 'Illustrative example · sample data' tag, Flat chips with state glyphs; Stopped not solid white, Drop the connector on mobile" [operator, plan gate] | asked |
| build-time throw and `fanout-validate.js` | — | inferred — justification: the drift test runs in CI, not in the docs deploy build, so without the throw a bad row ships where the test is not required; the validator is a separate module because a second named export from a data file silently disables the data (plan-review P0) |
| `scroll-margin-top`, reduced-motion scroll fix, forced-colors, print rules | — | inferred — justification: the header is fixed so the jump would land the heading under it; the section's no-motion claim needs the reduced-motion fix; spec FR3 says status is not conveyed by colour alone |
| `role="list"`, hidden colon, `aria-hidden` connector and glyphs | — | inferred — justification: spec FR3 (status conveyed by text) is lost to a screen reader without row semantics |
| forbidden-phrase pins | "Soleur pauses for your approval; it does not guarantee any check will pass" [spec FR2]; spec TR2's forbidden words | inferred — justification: CPO sign-off condition (no founder-defined-check claim before #9578 and #9620); the TR2 words are spec-sourced |
| spec amendment, brand-guide line, #9588 comment | "record the ship date on #9588 and in the 2026-11-03 hero CTA verdict" [brief] | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 7 | Estimated changed lines: ~400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. Open code-review overlap: none.

## Acceptance Criteria

- [ ] The Eleventy build fails, naming the row and key, on a row count other than four, a department key absent from `agents.js`, a status key outside the closed constant, a label that does not match its key, or a missing field; `_data/fanoutDemo.js` has a default export only and the test calls it.
- [ ] The test parses at least four keys from `STATUS_LABELS` in `apps/web-platform/lib/types.ts` (a stale regex reads RED), and every key the data file uses is among them.
- [ ] The built homepage shows exactly the four data-file rows in order, department names resolved from `agents.js`, with the approved copy (Option A) and both caption lines; the label reads "How a brief reaches the departments" (case-insensitive), the tag "Illustrative example · sample data" is visible in the figure, and the figure's accessible name starts "Illustrative example".
- [ ] The built homepage has exactly one `id="departments"` on the "Your AI Organization" `<section>`, the link's `href` resolves to it, and `style.css` gives it `scroll-margin-top: calc(var(--header-h) + var(--space-4))`; `scroll-behavior: auto` sits inside the top-level (unlayered) reduced-motion block.
- [ ] Section text and attribute values (extracted, never raw HTML; case-insensitive with word boundaries, `CLI` case-sensitive; must-PASS for "click", "Client", "ghosted") contain none of: "hosted", "web app", "dashboard", "install", "CLI", "terminal", "plugin", "Claude", "Anthropic", "your check", "your checks", "your standard", "your bar", "your definition of done", "acceptance check", "acceptance criteria", "you define", "checks you set", "margin check", "automatically", "verified"; "guarantee" appears only in the caption disclosure; no numerals; no `<button>`, `<form>`, `<script>`, `plausible` attribute or JSON-LD in the section. The existing hosted-wording guard still passes.
- [ ] `check-critical-css-coverage.mjs`, the screenshot gate (including its inline-CSS-only pass at 320 px, no horizontal overflow with the longest line), `seo-aeo-drift-guard.test.ts` (with its hosted-sentence floors), `marketing-content-drift.test.ts` and `jsonld-escaping.test.ts` pass unchanged.
- [ ] Phase 3 checks hold: each row reads "Department: Status. Line."; chips stay distinguishable in forced-colors mode; Done chip text ≥ 4.5:1; the jump clears the fixed header and is instant under reduced motion; no hover or pointer styling on rows or chips; the connector is absent below 768 px; the section is readable in print.
- [ ] The CLO has reviewed the built text and recorded a verdict; the spec is amended and wireframe PNGs 13–15 are marked superseded.
- [ ] Before merge: the attribution rule is commented on #9588 and the brand-guide hero-CTA note carries the bundled-change line. After deploy: the live homepage carries the section and the ship date is commented on #9588.

## Test Scenarios

- Given a data row with an unknown status key, or a label that does not match its key, when Eleventy builds, then the build fails and names the row and key.
- Given the data file lists five rows or three, or a department key `agents.js` no longer has, when the build runs, then it fails instead of rendering an orphan row.
- Given a visitor on a 320, 360 or 375 px screen, when the section renders, then the chip wraps under the department name by content, no connector is drawn and nothing overflows horizontally.
- Given a visitor activates "See every department below", when the page jumps, then the "Your AI Organization" heading sits below the fixed header, and with reduced motion enabled the jump is instant.
- Given an LLM summariser extracts only the figure, when it reads it, then the tag, the accessible name and the adjacent caption all say the example is illustrative.
- Verification of the PR itself (consumed by `soleur:qa`): **Browser:** navigate to the built homepage at 1440, 390 and 320 px, capture the section, click the link, and read the accessibility tree.

## Domain Review

**Domains relevant:** Product, Marketing, Legal, Engineering (carried forward from the brainstorm's `## Domain Assessments`)

### Marketing

**Status:** reviewed (brainstorm carry-forward; CMO advisory at plan review)
**Assessment:** Proof section, one H2, no button; below-fold, no event, so annotate (not restart) the hero test window. CMO: never ship the "margin check" line; rename "fans out"; mark rows illustrative for extraction. All applied through the plan-gate decisions.

### Legal

**Status:** reviewed (brainstorm carry-forward) — conditions carried as acceptance criteria
**Assessment:** Label the frame illustrative, no-guarantee line, fictional fixtures, no vendor marks, hosted depiction only at "coming soon" (none in v1), coordinate with #9620, CLO review of the built text (Phase 4.1). GDPR gate (plan Phase 2.7, trigger: a `single-user incident` threshold): no regulated-data surface, no new processing, no vendor and no analytics change (the section fires no event), so there is nothing to record in `compliance-posture.md` and no legal document needs an update.

### Engineering

**Status:** reviewed (brainstorm carry-forward; architecture and correctness review at plan review)
**Assessment:** Static HTML and CSS below the fold; styles in `style.css`; new classes `fanout-*`; build-time throw with the validator in a non-data module; one bun test building into a temp directory; no ADR.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** soleur:product:spec-flow-analyzer, soleur:product:cpo
**Skipped specialists:** none — the wireframe was produced and approved in the brainstorm (`knowledge-base/product/design/marketing/homepage-fanout-demo-9577.pen` exists on disk, 73 KB, screenshots 13–16, referenced in spec FR1); the design lens ran at plan review; no domain leader named soleur:marketing:copywriter or soleur:marketing:conversion-optimizer
**Pencil available:** yes

#### Findings

The mechanical UI-surface override fired on `index.njk` and `style.css`. Spec-flow produced the eight decisions folded into "Decisions this plan makes". CPO sign-off: **yes-with-conditions**, now met: Option A copy chosen, forbidden phrases pinned, CLO review of built text planned, copy-upgrade deferral filed (#9661).

## User-Brand Impact

- **If this lands broken, the user experiences:** a homepage section where a row renders empty, an anchor that dead-ends under the fixed header, or an illustration a visitor reads as a live product screenshot or a guarantee.
- **If this leaks, the user's workflow is exposed via:** not applicable to stored data; the exposure is a **public false claim** — the section implying a hosted dashboard, a guaranteed check or a founder-defined check that does not exist, on the page every visitor reads first.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** a single visitor who signs up for a product behaviour the illustration implied but the product lacks is a brand-trust incident on the most-read page; an aggregate-pattern tier would under-weight that.

`requires_cpo_signoff: true` — the CPO advisory above is the plan-time sign-off. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Guard Contract

### Guard 1 — Data, vocabulary, render and anchor drift

**Property.** The section renders exactly the four rows the data file declares, every status and department key exists in its source of truth, and the link resolves to exactly one `id="departments"`.

**Assembly.** The data file `_data/fanoutDemo.js` (default export only), the validator `plugins/soleur/lib/fanout-validate.js` (the one chokepoint, used by the Eleventy build and the test), the template loop in `index.njk`, the built homepage, `agents.js` department keys, the `STATUS_LABELS` keys parsed from `apps/web-platform/lib/types.ts`, and the `id`/`href`/`scroll-margin-top` trio; the template holds no second status or department list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change a row's `status` to a key outside the closed constant, or give it a label that does not match its key | RED (build throws; test fails) |
| 2 | Point the `types.ts` parser at a text with no `STATUS_LABELS` (the guard's own dispatch finding "0 keys") | RED |
| 3 | Add a fifth row after four compliant rows, or use a department key absent from `agents.js` | RED |
| 4 | Add a second named export to `_data/fanoutDemo.js` | RED (the test calls the default export) |
| 5 | Remove the `id`, add a second `id="departments"`, or typo the link `href` | RED |

**Harness rows.** Suite edit: make the validator return without throwing — the suite must go RED on the built-page assertions. Must-PASS non-canonical input: a different fictional company and brief text with the same keys, and display labels that differ from the product's `STATUS_LABELS`.

**Anchor.** `types.ts` is outside this feature's files, so a status key cannot be invented without editing the product vocabulary; one diff that edits both would pass, which is acceptable because this guard certifies keys only. Static assertions cannot prove the rendered landing position; Phase 3.3's browser check is the independent half.

### Guard 2 — Copy guardrails

**Property.** The rendered section contains both caption lines and none of the forbidden claims, in any text-bearing surface.

**Assembly.** Every text surface of the section: visible text, `alt`, `aria-label`, `title`, the figure's accessible name, the link text and the data file's strings. The chokepoint is one extractor built on `tagsOf`/`decodeEntities` from `plugins/soleur/test/lib/visible-text.ts` plus one forbidden-term list defined once in the test.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add "your check" to a row line | RED |
| 2 | Make the extractor return an empty string (selector drift; the guard's own dispatch) | RED (floors on text length and row count) |
| 3 | Put a forbidden word only in an `aria-label` | RED |
| 4 | Remove the second caption line, or add a second copy of the section after a compliant first | RED |

**Harness rows.** Suite edit: empty the forbidden-term list — the suite must go RED. Must-PASS: "guarantee" inside the caption line, and the words "click", "Client" and "ghosted".

**Anchor.** The list lives in the test; lifting a term requires a CPO-signed edit citing #9578, #9620 and the deferral #9661. The independent half is the CLO review of built text, which a test cannot replace.

## Dependencies & Risks

- **Public false-claim risk** is the single-user incident: mitigated by the illustrative framing, Option A copy, the pins and the CLO review; not eliminated by tests.
- **Hero-test confound:** about one extra screen above the quote and FAQ shifts scroll-based measures; handled by the attribution rule pre-registered on #9588 and the brand-guide line, not by a restart.
- **#9578 coupling:** this ships independently of the founder-check feature while the pins hold (they protect this section only, not other homepage copy); the copy upgrade is the deferral #9661.
- **Cross-package test coupling:** the test reads `apps/web-platform/lib/types.ts` as text, so a web-platform PR that refactors `STATUS_LABELS` goes RED in a plugin test its author does not own; the failure message names `types.ts` and `STATUS_LABELS` and the reason. Dependency-cruiser does not cover this path and `c4-canonical.test.ts` already reads `apps/` the same way.
- **Wireframe PNGs 13–15 are stale**; the spec is annotated and the `.pen` is not redrawn.
- **Dev watch:** editing `agents.js` does not re-run `fanoutDemo.js` under `--serve` (dev-only; the build and CI are correct).

## Sharp Edges

- Every new class is `fanout-*`; reusing `landing-section`, `section-label` and `section-title` is intended (already in the critical block), but a new `landing-*` or `section-*` class would trip the critical-CSS coverage check.
- Never use `--color-text-tertiary` (#737373) in the section; secondary (#848484) is the lowest allowed.
- The label's uppercase comes from CSS; the DOM text is mixed case.
- Keep `_data/fanoutDemo.js` default-export-only; the validator lives in `plugins/soleur/lib/`.
- A plan whose `## User-Brand Impact` section is empty or placeholder-only fails deepen-plan Phase 4.6.

## Deferrals (tracked)

- Upgrade the demo copy to reference a founder-defined check once #9578 ships and #9620 is decided, and lift the pins (#9661).
- Real per-department status display for self-hosted users (#2004, out of scope).

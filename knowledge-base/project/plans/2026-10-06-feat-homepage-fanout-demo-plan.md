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

Add one proof section to the marketing homepage (`plugins/soleur/docs/index.njk`): a labelled, static illustration of a single fictional founder brief reaching four departments, each with a text status, so the "human-in-the-loop" claim that the page asserts twice is shown. Rows come from a committed data file that fails the Eleventy build on bad input, a bun drift test pins keys, rendered text and copy guardrails, and the section carries no button, animation, hosted wording or analytics event. It ships after the positioning section and before the quote block, and the "Your AI Organization" section gains `id="departments"` as the link target.

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #9577, #9588 and #9620 are OPEN; #9584 is MERGED (2026-10-06); the wireframe `.pen` (73 KB) and screenshots 13–16 exist on disk; `STATUS_LABELS` and the four-key status union exist in `apps/web-platform/lib/types.ts` (the repo-research subagent put the union at "line ~220"; it is at line 634 and the label map at 657, so its other line numbers were re-verified before use). Stale: the wireframe PNGs 13–15 still show the **old H2 and the old Legal line** (the brainstorm and spec already say the `.pen` shows two superseded strings); the spec holds the final copy. No ADR in `knowledge-base/engineering/architecture/decisions/` concerns marketing-page sections, so the ADR-corpus check (mechanism vs rejected alternatives) found nothing to re-scope.

### Property List and Cut List (Phase 0.6b)

Properties:

1. A visitor sees what the founder still decides, through a worked fictional example.
2. The example cannot be read as a live product surface, a customer result or a guarantee.
3. The section's states cannot drift from the product's state vocabulary or from the department set.
4. The section cannot move the hero CTA test (no button, no event) and its ship date is recorded.
5. A bad data row cannot ship silently.

| Mechanism in the ask or brainstorm | Property | Verdict |
|---|---|---|
| Captured real self-hosted run | 1 | **Cut** (already rejected in the brainstorm: terminal register, developer-only) |
| Animation / reduced-motion stagger | 1 | **Cut** from v1 (YAGNI; reversible) |
| Demo-specific Plausible event | 4 | **Cut** (would need a login-gated goal and confounds the hero test) |
| JSON-LD for the section | none | **Cut** (spec non-goal; FAQ parity machinery is a drift surface) |
| Button or CTA inside the section | none | **Cut** (hero events must stay readable until 2026-11-03) |
| Data file + drift test | 3, 5 | **Kept** |
| Parsing `lib/types.ts` text for the vocabulary | 3 | **Kept** — a committed copy of the vocabulary would itself drift; reading the real source avoids a second source of truth, and a text read crosses no client/server import boundary |

### Repo facts (verified, content anchors)

- Section order in `index.njk`: hero → stats strip → `<!-- Problem Section -->` (the "This Is the Way" positioning section, `landing-section`) → `<section class="landing-quote">` → `<!-- Features Section -->` ("Your AI Organization", no `id` today).
- Data modules are ESM `export default function () {…}` (`agents.js`, `pillars.js`, `stats.js`). `agents.js` returns `{ domains, departmentList }`; each domain has `key` and `name`. The eight department keys include `legal`, `marketing`, `finance`, `engineering`.
- The critical-CSS check (`plugins/soleur/docs/scripts/check-critical-css-coverage.mjs`) only inspects classes whose prefix is in `ABOVE_FOLD_PREFIXES` in `index.njk`. New classes with a `fanout-` prefix are not matched, so they need no inline rules; the existing `landing-section`, `landing-section-inner`, `section-label` and `section-title` classes are already covered and may be reused for the frame.
- The header is fixed (`--header-h: 3.5rem`). `.category-section` already uses `scroll-margin-top: calc(var(--header-h) + var(--space-4))`.
- `html { scroll-behavior: smooth }` is set in both the inline critical block (`base.njk`, inside `@layer base`) and `style.css`. The `prefers-reduced-motion: reduce` block in `style.css` only shortens animation and transition durations, so it does **not** disable smooth scrolling. The new in-page link is the homepage's first same-page jump, which exposes this.
- The #9579 hosted-claims guards in `plugins/soleur/test/seo-aeo-drift-guard.test.ts` are sentence-local on hosted wording and floor the number of hosted sentences per page (`index.html` ≥ 4); a section with no hosted wording neither trips nor reduces them.
- Homepage analytics: only `plausible-event-name=Hero+Self-host+Click` on the hero button; the waitlist form fires a script-level event. The new section adds neither.
- The screenshot gate (`plugins/soleur/docs/scripts/screenshot-gate.mjs`, run by `ci.yml`) renders routes at a 320 px narrow viewport.
- Real product labels: `STATUS_LABELS` is `waiting_for_user: "Needs your decision"`, `active: "Executing"`, `completed: "Completed"`, `failed: "Needs attention"`. The demo's words ("Done", "Stopped", "Waiting on you") are deliberately illustrative and map to the keys only.

### Institutional learnings applied

- `2026-04-27-critical-css-fouc-prevention-via-static-and-playwright-gates.md` and `2026-04-27-hand-extracted-critical-css-misses-globally-rendered-selectors.md`: check the 320 px render, not only the build.
- `2026-04-21-eleventy-site-url-concatenation-broken-without-leading-slash.md`: any `{{ site.url }}` link needs a leading slash; the demo's link is a bare `#departments` anchor, so it avoids the class.
- `2026-05-22-ci-parity-test-docs-arrays-are-themselves-a-drift-surface.md`: a new test must not rely on a hard-coded page list that can go stale; this plan reads the rendered homepage and fails on an empty extraction.
- `2026-03-06-blog-citation-verification-before-publish.md`: no naked numbers; the section carries no counts or durations.
- The #9584 session (`feat-one-shot-9579-9580-homepage-copy-trust-fixes`): guards were added RED first.

### Open Code-Review Overlap

**None.** The open `code-review` issues (87 at query time) were searched for each planned path (`plugins/soleur/docs/index.njk`, `plugins/soleur/docs/css/style.css`, `plugins/soleur/docs/_data`, `plugins/soleur/test/seo-aeo-drift-guard.test.ts`, `knowledge-base/marketing/brand-guide.md`); no issue body names any of them.

### ADR and C4 (Phase 2.10)

No architectural decision: a static marketing section, no new substrate, boundary or data model, and no change to any existing ADR's Decision. The brainstorm reached the same conclusion ("No ADR needed"). The C4 files model the product's runtime, not marketing pages, so no `.c4` edit is planned; the test that proves it is the unchanged `c4-count-parity` suite, which the diff cannot move.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality | Plan response |
|---|---|---|
| TR3: "every status key in the data file exists in the product's state vocabulary" (open: parse `lib/types.ts` vs a committed vocabulary file) | `STATUS_LABELS` is an exported record whose keys are the vocabulary | Parse the keys of `STATUS_LABELS` as text in the test, with a floor of exactly four keys found (a stale regex must read RED, not empty-green) |
| FR1a: label `HOW A BRIEF FANS OUT` | The label pattern on the page is `section-label` (CSS uppercases it) | Source text "How a brief fans out", uppercased by CSS; the drift test compares case-insensitively |
| FR1: "a list of four department rows" | Safari/VoiceOver drops list semantics from a `list-style: none` list; the homepage uses no `role="list"` precedent | Put `role="list"` on the list and test it |
| TR1: "avoid `landing-*` and `section-*` class prefixes for new classes" | Existing `landing-section`/`section-label` classes are covered by the critical block | Reuse those existing classes for the frame and label; every NEW class is `fanout-*` |
| Wireframe screenshots 13–15 | They show the superseded H2 and Legal line | Annotate the spec so nobody implements from the PNGs (spec holds the final copy) |

## Decisions this plan makes (from the spec-flow analysis and CPO advisory)

1. **Validation lives in two places.** The data module (`_data/fanoutDemo.js`) **throws at Eleventy build time** on an unknown status key, a row count other than four, an unknown department key or a missing required field, and the bun test imports the same validator. The build fails first; the test pins it. Department display names come from `agents.js` by key (one source of truth), so a rename cannot orphan a row.
2. **Anchor ownership.** `id="departments"` goes on the "Your AI Organization" `<section>` (not the inner heading) in the same commit as the link; a test asserts exactly one such id in the built homepage and that the link's `href` resolves to it; `style.css` adds `scroll-margin-top: calc(var(--header-h) + var(--space-4))` to it.
3. **Disclosure placement.** The figure's accessible name reads "Illustrative example: …" (`aria-labelledby` the H2 plus an `Illustrative example` lead-in inside the figure before the list), the two disclosure lines stay in the visible `<figcaption>`, and the second line sits directly under the first so chunking cannot split them.
4. **Labels stay illustrative.** "Done", "Stopped" and "Waiting on you" stay (matching the hosted labels would make the section read as the waitlist-only Command Center). The data file carries a comment saying the labels deliberately differ from `STATUS_LABELS`; the test enforces key mapping only and asserts the display labels are *not required* to equal the product's.
5. **Motion.** Add `html { scroll-behavior: auto }` inside the existing `prefers-reduced-motion: reduce` block in `style.css` (unlayered, so it beats the critical block's `@layer base` rule). The "no motion" claim is otherwise false for the new link.
6. **Hero-test confound.** No event, no button, and a test that the link has no `plausible` class or attribute. The ship date is recorded on #9588 and in the hero-CTA test note in `knowledge-base/marketing/brand-guide.md` after deploy (a post-merge step, because the date does not exist before merge); the 2026-11-03 verdict reads that note.
7. **Row semantics.** Each row reads "Department: Status. Line." to a screen reader: a visually hidden colon between name and chip, the connector lines are CSS-only and `aria-hidden`, and every chip has a visible border so states survive forced-colors mode.
8. **Links and print.** The link carries an underline or arrow (a gold link without one fails WCAG 1.4.1 when alone) and a 44 px minimum hit area on mobile; the print stylesheet is checked so the dark section is not unreadable on paper.

### Open decision for the operator (User-Challenge, default kept)

The operator approved the Finance row "Add-on price held back. The margin check did not pass. You decide what happens next." (status **Stopped**). The CPO advisory (sign-off: yes-with-conditions) challenges it: no margin gate exists in the self-hosted product (the review/qa/preflight gates stop on code-level checks), and "the margin check" reads as a bar someone set earlier, which is the founder-defined check of #9578 — not yet built, and its v1 could not express a margin check as a command anyway. **This plan keeps the approved copy as the baseline** and makes the choice a data change, not a code change:

- **Option A (CPO recommendation)** — move "Stopped" to Engineering: "Reminders change held back. A test did not pass. You decide what happens next."; Finance becomes "Waiting on you": "Needs your answer: set the add-on price from the sample cost figures, or hold it until costs are clearer?" The stopped row then carries `gateSource: review | qa | preflight` and the drift test asserts it names an existing skill directory.
- **Option B** — keep the approved Finance copy; the status label stays "Stopped", the section frame keeps both disclosure lines, and the forbidden-phrase pins below apply except "margin check".
- **Option C (fallback)** — Finance "Add-on price not set. The sample costs leave the margin thin. The price is your call.", with a label other than "Stopped".

Under every option the drift test pins the founder-check phrases (below). #9578's own plan-review recorded the same constraint from its side: no demo copy may claim a founder-defined check before that feature ships and #9620 is decided.

## Design

### Data file `plugins/soleur/docs/_data/fanoutDemo.js`

`export default function () { … }` (matching `agents.js`), returning the label, H2, brief text, link text, the two disclosure lines and four rows `{ department, status, line }`, where `department` is a key in `agents.js` (the module imports that data function and resolves the display name) and `status` is a key of `STATUS_LABELS`. A pure `validateFanout(rows, departmentKeys, statusKeys)` is exported and used both by the default export (throws) and by the test.

### Markup (`index.njk`, between the positioning section and `<section class="landing-quote">`)

A `landing-section` frame (existing classes for padding and the `section-label` / `section-title` pattern) containing one H2, a `<figure class="fanout-figure">` with a "Founder brief" card, a `role="list"` of four rows with a text chip each, a `<figcaption>` with the two disclosure lines, and the single anchor link under it. Every new class is `fanout-*`. No `<button>`, `<form>`, `plausible` class, inline script or `{{ stats.* }}` count in the section.

### Styles (`style.css` only)

Frame, brief card, connector (CSS-only), rows, chips (visible border; Stopped solid light, Waiting on you gold outline, Done grey outline), responsive stack at the existing 768 px breakpoint with the chip dropping under the name at 320 px, `scroll-margin-top` on `#departments`, and the reduced-motion scroll fix. Caption and secondary text use `--color-text-secondary` (4.9:1); `--color-text-tertiary` is never used in the section.

## Implementation Phases

Test-first (`cq-write-failing-tests-before`): Phase 1 is RED, Phase 2 turns it GREEN.

### Phase 0 — Preconditions

- 0.1 `git fetch origin main` and re-confirm the section order in `index.njk` and the `ABOVE_FOLD_PREFIXES` list on `origin/main`.
- 0.2 Operator decision on the Finance/Engineering copy (Open decision above); record the chosen option in the PR body.

### Phase 1 — Failing drift tests (RED)

- 1.1 Create `plugins/soleur/test/fanout-demo-drift.test.ts` (reads `_data/fanoutDemo.js`, `_data/agents.js`, the `STATUS_LABELS` keys parsed from `apps/web-platform/lib/types.ts` as text, and the built `_site/index.html`; builds the site the way `marketing-content-drift.test.ts` does). Cases per the Guard Contract below, plus the acceptance criteria that are mechanically testable.
- 1.2 Fixtures are synthesized (`cq-test-fixtures-synthesized-only`): in-memory row sets (unknown status key, five rows, three rows, unknown department, extra field), HTML snippets for the extractor, and a `types.ts` text variant with no `STATUS_LABELS`.
- 1.3 Run the suite and record that each new case is RED for the right reason (module and section absent).

### Phase 2 — Build the section (GREEN)

- 2.1 Create `_data/fanoutDemo.js` with the validator and the approved copy (or the operator's chosen option).
- 2.2 Edit `index.njk`: add the section and `id="departments"` on the "Your AI Organization" section.
- 2.3 Edit `style.css`: section styles, `scroll-margin-top`, reduced-motion scroll fix.
- 2.4 Run `npm run docs:build`, the new suite, `check-critical-css-coverage.mjs` and the existing `seo-aeo-drift-guard.test.ts`, `marketing-content-drift.test.ts` and `jsonld-escaping.test.ts` suites.

### Phase 3 — Visual and accessibility verification

- 3.1 Run `screenshot-gate.mjs` (320 px pass) and capture 1440, 390 and 320 renders of the section; compare against wireframes 13–15 for layout (not copy).
- 3.2 Check the accessibility tree reads each row as "Department: Status. Line." at 1440 and 320, the figure's accessible name includes "Illustrative example", and forced-colors mode keeps the chips distinguishable.
- 3.3 Click the link and confirm the section heading lands below the fixed header; confirm no smooth scroll under reduced motion; print-preview the section.

### Phase 4 — Review gates before ship

- 4.1 CLO review of the **built** text (spec acceptance criterion, after the wireframe), recorded as a verdict.
- 4.2 Annotate the spec so wireframe PNGs 13–15 are marked superseded for the H2 and row copy.
- 4.3 `soleur:qa` browser pass on the built homepage.

### Phase 5 — After deploy (post-merge; `soleur:postmerge`)

- 5.1 Verify the live homepage carries the section, exactly one `id="departments"`, and no `plausible` markup on the link.
- 5.2 Record the ship date as a comment on #9588 and in the hero-CTA test note in `knowledge-base/marketing/brand-guide.md`.
- 5.3 Coordinate with #9620 before any hosted depiction (none in v1).

## Files to Create

- `plugins/soleur/docs/_data/fanoutDemo.js`
- `plugins/soleur/test/fanout-demo-drift.test.ts`

## Files to Edit

- `plugins/soleur/docs/index.njk`
- `plugins/soleur/docs/css/style.css`
- `knowledge-base/project/specs/feat-homepage-demo-9577/spec.md` (amendment note: PNGs 13–15 superseded; decisions above)
- `knowledge-base/marketing/brand-guide.md` (post-deploy: ship-date note in the hero-CTA test block)

**Not edited, on purpose:** the inline critical CSS in `base.njk`, `ABOVE_FOLD_PREFIXES`, any JSON-LD, `llms.txt.njk`, the hero markup, `stats.js`, the web-platform app, and the wireframe `.pen`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a labelled illustration, four departments, no button inside it, no animation in v1, a data file plus a drift test, shipped after the positioning section" [brief] | Design; Phase 2; Guard 1 | mapped |
| 2 | "the spec holds the final copy; the .pen still shows two old strings" [brief] | Phase 2.1 uses spec copy; Phase 4.2 annotates | mapped |
| 3 | "the CMO would hold the "check did not pass" line until #9578 ships; your approved scope kept it as an illustration" [brief] | Open decision (Options A–C), forbidden-phrase pins | mapped |
| 4 | "a CLO review of the built text" [brief] | Phase 4.1 | mapped |
| 5 | "add id="departments" to the "Your AI Organization" section" [brief] | Phase 2.2; Guard 3 | mapped |
| 6 | "record the ship date on #9588 and in the 2026-11-03 hero CTA verdict" [brief] | Phase 5.2 | mapped |
| 7 | "coordinate with #9620 before any hosted depiction" [brief] | Phase 5.3 | mapped |
| 8 | "No button or CTA inside the section, and no reuse of the hero's `Hero Self-host Click` or `Waitlist Signup` events" [spec] | Cut List; Guard 2 | mapped |
| 9 | "The critical-CSS coverage check, the screenshot gate (including the 320px overflow pass) and the hosted-claims drift guard pass" [spec TR2] | Phases 2.4, 3.1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `_data/fanoutDemo.js` | "a data file plus a drift test" | asked |
| `fanout-demo-drift.test.ts` | "a data file plus a drift test" | asked |
| `index.njk` section and id | "add id="departments" to the "Your AI Organization" section" | asked |
| `style.css` rules | "demo styles live in `style.css`, not the inline critical block" [spec TR1] | asked |
| build-time throw in the data module | — | inferred — justification: a drift test runs in CI, not in the Eleventy build, so without the throw a bad row ships green wherever the test is not required (spec-flow) |
| `scroll-margin-top` and reduced-motion scroll fix | — | inferred — justification: the header is fixed, so the jump would land the heading under it, and the section's "no motion" claim is false for the new link without the fix (spec-flow) |
| `role="list"`, hidden colon, `aria-hidden` connector | — | inferred — justification: spec FR3 says status is conveyed by text, which a screen reader loses without row semantics |
| forbidden-phrase pins | "no marketing, changelog or demo copy claims" [#9578 plan review] / "Soleur pauses for your approval; it does not guarantee any check will pass" [spec FR2] | inferred — justification: CPO sign-off condition; the section must not claim a founder-defined check before it ships |
| spec annotation (PNGs superseded) | "the .pen still shows two old strings" [brief] | asked |
| brand-guide ship-date note | "record the ship date on #9588 and in the 2026-11-03 hero CTA verdict" [brief] | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 6 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. Open code-review overlap: none (see Research Insights).

## Acceptance Criteria

- [ ] The Eleventy build fails on an unknown status key, a row count other than four, an unknown department key or a missing field; the same validator is exercised by the drift test.
- [ ] `STATUS_LABELS` keys are parsed from `apps/web-platform/lib/types.ts` as text, the parser finds exactly four keys (a stale regex reads RED), and every row's `status` is one of them.
- [ ] Each row's `department` is a key in `agents.js`, the rendered name comes from `agents.js`, and the rendered homepage shows exactly the four data-file rows in order.
- [ ] The rendered section contains both FR2 disclosure lines, the "Illustrative example" lead-in, the label (case-insensitive), the H2, the brief text and the four row lines from the data file.
- [ ] The built homepage has exactly one `id="departments"`, on the "Your AI Organization" `<section>`, and the demo link's `href` resolves to it; `style.css` gives it `scroll-margin-top: calc(var(--header-h) + var(--space-4))`.
- [ ] The section text and every attribute in it (alt, aria-label, title, the figure name) contain none of: "hosted", "web app", "dashboard", "install", "CLI", "terminal", "plugin", "Claude", "Anthropic", "your check", "your checks", "your standard", "your bar", "your definition of done", "acceptance check", "acceptance criteria", "you define", "checks you set", "automatically", "verified", "approved by"; "guarantee" appears only inside the FR2 disclosure; "margin check" is forbidden when Option A is chosen.
- [ ] The section has no `<button>`, `<form>`, `<script>`, `plausible` class or attribute, JSON-LD block, `{{ stats.* }}` count, or numeral (no counts, durations or percentages).
- [ ] Under `prefers-reduced-motion: reduce` the page's computed `scroll-behavior` is `auto` (unlayered rule in `style.css`).
- [ ] `check-critical-css-coverage.mjs`, the screenshot gate (320 px pass, no horizontal overflow with the longest Engineering line), `seo-aeo-drift-guard.test.ts` (including its hosted-sentence floors), `marketing-content-drift.test.ts` and `jsonld-escaping.test.ts` pass.
- [ ] A screen reader or the accessibility tree reads each row as "Department: Status. Line." at 1440 and 320 px; the figure's accessible name includes "Illustrative example"; the list carries `role="list"`; chips keep a visible border and the grey "Done" chip text meets 4.5:1.
- [ ] The Finance/Engineering copy decision is recorded in the PR body and the data file matches the chosen option.
- [ ] The CLO has reviewed the built text and recorded a verdict; wireframe PNGs 13–15 are annotated as superseded for the H2 and row copy.
- [ ] After deploy: the live homepage carries the section; the ship date is recorded on #9588 and in the brand-guide hero-CTA note.

## Test Scenarios

- Given a data row with an unknown status key, when Eleventy builds, then the build fails and names the key.
- Given the data file lists five rows or three, when the build runs, then it fails.
- Given `agents.js` renames the `finance` department key, when the build runs, then it fails instead of rendering an orphan row.
- Given a visitor on a 320 px screen, when the section renders, then the chip sits under the department name, the longest Engineering line wraps to four lines and nothing overflows horizontally.
- Given a visitor activates "See every department below", when the page jumps, then the "Your AI Organization" heading sits below the fixed header, and with reduced motion enabled the jump is instant.
- Given an LLM summariser extracts only the rows, when it reads the figure, then the accessible name and the adjacent disclosure both say the example is illustrative.
- Verification of the PR itself (consumed by `soleur:qa`): **Browser:** navigate to the built homepage at 1440, 390 and 320 px, capture the section, click the link, and read the accessibility tree.

## Domain Review

**Domains relevant:** Product, Marketing, Legal, Engineering (carried forward from the brainstorm's `## Domain Assessments`)

### Marketing

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Proof section, one H2, no button inside; adding it before the 2026-11-03 hero-test verdict is another bundled change, so the ship date is recorded; four departments; real HTML text for AEO; no new JSON-LD. The CMO would hold the "check did not pass" line until #9578 ships (see the Open decision).

### Legal

**Status:** reviewed (brainstorm carry-forward) — conditions carried as acceptance criteria
**Assessment:** Label the frame illustrative, no-guarantee line, fictional fixtures, no vendor marks, hosted depiction only at "coming soon" (none in v1), coordinate with #9620, and a CLO review of the built text after the wireframe (Phase 4.1).

### Engineering

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Static HTML and CSS below the fold; styles in `style.css` only; avoid `landing-*` / `section-*` for new classes; the 320 px overflow gate and the hosted-claims guard apply; a data file and a drift test; no ADR needed. The plan adds the build-time throw.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** soleur:product:spec-flow-analyzer, soleur:product:cpo
**Skipped specialists:** none — the wireframe was produced and approved in the brainstorm (`knowledge-base/product/design/marketing/homepage-fanout-demo-9577.pen` exists on disk, 73 KB, screenshots 13–16, referenced in spec FR1); no domain leader named soleur:marketing:copywriter or soleur:marketing:conversion-optimizer
**Pencil available:** yes

#### Findings

The mechanical UI-surface override fired on `index.njk` and `style.css`. Spec-flow produced the eight decisions folded into "Decisions this plan makes" and most acceptance criteria. CPO sign-off: **yes-with-conditions** — (1) resolve the Finance/Engineering copy (Open decision), (2) pin the forbidden phrases and, under Option A, a `gateSource` check, (3) CLO review of built text, (4) track the copy upgrade after #9578 ships. Declined with reason: renaming the label to "How a brief reaches the departments" (taste; the approved label stays).

## User-Brand Impact

- **If this lands broken, the user experiences:** a homepage section where a row renders empty, an anchor that dead-ends under the fixed header, or an illustration a visitor reads as a live product screenshot or a guarantee.
- **If this leaks, the user's workflow is exposed via:** not applicable to stored data; the exposure is a **public false claim** — the section implying a hosted dashboard, a guaranteed check or a founder-defined check that does not exist, on the page every visitor reads first.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** a single visitor who signs up for a product behaviour the illustration implied but the product lacks is a brand-trust incident on the most-read page; an aggregate-pattern tier would under-weight that.

`requires_cpo_signoff: true` — the CPO advisory above is the plan-time sign-off. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Guard Contract

### Guard 1 — Data, vocabulary and render drift

**Property.** Every department key and status key the section renders exists in its source of truth, and the built homepage shows exactly the four rows the data file declares.

**Assembly.** The data file `_data/fanoutDemo.js`, the template loop in `index.njk`, the built `_site/index.html`, the department keys from `agents.js`, and the `STATUS_LABELS` keys parsed from `apps/web-platform/lib/types.ts`. The chokepoint is the exported `validateFanout()` used by both the Eleventy build and the test; the template contains no second status or department list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change a row's `status` to a key not in `STATUS_LABELS` | RED (build throws; test fails) |
| 2 | Point the `types.ts` parser at a text with no `STATUS_LABELS` (the guard's own dispatch finding "0 keys") | RED (floor of exactly four keys) |
| 3 | Add a fifth row after four compliant rows | RED |
| 4 | Remove one row, or use a department key absent from `agents.js` | RED |
| 5 | Hard-code the rows in the template instead of reading the data file | RED (rendered text must equal the data file's lines) |

**Harness rows.** Suite edit: make `validateFanout` return without throwing — the suite must go RED (the in-memory RED fixtures are the negative control, with a floor on RED and must-PASS case counts). Must-PASS non-canonical inputs: a different fictional company and brief text with the same keys; display labels that differ from the product's `STATUS_LABELS` (allowed by design).

**Anchor.** `types.ts` lives outside this feature's files, so a status key cannot be invented without editing the product's vocabulary; one diff that edits both the vocabulary and the data file would pass, which is acceptable because this guard certifies **keys** only (labels are illustrative by decision).

### Guard 2 — Copy guardrails

**Property.** The rendered section contains both disclosure lines and none of the forbidden claims, in any text-bearing surface.

**Assembly.** Every text surface of the section: visible text, `alt`, `aria-label`, `title`, the figure's accessible name, the link text and the data file's strings. The chokepoint is one `sectionText(html)` extractor plus one forbidden-term list defined once in the test.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add "your check" to a row line | RED |
| 2 | Make the extractor return an empty string (selector drift; the guard's own dispatch) | RED (floors on text length and row count) |
| 3 | Put a forbidden word only in an `aria-label` | RED |
| 4 | Remove the second disclosure line | RED |
| 5 | Add a second copy of the section after a compliant first | RED (exactly one section) |

**Harness rows.** Suite edit: empty the forbidden-term list — the suite must go RED. Must-PASS: "guarantee" inside the FR2 disclosure line, and a row line that names a real department without any forbidden term.

**Anchor.** The list lives in the test; lifting a term requires a CPO-signed test edit with a comment citing #9578 and #9620. The independent half is the CLO review of built text, which a test cannot replace.

### Guard 3 — Anchor integrity

**Property.** The "See every department below" link resolves to exactly one `id="departments"` on the "Your AI Organization" section, and the target clears the fixed header.

**Assembly.** The link `href`, the section `id`, the `scroll-margin-top` rule in `style.css`, and the reduced-motion scroll rule; chokepoint: the built homepage plus `style.css`, read together by one test.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the id | RED |
| 2 | Add a second `id="departments"` elsewhere | RED |
| 3 | Typo the link `href` | RED |
| 4 | Remove the `scroll-margin-top` rule | RED |
| 5 | Remove the reduced-motion `scroll-behavior: auto` | RED |

**Harness rows.** Suite edit: drop the id assertion — the suite's own floor must report the missing assertion. Must-PASS: the id on the `<section>` with extra classes present.

**Anchor.** Static assertions cannot prove the rendered landing position; Phase 3.3's browser check is the independent half.

## Dependencies & Risks

- **Public false-claim risk** is the single-user incident: mitigated by the illustrative framing, the guardrail pins and the CLO review; not eliminated by tests.
- **Hero-test confound:** the section adds about a screen of content above the quote and FAQ and shifts any scroll-based measure; the ship date is recorded for the 2026-11-03 review. Whether the test window needs an explicit annotation or restart is a CMO call recorded on #9588.
- **#9578 coupling:** this ships independently of the founder-check feature as long as the pins hold; the copy upgrade ("your check") waits for #9578 and #9620 and is tracked as a deferral.
- **Wireframe PNGs 13–15 are stale** for copy; the spec is annotated and `.pen` is not redrawn (layout is unchanged).
- **Test floors:** `seo-aeo-drift-guard.test.ts` pins hosted-sentence counts per page; the section adds none, and the suite must still pass unchanged.

## Sharp Edges

- Every new class is `fanout-*`; reusing `landing-section`, `section-label` and `section-title` is intended (they are already in the critical block), but a new `landing-*` or `section-*` class would trip the critical-CSS coverage check.
- Never use `--color-text-tertiary` (#737373) in the section; secondary (#848484) is the lowest allowed.
- The label's uppercase comes from CSS; the DOM text is mixed case.
- A plan whose `## User-Brand Impact` section is empty or placeholder-only fails deepen-plan Phase 4.6.

## Deferrals (tracked)

- Upgrade the demo copy to reference a founder-defined check once #9578 ships and #9620 is decided (to be filed with the milestone from the roadmap).
- Real per-department status display for self-hosted users (#2004, out of scope).

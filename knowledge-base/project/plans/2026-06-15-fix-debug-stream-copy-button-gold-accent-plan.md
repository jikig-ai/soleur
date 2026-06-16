---
title: Fix the Debug stream panel "Copy" button — gold accent + header-chrome typographic consistency
type: fix
date: 2026-06-15
branch: feat-one-shot-copy-button-gold-debug-stream
lane: single-domain
status: ready
brand_survival_threshold: none
---

# 🐛 Fix: Debug stream "Copy" button — gold accent + header-chrome typographic consistency

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Research Reconciliation, Implementation Phases, ACs, Test Scenarios, Risks, Sharp Edges
**Agents used:** verify-the-negative pass (sonnet), code-simplicity-reviewer, web-design-guidelines (a11y/WCAG)

### Key improvements from deepen-plan
1. **Hover-contrast CORRECTION (load-bearing AA fix):** the original plan hovered
   to a gold `-fg` brighten. web-design-guidelines proved this FAILS WCAG SC 1.4.3
   in light theme (3.66:1) and inverts the contrast-on-interaction direction —
   SC 1.4.3 has no transient-state exemption. Hover now DARKENS to
   `text-soleur-text-primary` (AA-safe both themes).
2. **Border decision REVERSED (affordance):** the original plan dropped the border;
   review flagged that leaves color as the sole clickability cue next to the inert
   "not saved" label (SC 1.4.1). Now keeps a *gold-tinted* border
   (`border-soleur-accent-gold-text/30`) — affordance + gold unity, still light.
3. **Test/AC ceremony trimmed (YAGNI):** code-simplicity review cut the
   5-assertion className test + both-toggle-states test down to one load-bearing
   assertion (resting `-text` present) + an inline AA comment; collapsed the
   diff-restatement ACs.

### Verification done in this pass
- All 8 factual claims (current className, sibling tokens, gold hex values, vitest
  glob, untouched symbols) verified `confirms` against source.
- WCAG contrast recomputed for `-fg` / `-text` / `-primary` across both themes
  against the composited panel surface; drove every color decision.
- frontend-anti-slop pre-scan: proposed className uses `transition-colors` (not
  `-all`), theme tokens (no arbitrary hex / inline gradient) → passes Tier-1.

## Overview

The "Copy" control in the Debug stream panel header
(`apps/web-platform/components/chat/debug-stream-panel.tsx`, lines 206-219) is
styled inconsistently with the rest of the panel-header chrome:

- **Color (verified bug):** resting state is `text-soleur-text-muted` (grey),
  with `hover:text-soleur-text-primary`. The brand wants the interactive control
  in the **gold accent**, like every other interactive/link affordance in the app
  (`text-soleur-accent-gold-*`, 15+ precedents).
- **Typography (verified outlier):** the Copy button uses `font-mono text-[10px]`,
  while the sibling **"Show"/"Hide"** affordance (line 201) is sans-serif
  `text-[10px] font-medium text-soleur-text-secondary` and **"not saved"**
  (line 220) is sans `text-[10px] text-soleur-text-muted`. The monospace face is
  the dominant cause of the "looks oversized / wrong" perception — monospace
  "Copy" reads wider and heavier than the surrounding proportional 10px text.
- **Chrome heaviness:** Copy carries a `border border-soleur-border-default` box
  while its borderless siblings ("Hide", "not saved") do not, compounding the
  oversized look.

**Fix (single file + one regression test):** recolor Copy to the brand gold
(AA-safe token), drop `font-mono` + add `font-medium` to match "Hide", and swap
the grey border for a light gold-tinted one so it reads as lightweight chrome
while keeping a clear click affordance. Disabled, hover, and "Copied" states are
handled explicitly (see Research Reconciliation — the hover and border choices
were corrected at deepen-plan on WCAG grounds).

This is a **dev-cohort-only** panel (visibility gated on the `dev` `debug-mode`
flag), render-only, no data flow, no API, no server module. The blast radius is
one client component's header chrome.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Debug stream "Copy" control
  that is illegible (sub-AA gold on light theme), mis-colored, or that visually
  reads as inert when it is clickable (or vice-versa). Worst realistic case: a
  cosmetic regression on a dev-only diagnostic panel — no user-facing data,
  workflow, or money is touched.
- **If this leaks, the user's data is exposed via:** N/A — this change touches
  only `className` strings on an existing control. The Copy button's clipboard
  payload already routes through `serializeDebugEvents` →
  `redactCommandForDisplay` (the dual-gate); **this plan does not touch
  serialization or redaction**, so the secret-handling contract is unchanged.
- **Brand-survival threshold:** none. Reason: dev-cohort-only diagnostic panel,
  cosmetic `className` change, no regulated-data surface, no persistence, no
  secret-handling change. The diff touches no sensitive path
  (preflight Check 6 canonical regex: no schema/migration/auth/API/`.sql`).

## Research Reconciliation — Spec-flow gaps vs. resolution

The spec-flow analysis surfaced six state-level gaps a naive recolor would miss.
Each is resolved below with the lightest defensible disposition (YAGNI applies
on a dev-only panel; **accessibility is a non-negotiable carve-out** per
`constitution.md`).

| # | Gap | Disposition (resolved) |
|---|-----|------------------------|
| 1 | **Disabled state color.** Copy is `disabled` whenever `events.length === 0` — the default first-paint of every fresh panel. Faded-gold (gold + `opacity-40`) reads as "branded but mysteriously off." | **Disabled stays muted.** Add explicit `disabled:text-soleur-text-muted` so the gold never appears dimmed. Keep `disabled:cursor-not-allowed disabled:opacity-40`. |
| 2 | **"Copied" confirmation color.** "Copied" inherits the resting color. | **Keep "Copied" the same gold as resting.** The label swap "Copy"→"Copied" is the confirmation signal; a separate success token is scope creep with no existing token. |
| 3 | **Width change from dropping `font-mono`.** | **Accept the shrink** — it is the intended fix for "oversized." The button is in a `shrink-0` flex group (line 205) so it never compresses siblings. Note the resting↔"Copied" width reflow as a known, acceptable micro-shift; do NOT add `min-w` (over-engineering for a dev panel). |
| 4 | **Contrast/AA at 10px.** 10px is below WCAG "large text"; AA requires **4.5:1**. | **LOAD-BEARING — resolved by measurement (see below).** Light-theme `-fg` (#9c7a2e) **FAILS** (3.66:1 on the panel surface); `-text` (#7a5e1f) **PASSES** (5.56:1). Resting MUST be `text-soleur-accent-gold-text`, NOT `-fg`. |
| 5 | **Border / chip-vs-text affordance.** A borderless gold control sitting next to inert "not saved" text (same `text-[10px]` size) leaves COLOR as the only clickability cue — brushes WCAG SC 1.4.1 (Use of Color). [Resolved at deepen-plan after web-design-guidelines review.] | **Keep a gold-TINTED border** (`border border-soleur-accent-gold-text/30`). This preserves the click affordance (a box distinguishes the button from the adjacent label) AND unifies the gold language — strictly better than either dropping it (loses 1.4.1 affordance) or keeping it grey (reads as a different control class). The original grey `border-soleur-border-default` is what made it look heavy/mismatched; a faint gold border is light. |
| 6 | **Hover affordance** at 10px + WCAG SC 1.4.3 on the hover state. | **Hover DARKENS to `text-soleur-text-primary`** (max contrast: light #1a1612, dark #ffffff), NOT a gold brighten. [CORRECTED at deepen-plan — see contrast note.] Hover is an *active* state with NO transient exemption under SC 1.4.3; a gold-`-fg` hover would FAIL AA at 3.66:1 in light theme AND inverts the contrast-on-interaction direction. Hovering to `-primary` is guaranteed AA in both themes and mirrors the pre-fix hover + the sibling toggle button's hover. |

### Contrast measurement (verified, not asserted)

Computed via WCAG relative-luminance against the **actual** composited panel
surface `bg-soleur-bg-surface-1/30` over `bg-base`, using the exact resolved
hexes from `apps/web-platform/app/globals.css` (light block lines 64-86, dark
block lines 39-62):

| Theme | Surface (composited) | `-fg` (#9c7a2e/#c9a962) | `-text` (#7a5e1f/#d4b36a) | `-primary` (#1a1612/#fff) |
|-------|----------------------|-------------------------|---------------------------|---------------------------|
| Light | `#f9f4ea` | 3.66:1 **FAIL** | **5.56:1 PASS** | ~13:1 PASS |
| Dark | `#0d0d0d` | 8.64:1 PASS | 9.68:1 PASS | ~19:1 PASS |

**Conclusion — both resting AND hover must clear AA 4.5:1 (SC 1.4.3 has no
transient-state exemption; hover is an active state):**
- **Resting = `text-soleur-accent-gold-text`** — the gold brand accent, AA-safe
  both themes at 10px (light 5.56:1). `-fg` (#9c7a2e) FAILS light-theme AA
  (3.66:1) and must NOT be the resting color; the brand-guide itself documents
  `-fg` as "≥ AA non-text/large text" only.
- **Hover = `hover:text-soleur-text-primary`** — DARKENS on hover (contrast
  *increases*, the correct interaction direction), guaranteed AA in both themes.
  A gold `-fg` hover was the original plan; it was CORRECTED at deepen-plan
  because it fails light-theme AA (3.66:1) and lightens (de-emphasizes) on
  interaction. `-primary` hover also matches the sibling toggle button and the
  pre-fix Copy hover, so it is the established idiom for this header.

## Implementation Phases

### Phase 1 — RED: pin the ONE load-bearing regression (AA-safe gold token)

[Scoped down at deepen-plan per code-simplicity review.] The repo convention is
to assert behavior, not `className`. The ONLY className regression with real
consequences is a future revert of the resting color to `-fg` (the token that
FAILS light-theme AA at 10px). So add exactly **one** assertion to the existing
collected suite `apps/web-platform/test/components/debug-stream-panel.test.tsx`
(vitest `component` project, `include: ["test/**/*.test.tsx"]` — confirmed
collected): render the panel with ≥1 event and assert the
`data-testid="debug-stream-copy"` button's `className` **contains
`text-soleur-accent-gold-text`** (the AA-safe resting gold). A swap to `-fg`
fails this test.

Do NOT add the other four className assertions (no-`font-mono`, no-border,
no-bare-muted, disabled-fallback) — they merely restate the diff a reviewer reads
in two seconds, are brittle to Tailwind reordering, and are not behavior. Do NOT
add a both-toggle-states assertion — the Copy className is a static literal with
no `expanded` conditional, so asserting it is identical across toggle states
tests that a constant is constant. (The empirical 2×2 visual grid in Phase 3 is
the real cross-state verification.)

Run the suite to confirm RED:
`cd apps/web-platform && ./node_modules/.bin/vitest run test/components/debug-stream-panel.test.tsx`

### Phase 2 — GREEN: apply the className change

Edit `apps/web-platform/components/chat/debug-stream-panel.tsx` Copy button
(lines 206-219), `className` only. Target shape (resolve exact ordering to match
the surrounding file style):

```tsx
// apps/web-platform/components/chat/debug-stream-panel.tsx (Copy <button>, ~line 216)
// BEFORE:
//   className="rounded-sm border border-soleur-border-default px-1.5 py-0.5 font-mono text-[10px] text-soleur-text-muted transition-colors hover:text-soleur-text-primary disabled:cursor-not-allowed disabled:opacity-40"
// AFTER:
//   className="rounded-sm border border-soleur-accent-gold-text/30 px-1.5 py-0.5 text-[10px] font-medium text-soleur-accent-gold-text transition-colors hover:text-soleur-text-primary disabled:cursor-not-allowed disabled:text-soleur-text-muted disabled:opacity-40"
```

Also add a one-line inline comment on the className explaining the AA token
choice (the load-bearing rationale, so a future editor does not "simplify" it):

```tsx
// resting -text (gold) not -fg: -fg fails AA 4.5:1 at 10px on this surface (3.66:1 light).
// hover -primary (not a gold brighten): hover must DARKEN to stay AA (SC 1.4.3, no transient exemption).
```

Changes, itemized:
- `text-soleur-text-muted` → `text-soleur-accent-gold-text` (resting gold, AA-safe)
- `hover:text-soleur-text-primary` **kept as-is** (max-contrast hover — DARKENS,
  AA-safe both themes; do NOT change to a gold `-fg` hover, which fails light AA)
- `border-soleur-border-default` → `border-soleur-accent-gold-text/30`
  (gold-tinted border: keeps the click affordance per SC 1.4.1, unifies the gold
  language — Gap 5)
- remove `font-mono`; add `font-medium` (match "Hide" — Gap 3)
- add `disabled:text-soleur-text-muted` (disabled overrides gold — Gap 1)
- keep `rounded-sm border px-1.5 py-0.5 transition-colors disabled:cursor-not-allowed disabled:opacity-40`

Do **NOT** touch: `onClick={copyAll}`, `disabled={events.length === 0}`, the
`title` logic, the `{copied ? "Copied" : "Copy"}` label, `serializeDebugEvents`,
or the redaction path. The global focus-visible gold ring
(`globals.css` lines 164-169) applies automatically — no per-component focus class.

Re-run the suite → GREEN. Run the full web-platform component suite to confirm no
collateral break:
`cd apps/web-platform && ./node_modules/.bin/vitest run test/components/debug-stream-panel.test.tsx test/components/debug-stream-panel-autoscroll.test.tsx`

### Phase 3 — Verify (typecheck + frontend-anti-slop + visual)

1. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
   (this is the canonical form — `npm run -w` fails, repo has no root `workspaces`).
2. frontend-anti-slop scanner: run
   `plugins/soleur/skills/frontend-anti-slop` (or its scanner script) against the
   changed file. The change introduces no inline-style gradient, no arbitrary
   color, no `transition-all` — it uses theme tokens via Tailwind classes, so it
   should pass clean. Record the result.
3. **Visual QA (browser, Playwright MCP):** capture a 2×2 before/after grid —
   {light, dark} × {disabled (events=0), resting (events>0)} — to empirically
   close Gaps 1 (disabled muted), 4 (AA contrast), 5 (gold-tinted border
   affordance). Use `mcp__playwright__*` to drive the dev-cohort debug
   panel; if the panel is not reachable without a seeded dev session, fall back to
   capturing at least the dark-theme resting state (the default render) AND cite
   the contrast table above as the AA evidence (already computed against the exact
   resolved tokens).

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AA-safe resting gold (the one load-bearing post-condition):** the Copy
  button resting className contains `text-soleur-accent-gold-text` and the hover
  is `hover:text-soleur-text-primary` (NOT a gold `-fg` hover). Pinned by the
  Phase 1 test; a revert to `-fg` (light-theme 3.66:1, sub-AA) fails the test.
- [x] Phase 1 regression test is collected + GREEN, and the full existing suite
  (incl. AC4/AC5/AC6 + #5241 Show/Hide tests) still passes:
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/debug-stream-panel.test.tsx test/components/debug-stream-panel-autoscroll.test.tsx`.
- [x] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [x] frontend-anti-slop scanner returns clean on the changed file (or any finding
  is triaged and recorded).
- [x] The diff is `className`-only on the Copy `<button>` (plus the inline AA
  comment and the one new test): `serializeDebugEvents`, `redactCommandForDisplay`,
  `copyAll`, the `disabled={events.length === 0}` gate, and the `copied`/`title`
  logic are untouched (reviewer verifies from `git diff`).

### Post-merge (operator)

- None. Pure client-component change; deployed by the standard
  `web-platform-release.yml` pipeline on merge to main (path-filtered on
  `apps/web-platform/**`). No migration, no infra, no secret, no operator step.

## Observability

Not applicable — this plan's Files-to-Edit are a client React component
(`apps/web-platform/components/**`, NOT under `server/`/`infra/`) and a test
file; it introduces no new error path, log call, server route, or infra surface.
Per Phase 2.9 skip condition ("pure code change with no new code/infra error
surface"), no `## Observability` 5-field schema is required. The Copy button's
only failure mode (clipboard write rejected in an insecure context) is a
pre-existing, intentionally-silent `catch` (lines 133-137) that this plan does
not touch.

## Domain Review

**Domains relevant:** Product (ADVISORY)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** spec-flow-analyzer
**Skipped specialists:** none — `ux-design-lead` not required: this edits an
existing component's `className` only (no new `components/**/*.tsx` file, no new
`app/**/page.tsx`/`layout.tsx`), so neither the mechanical UI-surface override nor
the new-file escalation fires. No `.pen` wireframe is required for an in-place
recolor of an existing control (`wg-ui-feature-requires-pen-wireframe` targets
new UI surfaces).
**Pencil available:** N/A (no new UI surface)
**Wireframe (`.pen`) requirement:** EXEMPT. Per the canonical UI-surface
definition (`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`
§"Excluded — no wireframe required"), "Pure copy or style tweaks with no
structural/layout change" do not require a `.pen`. This plan swaps color/typography
tokens and drops a border on an existing control — no new component, page, flow,
or layout restructure (the flex layout, button position, and DOM are unchanged).
The deepen-plan Phase 4.9 mechanical glob (`components/**/*.tsx`) matches as a
superset, but the prose exclusion governs intent; the design decision here is a
measured color-token + AA-contrast choice, fully captured in the Contrast
measurement table above. No design signal would be added by a wireframe.

#### Findings

spec-flow-analyzer walked the Copy button's state machine (resting / hover /
disabled / "Copied" / × {light,dark} themes) and surfaced six gaps; all six are
resolved in the Research Reconciliation table above. The one load-bearing finding
— light-theme `-fg` gold fails AA at 10px — was confirmed by direct WCAG
contrast computation and drove the token choice (`-text` not `-fg`). The
"brand-meaning shift" learning (`2026-05-06-scope-out-criterion-misclassification...`)
notes that elevating a muted-neutral control to gold is a deliberate CTA-class
change; here it is explicitly requested by the issue and surfaced as such, not
silently absorbed.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` checked against the single
planned file `apps/web-platform/components/chat/debug-stream-panel.tsx` and the
test file — no open scope-out names either path.)

## Files to Edit

- `apps/web-platform/components/chat/debug-stream-panel.tsx` — Copy `<button>`
  `className` (~line 216) + a one-line inline AA-rationale comment above it.
- `apps/web-platform/test/components/debug-stream-panel.test.tsx` — add the
  gold-accent + no-`font-mono` regression test (new `it(...)` in the existing
  Copy-button `describe` block).

## Files to Create

- None.

## Test Scenarios

1. **AA-safe resting gold (the one new test, RED→GREEN):** render panel with ≥1
   event; assert the `debug-stream-copy` button className `.includes('text-soleur-accent-gold-text')`.
   Single `.includes(token)` assertion — order-independent, guards the only
   regression with real consequences (a sub-AA `-fg` revert).
2. **Regression guards unbroken (existing tests, no new code):** AC4/AC5/AC6 +
   the #5241 Show/Hide tests still pass — Copy is a sibling not a descendant of
   the toggle; disabled with no events does not write; clicking Copy does not
   toggle the panel.

(No-`font-mono`, no-grey-border, disabled-fallback, and both-toggle-states are
NOT separate test cases — they restate the one-line diff / assert a constant, per
the code-simplicity review. The empirical 2×2 visual grid in Phase 3 is the real
cross-state + cross-theme verification.)

## Risks & Mitigations

- **Risk:** a future edit reverts resting gold to `-fg`, or changes the hover to a
  gold brighten — both reintroduce the light-theme sub-AA failure (3.66:1).
  **Mitigation:** the Phase 1 test pins `text-soleur-accent-gold-text` resting;
  the inline AA comment documents why hover must darken to `-primary` not brighten
  to gold. (The hover token is not separately test-pinned — the comment + the
  measured contrast table carry it; a stronger guard is unwarranted on a dev panel.)
- **Risk:** dropping the border would leave color as the sole clickability cue next
  to the inert "not saved" label (WCAG SC 1.4.1). **Mitigation:** the plan keeps a
  *gold-tinted* border (`border-soleur-accent-gold-text/30`) — affordance preserved,
  gold language unified, and far lighter than the original grey box that caused the
  "oversized/mismatched" look.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This plan's threshold is `none` with a stated reason and a
  no-sensitive-path justification — preflight Check 6 will pass.
- **WCAG SC 1.4.3 has no transient-state exemption — the HOVER state of a control
  must meet AA 4.5:1, not just the resting state.** This is why the hover here
  DARKENS to `text-soleur-text-primary` rather than brightening to a gold `-fg`
  (which is 3.66:1 in light theme). When recoloring any interactive control, check
  contrast on resting AND hover, and prefer hover that increases contrast
  (darker-on-light / lighter-on-dark), the correct interaction direction.
- Light-theme `-fg` gold (#9c7a2e) is a tempting "interactive gold" default
  (it's the common `text-sm` link idiom), but it FAILS AA at 10px on this panel's
  surface (3.66:1). The deeper `-text` token (#7a5e1f, 5.56:1) is the AA-safe
  resting color for any ≤10px gold control. Do not "simplify" the resting token
  to `-fg` to match the larger-text link precedent.

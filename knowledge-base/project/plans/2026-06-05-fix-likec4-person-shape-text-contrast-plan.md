---
title: "fix: LikeC4 person-shape text overruns the gold silhouette and becomes unreadable"
type: bug
date: 2026-06-05
branch: feat-one-shot-likec4-person-shape-contrast
lane: single-domain
status: draft
requires_cpo_signoff: false
brand_survival_threshold: none
---

# 🐛 fix: LikeC4 person-shape text contrast — light text over the gold silhouette is unreadable

## Overview

The Soleur-themed LikeC4 C4 visualizer renders `actor` elements with `shape person`
(`knowledge-base/engineering/architecture/diagrams/spec.c4:6-14`). On a person node
— e.g. the **"Founder"** node in the System Context view — the library draws a gold
**person silhouette** in the bottom-right corner of the node, behind the centered
title + description text. Where the (light) title/description text overlaps the
**bright gold** silhouette, contrast collapses and the text becomes unreadable. This
is the exact symptom in the user's screenshot.

### Root cause (verified against the installed library, not memory)

`@likec4/diagram@1.50.0` (`apps/web-platform/node_modules/@likec4/diagram/package.json:version`)
renders the `person` shape in
`node_modules/@likec4/diagram/dist/base-primitives/element/ElementShape.js` (`case "person"`, ~L202):

```js
// ElementShape.js — case "person"
jsxs(Fragment, { children: [
  jsx("rect", { width: w, height: h, rx: 6, strokeWidth: 0 }),          // base node rect
  jsx("svg", {
    x: w - PersonIcon.width - 6,                                        // bottom-right corner
    y: h - PersonIcon.height,
    width: PersonIcon.width,   // 115
    height: PersonIcon.height, // 120
    "data-likec4-fill": "mix-stroke",                                   // <-- tinted by STROKE
    children: jsx("path", { strokeWidth: 0, d: PersonIcon.path })
  })
]})
```

The `data-likec4-fill="mix-stroke"` attribute resolves, in the library's bundled CSS
(`node_modules/@likec4/diagram/dist/styles.css2.js`), to:

```css
[data-likec4-fill=mix-stroke]{
  fill: color-mix(in oklab, var(--likec4-palette-stroke) 80%, var(--likec4-palette-fill));
}
```

So the silhouette fill is **80% of the element STROKE color**. Soleur's
`c4-theme.css` re-points `--likec4-palette-stroke` → `--soleur-border-emphasized`
(gold: `#c9a962` dark / `#9b8857` light — `apps/web-platform/app/globals.css:48,102`).
Result: an **80%-gold silhouette** at the bottom-right.

Meanwhile the node label is a centered content `<div>` rendered by
`ElementData.js` (`Title` span `data-likec4-node-title`, `Description` span
`data-likec4-node-description`, inside `.likec4-element-node-content`). DOM/paint
order in the main node composer (`likec4diagram/custom/nodes/nodes.js:77-78`) is
`ElementShape` **then** `ElementData` — i.e. the text is painted *over* the
silhouette. For the Founder node (long description that wraps), the text block
overruns into the bottom-right region the gold silhouette occupies. Light text on
bright gold → fails WCAG AA → unreadable.

### Fix shape (CSS-only, in `c4-theme.css`, scoped to `.soleur-c4`)

The library renders in the **light DOM** (verified in the prior C4 theme work, PR #4938 —
`<LikeC4Diagram>` uses `RootContainer`, not a ShadowRoot), so the existing
`c4-theme.css` scoped overrides already reach these nodes. Add a rule keyed on the
**intrinsic, stable** node attribute the container always emits
(`ElementNodeContainer.js:69` → `data-likec4-shape`) plus the silhouette's
`data-likec4-fill="mix-stroke"`:

```css
/* Tone the person silhouette down so overrun label text stays legible.
   Keeps gold identity (still the stroke color) but drops the mix toward
   the dark surface + lowers opacity so it reads as a faint corner motif. */
.soleur-c4 [data-likec4-shape="person"] [data-likec4-fill="mix-stroke"] {
  fill: var(--likec4-palette-fill) !important;  /* dark surface, not 80% gold */
  opacity: 0.35 !important;                      /* faint accent, not a slab */
}
```

This is the chosen approach (option **a** from the task brief — tone down the
silhouette). It preserves the gold accent identity (the silhouette is still
present, still gold-derived via the stroke at low opacity) while guaranteeing the
text reads over a faint, low-contrast corner motif in **both** themes — because it
references the theme-aware `--likec4-palette-fill` / palette tokens that already
flip with `data-theme`.

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Reality (verified) | Plan response |
| --- | --- | --- |
| `person` rendered in `ElementShape.js` case "person" ~L202 with PersonIcon at bottom-right, `data-likec4-fill="mix-stroke"` | **Confirmed** — `ElementShape.js:201-230`, `x: w-PersonIcon.width-6, y: h-PersonIcon.height`, `data-likec4-fill: "mix-stroke"`. PersonIcon is 115×120. | Use as root cause. |
| `mix-stroke` tinted by stroke = gold | **Confirmed** — bundled CSS: `mix-stroke` → `color-mix(in oklab, var(--likec4-palette-stroke) 80%, var(--likec4-palette-fill))`; `c4-theme.css:71` maps stroke → `--soleur-border-emphasized` (gold). | Override the `fill` on the person silhouette node. |
| Fix should live in `c4-theme.css`, scoped to `.soleur-c4`, library in light DOM | **Confirmed** — `c4-shared.tsx:89` wraps `<LikeC4Diagram>` in `.soleur-c4`; `c4-theme.css` already overrides `--likec4-palette-*` with `!important` and reaches nodes. | CSS-only fix in `c4-theme.css`. No library patch. |
| Add a test in `c4-theme.test.ts` | **Confirmed** — exists, vitest, source-level negative-space gates. Runner is `vitest` (`package.json:15`); `bunfig.toml:11` `pathIgnorePatterns=["**"]` blocks `bun test`. Node-env include glob is `test/**/*.test.ts` (`vitest.config.ts:44`) — file already matches. | Add assertions; run `./node_modules/.bin/vitest run test/c4-theme.test.ts`. |
| `spec.c4` actor sets `shape person; color secondary` | **Confirmed** — `spec.c4:6-14`. No edit needed (the shape/color are correct; only the Soleur silhouette tint is the bug). | `spec.c4` is reference context, NOT edited. |

## User-Brand Impact

**If this lands broken, the user experiences:** an unreadable "Founder" node title +
description in the System Context C4 view (light text smeared over a bright-gold
silhouette) — the diagram looks broken/unpolished in the dogfooded KB viewer.

**If this leaks, the user's data / workflow is exposed via:** N/A — this is a
presentation-only CSS change to a flag-gated internal visualizer. No data path, no
auth, no persistence touched.

**Brand-survival threshold:** none — cosmetic legibility fix on an internal,
flag-gated (`c4-visualizer`) surface; failure is a polish regression, not a breach
or an aggregate pattern. (Sensitive-path scope-out: `threshold: none, reason:
CSS-only change to a flag-gated internal diagram viewer; no schema/auth/API/data
surface touched.`)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Silhouette toned down.** `c4-theme.css` contains a rule scoped to
  `.soleur-c4` that targets the person silhouette via the intrinsic attributes
  `[data-likec4-shape="person"]` **and** `[data-likec4-fill="mix-stroke"]`, and
  re-points its `fill` off the 80%-gold mix (to `--likec4-palette-fill` or an
  equivalently-toned token) **and/or** lowers its `opacity`. Verify:
  `grep -E '\[data-likec4-shape="person"\][^{]*\[data-likec4-fill="mix-stroke"\]' apps/web-platform/components/kb/c4-theme.css` returns ≥1.
- [ ] **AC2 — Theme-aware, not hard-coded.** The new rule references a Soleur/LikeC4
  palette **var** (`var(--likec4-palette-fill)` or `var(--soleur-*)`), not a literal
  hex, so it flips with `data-theme`. Verify the rule body contains `var(--` and the
  file still contains **no** `#3b82f6` (upstream blue) regression.
- [ ] **AC3 — `!important` carried.** The new `fill`/`opacity` declarations carry
  `!important` (required to beat the library's `[data-likec4-fill=mix-stroke]`
  zero-specificity rule from the bundled stylesheet — a plain class rule does not
  win source-order against an `id`-scoped/runtime rule reliably; mirror the existing
  §2b convention). Verify the rule block matches `!important`.
- [ ] **AC4 — Intrinsic-hook guard against a library bump.** `c4-theme.test.ts`
  asserts the installed `ElementShape.js` still emits BOTH hooks the selector
  depends on: `data-likec4-fill: "mix-stroke"` (the silhouette tint attr) inside the
  `person` case, so a library bump that renames the attribute fails CI loudly
  instead of silently un-toning the silhouette. (Pairs the source-grep "our CSS
  contains selector X" assertion — which is vacuous alone — with a guard reading the
  installed component, per the vendored-CSS Sharp Edge from PR #4938.)
- [ ] **AC5 — Existing theme test still green.** `./node_modules/.bin/vitest run test/c4-theme.test.ts`
  passes (all prior assertions + the new ones). Run from `apps/web-platform/`.
- [ ] **AC6 — Visual verification, both themes.** Founder node title + description in
  the System Context view are legible (no light-on-bright-gold overlap) in **both**
  light and dark themes in the running viewer; gold silhouette still visible as a
  faint accent. Capture a before/after screenshot pair per theme for the PR body
  (Playwright MCP against the running dev viewer — see Test Scenarios).

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)

1. Re-confirm the two DOM hooks on the installed library (already verified at
   plan-time; re-run at /work as the load-bearing precondition):
   - `grep -n 'data-likec4-fill: "mix-stroke"' apps/web-platform/node_modules/@likec4/diagram/dist/base-primitives/element/ElementShape.js` — present in the `person` case (and `browser`/`queue`/etc.; the `[data-likec4-shape="person"]` ancestor scopes ours to person only).
   - `grep -n 'data-likec4-shape' apps/web-platform/node_modules/@likec4/diagram/dist/base-primitives/element/ElementNodeContainer.js` — container emits `data-likec4-shape: data.shape` (so `[data-likec4-shape="person"]` is valid and stable).
2. Confirm the `mix-stroke` CSS resolution is still stroke-tinted:
   `grep -o 'mix-stroke]{[^}]*}' apps/web-platform/node_modules/@likec4/diagram/dist/styles.css2.js`
   → `color-mix(... var(--likec4-palette-stroke) 80% ...)`. (If a bump changed this to
   no longer use stroke, re-derive — but our fix overrides `fill` outright, so it is
   robust to the mix ratio changing.)
3. Confirm the dev viewer route + the `c4-visualizer` flag is ON for the dev cohort
   (per MEMORY: flag ON, `harry@jikigai.com` promoted) so the running-viewer check in
   Phase 4 is reachable.

### Phase 1 — Tone down the person silhouette (the fix)

Edit `apps/web-platform/components/kb/c4-theme.css`. Add a new numbered section
(e.g. **§2c**) after the per-node palette override block (§2b, ends ~L79),
documenting *why* (the `mix-stroke` 80%-gold tint + label overrun) and the chosen
trade-off (faint corner motif preserves gold identity while guaranteeing legible
text). Rule:

```css
/*
 * 2c. Person-shape silhouette legibility. The `person` shape (ElementShape.js
 *     case "person") paints a PersonIcon SVG at the node's bottom-right with
 *     data-likec4-fill="mix-stroke" → color-mix(stroke 80%, fill). With Soleur's
 *     gold stroke that is a bright-gold slab; the node's centered title +
 *     description (ElementData.js) overrun into that corner and light text on
 *     bright gold fails WCAG. Re-point the silhouette fill at the dark surface
 *     and drop its opacity so it reads as a faint gold-tinted accent the text
 *     stays legible over. Theme-aware (palette var flips with data-theme).
 */
.soleur-c4 [data-likec4-shape="person"] [data-likec4-fill="mix-stroke"] {
  fill: var(--likec4-palette-fill) !important;
  opacity: 0.35 !important;
}
```

Tuning note for /work: at `opacity: 0.35` over `--likec4-palette-fill` (the node's
own surface), the silhouette is a faint corner motif. If the visual check (Phase 4)
shows it too faint to read as "person" or still too strong under the text, adjust
the opacity within `[0.25, 0.5]` and/or keep a low-gold tint by using
`color-mix(in oklab, var(--likec4-palette-stroke) 25%, var(--likec4-palette-fill))`
instead of a flat fill — the AC only requires "toned off the 80% mix" + theme-aware
var + legible text, so either form satisfies it. Prefer the simplest that passes
the visual check.

### Phase 2 — Add/adjust the test

Edit `apps/web-platform/test/c4-theme.test.ts`. Add one `it(...)` block to the
existing `describe`:

1. **CSS selector present (negative-space gate).** Assert `c4-theme.css` matches the
   person-silhouette rule (scoped to `.soleur-c4`, keyed on both
   `[data-likec4-shape="person"]` and `[data-likec4-fill="mix-stroke"]`) AND that the
   rule body carries `!important` AND references `var(--` (theme-aware). (Mirror the
   existing AC3 palette-test shape at `c4-theme.test.ts:48-59`.)
2. **Intrinsic-hook guard (reads installed lib).** Extend the existing
   "logo hook still exists" pattern (`c4-theme.test.ts:42-46`) with an assertion that
   `node_modules/@likec4/diagram/dist/base-primitives/element/ElementShape.js`
   still contains `data-likec4-fill: "mix-stroke"` — so a library bump that renames
   the silhouette tint attribute fails CI instead of silently un-toning it. Define
   the path constant the same way `LIKEC4_LOGO` is defined (`c4-theme.test.ts:14-23`).

> Why the pair: the source-grep "our CSS contains selector X" assertion passes even
> when X matches nothing in the rendered DOM (vacuous). Pairing it with a guard that
> reads the installed component is the PR #4938 vendored-CSS Sharp Edge applied here.

### Phase 3 — Verify (see Test Scenarios)

Run the test, then visually verify the Founder node in both themes in the running
viewer and capture screenshots for the PR body.

## Files to Edit

- `apps/web-platform/components/kb/c4-theme.css` — add §2c person-silhouette
  legibility rule (Phase 1).
- `apps/web-platform/test/c4-theme.test.ts` — add the selector-present gate + the
  installed-library `mix-stroke` hook guard (Phase 2).

## Files to Create

- None. (Plus this plan file + `tasks.md`, which are planning artifacts.)

## Files NOT Edited (reference context only)

- `apps/web-platform/components/kb/c4-shared.tsx` — already wraps `<LikeC4Diagram>`
  in `.soleur-c4` (the anchor the fix relies on). No change.
- `apps/web-platform/app/globals.css` — tokens already correct; the fix references
  them, doesn't change them. No change.
- `knowledge-base/engineering/architecture/diagrams/spec.c4` — `actor` `shape person;
  color secondary` is correct as authored. No change.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no open scope-out
whose body references `c4-theme.css` (checked at plan-time via `jq` contains-path).

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| **(b) Push the silhouette behind the text / shrink it** | The silhouette is *already* behind the text in paint order (`nodes.js:77-78` renders shape before data). Shrinking the PersonIcon requires patching the library's `x/y/width/height` (`ElementShape.js`) — a library patch the brief explicitly disprefers. Toning the fill is purely CSS and needs no geometry change. |
| **(c) Constrain the text block so it never overruns the silhouette region** | Would require overriding `.likec4-element-node-content` width/padding (recipe-class-driven, fragile across library bumps) and risks clipping legitimate description text. Doesn't address light-on-gold for short text that *does* sit near the corner. Toning the silhouette is the minimal, robust fix. |
| **Upstream `styles.theme.colors` config API** | The blessed theming hook (surfaced in PR #4938's plan) overrides palette *colors*, but `mix-stroke` is a *fill recipe* (80% stroke); there is no config knob to opt a single shape's icon out of the mix. CSS override of the resolved `fill` is the only per-shape lever. |
| **Drop the `person` shape entirely (use `rectangle`)** | Loses the C4 "person/actor" visual semantics the spec deliberately encodes (`spec.c4:8 notation "Person"`). Out of scope — the bug is contrast, not the shape choice. |

## Domain Review

**Domains relevant:** Product (UI surface — mechanical override fires: edits
`components/kb/c4-theme.css`).

### Product/UX Gate

**Tier:** advisory — modifies the *styling* of an existing, already-shipped UI
surface (the C4 diagram person node); adds no new page, route, component file, or
interactive flow. No new file under `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx`, so the mechanical BLOCKING escalation does not fire.
**Decision:** auto-accepted (pipeline) — this is the one-shot/pipeline path; an
ADVISORY-tier styling tweak to an existing surface auto-accepts. No new wireframe is
warranted (no new layout/flow; the design intent — "faint gold silhouette, legible
text" — is fully specified by the fix).
**Agents invoked:** none (auto-accepted pipeline ADVISORY).
**Skipped specialists:** ux-design-lead (N/A — no new UI surface/flow; styling-only
change to an existing node, not a `wg-ui-feature-requires-pen-wireframe` UI feature),
copywriter (N/A — no copy change).
**Pencil available:** N/A (no new UI surface).

#### Findings

The change improves accessibility (restores WCAG-legible text) while preserving the
gold brand accent. No product-strategy or positioning concern. Note for the visual
check: keep the silhouette visible enough to read as "person" — it carries the C4
actor semantic.

## Observability

Skipped — pure presentation change. No Files-to-Edit under `apps/*/server/`,
`apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`; the only code-class edit is
a CSS file + a source-level test. No new runtime surface, no logs, no failure modes
to instrument. (Per Phase 2.9 skip rule: pure-presentation / no new code-or-infra
runtime surface.)

## Infrastructure (IaC)

Skipped — no new server, service, secret, vendor, cron, DNS, cert, or persistent
runtime process. Pure code change against an already-provisioned surface
(`apps/web-platform/components/**`). (Per Phase 2.8 skip rule.)

## Test Scenarios

1. **Unit (source-level gate) — `c4-theme.test.ts` via vitest.**
   - Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-theme.test.ts`
     (NOT `bun test` — `bunfig.toml:11` `pathIgnorePatterns=["**"]` blocks it; file
     matches the node-env include glob `test/**/*.test.ts` at `vitest.config.ts:44`).
   - Asserts: person-silhouette rule present (scoped, both attrs, `!important`,
     theme-aware var); installed `ElementShape.js` still emits `data-likec4-fill:
     "mix-stroke"`; all prior theme assertions still green.

2. **Visual — running viewer, both themes (Playwright MCP).**
   - Start the dev viewer (`npm run dev` in `apps/web-platform/`), navigate to the
     C4 visualizer KB page (the `c4-model.md` interactive page, flag `c4-visualizer`
     ON for dev), select the **System Context** view.
   - For `data-theme="dark"` and `data-theme="light"` (toggle via the dashboard theme
     control): screenshot the **Founder** person node. Assert the title +
     description are legible (no light-on-bright-gold overlap) and the gold silhouette
     is still visible as a faint accent.
   - Attach the before/after × {light, dark} screenshots to the PR body.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty / `TBD` / lacks the
  threshold fails `deepen-plan` Phase 4.6.** This plan's section is filled
  (threshold `none`, with the sensitive-path scope-out reason). Do not blank it.
- **The fix depends on the library rendering in the LIGHT DOM** (`<LikeC4Diagram>` →
  `RootContainer`, not a ShadowRoot). If `<LikeC4Diagram>` is ever swapped for
  `ReactLikeC4` / `LikeC4View` / `custom` (ShadowRoot variants), this CSS — and the
  entire `c4-theme.css` approach — stops reaching the diagram. The existing
  `c4-theme.test.ts` already guards `<LikeC4Diagram` in `c4-shared.tsx`
  (`c4-theme.test.ts:68`); that guard also covers this rule.
- **Source-grep CSS tests are vacuous alone.** "Our CSS contains selector X" passes
  even when X matches nothing in the rendered DOM. AC4's installed-library
  `mix-stroke` guard is the load-bearing half — keep both halves. This is the
  PR #4938 vendored-library-CSS Sharp Edge
  (`knowledge-base/project/learnings/2026-06-04-vendored-library-css-hook-must-be-verified-against-rendered-dom-not-stylesheet.md`).
- **`opacity` on an SVG `<svg>`/`<path>` element** applies as element opacity (fine
  here — the silhouette is a standalone inner `<svg>`). If a future library version
  nests the icon inside a group with siblings, prefer `fill-opacity` over `opacity`
  to avoid bleeding onto siblings. The current `case "person"` has the icon as a
  lone inner `<svg>`, so `opacity` is safe.
- **Don't over-tone.** If `fill: var(--likec4-palette-fill)` + low opacity makes the
  silhouette invisible, the C4 "actor/person" semantic is lost. Keep it readable as a
  person at the chosen opacity (Phase 4 visual check is the gate; tune within
  `[0.25, 0.5]` or use a low-percentage gold `color-mix`).

## Resume

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-06-05-fix-likec4-person-shape-text-contrast-plan.md
Branch: feat-one-shot-likec4-person-shape-contrast. Worktree: .worktrees/feat-one-shot-likec4-person-shape-contrast/.
CSS-only fix in c4-theme.css (tone the person silhouette mix-stroke fill) + a test in c4-theme.test.ts. Plan written, implementation next.
```

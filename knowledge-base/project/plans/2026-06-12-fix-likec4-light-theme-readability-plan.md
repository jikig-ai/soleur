---
title: "fix: LikeC4 light-theme readability — node fills blend into canvas + edge-label pills wash out"
type: bug
date: 2026-06-12
branch: feat-one-shot-likec4-light-theme-readability
lane: single-domain
status: draft
requires_cpo_signoff: false
brand_survival_threshold: none
---

# 🐛 fix: LikeC4 light-theme readability — node fills + edge-label contrast

## Overview

In the Soleur-themed LikeC4 C4 visualizer (`apps/web-platform/components/kb/c4-shared.tsx`
→ `<LikeC4Diagram>`, scoped by `.soleur-c4` in `c4-theme.css`), the **light theme**
reads poorly. In the reference screenshot — the C4 L1 **"Soleur Platform — System
Context"** view — two distinct symptoms appear:

1. **Node fills blend into the canvas.** Element nodes are filled with
   `--likec4-palette-fill = var(--soleur-bg-surface-2) = #ede4cc` (cream/tan). The
   canvas behind them is `--soleur-bg-base = #fbf7ee` and adjacent surfaces are
   `--soleur-bg-surface-1 = #f4eedf`. These three creams are within ~6% luminance of
   each other, so node *boundaries* (node-vs-canvas separation) nearly vanish — the
   diagram is hard to parse as discrete boxes even though the **text-on-fill**
   contrast is individually fine (title 14.2:1, description 6.2:1 — both pass AA).
2. **Edge / relationship label pills wash out to grey.** The grey-pill low-contrast
   the brief describes is produced by the **library's own light-scheme transform**,
   not by the Soleur token value: under `[data-mantine-color-scheme=light]` the
   bundled CSS sets
   `--xy-edge-label-color: oklch(from var(--likec4-palette-relation-label) calc(l + .05) c h)`
   (lightens the label text +0.05 L) and
   `--xy-edge-label-background-color: oklch(from var(--likec4-palette-relation-label-bg) l c h / 60%)`
   (drops the pill background to **60% opacity** over the canvas). The net effect is
   a pale label on a translucent pale pill — a washed-out grey.

### Root cause — verified against the installed library (not memory)

`@likec4/diagram@1.50.0` (`apps/web-platform/node_modules/@likec4/diagram`). Three
facts, each read from the installed bundle:

**(A) The Mantine color-scheme seam is broken** — this is the load-bearing root
cause that makes a naive token tweak unreliable. The library wraps the diagram in
its own Mantine provider **only when none is already in scope**
(`EnsureMantine.js:13` → if no `MantineContext`, render `DefaultMantineProvider`).
Soleur does **not** wrap `<LikeC4Diagram>` in any `MantineProvider`
(grep: zero `@mantine/core` imports in `apps/web-platform/app` + `components`), so
the library injects `DefaultMantineProvider.js`, which hard-codes
`defaultColorScheme: "auto"` (`DefaultMantineProvider.js:67`). Mantine `"auto"`
resolves `data-mantine-color-scheme` from the OS `prefers-color-scheme` media query
— **NOT** from Soleur's `<html data-theme>`. Consequences:

- A user who picks **Light** in Soleur on a **dark-OS** machine gets
  `data-mantine-color-scheme=dark` on the diagram → the library paints with its
  **dark-scheme** edge-label rules (e.g. `bg ... / 45%`) while the Soleur tokens are
  the **light** cream palette. Dark-tuned label colors over a light cream canvas =
  the low-contrast grey pills in the screenshot.
- Conversely a Light-OS user gets the light branch but the +0.05 L / 60%-opacity
  wash described above.

Either way the diagram's light/dark internal rules drift out of phase with Soleur's
chosen theme. **The token is fine; the scheme attribute lies.**

**(B) Node fill is set unconditionally** (no light-scheme munging). `c4-theme.css`
§2a/§2b point `--likec4-palette-fill → var(--soleur-bg-surface-2)` for all schemes;
the library consumes it directly on the node shape
(`.likec4-element-shape--shapetype_svg { fill: var(--likec4-palette-fill) }`) with no
`[data-mantine-color-scheme=light]` transform. So the cream-on-cream blend is purely
a token-choice problem we can fix in the Soleur layer.

**(C) Edge-label DOM hooks are stable and Soleur-driven.** The label pill is
`.likec4-edge-label` (`background: var(--xy-edge-label-background-color); color:
var(--xy-edge-label-color)`) and the SVG variant is `.react-flow__edge-text { fill:
var(--xy-edge-label-color) }`; both `--xy-*` vars derive from
`--likec4-palette-relation-label{,-bg}`, which `c4-theme.css` already re-points at
`--soleur-text-secondary` / `--soleur-bg-surface-1`. So the *hooks* exist and are
ours to tune — but the value flows through the library's scheme-gated `oklch(...)`
transform (A), so tuning the token without fixing the scheme is a partial fix.

### Fix shape (two coordinated levers)

This plan adopts **Approach B** (fix the seam, then tune tokens) over a token-only
patch, because the broken seam (A) means a token-only change is unreliable across
the OS-mismatch population. Two levers:

- **Lever 1 — bind Mantine's color scheme to Soleur's `data-theme`** so the
  diagram's internal light/dark rules fire in phase with the app theme. Two candidate
  mechanisms (the plan recommends the simpler; deepen-plan + plan-review pick):
  - **(1a) Wrap `<LikeC4Diagram>` in a Soleur `<MantineProvider forceColorScheme=…>`**
    in `c4-shared.tsx`, reading `data-theme` (and `prefers-color-scheme` for
    `system`). Because `EnsureMantine` defers to an existing context, this makes the
    library use **our** scheme. Cost: makes `@mantine/core` a **direct** dependency
    (today it is transitive only — see Sharp Edges).
  - **(1b) Set `data-mantine-color-scheme` on the `.soleur-c4` wrapper element**
    (and keep it in sync with `data-theme` via the existing no-FOUC theme script or
    a small effect). Mantine's CSS selectors are attribute-based
    (`[data-mantine-color-scheme=light] …`), so the attribute alone gates the rules
    without adding a dep. Cost: relies on Mantine reading the attribute off an
    ancestor rather than its provider state (verify at deepen-plan).
  - The plan **recommends (1b)** as the minimal change (no new direct dep, no
    provider nesting) **pending the deepen-plan verification** that Mantine's
    bundled `[data-mantine-color-scheme=…]` rules resolve off a wrapper attribute
    and not exclusively off provider-injected `:root`/`html`. If (1b) does not gate
    the rules, fall back to (1a).
- **Lever 2 — tune the light-theme Soleur tokens** so that, once the light branch
  fires correctly, nodes separate from the canvas and label pills read cleanly:
  - **Node separation:** give element fills a token that sits a notch away from the
    canvas in light theme. Options (deepen-plan/visual-check picks): re-point the
    diagram's `--likec4-palette-fill` at a *lighter* surface than the canvas (e.g.
    `--soleur-bg-surface-1`/a near-white) so nodes read as raised cards on the cream
    base, **or** keep the fill and lean on a stronger node **stroke**
    (`--likec4-palette-stroke` is already `--soleur-border-emphasized = #9b8857`
    gold — verify it renders as a visible border at the library's stroke width).
    The change must be **scoped to light theme** (so dark theme, which works today,
    is untouched) — i.e. a `:root[data-theme="light"] .soleur-c4 { … }` /
    `[data-mantine-color-scheme=light] .soleur-c4 { … }` override, not a global token
    flip.
  - **Edge-label pills:** raise the effective label contrast. Because the library
    lightens the label text (+0.05 L) and drops the pill background to 60% opacity,
    the most robust lever is to (i) darken the Soleur `relation-label` token in light
    theme toward `--soleur-text-primary` (label text 6.8:1 → 15.5:1 head-room
    absorbs the +0.05 L lift) and/or (ii) raise the pill background opacity back
    toward opaque by overriding `--xy-edge-label-background-color` on
    `.soleur-c4 .likec4-edge-label` directly (the `--xy-*` var is the library's own
    consumption point, overridable under our scope). Theme-scoped to light.

All Soleur-layer edits stay in `c4-theme.css` (CSS) + at most a small
`c4-shared.tsx` change for Lever 1; **no library patch**, consistent with the prior
C4 theme work (PR #4938, person-shape plan 2026-06-05).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified against installed lib) | Plan response |
| --- | --- | --- |
| "element node fill colors are too dark/saturated for the dark label text" | **Partly reframed.** Light-theme fill is `--soleur-bg-surface-2 #ede4cc` (cream, NOT dark). Title (`hiContrast #1a1612`) is 14.2:1 and description (`loContrast #5c5043`) is 6.2:1 on it — both pass AA. The real defect is **node-vs-canvas blend** (3 creams within ~6% L), not text-on-fill. | Lever 2 (node separation), light-scoped. |
| "edge/relationship labels have low contrast" | **Confirmed + root-caused.** Library light-branch lightens label text (+0.05 L) and sets pill bg to 60% opacity; AND the mantine seam (A) can paint dark-scheme label rules under a light canvas. Tokens themselves are 6.8:1 (fine). | Lever 1 (seam) + Lever 2 (label token/opacity). |
| Fix is "light-theme color tokens" | **Necessary but not sufficient.** Tokens are mostly fine; the **Mantine color-scheme seam** (`defaultColorScheme:"auto"` ignoring `data-theme`) is the load-bearing root cause that makes any token tweak unreliable. | Plan elevates seam fix to Lever 1; tokens are Lever 2. |
| Cream/tan fills + grey pills "hard to read" (screenshot) | **Confirmed** as the two symptoms above. | Both levers, light-scoped, both-theme visual verification. |
| Library renders in light DOM; `.soleur-c4` overrides reach it | **Confirmed** (PR #4938, person-shape plan): `<LikeC4Diagram>` uses `RootContainer`, not a ShadowRoot. | CSS overrides under `.soleur-c4` are valid. |
| `@mantine/core` available to wrap a provider | **Transitive only** — not in `apps/web-platform/package.json` deps (it ships under `@likec4/diagram`). | Approach (1b) avoids a new direct dep; (1a) would add one. |

## User-Brand Impact

**If this lands broken, the user experiences:** an unreadable / mushy "Soleur
Platform — System Context" C4 diagram in light theme — cream boxes melting into a
cream canvas and grey unreadable relationship labels — in the dogfooded KB viewer.
The diagram looks unpolished, undermining confidence in the product surface the
founder demos.

**If this leaks, the user's data / workflow is exposed via:** N/A — this is a
presentation-only CSS (+ optional provider-wrapper) change to a flag-gated
(`c4-visualizer`) internal visualizer. No data path, auth, persistence, or API
surface is touched.

**Brand-survival threshold:** none — cosmetic legibility fix on an internal,
flag-gated surface; failure is a polish regression, not a breach or aggregate
pattern. (Sensitive-path scope-out: `threshold: none, reason: CSS + optional
client-only Mantine provider wrapper on a flag-gated internal diagram viewer; no
schema/auth/API/data surface touched.`)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Mantine color scheme tracks Soleur theme (the seam fix).** When
  `<html data-theme="light">`, the LikeC4 diagram subtree resolves
  `data-mantine-color-scheme=light` (and `=dark` for dark theme; `system` follows
  `prefers-color-scheme`) **regardless of OS `prefers-color-scheme`**. Verify in the
  running viewer via Playwright: set Soleur Light, then assert
  `document.querySelector('.soleur-c4 [data-mantine-color-scheme]')` (or the diagram
  root) reports `light`. (If approach 1a: a Soleur `<MantineProvider>` wraps
  `<LikeC4Diagram>` with `forceColorScheme` derived from `data-theme`. If 1b: the
  `.soleur-c4` wrapper carries `data-mantine-color-scheme` synced to `data-theme`.)
- [ ] **AC2 — Node separation in light theme.** In the running viewer, light theme,
  element nodes are visually distinguishable from the canvas (a visible
  fill-vs-canvas delta and/or a visible node border). The fix is **scoped to light
  theme** — a `[data-mantine-color-scheme="light"]`/`:root[data-theme="light"]`
  selector under `.soleur-c4`, leaving the dark-theme node rendering byte-identical.
  Verify: `c4-theme.css` contains the light-scoped node rule and dark-theme
  screenshots are unchanged from `main`.
- [ ] **AC3 — Edge-label pills legible in light theme.** Relationship labels read
  clearly in light theme (label text ≥ 4.5:1 against the *rendered* pill, accounting
  for the library's +0.05 L lift and pill opacity). Achieved by darkening the
  light-theme `relation-label` token toward `--soleur-text-primary` and/or raising
  `--xy-edge-label-background-color` opacity under `.soleur-c4 .likec4-edge-label`.
  Theme-scoped to light.
- [ ] **AC4 — Theme-aware, no hard-coded hex regression.** All new rules reference
  Soleur/LikeC4 palette **vars** (`var(--soleur-*)` / `var(--likec4-palette-*)`), not
  literal hex; `c4-theme.css` still contains **no** `#3b82f6` (upstream blue) and the
  dark-theme path still resolves to the existing dark tokens. Verify by grep.
- [ ] **AC5 — `!important` carried where it must beat the library.** Any per-node /
  per-`--xy-*` override carries `!important` (mirrors the §2b/§2c convention — needed
  to beat the library's runtime ID-specificity + bundled-CSS rules). Verify the new
  rule blocks match `!important`.
- [ ] **AC6 — Seam-hook guard against a library bump.** `c4-theme.test.ts` asserts
  the installed library still (a) gates light rules on `data-mantine-color-scheme`
  (grep `styles.css2.js` for `[data-mantine-color-scheme=light]`) and (b) consumes
  `--xy-edge-label-color` / `--xy-edge-label-background-color` on `.likec4-edge-label`
  / `.react-flow__edge-text` — so a bump that renames either hook fails CI loudly
  instead of silently un-fixing the labels. (Pairs the vacuous "our CSS contains
  selector X" source-grep with a guard reading the installed library — PR #4938
  vendored-CSS Sharp Edge.) If approach 1a, also assert `c4-shared.tsx` wraps
  `<LikeC4Diagram>` in a `MantineProvider`.
- [ ] **AC7 — Existing theme test still green.**
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-theme.test.ts`
  passes (all prior assertions — logo hide, palette override, person silhouette — plus
  the new ones). NOT `bun test` (`bunfig.toml:11` `pathIgnorePatterns=["**"]` blocks
  discovery; file matches the node-env include glob `test/**/*.test.ts`).

### Post-merge (operator)

- [ ] **AC8 — Visual verification, both themes (Playwright MCP, dev viewer).** In the
  running viewer (flag `c4-visualizer` ON for dev; `harry@jikigai.com` promoted —
  MEMORY), open the **"Soleur Platform — System Context"** view. For Soleur Light AND
  Dark: screenshot the diagram, assert (i) nodes separate from canvas, (ii) edge
  labels legible, (iii) node titles/descriptions legible, (iv) the gold accent
  identity (stroke/relationships) preserved. Capture before/after × {light, dark} for
  the PR body. **Also** verify AC1's OS-mismatch case: with the dev machine reporting
  `prefers-color-scheme: dark` (or emulated via Playwright `colorScheme: 'dark'`),
  Soleur Light still renders a light diagram. Automation: Playwright MCP — feasible,
  not operator-manual.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)

1. **Re-confirm the Mantine seam** on the installed library (load-bearing):
   - `grep -n 'defaultColorScheme' apps/web-platform/node_modules/@likec4/diagram/dist/context/DefaultMantineProvider.js` → `"auto"` (L67).
   - `grep -n 'MantineContext' apps/web-platform/node_modules/@likec4/diagram/dist/context/EnsureMantine.js` → library defers to an existing provider if present (L13).
   - Confirm Soleur has no MantineProvider in scope:
     `grep -rln '@mantine/core\|MantineProvider' apps/web-platform/app apps/web-platform/components` → empty today.
2. **Confirm the light-branch edge-label rule + DOM hooks** still present:
   `grep -o '\[data-mantine-color-scheme=light\][^}]*xy-edge-label[^}]*}' apps/web-platform/node_modules/@likec4/diagram/dist/styles.css2.js`
   and `grep -o '\.likec4-edge-label{[^}]*}' …` → `color: var(--xy-edge-label-color)` + `background: var(--xy-edge-label-background-color)`.
3. **Decide Lever-1 mechanism (1a vs 1b).** Verify whether Mantine's
   `[data-mantine-color-scheme=light]` bundled rules resolve when the attribute is set
   on the `.soleur-c4` **wrapper** (ancestor) vs requiring it on the provider-injected
   root. If a wrapper attribute gates the rules → **1b** (no new dep). If not → **1a**
   (wrap in `<MantineProvider forceColorScheme>`, add `@mantine/core` as a direct dep,
   reconcile with any "no new dependencies" intent). Record the determination in the
   PR body. (deepen-plan Phase 4.4 precedent-diff handles this.)
4. Confirm `@mantine/core` resolves (transitive) for 1a feasibility:
   `node -e "require('@mantine/core/package.json')"` from `apps/web-platform`.

### Phase 1 — Lever 1: bind color scheme to `data-theme`

Implement the mechanism chosen in Phase 0.3.

- **1b (recommended, no new dep):** sync `data-mantine-color-scheme` onto the
  `.soleur-c4` wrapper (owned by `C4Canvas` in `c4-shared.tsx`) from `data-theme`. The
  existing no-FOUC theme script in `app/layout.tsx` already writes `data-theme`; mirror
  it with a small effect or derive `colorScheme` in `c4-shared.tsx` (it already reads
  `data-theme` at `c4-shared.tsx:402` for the editor — reuse the same read) and set the
  attribute on the wrapper. Keep it reactive to theme changes (effect on a
  theme-change signal / `MutationObserver` on `<html data-theme>`), consistent with how
  the app flips theme live.
- **1a (fallback):** wrap `<LikeC4Diagram>` (both the inline embed and the fullscreen
  portal — the `.soleur-c4` choke point) in `<MantineProvider forceColorScheme={scheme}>`
  where `scheme` is derived from `data-theme` (+ `prefers-color-scheme` for `system`).
  Import `MantineProvider` from `@mantine/core` (add to `package.json` deps). Because
  `EnsureMantine` defers to an existing context, the library uses our scheme.

> Phase-order note: Lever 1 (seam) ships **before/with** Lever 2 (tokens) because the
> token tuning's correctness depends on the right scheme branch firing
> (contract-before-consumer — `2026-05-10-plan-phase-order-load-bearing…`).

### Phase 2 — Lever 2: light-theme node separation + edge-label contrast

Edit `apps/web-platform/components/kb/c4-theme.css`. Add a new **§4** (light-theme
readability) block, scoped to light only so dark theme is untouched:

```css
/*
 * 4. Light-theme readability. Once §1 binds data-mantine-color-scheme to the
 *    Soleur data-theme, the library's light-branch rules fire in phase. In light
 *    theme the three Soleur creams (bg-base #fbf7ee / surface-1 #f4eedf /
 *    surface-2 #ede4cc) sit within ~6% luminance, so element nodes blend into the
 *    canvas; and the library lightens edge-label text (+0.05 L) over a 60%-opacity
 *    pill, washing labels to grey. Light-scope (a) separates nodes from the canvas
 *    and (b) restores label contrast. Dark theme is unchanged (it works today).
 */
[data-mantine-color-scheme="light"] .soleur-c4 :is([data-likec4-color]) {
  /* (a) node separation — pick lighter fill OR rely on stroke (visual-check) */
  --likec4-palette-fill: var(--soleur-bg-surface-1) !important; /* or near-white */
  /* relation-label darkened toward primary so +0.05 L lift still reads */
  --likec4-palette-relation-label: var(--soleur-text-primary) !important;
}
/* (b) restore pill opacity so the label background is opaque enough to read */
[data-mantine-color-scheme="light"] .soleur-c4 .likec4-edge-label {
  --xy-edge-label-background-color: var(--soleur-bg-surface-1) !important;
}
```

(Exact fill/label choices + whether stroke alone suffices are tuned by the Phase 3
visual check within the AC bounds; the form above is the starting point.)

#### Research Insights

**Precedent diff (Phase 4.4):** `c4-theme.css` already establishes the convention
this extends — scoped `.soleur-c4` ancestor + intrinsic `[data-likec4-*]` /
`--likec4-palette-*` hook + `!important` to beat the library's runtime rule (§2a/2b/2c).
The light-scoped `[data-mantine-color-scheme="light"]` prefix is **novel** for this
file but is the library's own scheme-gating idiom (mirrors how the bundle scopes its
light rules). No `MantineProvider` precedent exists in `apps/web-platform` — Lever-1
(1a) would be the first; (1b) is a plain attribute sync (no precedent needed).

**Contrast math (verified, sRGB WCAG):** light-theme token contrasts are individually
fine — node title 14.2:1, description 6.2:1, edge-label token 6.8:1. The failure is
**node-vs-canvas separation** (creams within ~6% L) + the library's **light-branch
label transform** (+0.05 L text, 60% pill opacity), gated by the **broken mantine
seam**. Darkening `relation-label` to `--soleur-text-primary` lifts label head-room to
15.5:1 so the +0.05 L lift still clears AA.

### Phase 3 — Verify (see Test Scenarios)

Run the vitest gate, then visually verify the System Context view in **both** themes
(plus the OS-mismatch case) in the running viewer; capture screenshots for the PR.

## Files to Edit

- `apps/web-platform/components/kb/c4-theme.css` — add §4 light-theme readability
  block (node separation + edge-label pill opacity/contrast), light-scoped (Phase 2).
- `apps/web-platform/components/kb/c4-shared.tsx` — Lever 1: sync
  `data-mantine-color-scheme` to `data-theme` on the `.soleur-c4` wrapper (1b) OR wrap
  `<LikeC4Diagram>` in `<MantineProvider forceColorScheme>` (1a) (Phase 1).
- `apps/web-platform/test/c4-theme.test.ts` — add the seam-hook + edge-label-hook
  installed-library guards and the new CSS-rule presence assertions (AC6).
- `apps/web-platform/package.json` — **only if approach 1a is chosen**: add
  `@mantine/core` as a direct dependency (today transitive). Skip for 1b.

## Files to Create

- None. (Plus this plan file + `tasks.md`, which are planning artifacts.)

## Files NOT Edited (reference context only)

- `apps/web-platform/app/globals.css` — the light-theme Soleur tokens are mostly
  correct (the contrast problem is node-vs-canvas separation + the library's
  scheme-gated transform, not the token *values*). The fix references these tokens
  and re-points the diagram's palette light-scoped; it does **not** change the global
  brand tokens (which other surfaces depend on). If the visual check shows the global
  `--soleur-bg-surface-2` cream is genuinely too close to the canvas for ALL surfaces
  (not just the diagram), that is a separate brand-token decision — file as a
  follow-up, do not widen scope here.
- `app/layout.tsx` no-FOUC theme script — referenced by Lever 1 (1b mirrors its
  `data-theme` write); edited only if 1b needs the attribute written at SSR time to
  avoid a flash (deepen-plan to confirm whether a client effect suffices).

## Open Code-Review Overlap

Two open code-review issues mention `globals.css` but neither concerns C4 color
tokens: **#3564** (Core Web Vitals infrastructure) and **#2349** (qa skill port-probe
/ ESM loader cache). **Acknowledge** — different concern; this plan does not touch
their surfaces and leaves both open. No open scope-out references `c4-theme.css` or
`c4-shared.tsx` (checked via `jq` contains-path over `gh issue list --label
code-review --state open`).

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| **Token-only (Approach A): tweak light-theme `relation-label` / fill in `globals.css`, no seam fix** | Unreliable: the broken Mantine seam means the library may paint dark-scheme label rules under a light canvas for any dark-OS user who picks Light, so a token tweak fixes only the light-OS subset. Also a global `globals.css` token change blasts every Soleur surface, not just the diagram. The seam fix (Lever 1) is the load-bearing root cause. |
| **Patch the library to set `defaultColorScheme` from `data-theme`** | A library patch (brief + prior C4 work disprefer it); brittle across bumps. Wrapping our own provider / attribute is the supported integration seam (`EnsureMantine` is explicitly designed to defer to a parent provider). |
| **Force the diagram always light (or always dark)** | Breaks the working dark theme or breaks light; the diagram must follow the app theme. |
| **Re-author all three Soleur light creams for more separation globally** | Out of scope — that is a brand-guide token decision affecting every surface, not a diagram readability fix. If warranted, file a follow-up against the brand tokens. |

## Domain Review

**Domains relevant:** Product (UI surface — mechanical override fires: edits
`components/kb/c4-theme.css` + `components/kb/c4-shared.tsx`, both UI-surface paths).

### Product/UX Gate

**Tier:** advisory — modifies the *styling* / theme-binding of an existing,
already-shipped UI surface (the C4 diagram). Adds no new page, route, component file,
or interactive flow. No new file under `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx`, so the mechanical BLOCKING escalation does not fire.
**Decision:** auto-accepted (pipeline) — one-shot/pipeline path; an ADVISORY-tier
styling/theme-binding tweak to an existing surface auto-accepts. No new wireframe is
warranted (no new layout/flow; the design intent — "nodes separate from canvas,
labels legible, gold accent preserved, both themes" — is fully specified by the ACs).
**Agents invoked:** none (auto-accepted pipeline ADVISORY).
**Skipped specialists:** ux-design-lead (N/A — no new UI surface/flow; styling-only
change to an existing diagram, not a `wg-ui-feature-requires-pen-wireframe` UI
feature), copywriter (N/A — no copy change).
**Pencil available:** N/A (no new UI surface).

#### Findings

The change restores WCAG-legible diagram readability in light theme while preserving
the gold brand accent (strokes/relationships) and leaving the working dark theme
untouched. It also corrects a latent correctness bug (the diagram ignoring the app's
chosen theme on OS-mismatch machines). No product-strategy or positioning concern.
Visual-check note: keep node fills clearly distinct from the canvas without losing the
warm Soleur cream identity; keep the gold accent on strokes/relationships.

## Observability

Skipped — pure presentation + a client-only theme-binding change. The only
Files-to-Edit are a CSS file, a client React component (`"use client"`
`c4-shared.tsx`, no server/route/infra surface), a source-level test, and (1a only)
`package.json`. No new `apps/*/server/`, `apps/*/src/` runtime path, `apps/*/infra/`,
or `plugins/*/scripts/` surface; no new logs, failure modes, or runtime process to
instrument. (Per Phase 2.9 skip rule: pure-presentation / no new code-or-infra
runtime surface.)

## Infrastructure (IaC)

Skipped — no new server, service, secret, vendor, cron, DNS, cert, or persistent
runtime process. Pure client code change against an already-provisioned surface
(`apps/web-platform/components/**`). (Per Phase 2.8 skip rule.) The `@mantine/core`
direct-dependency add (1a only) is an npm-package change, not infrastructure.

## Test Scenarios

1. **Unit (source-level gate) — `c4-theme.test.ts` via vitest.**
   - Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-theme.test.ts`
     (NOT `bun test` — `bunfig.toml:11` `pathIgnorePatterns=["**"]` blocks discovery;
     file matches the node-env include glob `test/**/*.test.ts` at `vitest.config.ts`).
   - Asserts: new light-theme rules present (light-scoped, theme-aware var,
     `!important`); installed `styles.css2.js` still gates on
     `[data-mantine-color-scheme=light]` and consumes `--xy-edge-label-*` on
     `.likec4-edge-label` / `.react-flow__edge-text`; (1a) `c4-shared.tsx` wraps
     `<LikeC4Diagram>` in `MantineProvider`; all prior theme assertions still green.

2. **Visual — running viewer, both themes + OS-mismatch (Playwright MCP).**
   - Start the dev viewer (`npm run dev` in `apps/web-platform/`), open the C4
     visualizer KB page, select **"Soleur Platform — System Context"**.
   - For `data-theme="light"` and `data-theme="dark"`: screenshot the diagram; assert
     nodes separate from canvas, edge labels legible, titles/descriptions legible,
     gold accent preserved.
   - **OS-mismatch (AC1 regression):** emulate `prefers-color-scheme: dark` (Playwright
     `colorScheme: 'dark'`) with Soleur Light → assert the diagram renders **light**
     (`data-mantine-color-scheme=light` on the diagram subtree), proving the seam fix.
   - Attach before/after × {light, dark} screenshots to the PR body.

## Sharp Edges

- **The Mantine seam is the load-bearing root cause — do not ship Lever 2 without
  Lever 1.** A token-only change leaves the OS-mismatch (dark-OS + Soleur-Light)
  population with dark-scheme label rules on a light canvas. Phase order: seam first.
- **`@mantine/core` is a transitive dep today (not in `package.json`).** Approach 1a
  makes it a **direct** dep — add it explicitly and reconcile with any "no new
  dependency" intent; do NOT import from `@mantine/core` while relying on it being
  hoisted (it may not be at the top level under a strict installer). Approach 1b
  avoids this entirely — prefer it unless Phase 0.3 proves the attribute does not gate
  the rules.
- **Light-scope every Lever-2 rule.** Dark theme works today; an un-scoped token flip
  would regress it. Use `[data-mantine-color-scheme="light"]` (or
  `:root[data-theme="light"]`) under `.soleur-c4`. AC2 requires dark-theme screenshots
  unchanged.
- **Source-grep CSS tests are vacuous alone** ("our CSS contains selector X" passes
  when X matches nothing). AC6's installed-library guards (`[data-mantine-color-scheme
  =light]`, `--xy-edge-label-*` on `.likec4-edge-label` / `.react-flow__edge-text`) are
  the load-bearing half — keep both halves. PR #4938 vendored-CSS Sharp Edge
  (`knowledge-base/project/learnings/2026-06-04-vendored-library-css-hook-must-be-verified-against-rendered-dom-not-stylesheet.md`).
- **The fix depends on the library rendering in the LIGHT DOM** (`<LikeC4Diagram>` →
  `RootContainer`, not a ShadowRoot). If `<LikeC4Diagram>` is ever swapped for
  `ReactLikeC4` / `LikeC4View` / `custom` (ShadowRoot variants), this CSS — and the
  whole `c4-theme.css` approach — stops reaching the diagram. `c4-theme.test.ts:138`
  already guards `<LikeC4Diagram` in `c4-shared.tsx`.
- **Don't over-separate the nodes.** Pushing the fill to stark white loses the warm
  Soleur cream identity. Keep nodes readable as warm cards distinct from the canvas;
  the Phase 3 visual check is the gate.
- **A plan whose `## User-Brand Impact` section is empty / `TBD` / lacks the threshold
  fails `deepen-plan` Phase 4.6.** This section is filled (threshold `none`, with the
  sensitive-path scope-out reason). Do not blank it.

## Resume

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-06-12-fix-likec4-light-theme-readability-plan.md
Branch: feat-one-shot-likec4-light-theme-readability. Worktree: .worktrees/feat-one-shot-likec4-light-theme-readability/.
Two levers: (1) bind data-mantine-color-scheme to Soleur data-theme in c4-shared.tsx (prefer attribute-sync over a new MantineProvider dep); (2) light-scoped node-separation + edge-label-contrast in c4-theme.css. Plan written, implementation next.
```

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

## Enhancement Summary

**Deepened on:** 2026-06-12
**Sections enhanced:** Overview (Lever-1 mechanism resolved), Acceptance Criteria
(AC1), Implementation Phases (Phase 0.3 + Phase 1), Files to Edit, Alternative
Approaches, Sharp Edges.
**Research used:** installed-library inspection (`@mantine/core` MantineProvider /
`use-provider-color-scheme.cjs` / `MantineProvider.d.ts`; `@likec4/diagram@1.50.0`
`EnsureMantine.js`, `DefaultMantineProvider.js`, bundled `styles.css2.js`); Soleur
theme surface (`components/theme/theme-provider.tsx` `useTheme()`/`resolvedTheme`,
`components/theme/no-fouc-script.tsx`); verify-the-negative pass (6/6 plan premises
confirmed); precedent grep (no existing `MantineProvider`/`forceColorScheme`).

### Key Improvements (from deepen)

1. **Lever-1 mechanism RESOLVED → approach 1a (MantineProvider + `forceColorScheme`),
   and 1b is eliminated.** Mantine writes `data-mantine-color-scheme` onto the element
   returned by `getRootElement()` — **default `document.documentElement` (`<html>`)**
   (`@mantine/core/cjs/core/MantineProvider/use-mantine-color-scheme/use-provider-color-scheme.cjs:10`
   `getRootElement()?.setAttribute("data-mantine-color-scheme", computedColorScheme)`).
   The library's light/dark CSS variables AND Mantine's own baseline rules are gated on
   the attribute being on the **root**, not on an arbitrary ancestor div — so setting
   `data-mantine-color-scheme` on the `.soleur-c4` wrapper (1b) does **not** reliably
   flip the diagram's scheme. **1a is the only viable mechanism.**
2. **1a adds NO new npm dependency.** `@mantine/core` is hoisted at the top of
   `apps/web-platform/node_modules` and `require.resolve("@mantine/core")` succeeds —
   the wrapper imports `MantineProvider` from the existing transitive copy. (The plan
   still RECOMMENDS adding `@mantine/core` as an explicit direct dep for robustness —
   see Sharp Edges: relying on a hoisted transitive is brittle under a stricter
   installer; the cost is zero install-size since it's already in the tree.)
3. **`EnsureMantine` defers to our provider (verified).** `EnsureMantine.js:13` returns
   a `Fragment` when a `MantineContext` already exists, so wrapping `<LikeC4Diagram>` in
   OUR `<MantineProvider forceColorScheme={…}>` makes the library use our scheme and
   skip its own `defaultColorScheme:"auto"` provider. No double-provider conflict.
4. **`forceColorScheme?: 'light' | 'dark'` confirmed** (`MantineProvider.d.ts:16`) and
   maps cleanly from Soleur's `useTheme().resolvedTheme` (`theme-provider.tsx:343`,
   `ResolvedTheme = "light" | "dark"` — `system` is already resolved upstream). Setting
   it overrides OS `prefers-color-scheme` unconditionally — exactly the seam fix.
5. **All 6 negative premises confirmed** by a verify-the-negative pass (no Soleur
   `MantineProvider`/`@mantine/core` import; `@mantine/core` absent from
   `package.json`; `globals.css` not edited; no light-scheme transform on
   `--likec4-palette-fill`; existing `c4-theme.css` rules are scheme-unscoped so a new
   light-scoped rule cannot regress dark; `c4-shared.tsx:402` reads `data-theme`).

### New Considerations Discovered

- **Soleur already has a `resolvedTheme` source of truth** — `useTheme()` from
  `components/theme/theme-provider.tsx` (and `no-fouc-script.tsx` sets
  `html.style.colorScheme` + `html.dataset.theme` at boot). The wrapper should consume
  `useTheme().resolvedTheme` directly rather than re-reading `data-theme` off the DOM,
  so it stays reactive through React state (the existing `c4-shared.tsx:402` raw DOM
  read is for the CodeMirror editor and is NOT reactive — do not copy that pattern for
  the provider).
- **`forceColorScheme` is a 2-value union** (`'light' | 'dark'`) — pass
  `resolvedTheme` (already 2-valued), never the 3-valued `theme` (`light|dark|system`).
- This is the **first** `MantineProvider` in the Soleur app (novel precedent) — keep it
  scoped to the C4 canvas (the `.soleur-c4` choke point in `c4-shared.tsx`), do not
  hoist it to the app root (it would wrap the whole app in Mantine's CSS reset).

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

- **Lever 1 — bind Mantine's color scheme to Soleur's `resolvedTheme`** so the
  diagram's internal light/dark rules fire in phase with the app theme. **Mechanism
  resolved at deepen-plan: approach 1a (wrap in `MantineProvider`).**
  - **(1a — CHOSEN) Wrap `<LikeC4Diagram>` in a Soleur
    `<MantineProvider forceColorScheme={resolvedTheme}>`** at the `.soleur-c4` choke
    point in `c4-shared.tsx`, where `resolvedTheme` comes from Soleur's
    `useTheme()` (`components/theme/theme-provider.tsx:343` → `"light" | "dark"`).
    Because `EnsureMantine.js:13` defers to an existing `MantineContext`, the library
    uses **our** scheme and skips its `defaultColorScheme:"auto"` provider.
    `forceColorScheme` overrides OS `prefers-color-scheme` unconditionally, fixing the
    seam. **Adds no new dependency** — `@mantine/core` is hoisted and resolvable today
    (the plan still recommends declaring it directly for robustness; see Sharp Edges).
  - **(1b — REJECTED) Set `data-mantine-color-scheme` on the `.soleur-c4` wrapper.**
    Deepen-plan verified Mantine writes the attribute onto `getRootElement()` =
    `document.documentElement` (`<html>`), and the library's CSS-variable flips +
    Mantine's baseline rules are gated on the **root** attribute — an ancestor-div
    attribute does not reliably flip the scheme. 1b is not viable.
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
| `@mantine/core` available to wrap a provider | **Transitive, but hoisted + resolvable** — absent from `package.json` deps, yet `require.resolve("@mantine/core")` succeeds. `forceColorScheme?: 'light'\|'dark'` confirmed (`MantineProvider.d.ts:16`); `EnsureMantine.js:13` defers to our provider. | Approach **1a** (provider) chosen; add `@mantine/core` as a direct dep for robustness (no install-size delta). |
| Lever-1 could be a wrapper-attribute sync (1b) avoiding a provider | **False (verified at deepen-plan).** Mantine writes `data-mantine-color-scheme` to `getRootElement()` = `<html>`; CSS-var flips + baseline rules gate on the root attr. An ancestor-div attr does not flip the scheme. | 1a (provider) is required; 1b eliminated. |

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

- [ ] **AC1 — Mantine color scheme tracks Soleur theme (the seam fix).** When the app
  resolves to Light (`resolvedTheme === "light"`), the diagram resolves
  `data-mantine-color-scheme=light` (and `=dark` for Dark) **regardless of OS
  `prefers-color-scheme`**, because `c4-shared.tsx` wraps `<LikeC4Diagram>` in
  `<MantineProvider forceColorScheme={resolvedTheme}>` (approach 1a). Mantine writes
  the attribute onto `<html>` (`getRootElement()` default). Verify in the running
  viewer via Playwright: with `prefers-color-scheme: dark` emulated AND Soleur set to
  Light, assert `document.documentElement.getAttribute('data-mantine-color-scheme')`
  reports `light`. Source-side: `c4-shared.tsx` imports `MantineProvider` and passes
  `forceColorScheme={resolvedTheme}` from `useTheme()`.
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
  vendored-CSS Sharp Edge.) Also assert `c4-shared.tsx` wraps `<LikeC4Diagram>` in a
  `MantineProvider` with `forceColorScheme` (the seam fix, approach 1a).
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
3. **Lever-1 mechanism is decided (1a) — re-confirm the supporting facts at /work:**
   - `grep -n 'getRootElement\|data-mantine-color-scheme' apps/web-platform/node_modules/@mantine/core/cjs/core/MantineProvider/use-mantine-color-scheme/use-provider-color-scheme.cjs`
     → attribute is written to `getRootElement()` (default `document.documentElement`),
     confirming 1b (ancestor-div attribute) is not viable.
   - `grep -n 'forceColorScheme' apps/web-platform/node_modules/@mantine/core/lib/core/MantineProvider/MantineProvider.d.ts`
     → `forceColorScheme?: 'light' | 'dark'` (line 16).
   - `grep -n 'MantineContext\|Fragment' apps/web-platform/node_modules/@likec4/diagram/dist/context/EnsureMantine.js`
     → library defers to an existing provider (so our wrapper wins).
4. **Confirm `@mantine/core` resolves without a package.json add:**
   `cd apps/web-platform && node -e "console.log(require.resolve('@mantine/core'))"`
   → resolves to `…/@mantine/core/cjs/index.cjs` (hoisted transitive). Get the version
   to pin via a **file read**, NOT `require('@mantine/core/package.json')` — Mantine's
   `exports` map blocks the `./package.json` subpath (`ERR_PACKAGE_PATH_NOT_EXPORTED`):
   `grep '"version"' node_modules/@mantine/core/package.json` → `8.3.15` (the version
   `@likec4/diagram` itself pins). Add `"@mantine/core": "8.3.15"` to deps.
5. Confirm Soleur's theme hook surface:
   `grep -n 'export function useTheme\|resolvedTheme' apps/web-platform/components/theme/theme-provider.tsx`
   → `useTheme()` returns `{ resolvedTheme: "light" | "dark", ... }`.

### Phase 1 — Lever 1: bind color scheme to `data-theme`

Implement approach **1a** (resolved at deepen-plan).

- Wrap `<LikeC4Diagram>` at the `.soleur-c4` choke point (owned by `C4Canvas` in
  `c4-shared.tsx`, covering both the inline embed and the fullscreen portal) in
  `<MantineProvider forceColorScheme={resolvedTheme}>`:
  - Import `MantineProvider` from `@mantine/core` (already resolvable; add to
    `package.json` deps for robustness — pin to the version already in the tree).
  - `const { resolvedTheme } = useTheme();` (from
    `components/theme/theme-provider.tsx`) → `resolvedTheme` is `"light" | "dark"`,
    the exact `forceColorScheme` union. Do NOT read `data-theme` off the DOM (the
    `c4-shared.tsx:402` raw read is non-reactive and editor-only); the hook keeps the
    provider reactive to live theme flips.
  - `EnsureMantine.js:13` returns a `Fragment` when a `MantineContext` exists, so the
    library uses our provider and skips its `defaultColorScheme:"auto"` injection.
  - Keep the provider scoped to the C4 canvas — do NOT hoist to the app root (it would
    apply Mantine's global CSS reset to the whole app). Mantine still writes
    `data-mantine-color-scheme` to `<html>` (its `getRootElement()` default), which is
    what the diagram's bundled rules require — that is correct and intended.

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

**Precedent diff (Phase 4.4, verified at deepen-plan):** `c4-theme.css` already
establishes the CSS convention this extends — scoped `.soleur-c4` ancestor + intrinsic
`[data-likec4-*]` / `--likec4-palette-*` hook + `!important` to beat the library's
runtime rule (§2a/2b/2c). The light-scoped `[data-mantine-color-scheme="light"]`
prefix is **novel** for this file but is the library's own scheme-gating idiom. For
Lever 1: a grep of `apps/web-platform/{app,components,lib}` for `MantineProvider` /
`forceColorScheme` / `data-mantine-color-scheme` returned **zero** — this is the
**first `MantineProvider` in the Soleur app (no precedent; pattern is novel)**. The
closest precedent is Soleur's own theme infrastructure (`theme-provider.tsx`
`useTheme()`/`resolvedTheme`, `no-fouc-script.tsx` writing `html.dataset.theme` +
`html.style.colorScheme` at boot) — the new provider consumes `resolvedTheme` from
that source of truth rather than introducing a parallel theme read.

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
- `apps/web-platform/components/kb/c4-shared.tsx` — Lever 1 (approach 1a): wrap
  `<LikeC4Diagram>` in `<MantineProvider forceColorScheme={resolvedTheme}>` (from
  `useTheme()`) at the `.soleur-c4` choke point (Phase 1).
- `apps/web-platform/test/c4-theme.test.ts` — add the seam-hook + edge-label-hook
  installed-library guards, the new CSS-rule presence assertions, and the
  `MantineProvider`/`forceColorScheme` source assertion on `c4-shared.tsx` (AC6).
- `apps/web-platform/package.json` — add `"@mantine/core": "8.3.15"` (the version
  `@likec4/diagram@1.50.0` pins) as a direct dependency. It resolves today as a hoisted
  transitive but a stricter installer could un-hoist it. Run the workspace install +
  re-run the lockfile-sync gate per `cq-before-pushing-package-json-changes`.

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
- `components/theme/no-fouc-script.tsx` / `theme-provider.tsx` — the source of truth
  for `resolvedTheme` (boot-time `html.dataset.theme` + `html.style.colorScheme`; the
  `useTheme()` hook). Lever 1 *consumes* `resolvedTheme` from here; it does **not**
  edit these. (The C4 diagram renders client-side via `next/dynamic({ssr:false})`, so
  there is no SSR flash to guard for the diagram's mantine attribute.)

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
| **Patch the library to set `defaultColorScheme` from `data-theme`** | A library patch (brief + prior C4 work disprefer it); brittle across bumps. Wrapping our own provider is the supported integration seam (`EnsureMantine.js:13` is explicitly designed to defer to a parent provider). |
| **Lever-1 via wrapper attribute (1b): set `data-mantine-color-scheme` on `.soleur-c4`** | **Rejected at deepen-plan.** Mantine writes the attribute to `getRootElement()` = `<html>` and gates its CSS-variable flips + baseline rules on the root attribute; an ancestor-div attribute does not reliably flip the diagram's scheme. 1a (provider) is required and adds no dependency. |
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
`c4-shared.tsx`, no server/route/infra surface), a source-level test, and
`package.json` (declare an already-resolvable dep). No new `apps/*/server/`,
`apps/*/src/` runtime path, `apps/*/infra/`, or `plugins/*/scripts/` surface; no new
logs, failure modes, or runtime process to instrument. (Per Phase 2.9 skip rule:
pure-presentation / no new code-or-infra runtime surface.)

## Infrastructure (IaC)

Skipped — no new server, service, secret, vendor, cron, DNS, cert, or persistent
runtime process. Pure client code change against an already-provisioned surface
(`apps/web-platform/components/**`). (Per Phase 2.8 skip rule.) The `@mantine/core`
direct-dependency add is an npm-package change, not infrastructure.

## Test Scenarios

1. **Unit (source-level gate) — `c4-theme.test.ts` via vitest.**
   - Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-theme.test.ts`
     (NOT `bun test` — `bunfig.toml:11` `pathIgnorePatterns=["**"]` blocks discovery;
     file matches the node-env include glob `test/**/*.test.ts` at `vitest.config.ts`).
   - Asserts: new light-theme rules present (light-scoped, theme-aware var,
     `!important`); installed `styles.css2.js` still gates on
     `[data-mantine-color-scheme=light]` and consumes `--xy-edge-label-*` on
     `.likec4-edge-label` / `.react-flow__edge-text`; `c4-shared.tsx` wraps
     `<LikeC4Diagram>` in `<MantineProvider forceColorScheme=…>`; all prior theme
     assertions still green.

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
  imports `MantineProvider` from it. It resolves today via hoisting
  (`require.resolve("@mantine/core")` succeeds), but importing a package you don't
  declare is brittle under a stricter installer that un-hoists it. **Add it as a direct
  dep** pinned to the version already in the tree (zero install-size delta), and re-run
  the lockfile-sync gate (`cq-before-pushing-package-json-changes`).
- **`<MantineProvider forceColorScheme>` writes `data-mantine-color-scheme` to
  `<html>` (a global attribute), not to the wrapper.** This is required (the diagram's
  bundled rules need the root attribute) and harmless here because the forced value
  always equals Soleur's own `resolvedTheme` — but it means the attribute appears on
  `<html>` only while the C4 canvas is mounted. Confirm at the visual check that
  mounting/unmounting the diagram does not flicker the global attribute in a way that
  affects other surfaces (it should not — no other Soleur surface reads
  `data-mantine-color-scheme`). Keep the provider scoped to `.soleur-c4`; never hoist
  it to the app root.
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

---
title: "LikeC4 Mantine color-scheme seam fix + preserving a vendored library's theme when you displace its provider"
date: 2026-06-12
category: ui-bugs
module: apps/web-platform/components/kb
tags: [likec4, mantine, theming, vendored-css, color-scheme, react-context, testing]
pr: 5217
---

# LikeC4 light-theme readability: the Mantine color-scheme seam + theme-preservation tradeoff

## Problem

The dogfooded LikeC4 C4 visualizer read poorly in Soleur **light** theme: element
nodes (cream) melted into the cream canvas, and relationship-label pills washed out
to an unreadable grey. The brief framed it as "light-theme color tokens too
dark/saturated."

## Root cause (the non-obvious part)

The token *values* were individually fine (WCAG-passing). The load-bearing defect was
a **broken Mantine color-scheme seam**:

- `@likec4/diagram` wraps `<LikeC4Diagram>` in its OWN `MantineProvider` with
  `defaultColorScheme: "auto"` — but **only when no `MantineContext` is already in
  scope** (`EnsureMantine.js`: renders `DefaultMantineProvider` iff
  `!useContext(MantineContext)`, else a `Fragment`).
- Soleur wrapped the diagram in NO `MantineProvider`, so the library's `"auto"`
  provider was active. `"auto"` resolves `data-mantine-color-scheme` from the OS
  `prefers-color-scheme` — **NOT** Soleur's `data-theme`.
- A dark-OS user who picks Soleur **Light** therefore got the library's **dark-scheme**
  edge-label rules (translucent pills) painted over a **light** cream canvas → the grey
  wash. The token is fine; the scheme attribute lied.

## Solution

Two coordinated levers (CSS-only + one client component; no library patch):

1. **Seam fix** — wrap the diagram subtree in a Soleur-owned
   `<MantineProvider forceColorScheme={resolvedTheme}>` (`resolvedTheme` from
   `useTheme()`, the exact `"light" | "dark"` union). Because `EnsureMantine` defers
   to an existing context, the library uses *our* scheme and skips its `"auto"`
   provider. `forceColorScheme` overrides the OS unconditionally.
2. **Token tuning** (`c4-theme.css` §4, scoped to `[data-mantine-color-scheme="light"]`
   so dark stays byte-identical): nudge the node fill warmer/deeper via
   `color-mix(in oklab, surface-2, border-default 25%)` for separation; darken the
   relation-label to `text-primary` (absorbs the library's +0.05 L light-branch lift);
   re-point the library's own `--xy-edge-label-background-color` to opaque surface-1
   (the library drops it to 60% in light).

## Key Insight — displacing a vendored library's provider silently drops its theme

When you supply your own `MantineProvider` to satisfy a library's "defer to parent
context" check, you also **displace the theme** that the library's default provider
carried (`@likec4/diagram`'s `DefaultMantineProvider` builds a `createTheme({...})`
with `primaryColor: "indigo"`, fonts, spacing, component overrides). The diagram BODY
is driven by static `--likec4-*` CSS vars and is unaffected, but the interactive
**chrome** (controls, element-details, segmented control) reverts to Mantine's default
accent (indigo → blue) — a real, easily-missed regression caught only by
architecture review.

**Right fix:** pass a minimal theme preserving only the **zero-drift scalars**
(`primaryColor`, `autoContrast`, `cursorType`, `defaultRadius`) — NOT the library's
full unexported theme (its `fontSizes`/`spacing` maps re-point at library-internal
vars and would silently drift on a bump; the library blocks deep-importing it via its
`exports` map). And guard the seam's load-bearing invariant — that the app's
`@mantine/core` dedupes to the SAME physical copy as the library's (one
`MantineContext`) — with a **pin-equality test** (`app package.json` pin ===
library's resolved pin). A future non-matching bump installs two Mantine copies → the
Fragment-collapse silently stops firing → the OS-mismatch bug returns with green
source-grep tests.

## Verifying a vendored CSS override: computed style, not screenshot

A source-grep test ("our CSS contains selector X") is vacuous alone. The non-vacuous
proof is a **reconstructed-DOM harness**: load the real library `styles.css` + your
`c4-theme.css` + inlined brand tokens, rebuild the library's node/edge DOM contract,
and assert `getComputedStyle()` flips off the library default in BOTH schemes (proves
cascade victory — `!important` beating the library's ID-specificity runtime rule).

- **chromium returns `oklab()`/`oklch()`, not `rgb()`, for `color-mix`-derived and
  some var-resolved values.** Computed-style assertions on themed CSS MUST be
  color-space-agnostic: parse the oklab/oklch lightness (first number) and the oklch
  alpha (`/ A`) rather than comparing literal `rgb(...)` strings.
- **The screenshot may render blank** — `@likec4/diagram` gates `.likec4-root` paint
  (opacity/visibility) on react-flow runtime init, which never fires in a static
  harness. `getComputedStyle` reads the cascaded values regardless, so it is the
  authoritative proof; the screenshot is supplementary.

## Session Errors

1. **QA harness chromium path wrong.** `playwright` module's `executablePath()`
   reported `chromium-1208` but the installed cache build was `chromium-1223`; launch
   failed `executable doesn't exist`. **Recovery:** used the literal
   `~/.cache/ms-playwright/chromium-1223/chrome-linux64/chrome`. **Prevention:** derive
   the path from `ls -d ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome | tail -1`,
   never from the module's reported `executablePath()` — they drift. (Already noted in
   `2026-06-05-verify-vendored-css-override-via-reconstructed-dom-harness.md`.)
2. **Computed-style assertions assumed `rgb()`.** chromium returns `oklab`/`oklch` for
   `color-mix`-derived values; first run false-failed. **Recovery:** color-space-agnostic
   lightness/alpha parsing. **Prevention:** see "Verifying a vendored CSS override" above.
3. **`vitest > log; echo VITEST_EXIT=$?` masked the runner exit.** The wrapper command
   exited 0 while vitest exited 1 (8 failures); the summary grep hid it. **Recovery:**
   grepped `VITEST_EXIT=` inside the log. **Prevention:** the existing AGENTS pipefail
   rule — capture `rc=$?` and inspect it explicitly; do not trust a tail/echo wrapper's
   exit. Already covered; one-off here (caught immediately).
4. **`c4-fullscreen.test.tsx` broke (8 tests) when `C4Canvas` gained `useTheme()`.**
   The test rendered `C4Canvas` directly without a `ThemeProvider`
   (`useTheme must be used inside <ThemeProvider>`). **Recovery:** added `vi.mock`
   stubs for `@/components/theme/theme-provider` (`useTheme`) and `@mantine/core`
   (`MantineProvider` + `createTheme` passthrough). **Prevention:** when adding a
   React-context-dependent hook (`useTheme`, `useRouter`, any provider-gated hook) to a
   SHARED component, grep `test/` for every file that renders that component DIRECTLY
   (not via a mock of its module) and add the provider stub in the SAME commit —
   `tsc` and the component's own test pass; sibling direct-render tests fail at runtime.
5. **QA screenshot rendered blank.** Library paint gated on react-flow init.
   **Recovery:** treated `getComputedStyle` as authoritative. **Prevention:** see
   "Verifying a vendored CSS override" above.

## Related

- [[2026-06-05-verify-vendored-css-override-via-reconstructed-dom-harness]] — the harness
  pattern this extends (adds the oklab-form + blank-screenshot gotchas).
- [[2026-06-04-vendored-library-css-hook-must-be-verified-against-rendered-dom-not-stylesheet]]
- PR #4938 / the person-shape C4 theme plan — prior `.soleur-c4` re-theme precedent.

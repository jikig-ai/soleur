# Learning: verify a vendored-library CSS override via a reconstructed-DOM harness + project chromium

## Problem

The LikeC4 C4 visualizer (`@likec4/diagram@1.50.0`) renders `person`/actor nodes with a
gold silhouette whose label text became unreadable where it overran the bright-gold
icon. The fix is a CSS override in `c4-theme.css` (`.soleur-c4 [data-likec4-shape="person"]
[data-likec4-fill="mix-stroke"]`) that tones the silhouette down. Two verification
problems:

1. **Source-grep on the CSS is vacuous** (the PR #4938 vendored-CSS Sharp Edge): a test
   that asserts "our stylesheet contains selector X" passes even if X matches nothing in
   the rendered DOM.
2. **The live surface is expensive to reach:** the viewer is behind the dashboard auth +
   onboarding flow AND a runtime Flagsmith flag (`c4-visualizer`). Standing that up just to
   eyeball a cosmetic CSS tweak is slow and flaky.

Compounding foot-guns hit while trying to render:
- **Playwright MCP failed**: `Chromium distribution 'chrome' is not found at
  /opt/google/chrome/chrome` — the MCP server is configured for the Chrome *channel*, which
  is not installed on this machine.
- **The project's own `playwright` module** (1.58.2) wanted chromium build `1208` but the
  installed cache had build `1223`, so a bare `chromium.launch()` also failed.

## Solution

Reconstruct the **exact library DOM** in a standalone HTML harness and render it with the
project's installed chromium, asserting computed style — no dev server, no auth, no flag.

1. **Read the real DOM contract from `node_modules`** (don't guess): the person case in
   `@likec4/diagram/dist/base-primitives/element/ElementShape.js` emits an inner
   `<svg data-likec4-fill="mix-stroke"><path d="<PersonIcon.path>"/></svg>`; the container
   in `ElementNodeContainer.js` emits `data-likec4-shape`. The bundled `styles.css2.js`
   resolves `mix-stroke` to `color-mix(in oklab, var(--likec4-palette-stroke) 80%,
   var(--likec4-palette-fill))`. Copy these verbatim into the harness (real path, real CSS
   recipe, real Soleur tokens from `globals.css`).
2. **Render with the installed chromium via explicit `executablePath`** to dodge both the
   MCP chrome-channel miss and the module/cache build mismatch:
   ```js
   const browser = await chromium.launch({
     executablePath: process.env.HOME +
       "/.cache/ms-playwright/chromium-1223/chrome-linux64/chrome",
   });
   ```
   (Find the build dir with `ls ~/.cache/ms-playwright | grep chromium-`.)
3. **Assert computed style, then screenshot.** `getComputedStyle(svg).fill` flipping from
   the 80%-gold `oklab(...)` mix to the toned value in *both* `data-theme` states proves the
   `.soleur-c4` rule actually wins the cascade against the library recipe — the non-vacuous
   half the source-grep can't give you. A before/after × {dark,light} screenshot then
   confirms legibility for the PR body.

This is the runtime complement the unit test lacks, and it's much cheaper than the auth'd
viewer. Pair it with an installed-library guard test (assert the hook still exists in
`ElementShape.js`, scoped to the `person` case — the literal recurs in ~6 shape cases) so a
library bump fails CI loudly.

## Key Insight

For a CSS override of a **vendored library** on an **auth/flag-gated** surface, the highest
ROI verification is a reconstructed-DOM harness rendered by the project's own chromium, not
the live flow. Read the DOM contract + CSS recipe straight out of `node_modules` so the
harness is faithful; assert **computed style** (proves cascade victory) before screenshotting
(proves legibility). When Playwright MCP can't launch (Chrome channel absent) or the
`playwright` module's expected build ≠ the cached build, pass an explicit `executablePath` to
the chromium under `~/.cache/ms-playwright/chromium-<build>/`.

Secondary: when re-pointing a tinted SVG icon's `fill` toward the node surface, a flat
surface-fill can tone it out entirely (lost semantic). A low-percentage `color-mix` of the
accent into the surface keeps the icon faintly visible while restoring text contrast.

## Session Errors

1. **Phase 0 grep used the unquoted key form** `data-likec4-fill: "mix-stroke"` → 0 hits.
   Recovery: the JS bundle emits the quoted-key form `"data-likec4-fill": "mix-stroke"`;
   re-grepped. Prevention: grep a short unique substring (`mix-stroke`) first, then read the
   surrounding line for the exact quoting before pinning a literal into a test.
2. **Playwright MCP launch failed — Chrome channel not installed.** Recovery: rendered via
   the project's `playwright` module with an explicit chromium `executablePath`. Prevention:
   for headless rendering, prefer the installed chromium over the MCP Chrome channel.
3. **`playwright` module expected chromium build 1208, cache had 1223.** Recovery: explicit
   `executablePath` to the cached build. Prevention: don't rely on the module's default
   browser resolution when builds drift; point at the installed build directly.
4. **`Edit` failed "File has not been read yet" on `c4-theme.css`** after a skill boundary
   reset the read-state. Recovery: re-Read then Edit. Prevention: re-Read a file in the
   current skill/turn before editing if a boundary may have intervened.
5. **First CSS value over-toned the silhouette to invisible** (flat surface fill + opacity
   0.35). Recovery: the render harness caught it; tuned to `color-mix(... stroke 25%, fill)`.
   Prevention: visually verify icon-tinting CSS, not just the unit gate — a passing
   selector-present test says nothing about whether the icon is still readable.

## Tags
category: ui-bugs
module: apps/web-platform/components/kb
related: 2026-06-04-vendored-library-css-hook-must-be-verified-against-rendered-dom-not-stylesheet

---
type: bug-fix
status: draft
created: 2026-05-06
deepened: 2026-05-06
branch: feat-one-shot-theme-selector-gap-and-fouc-fixes
related_pr: "#3271, #3308"
related_issue: TBD
requires_cpo_signoff: false
---

# Fix Theme Selector Gap, Theme-Switch Animation Mismatch, and Light-Mode FOUC

## Enhancement Summary

**Deepened on:** 2026-05-06
**Sections enhanced:** Research Insights (Issue 2 + Issue 3 cross-validated against external sources), Risks (Chromium-specific note added), Sharp Edges (next-themes parity note added).

### Key Improvements

1. **Issue 2 root cause is industry-validated, not just locally diagnosed.** Tailwind GitHub Discussion #15598 ("Colors not updating synchronously when applying transition-colors property to all elements on Chromium") documents the exact symptom the user reported — Chromium's `transition-colors` repaints elements in DOM-walk order rather than in a single composite frame, producing visible per-element lag against non-transitioning surfaces. The plan's transition-disable approach is the canonical fix; Chromium developers have not committed to changing the rendering behavior. Source: [tailwindlabs/tailwindcss#15598](https://github.com/tailwindlabs/tailwindcss/discussions/15598).
2. **Issue 2 fix matches next-themes' shipping pattern verbatim.** Context7 query against `/pacocoursey/next-themes` confirms `disableTransitionOnChange` is implemented as a transient `<style>* { transition: none !important; }</style>` injection + reflow-forcing `getComputedStyle` call + double-rAF cleanup. The plan's `disableTransitionsForOneFrame` helper mirrors this, with one deliberate difference: it adds `animation-duration: 0s !important;` because Soleur has a `pulse-border` keyframe animation declared in `globals.css:165-172` that next-themes does not have to defend against. Reference: [pacocoursey/next-themes README — Disable transitions on theme change](https://github.com/pacocoursey/next-themes/blob/main/README.md).
3. **Issue 3 fix grounded in Tailwind v4 + CSS-variable interaction semantics.** Tailwind v4's `@theme` directive (used at `globals.css:122-138`) compiles `--color-soleur-*` variables into `var(--soleur-*)` references at every utility class. CSS variables resolve **per-element-at-paint-time**, not at parse-time — so a script-driven `data-theme` attribute change on `<html>` should produce a single repaint with the new var values. The flash window only opens when the script executes AFTER the browser has committed a "first frame." The inline-style hint (`html.style.colorScheme` + `html.style.backgroundColor`) makes the first frame correct regardless of script-vs-stylesheet load timing.
4. **Tailwind v4-specific constraint pinned.** Tailwind v4's `transition-colors` utility does NOT itself emit CSS variables (per Tailwind issue #16639 — `transition-property` theme variables are not yet wired through). This means the plan's helper that injects `* { transition: none !important; }` cannot be replaced with a "set `--tw-transition-property: none` via inline style" alternative — direct CSS override is the only working pattern in v4. Source: [tailwindlabs/tailwindcss#16639](https://github.com/tailwindlabs/tailwindcss/issues/16639).

### New Considerations Discovered

- The existing FOUC-prevention learning (`knowledge-base/project/learnings/best-practices/2026-04-27-critical-css-fouc-prevention-via-static-and-playwright-gates.md`) addresses a **different** FOUC class — Eleventy `<link rel="preload" onload="this.rel='stylesheet'">` async-swap timing — and prescribes static + Playwright screenshot gates. It is adjacent but not directly applicable here. The Next.js theme-FOUC class is mitigated by inline-style hints, not by widening a critical-CSS subset.
- The drift-guard test (Phase 4.2 in this plan) is the analog of that learning's "Layer 2 — static selector-coverage gate" — different mechanism, same intent: prevent the inline `<style>` from drifting silently from the source-of-truth CSS file.

## Overview

Three small theme-system polish bugs surfaced after PRs #3271 (theme toggle + tokens) and #3308 (web-platform tokenization):

1. **Visual gap asymmetry under the theme selector.** In `apps/web-platform/app/(dashboard)/layout.tsx`, the wrapper around the THEME label + `<ThemeToggle />` uses `px-3 pt-3` (12px top padding, **0px bottom padding**) — the toggle's bottom edge butts directly against the next sibling's `border-t`. The "line above the selector" sits 12px from the THEME label; the "line below the selector" sits flush against the toggle. Result: visibly asymmetric vertical rhythm in the sidebar.
2. **Theme-switch animation mismatch.** Surfaces with `transition-colors` (theme-toggle squares, active-page nav indicator, footer links, conversations-rail rows, many chat surfaces) animate their background/border/text from the old palette to the new over Tailwind's default 150ms `transition-duration`. The `<body>` background and most non-transitioning surfaces snap instantly because they consume `var(--soleur-bg-*)` directly with no `transition` declaration. The user perceives this as "some elements switch theme at a different speed than the rest of the page."
3. **Light-mode FOUC on reload.** When a user with stored `theme="light"` reloads, certain buttons briefly render with the dark palette before snapping to light. Root cause: the inline `<NoFoucScript>` (`components/theme/no-fouc-script.tsx`) writes `<html data-theme="light">` synchronously during head parse, but the browser has already begun computing styles against the default `:root` cascade (which declares dark vars). Whether this produces a visible flash depends on whether the script executes before any "first paint" the browser flushes after the stylesheet loads. On Light reloads in particular, the dark `--soleur-bg-base: #0a0a0a` resolves into Tailwind utilities like `bg-soleur-bg-surface-1` on individual buttons, producing a one-frame dark flash. The body background is also affected but the user notices buttons more (higher contrast against the eventual light surface).

All three fixes are scoped to the theme system itself and to `(dashboard)/layout.tsx`. No business logic, no DB, no API. Pure CSS/JSX/inline-script changes.

## Research Reconciliation — Spec vs. Codebase

| Claim from prompt | Codebase reality (2026-05-06 worktree) | Plan response |
|---|---|---|
| "Line under selector doesn't have same gap as line above" | `app/(dashboard)/layout.tsx:327` wrapper is `border-t border-soleur-border-default px-3 pt-3` (no `pb-*`); the next sibling at line 336 is `border-t ... ${collapsed ? "p-1" : "p-3"}`. The toggle's bottom edge has 0px padding before the next border-t. The label/toggle's top has `pt-3` + a `pb-2` on the label. | Add `pb-3` to the wrapper so the gap below mirrors `p-3` of the footer. Verified: no other sibling pattern depends on the wrapper having zero bottom padding. |
| "Squares in theme selector switch theme at different speed" | `theme-toggle.tsx:73` button has `transition-colors`; CSS-variable-driven background swaps take 150ms (default `transition-duration` for `transition-colors`). Body and other non-transitioning surfaces snap instantly. | Disable transitions for one paint frame around `setTheme()` writes. Implements the well-known next-themes "disable transition on theme change" pattern via a transient `<style>* { transition: none !important; }</style>` injected in `theme-provider.tsx`. |
| "Currently-selected page indicator in dashboard" lags | `app/(dashboard)/layout.tsx:289` Link uses `transition-colors`; the active variant `bg-soleur-bg-surface-2 text-soleur-text-primary` interpolates over 150ms. | Same fix as above (one-frame transition disable) covers this and every other `transition-colors` consumer. |
| "Buttons flash dark→light on Light-mode reload (FOUC)" | `<NoFoucScript>` sets `<html data-theme=…>`. CSS link is also in head; if the link is parsed before the script, the script blocks until stylesheet loads. In some browser/cache states this produces a flash. Today, the inline script does **not** set `<html style.colorScheme>` or `<html style.backgroundColor>` directly. | Have the inline script ALSO set `documentElement.style.colorScheme` and `documentElement.style.backgroundColor` synchronously. These computed values bypass stylesheet load timing and remove the flash window without altering CSS-variable resolution semantics. |

## User-Brand Impact

**If this lands broken, the user experiences:** A theme toggle that visibly stutters on every switch (mismatched fade + snap) plus a flash on every Light-mode reload. Reads as "the theme feature is half-finished." For Forge users this is invisible; for Light users it is the first impression of every page load.
**If this leaks, the user's [data / workflow / money] is exposed via:** Not applicable — this is a pure visual/styling change. No new code paths handle credentials, payments, or user data.
**Brand-survival threshold:** none

This change carries no data-exposure or single-user-incident risk. It is a visual quality bar enforcement against features already shipped publicly in #3271 and #3308.

## Research Insights

### Issue 1 — Sidebar vertical-rhythm baseline

The dashboard sidebar uses three sibling sections separated by `border-t border-soleur-border-default`:

| Section | Padding | Comment |
|---|---|---|
| Navigation list (lines 277-302) | `space-y-1 px-3` (no top/bottom in the nav itself) | The first border-t lives on the nav-collapse button row above, not the nav. |
| **Theme block (lines 326-333)** | `px-3 pt-3` | Asymmetric — top 12px, bottom 0. Bug. |
| Footer links (lines 336-385) | `p-3` (collapsed: `p-1`) | Top + bottom 12px. Reference rhythm. |

The theme block's `pb-2` on the label adds 8px below the label; the toggle then sits with 0px below before the footer's `border-t`. Footer's `p-3` puts the email/Status link 12px below the border. **Fix is local — make the theme block `px-3 py-3` (or `p-3`).** No collapsed-state code path because the entire theme block is gated on `!collapsed`.

### Issue 2 — Transition-colors interaction with theme switch

Every `transition-colors` consumer animates `background-color`, `color`, `border-color`, `fill`, `stroke`, `text-decoration-color` for `150ms` (Tailwind v4 default). When `<html data-theme>` flips, the CSS variables under `bg-soleur-bg-surface-*` recompute, which **does** trigger a transition on those properties because the property's computed value changed.

Surfaces with `transition-colors` in scope (representative — not exhaustive):

```
apps/web-platform/components/theme/theme-toggle.tsx:73
apps/web-platform/app/(dashboard)/layout.tsx:289      # nav links (active page indicator)
apps/web-platform/app/(dashboard)/layout.tsx:350      # Status footer link
apps/web-platform/app/(dashboard)/layout.tsx:358      # Sign out button
apps/web-platform/components/chat/conversations-rail.tsx:67
# ...30+ other component files use transition-colors per `rg -l 'transition-colors' apps/web-platform`
```

**Mitigation options considered:**

1. **Remove `transition-colors` from theme-bound surfaces.** Rejected — the transition is correct for hover/focus/state changes; only the theme-switch case is unwanted.
2. **Add `transition-colors` globally to body/all elements.** Rejected — applies the 150ms ramp universally to bg-base too, making the WHOLE page do the slow ramp. Brand goal is instant theme switch.
3. **Disable transitions for one frame around `setTheme()` writes.** Selected. This is the [next-themes `disableTransitionOnChange`](https://github.com/pacocoursey/next-themes/blob/main/README.md) pattern — inject a `<style>` element with `* { transition: none !important; }` before the `data-theme` attribute change, force a reflow, then remove the style on the next animation frame. The browser commits the theme change as a single paint with no animation. Hover transitions resume after the next frame.

**Browser-engine note (Chromium).** [Tailwind GitHub Discussion #15598](https://github.com/tailwindlabs/tailwindcss/discussions/15598) documents that on Chromium-based browsers, `transition-colors` repaints affected elements **sequentially in DOM-walk order** rather than in a single composite frame — so even when every transition-bound element has the same `duration-150`, they visibly cascade. Firefox and Safari composite the changes more uniformly. This is the engine-level reason a non-transitioning surface (body bg) appears to "snap" while transition-bound elements "fade" out of sync. The disable-on-change pattern bypasses the bug entirely by removing the transition declaration during the data-theme write — no per-element ramp, no DOM-order cascade. Verified at `apps/web-platform/components/theme/theme-toggle.tsx:73`, `app/(dashboard)/layout.tsx:289`, and `components/chat/conversations-rail.tsx:67`, all of which use `transition-colors`.

**Tailwind v4 constraint.** Per [tailwindlabs/tailwindcss#16639](https://github.com/tailwindlabs/tailwindcss/issues/16639), the `transition-property` family does NOT yet expose CSS-variable theme overrides in Tailwind v4 — `--tw-transition-property` is not a writable token. So the only working override is a direct CSS rule `* { transition: none !important; }` injected into the document. A future Tailwind v4 release that exposes `transition-property` as a token may permit a cleaner `style.setProperty('--tw-transition-property', 'none')` approach; not available today.

The implementation lives in `theme-provider.tsx`'s `setTheme` callback. Cross-tab sync (the `storage` event handler) ALSO writes `data-theme` indirectly via the `setThemeState` → effect chain — apply the same suppression there too, otherwise tab B's theme change still animates in tab A.

### Issue 3 — Light-mode reload FOUC mechanics

Three relevant facts:

1. **HTML parse-and-paint timing.** Per the HTML spec, a `<script>` element in `<head>` is blocked from executing until any preceding `<link rel="stylesheet">` has loaded ([WHATWG HTML §4.12.1 — "currently parsed style sheets"](https://html.spec.whatwg.org/multipage/scripting.html#parsing-main-inscript)). If Next.js injects its compiled `globals.css` link **before** our `<NoFoucScript>` element in the served HTML, the inline script runs only after the stylesheet has been fetched and applied. Until that point, the browser may have already started computing styles against the cascade — and may, on some engines / cache states, paint a "first contentful frame" with the default cascade resolution.
2. **Default cascade resolution without `data-theme`.** The current `globals.css` has `:root, :root[data-theme="dark"] { ...dark vars }` AND `@media (prefers-color-scheme: light) { :root:not([data-theme]) { ...light vars } }`. So a Light-OS user sees light vars even with no `data-theme`; a Dark-OS user with stored Light preference sees DARK vars until the script runs. **The reported flash is most likely on Dark-OS Light-preference users.** Confirm during QA.
3. **`color-scheme` property.** Setting `style.colorScheme = "light"` on `<html>` immediately tells the browser to use light system colors for form controls, scrollbars, and the default `<body>` background fallback. It is independent of stylesheet load timing because it's a direct inline style.

**Fix — augment `<NoFoucScript>` to write inline style attributes in addition to `data-theme`:**

```js
(function () {
  try {
    var v = localStorage.getItem("soleur:theme");
    if (v !== "dark" && v !== "light" && v !== "system") {
      v = "system";
    }
    var html = document.documentElement;
    html.dataset.theme = v;

    // Resolve the effective palette for the inline pre-paint hint.
    // For "system", read prefers-color-scheme. The matchMedia call is
    // synchronous and safe in a head script.
    var effective = v;
    if (v === "system") {
      effective = (window.matchMedia &&
        window.matchMedia("(prefers-color-scheme: light)").matches)
        ? "light" : "dark";
    }

    // Inline pre-paint hint — bypasses stylesheet load timing entirely.
    // Color-scheme tells the browser which system colors to use for form
    // controls, scrollbars, and the default <body> background. Setting
    // backgroundColor on <html> ensures the very first paint matches the
    // resolved palette even if globals.css is still loading.
    html.style.colorScheme = effective === "light" ? "light" : "dark";
    html.style.backgroundColor = effective === "light" ? "#fbf7ee" : "#0a0a0a";
  } catch (_e) {
    document.documentElement.dataset.theme = "system";
  }
})();
```

The hex literals (`#fbf7ee`, `#0a0a0a`) duplicate the values declared in `:root[data-theme="light"]` and `:root[data-theme="dark"]` for `--soleur-bg-base`. **Drift class:** if `globals.css` changes those hexes (e.g., a brand-guide refresh), the inline script's literals must update in lockstep. Add a comment in the script AND a regression test that asserts the values match.

### Connection between issues 2 and 3

The same `transition-colors` consumers that lag on a USER theme toggle (issue 2) ALSO contribute to the visible FOUC on reload (issue 3) — the inline script's `data-theme` write triggers transitions on every consumer. With the inline-style hint added (issue 3 fix), `<html>` gets the right backgroundColor instantly; but child surfaces like nav links, theme-toggle squares, etc. still use CSS-variable-resolved colors that may transition over their initial render. The transition-disable-on-change pattern (issue 2 fix) **must also be applied at boot** — wrap the inline script's logic in a one-frame transition-disabler too, so nothing animates on first paint. Implementation: inject the `<style>* { transition: none !important; }</style>` from the inline script itself, removed via `requestAnimationFrame` after first paint.

This means the inline script grows from ~10 lines to ~25 lines and includes a transient style injection. Total payload is still well under 1 KB minified — negligible for TTFCP.

## Implementation Phases

### Phase 1 — Sidebar Gap Fix

**File:** `apps/web-platform/app/(dashboard)/layout.tsx`

- [x] 1.1 Change line 327 from `className="border-t border-soleur-border-default px-3 pt-3"` to `className="border-t border-soleur-border-default p-3"` (or `px-3 py-3` for consistency with the footer's pattern).
- [x] 1.2 Verify the THEME label's `pb-2` still produces the intended 8px below the label before the toggle (no change needed).
- [ ] 1.3 Visual confirm: above-toggle gap (border-t → label) and below-toggle gap (toggle → border-t) are now 12px each.

### Phase 2 — Transition Disable on Theme Change

**File:** `apps/web-platform/components/theme/theme-provider.tsx`

- [ ] 2.1 Add a `disableTransitionsForOneFrame()` helper inside the module:

  ```ts
  function disableTransitionsForOneFrame() {
    if (typeof document === "undefined") return;
    const style = document.createElement("style");
    // Cover every property `transition-colors` / `transition-all` /
    // `transition-[<prop>]` could animate. `* { transition: none ... }`
    // covers them all uniformly. The !important neutralises any
    // component-level specificity. `pointer-events: none` is NOT added —
    // the user can still interact during the suppression window; we only
    // freeze color animations.
    style.textContent = `* { transition: none !important; animation-duration: 0s !important; }`;
    document.head.appendChild(style);
    // Force a style recalc so the transition: none is committed BEFORE
    // the data-theme attribute flips. Reading getComputedStyle on a
    // non-pseudo element is the standard reflow-forcing trick.
    void window.getComputedStyle(document.body).opacity;
    // Remove on the next paint — double-rAF gives the browser one full
    // frame to commit the theme change without animation.
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        style.remove();
      });
    });
  }
  ```

- [ ] 2.2 Call `disableTransitionsForOneFrame()` at the top of:
  - The `useEffect` block that writes `document.documentElement.dataset.theme = theme` (currently lines 76-78).
  - The `setTheme` callback (currently lines 125-140) before `setThemeState(next)`.
  - The cross-tab `onStorage` handler (currently lines 103-122) before `setThemeState(next)`.
  - The `prefers-color-scheme` media-query handler when `theme === "system"` (currently lines 92-99) — when the OS flips, the same flicker applies.

- [ ] 2.3 Verify there is no double-disable nesting (e.g., setTheme triggers the effect which would re-disable). The first call attaches a `<style>`; if a second call lands inside the same frame, it appends a second `<style>` element. Both are removed independently across two rAFs. This is benign but slightly wasteful — a guard `if (document.getElementById("__soleur-no-transition")) return;` with a unique id solves it.

### Phase 3 — Light-Mode FOUC Fix

**File:** `apps/web-platform/components/theme/no-fouc-script.tsx`

- [ ] 3.1 Replace the `SCRIPT` constant with the augmented version (see Research Insights → Issue 3). It must:
  - Resolve `effective` palette (light/dark) by reading `prefers-color-scheme` for "system".
  - Set `documentElement.style.colorScheme`.
  - Set `documentElement.style.backgroundColor` to the literal hex of `--soleur-bg-base` for the resolved palette.
  - Inject a transient `<style id="__soleur-no-transition">* { transition: none !important; animation-duration: 0s !important; }</style>` into `<head>` and remove it via double-rAF, mirroring the runtime helper. This prevents first-paint transitions on hydration when React mounts and consumers compute their own initial colors.

- [ ] 3.2 Add an inline comment naming `--soleur-bg-base` value drift as a Sharp Edge — the hex literals in this script duplicate `globals.css` and must move together.

- [ ] 3.3 Confirm the inline-style hint clears once React's hydration runs OR at the moment the `<style id="__soleur-no-transition">` is removed. Ideally the inline `style.backgroundColor` is removed as part of the post-rAF cleanup, OR set on a `<html data-theme-bootstrapping>` attribute that's removed in a `useEffect` after first paint. **Prefer: remove `style.backgroundColor` and `style.colorScheme` after the first rAF as well, so future CSS-only theming (e.g., a future `:root[data-theme="dim"]`) is not pinned by an inline override.**

  Implementation choice: keep `style.colorScheme` (browser defaults benefit from this — scrollbars, autofill) but clear `style.backgroundColor` after first rAF; the body/`html` will then resolve via the now-correct CSS cascade.

### Phase 4 — Tests

**File (new):** `apps/web-platform/test/components/theme-no-fouc-script.test.tsx`

- [ ] 4.1 Unit-test the augmented `<NoFoucScript>` script string for:
  - Contains `style.colorScheme` write.
  - Contains `style.backgroundColor` write.
  - Contains both light hex (`#fbf7ee`) and dark hex (`#0a0a0a`) literals (drift-guard).
  - Contains the `__soleur-no-transition` id.
  - Calls `localStorage.getItem("soleur:theme")` exactly once.
  - Falls back to `"system"` on invalid stored values.

  These are string-match assertions on the SCRIPT constant; no JSDOM execution required because the script is rendered via `dangerouslySetInnerHTML` as a static string.

- [ ] 4.2 Add a "hex literal parity" assertion that reads `apps/web-platform/app/globals.css` and confirms the `--soleur-bg-base` declarations for `:root[data-theme="light"]` and `:root[data-theme="dark"]` match the script's literal strings. This is the drift-guard for the Sharp Edge in Phase 3.2.

  ```ts
  import { describe, expect, it } from "vitest";
  import { readFileSync } from "node:fs";
  import { resolve } from "node:path";

  const SCRIPT_FILE = resolve(__dirname, "../../components/theme/no-fouc-script.tsx");
  const CSS_FILE = resolve(__dirname, "../../app/globals.css");

  describe("no-fouc-script hex literal drift-guard", () => {
    it("script literals match globals.css --soleur-bg-base values", () => {
      const script = readFileSync(SCRIPT_FILE, "utf8");
      const css = readFileSync(CSS_FILE, "utf8");

      // Extract --soleur-bg-base from :root[data-theme="dark"] and "light" blocks.
      const lightMatch = css.match(/\[data-theme="light"\][^}]*--soleur-bg-base:\s*([^;]+);/);
      const darkMatch = css.match(/\[data-theme="dark"\][^}]*--soleur-bg-base:\s*([^;]+);/);

      expect(lightMatch?.[1]?.trim()).toBeTruthy();
      expect(darkMatch?.[1]?.trim()).toBeTruthy();
      expect(script).toContain(lightMatch![1].trim());
      expect(script).toContain(darkMatch![1].trim());
    });
  });
  ```

**File (extend):** `apps/web-platform/test/theme-provider.test.tsx`

- [ ] 4.3 Add a unit test that calling `setTheme("light")` from `useTheme()` injects a `<style>` element with `transition: none` into `document.head`, and that the style is removed after two animation frames. Use JSDOM's `document.head.querySelectorAll("style")` to inspect, and a `requestAnimationFrame` polyfill (existing test file may already have one — verify in Phase 1 of /work).

### Phase 5 — Visual QA

- [ ] 5.1 Local: `bun run dev` (or whichever script `apps/web-platform/package.json` exposes), open `http://localhost:3000`, log in.
- [ ] 5.2 Sidebar gap: with sidebar expanded, screenshot the THEME block in both Forge and Radiance. Verify above-toggle and below-toggle gaps are visually equal (12px each).
- [ ] 5.3 Theme switch animation: with the dashboard route open AND a chat conversation visible (so conversations-rail rows are mounted), toggle Forge → Radiance → System. Confirm:
  - Theme-toggle squares change instantly with the rest of the page.
  - The active-page nav indicator changes instantly.
  - Conversations-rail rows change instantly.
  - Chat-message bubbles change instantly.
  - Hover transitions still feel smooth on subsequent pointer-overs.
- [ ] 5.4 Light-mode FOUC: in DevTools, force-reload (Cmd+Shift+R) on a Light-mode page on a dark-OS machine (or simulate via DevTools → Rendering → Emulate prefers-color-scheme: dark). Watch for any dark frame on page load. With Network throttling at "Fast 3G" the flash window is widest — easiest to detect.
- [ ] 5.5 Save before/after screenshots under `knowledge-base/product/design/theme-toggle/screenshots/2026-05-06-{gap,switch,fouc}-{before,after}.png`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/app/(dashboard)/layout.tsx`: theme block wrapper has equal top + bottom padding (`p-3` or `py-3 px-3`).
- [ ] `apps/web-platform/components/theme/theme-provider.tsx`: `setTheme()`, the data-theme effect, the cross-tab `storage` handler, and the `prefers-color-scheme` listener all call `disableTransitionsForOneFrame()` before mutating theme.
- [ ] `apps/web-platform/components/theme/no-fouc-script.tsx`: inline script writes `style.colorScheme` and `style.backgroundColor` synchronously; injects a transient `transition: none` style; cleans up after double-rAF.
- [ ] New test `apps/web-platform/test/components/theme-no-fouc-script.test.tsx` passes; existing theme tests continue to pass.
- [ ] `bun test apps/web-platform/test/` green.
- [ ] `tsc --noEmit` clean.
- [ ] Visual QA screenshots committed under `knowledge-base/product/design/theme-toggle/screenshots/` for the three issues × before/after (6 PNGs minimum).
- [ ] PR body references `Ref #3271, #3308` (no `Closes` — these PRs were merged separately; this is a follow-up polish).

### Post-merge (operator)

- [ ] None. CSS/inline-script change with no migrations, deploys, or external service mutations.

## Risks

- **Transition-disable affects every transition, not just theme-bound ones.** During the one-frame suppression window, any in-flight hover transition snaps to its end state. Acceptable — the window is one paint frame (~16ms at 60Hz). If a user happens to toggle theme while hovering an element, the hover effect appears instantly instead of fading, which is imperceptible.
- **Inline-style hint pins `<html>` background until removed.** If the rAF cleanup fails to fire (e.g., the page is hidden via `display: none` before paint, or DevTools throttles rAF), the inline `style.backgroundColor` persists. CSS-cascade-driven background still applies to descendants but the `<html>` element shows the literal hex. Mitigation: prefer setting `style.colorScheme` permanently (browser system colors only) and clearing `style.backgroundColor` after rAF — the cascade then takes over.
- **Hex-literal drift.** The inline script duplicates `--soleur-bg-base` from `globals.css`. A brand-guide palette refresh that updates the hex without updating the script will produce a one-frame mismatch on Light-mode reload. The Phase 4.2 drift-guard test catches this at CI time.
- **`prefers-color-scheme` query during head parse.** Some browsers may not have the `matchMedia` API available synchronously at the moment the inline head script runs. The current script wraps `localStorage` in try/catch; the new script must wrap `matchMedia` similarly and default to dark on failure (matching the existing fallback behavior).
- **Cross-tab sync now triggers transition disable in the OTHER tab.** Tab A's setTheme writes localStorage; tab B's `storage` event fires → disableTransitionsForOneFrame runs in tab B too. This is desired behavior — the same instant-switch invariant should hold cross-tab. No new risk.
- **Test runner crash on JSDOM rAF polyfill.** `apps/web-platform/test/theme-provider.test.tsx` may not yet polyfill `requestAnimationFrame`. If absent, add a simple `globalThis.requestAnimationFrame = (cb) => setTimeout(cb, 0)` polyfill at the top of the file.
- **Theme-toggle `transition-colors` may still feel right on its OWN hover.** Removing `transition-colors` from the toggle would lose the hover smoothness for pointer-overs. The disable-on-theme-change approach preserves hover smoothness — verify this in QA and do NOT regress to "remove transition-colors entirely."
- **Chromium-only sequential repaint of `transition-colors`.** Per Tailwind Discussion #15598, Chromium repaints transition-bound elements in DOM-walk order, not as a single composite frame. The disable-on-change pattern bypasses this — no transition is in effect during the theme write — so the bug is mitigated, not relied upon. If a future Chromium release fixes #15598, the disable-helper remains correct (no behavior change). If a future Chromium release introduces a NEW divergence (e.g., `requestAnimationFrame` ordering changes), the helper's double-rAF cleanup may need a revisit. Track upstream.
- **Two parallel timers (transition-disable + inline-style hint).** The boot script's transient `<style id="__soleur-no-transition">` and the runtime helper's transient `<style>` are separate elements with separate cleanup schedules. If a user toggles theme within ~16ms of page load, the runtime helper appends a second style; the boot helper's rAF removes its own element while the runtime element persists for another rAF cycle. Both are valid; both clean up. Verify there's no orphaned `__soleur-no-transition` element after a settling test (e.g., toggle + wait 100ms, expect zero matching `<style>` in DOM).

## Sharp Edges

- **Hex-literal drift between `globals.css` and `no-fouc-script.tsx`.** The inline script duplicates `--soleur-bg-base` for both palettes. Phase 4.2 drift-guard test enforces parity, but reviewers must remember to update both files in any palette refresh.
- **`pb-3` vs `py-3` choice.** Use `p-3` (or `px-3 py-3`) to match the footer's `p-3` exactly. Mixing `px-3 pt-3 pb-3` works but reads as "the bug fix that forgot it could be `p-3`."
- **`disableTransitionsForOneFrame` must NOT add `pointer-events: none`.** The next-themes library historically did; user keyboard nav during the suppression window should remain functional. The version in this plan deliberately omits `pointer-events`.
- **`__soleur-no-transition` style id collision.** The runtime helper and the inline boot script BOTH inject styles with this id. The runtime helper checks `if (document.getElementById("__soleur-no-transition")) return;` — but at boot the inline script's element may still be present when the runtime helper first runs (e.g., a fast user toggle within 16ms of page load). Document this benign overlap; the runtime helper should NOT clobber the inline script's element if it's already there — bail early.
- **No `dark:`-prefix Tailwind classes added.** Per PR #3271 + #3308 architecture (`@custom-variant dark` pinned to `[data-theme="dark"]`), the theme system uses single tokenized classes that respond to `<html data-theme>`. Do not add `dark:bg-zinc-900 light:bg-amber-50` pairs to fix any of these issues.
- **The inline script may execute after first paint on some browsers.** The augmentation (writing inline style attributes) defends against this case, but does not GUARANTEE no flash. Visual QA on Network-throttled reload is the only confirmation. If a residual flash remains, a follow-up issue can explore moving CSS to a synchronous inline `<style>` block in head (rejected here for bundle size).
- **Per AGENTS.md `cq-write-failing-tests-before` (TDD), the new test must land in a commit BEFORE the implementation.** Write the drift-guard test (Phase 4.2) first against the CURRENT (regex won't match because the literals aren't there yet) — the test fails RED. Then add the script changes (Phase 3.1) to make it pass GREEN.
- **Per AGENTS.md `hr-when-a-plan-specifies-relative-paths-e-g`, every Phase file path was verified at plan time** via `Read` of `app/(dashboard)/layout.tsx`, `components/theme/theme-toggle.tsx`, `components/theme/theme-provider.tsx`, `components/theme/no-fouc-script.tsx`, `app/layout.tsx`, and `app/globals.css`.
- **`color-scheme: light` on `<html>` reveals system-color form controls.** This is desired. But existing custom-styled inputs (e.g., the chat input) must NOT visibly regress in Light mode — verify in Phase 5.3.
- **next-themes parity.** Soleur's theme system is a hand-rolled equivalent of `next-themes` (no dependency on the library). The disable-transition helper added in Phase 2 is a hand-port of next-themes' `disableTransitionOnChange` behavior. If Soleur ever migrates to `next-themes` directly, the helper becomes the `disableTransitionOnChange` prop on `<ThemeProvider>` and the inline-script logic moves to the library's `<Script id="next-themes" />` shipping pattern. Track this as a deferred refactor option; do NOT add `next-themes` as a dependency in this PR.
- **`animation-duration: 0s !important` is added in addition to `transition: none`** because `globals.css:165-172` declares a `pulse-border` keyframe used by `.message-bubble-active`. Without the animation override, an active message bubble would mid-pulse during a theme switch, momentarily desaturating before the disable lifts. next-themes does not need this rule because it doesn't ship keyframe animations; Soleur does.

## Domain Review

**Domains relevant:** Product/UX (advisory)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (auto-accepted in pipeline)
**Skipped specialists:** ux-design-lead (auto-accepted in pipeline; visual QA in Phase 5 covers screenshot validation)
**Pencil available:** N/A

#### Findings

This plan modifies **existing** UI surfaces with no new pages, modals, or flows. It corrects a layout-rhythm bug, an animation-timing bug, and a FOUC bug. The visual contract is the Radiance/Forge palette already chosen and shipped in PR #3271. Phase 5 visual QA validates the fixes preserve brand-aligned color behavior — no new design surface to review.

Per the plan skill's pipeline-mode rule for ADVISORY tier, the gate auto-accepts and proceeds with documented visual-QA gating in Phase 5 instead of a fresh ux-design-lead Pencil session.

## Open Code-Review Overlap

None — this plan touches only `app/(dashboard)/layout.tsx` (single line of CSS classes), `components/theme/theme-provider.tsx`, `components/theme/no-fouc-script.tsx`, and one new test file. No open `code-review`-labeled issues match these paths as of plan time.

## Test Scenarios

1. **Sidebar gap** (visual): with sidebar expanded, the THEME block has 12px above the label and 12px below the toggle. Both gaps match the footer's `p-3` rhythm.
2. **Theme-switch animation** (visual): toggling theme while a dashboard chat session is open changes every visible surface (theme-toggle squares, active nav indicator, footer links, chat bubbles, conversations-rail rows) in the same paint frame as the body background.
3. **Hover-transition preservation** (visual): after the theme switch completes, hovering a nav link still produces the smooth `transition-colors` 150ms fade.
4. **Light-mode reload, Light-OS user** (visual): force-reload `/dashboard` with stored `theme="light"` and OS preference light. No dark frame visible at any throttle setting up to "Fast 3G."
5. **Light-mode reload, Dark-OS user** (visual): force-reload `/dashboard` with stored `theme="light"` and OS preference dark. No dark frame visible — this is the case the inline-style hint primarily defends.
6. **System-mode reload, Light-OS user** (visual): force-reload `/dashboard` with stored `theme="system"` and OS preference light. Page renders Radiance with no dark frame.
7. **Drift-guard test (CI)**: the hex-literal parity test fails RED if `globals.css` changes `--soleur-bg-base` for either palette without the script being updated.
8. **`setTheme` transition-disable test (CI)**: calling `setTheme("light")` in JSDOM injects a `<style>` element with `transition: none` and removes it within two animation frames.
9. **Cross-tab sync transition-disable (manual or CI)**: a `storage` event with key `soleur:theme` triggers the same disable behavior.
10. **No-FOUC script string assertions (CI)**: the SCRIPT constant contains `style.colorScheme`, `style.backgroundColor`, both palette hexes, and `__soleur-no-transition`.

## Commit Strategy

Recommended: 4 commits on the feature branch.

1. `test: add no-fouc-script drift-guard and theme-provider transition-disable tests` — RED state. New test file + extension to `theme-provider.test.tsx`.
2. `fix(theme): equal vertical padding around theme block in dashboard sidebar` — Phase 1, single-line CSS class change.
3. `fix(theme): disable CSS transitions for one frame on theme change` — Phase 2, runtime helper + four call sites in `theme-provider.tsx`.
4. `fix(theme): inline-style hint and transient transition disable in NoFoucScript` — Phase 3, augments the inline script. Tests now GREEN.

After commit 4, all CI tests pass and visual QA can run. Each commit is independently reviewable and revertable.

## Files to Edit

- `apps/web-platform/app/(dashboard)/layout.tsx` — line 327 className change.
- `apps/web-platform/components/theme/theme-provider.tsx` — add helper, call from four hook sites.
- `apps/web-platform/components/theme/no-fouc-script.tsx` — augment inline script string.
- `apps/web-platform/test/theme-provider.test.tsx` — add transition-disable assertions.

## Files to Create

- `apps/web-platform/test/components/theme-no-fouc-script.test.tsx` — new unit + drift-guard test.
- `knowledge-base/product/design/theme-toggle/screenshots/2026-05-06-{gap,switch,fouc}-{before,after}.png` — 6 visual QA screenshots captured during Phase 5.

## Out of Scope (deferred)

- Tokenizing remaining literal-gray surfaces — covered by PRs #3271 / #3308. Any residual hardcoded grays that surface during Phase 5 visual QA should be filed as follow-ups, not folded in.
- Adding `--soleur-status-{danger,warning,success,info}` tokens. Status color theming was deferred from #3308; revisit only if Phase 5 shows status-color contrast issues against Radiance.
- Replacing `transition-colors` with custom transitions per surface. The disable-on-change pattern covers the systemic concern; per-surface tuning can be a follow-up if needed.
- Eleventy docs site theming — different rendering pipeline, out of scope.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-06-fix-theme-selector-gap-and-fouc-plan.md. Branch: feat-one-shot-theme-selector-gap-and-fouc-fixes. Worktree: .worktrees/feat-one-shot-theme-selector-gap-and-fouc-fixes/. Issue: TBD (follow-up polish to #3271/#3308). Plan reviewed, implementation next.
```

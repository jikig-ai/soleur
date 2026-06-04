---
title: "A vendored-library CSS class existing in styles.css does NOT mean the component renders it — verify against the JS that emits the element"
date: 2026-06-04
category: ui-bugs
tags: [css, vendored-library, likec4, dom-hooks, scoped-styling, review-catch]
module: apps/web-platform/components/kb
pr: 4938
---

# Learning: vendored-library CSS hooks must be verified against the rendered DOM, not the stylesheet

## Problem

Re-theming the LikeC4 C4 visualizer required hiding the upstream "LikeC4" wordmark
via scoped CSS. The plan picked the selector `.likec4-navigation-panel__logo` and
"verified" it by confirming the class is present in the installed
`@likec4/diagram/styles.css` (`grep -o 'likec4-navigation-panel__logo' …` returned
a hit). The implementation shipped `.soleur-c4 .likec4-navigation-panel__logo {
display: none }` and a source-grep test that asserted the selector text was present
in our CSS file. Typecheck + unit tests were green.

**The selector matched zero elements in the diagram.** AC1 ("logo not visible") was
silently unmet — the whole point of the PR — and no automated gate caught it.

## Root Cause

A class appearing in a compiled stylesheet only proves a *rule* exists; it does NOT
prove any rendered component carries that class. In `@likec4/diagram@1.50.0`:

- `.likec4-navigation-panel__logo` is a PandaCSS recipe-slot class
  (`@likec4/styles/.../navigation-panel.mjs`) consumed by `components/NavigationPanel.js`
  — used only by the **projects-overview** panel, NOT the diagram.
- The diagram's logo is rendered by `navigationpanel/controls/LogoButton.js`, which
  emits a Mantine `<UnstyledButton>` (a class-less `<button>`) wrapping
  `<Logo>` / `<LogoIcon>` from `components/Logo.js` — plain `<svg>` elements with
  atomic `css({…})` classes and **no BEM class**.

So the stylesheet-grep "verification" validated the wrong component's class.

## Solution

Re-target the actual rendered DOM. `LogoButton` has no stable class, but `<Logo>`
renders the brand `<svg viewBox="0 0 222 56">` (full wordmark) and that viewBox is
**unique across the entire library** (grep of `dist/` returns one file). Use `:has()`
to collapse the whole button:

```css
.soleur-c4 button:has(svg[viewBox="0 0 222 56"]) { display: none !important; }
/* defense-in-depth if :has() is unavailable: blank the unique wordmark art */
.soleur-c4 svg[viewBox="0 0 222 56"] { display: none !important; }
```

And convert the brittle coupling into a guarded one: a test reads the installed
`@likec4/diagram/dist/components/Logo.js` and asserts `viewBox: "0 0 222 56"` still
exists, so a library bump that redraws the logo fails CI instead of silently
un-hiding it.

## Key Insight

When targeting a third-party library's internal DOM via CSS, the verification step
must trace the **component that emits the element** (the JS in `dist/`), not the
presence of a class name in the compiled `styles.css`. Stylesheets carry rules for
*every* component the library ships; only the rendered component proves which class
your target actually wears. The cheap gate: `grep` the JSX-emitting `dist/*.js` for
the `className`/`data-*`/tag you intend to select, and prefer an intrinsic, unique
attribute (a logo's `viewBox`, a fixed `role`, a `data-*` the component sets) over a
recipe-slot class that may belong elsewhere.

Corollary: a source-grep test that asserts "our CSS contains selector X" is vacuous
for this failure class — it passes even when X matches nothing. Pair it with a guard
that reads the installed library and asserts the hook X targets still exists.

## Session Errors

1. **Logo-hide selector targeted a stylesheet-only class, not the rendered DOM.**
   Recovery: `architecture-strategist` traced `LogoButton.js` → found the BEM class
   belongs to a different component; re-targeted via the unique `viewBox` `:has()`
   selector (commit `1dd8017d`). **Prevention:** when a plan/impl selects a vendored
   library's internal DOM hook, grep the JSX-emitting `dist/*.js` for the
   class/attr/tag and confirm the *target* component renders it — never accept
   "the class is in styles.css" as proof. Add a CI guard reading the installed
   component so a library bump fails loudly.

## Tags
category: ui-bugs
module: apps/web-platform/components/kb

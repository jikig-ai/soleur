---
title: "Playwright x-alignment assertions must measure the visible glyph, not the element border-box"
date: 2026-06-03
category: test-failures
module: apps/web-platform/e2e
tags: [playwright, e2e, layout, flexbox, bounding-box, css]
branch: feat-one-shot-workspace-selector-nav-overflow
---

# Learning: Playwright x-alignment — measure the glyph, not the element box

## Problem

A new e2e assertion in `nav-states-shell.e2e.ts` checked that the nav rail's
"Back to menu" affordance shares the brand-row collapse-toggle's left gutter:

```ts
const backBox = await railBand(page).getByTestId("nav-back-chevron").boundingBox();
const collapseBox = await page.getByRole("button", { name: "Collapse sidebar" }).boundingBox();
expect(Math.abs(backBox!.x - collapseBox!.x)).toBeLessThanOrEqual(6); // got 12
```

It failed with a 12px delta even though the controls were visually aligned at
the `px-3` (12px) gutter and the fix (unifying the brand row `px-5 → px-3`) was
correct.

## Root cause

`boundingBox()` returns the **border-box**, and the two elements carry their
`px-3` differently:

- The back affordance is a `<Link className="flex ... px-3 ...">` that, as a
  flex item of a `flex-col` parent, **stretches to full rail width**. Its
  border-box left edge sits at the rail edge (x≈0) and its `px-3` is *internal*
  padding — the glyph lands at x≈12.
- The collapse toggle is a zero-padding `h-6 w-6` button inside a `px-3` row.
  Its border-box left edge IS the gutter (x≈12); the glyph is centered inside,
  at x≈16.

So border-box-to-border-box = 12px (the padding difference), while the visible
arrowheads are only ~4px apart. The assertion compared a padded, stretched box
against an unpadded one.

## Solution

Measure the glyph `<svg>` of each control, not the element:

```ts
const backGlyph = await railBand(page).getByTestId("nav-back-chevron").locator("svg").boundingBox();
const collapseGlyph = await page.getByRole("button", { name: "Collapse sidebar" }).locator("svg").boundingBox();
expect(Math.abs(backGlyph!.x - collapseGlyph!.x)).toBeLessThanOrEqual(6); // 4px → passes
```

## Key Insight

When asserting horizontal alignment between two controls in Playwright, measure
the **innermost visible element** (the icon/glyph/text), not the interactive
element's `boundingBox()`. Two controls can share a layout gutter while their
border-boxes differ by their (asymmetric) padding or flex-stretch — the user
sees the glyphs aligned, so assert on the glyphs. A 6px tolerance comfortably
absorbs icon-centering offsets while still catching a real gutter regression
(the pre-fix px-5-vs-px-3 defect was ~8px).

## Session Errors

1. **e2e border-box vs glyph alignment (above).** Recovery: measure the `<svg>`
   glyphs. **Prevention:** this learning; assert on innermost visible element
   for cross-element alignment checks.
2. **Transient Playwright `Target page, context or browser has been closed`** on
   the pre-existing "drilled (expanded)" test, first run only — passed on rerun.
   `gotoOrSkip`'s retry regex covers network aborts (`ERR_ABORTED` etc.) but not
   context-closed cold-start crashes. **Prevention:** treat a lone
   context-closed failure on a cold first navigation as a flake; rerun before
   diagnosing. (Could widen the retry regex to include
   `Target page.*has been closed`, but it's rare — left as-is.)
3. **`git commit` exit 128 (doubled path `apps/web-platform/apps/web-platform/...`)**
   — the Bash tool's CWD had drifted into `apps/web-platform` after a prior
   `cd apps/web-platform && playwright …` call, so a relative `git add
   apps/web-platform/...` doubled the path. Recovery: `cd <worktree-root> &&
   git …` in a single Bash call. **Prevention:** known class — always prefix git
   operations with an absolute `cd <worktree-root> &&` after any subdir `cd`.

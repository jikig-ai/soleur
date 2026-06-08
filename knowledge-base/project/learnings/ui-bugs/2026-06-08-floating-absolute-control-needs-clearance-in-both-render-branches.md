---
title: "Floating an absolute control over a multi-state sidebar needs clearance in BOTH render branches, and VRT for a state-flipping toggle must match both aria-labels"
date: 2026-06-08
category: ui-bugs
module: apps/web-platform/components/dashboard
tags: [tailwind, absolute-positioning, playwright-vrt, jsdom, aria-label, sidebar]
pr: 4997
---

# Learning: floating a control over a multi-state container

## Problem

PR #4997 reclaimed ~45px of wasted sidebar top space by removing a near-empty
toggle row and FLOATING the collapse toggle (`absolute right-3 top-3 z-10 hidden
md:flex`) so the workspace band rises to the sidebar top. What looked like a
one-line CSS reposition had a wider blast radius than expected:

1. **An absolute control overlays content in EVERY render branch, not just the
   one you eyeballed.** The sidebar band renders two structurally different
   subtrees — an expanded pill row (`workspace-context-band.tsx`, multi-workspace
   variant has a `▾` chevron `shrink-0` at the card's right edge) and a separate
   collapsed icon-only column (centered monogram tile in a 56px rail). A top-right
   floated toggle collides with the chevron in the expanded branch AND the
   centered tile in the collapsed branch. Fixing only the branch you're looking at
   ships a collision in the other.

2. **A toggle's accessible name flips with state, so a single-label VRT locator
   half-fails.** The toggle is `aria-label={collapsed ? "Expand sidebar" :
   "Collapse sidebar"}`. A Playwright locator `getByRole("button", { name:
   "Collapse sidebar" })` resolves fine in the expanded tests but throws
   "element(s) not found" in the collapsed test — where the label is "Expand
   sidebar".

## Solution

- **Reserve clearance in both branches, not the toggle's offset.** Keep the toggle
  at the repo's existing corner-control offset (`absolute right-3 top-3`, mirroring
  `components/ui/error-card.tsx:27`) and push the *content* clear: `md:pr-10` on the
  expanded pill row (40px ≥ the toggle's right-36px footprint) and `pt-10` on the
  collapsed icon column (40px ≥ the toggle's bottom-36px footprint). The collapsed
  rail has ample vertical room, so the top offset costs nothing the user notices.
- **Match either label in the VRT locator:** `getByRole("button", { name:
  /^(Collapse|Expand) sidebar$/ })` — it is the only `… sidebar` button, so the
  alternation is unambiguous and works in both states.
- **Exercise the collision branch with a real fixture.** The single-membership
  mock renders the non-interactive identity chip (NO chevron). The chevron-overlap
  assertion needs a ≥2-membership `page.route` override registered AFTER
  `setupNavMocks` (Playwright matches last-registered first), or the test passes
  vacuously against a chevron that never rendered.

## Key Insight

jsdom renders no CSS, so the geometry proof is the Playwright VRT — and the VRT
must drive *every render branch the floated element overlaps* (expanded multi-
workspace, collapsed rail, mobile) with rect-intersection assertions, not just the
default view. A CSS-only "reposition one element" change has a test-rewrite blast
radius proportional to the number of states the element now overlays.

## Session Errors

- **JSX `{/* */}` comment between element attributes** — invalid syntax (parsed as
  a malformed attribute). Recovery: use `//` line comments between attributes (those
  ARE valid in TSX). Prevention: never place `{/*…*/}` inside a JSX opening tag's
  attribute list; put it above the element or use `//`.
- **`getByLabelText` used in a Playwright e2e spec** — that is React Testing
  Library's API; Playwright's `Page` has `getByLabel`/`getByRole`, not
  `getByLabelText`. tsc caught it (TS2551). Prevention: in `e2e/*.e2e.ts` use
  `getByRole("button", { name })` (the file's established idiom); RTL queries belong
  in `test/*.test.tsx`.
- **VRT locator matched only the expanded-state aria-label** — see Problem #2.
  Prevention: when locating a control whose `aria-label` flips with component state,
  match all states (regex alternation) or query by a stable `data-testid`.
- **Mobile drawer-open click fired pre-hydration** — the SSR hamburger paints before
  its `onClick` attaches, so an early click no-ops. Recovery: settle for hydration
  before clicking (mirrors this file's widenable-rail drag tests). Prevention:
  before any `page.mouse`/`.click()` that depends on a React handler, wait for the
  element visible + a hydration settle.
- **Transient `page.goto: Target page... has been closed`** on an untouched test —
  a browser-context crash under single-worker + cold-compile pressure. Recovery:
  `--retries=1`. One-off transient; already documented in the qa skill.
- **one-shot collision gate aborted on a contextual `#4915`** — a closed issue cited
  as history, not a work target. Recovery: re-invoked with `#N` refs de-hashed.
  Already a documented class (`2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md`).

## Tags
category: ui-bugs
module: apps/web-platform/components/dashboard

---
title: "Tasks: Float the sidebar collapse toggle"
feature: feat-one-shot-sidebar-top-space-float-toggle
lane: single-domain
plan: knowledge-base/project/plans/2026-06-07-feat-sidebar-float-collapse-toggle-plan.md
status: planned
---

# Tasks — Float the sidebar collapse toggle

Derived from `2026-06-07-feat-sidebar-float-collapse-toggle-plan.md`. CSS/layout-only.
NEVER assert jsdom layout values — pixel proof lives in the Playwright VRT spec.

## Phase 0 — Preconditions (no code)

- [x] 0.1 Confirm `<aside>` is a positioned containing block (`layout.tsx:304-308`,
      `fixed ... md:relative`) so an `absolute` toggle anchors to the sidebar box.
- [x] 0.2 Confirm the desktop toggle is the only non-keyboard expand affordance in the
      collapsed rail; the floating toggle must stay reachable + inside the 56px rail.
- [x] 0.3 Re-read the geometry-pinning assertions to be rewritten:
      `dashboard-sidebar-collapse.test.tsx:105-110` and `nav-states-shell.e2e.ts:419-440`.

Wireframe: `knowledge-base/product/design/dashboard-nav/sidebar-float-collapse-toggle.pen`
(before/after expanded + collapsed).

## Phase 1 — Restructure (production change) — `app/(dashboard)/layout.tsx`

- [x] 1.1 Make the brand row (`:326`) mobile-only: hold only the close button; drop
      `justify-between`; keep `safe-top`; gate `md:hidden`.
- [x] 1.2 Move the collapse `<button>` (`:344-351`) out of the row; render it as an
      `absolute right-3 top-3 z-10 h-6 w-6 ... hidden md:flex` direct child of `<aside>`
      (adopt the `error-card.tsx:27` corner-control precedent — NOT a new offset).
- [x] 1.3 Preserve verbatim: `onClick={toggleCollapsed}`, `aria-label` Expand/Collapse,
      `title` "(⌘B)", `PanelToggleIcon h-4 w-4`.
- [x] 1.4 Verify (via VRT screenshots, not speculation) the band's top room is reclaimed and
      the toggle does not overlap the card; apply `md:pr-8` band fallback only if needed.

## Phase 2 — vitest DOM/token test — `test/dashboard-sidebar-collapse.test.tsx`

- [x] 2.1 Rewrite the "Issue 1" row-geometry test (`:105-110`) to assert the toggle's
      className contains `absolute` + `md:flex` (token-level only).
- [x] 2.2 Keep ALL behavior tests (`:112-201`) unmodified and green (aria-label toggle,
      collapsed titles, localStorage persist, ⌘B/Ctrl+B + input/textarea guards).

## Phase 3 — Playwright VRT gate — `e2e/nav-states-shell.e2e.ts`

- [x] 3.1 Rewrite the Bug-2 alignment assertion (`:419-440`): replace gutter-alignment with
      (a) reclaimed-space (band top ≤12px from aside top), (b) no-overlap with card + chevron.
- [x] 3.2 Confirm `setupNavMocks` seeds a multi-workspace fixture (≥2 memberships) for the
      chevron-overlap assertion; extend it if not.
- [x] 3.3 Extend the collapsed-state test (`:443-481`): toggle visible, inside 56px rail, no
      overlap with `workspace-identity-icon` tile.
- [x] 3.4 Guard mobile (390px): close button (`Close navigation`) + mobile band present.
- [x] 3.5 Prove the gate RED against old markup, GREEN against new; record in PR body.

## Phase 4 — Gates

- [x] 4.1 `tsc --noEmit` clean.
- [x] 4.2 Full vitest suite green via `./node_modules/.bin/vitest run` (NOT bun test).
- [x] 4.3 Playwright VRT spec green headless on the `authenticated` project (zero creds).

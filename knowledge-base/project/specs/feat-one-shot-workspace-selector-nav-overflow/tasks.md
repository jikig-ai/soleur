---
title: "Tasks — Fix workspace-selector nav overflow + chevron alignment"
plan: knowledge-base/project/plans/2026-06-03-fix-workspace-selector-nav-overflow-chevron-alignment-plan.md
branch: feat-one-shot-workspace-selector-nav-overflow
lane: single-domain
---

# Tasks

## 1. Setup / Reproduce (RED)

- [x] 1.1 Confirm runner: `./node_modules/.bin/vitest run` (NOT `bun test`).
- [x] 1.2 Run existing nav/org tests green as a baseline (`org-switcher*`,
      `workspace-context-band`, `nav-rail-drill`, `nav-single-mount`).
- [x] 1.3 Write failing test `apps/web-platform/test/nav-chevron-alignment.test.tsx`:
  - [x] 1.3.1 Drilled state → exactly one collapse toggle + exactly one
        `nav-back-chevron`, and they are distinct controls (AC3/AC4).
  - [x] 1.3.2 Both `collapsed={false}` and `collapsed={true}` band paths render the
        back affordance (AC5).
  - [x] 1.3.3 Pill button/static chip carry width-clamp classes (`w-full min-w-0`)
        and caret is `shrink-0` (AC1 unit-level).

## 2. Core Implementation (GREEN)

- [x] 2.1 Fix A (chevron alignment) — `workspace-context-band.tsx`:
  - [x] 2.1.1 Disambiguate the back affordance from the collapse glyph (A1 labelled
        "Back to menu" row preferred; A2 distinct icon fallback) in BOTH paths.
  - [x] 2.1.2 Unify the band's left gutter with the brand-row collapse-toggle gutter.
  - [x] 2.1.3 If gutter unification requires it, adjust the brand row in
        `app/(dashboard)/layout.tsx` (keep the single collapse toggle; do NOT remove).
- [x] 2.2 Fix B (overflow clamp):
  - [x] 2.2.1 `org-switcher-container.tsx` — remove the redundant nested `px-3`
        wrapper padding (keep `border-b`).
  - [x] 2.2.2 `org-switcher.tsx` — add `w-full min-w-0 max-w-full` to the multi-org
        button (L102) and solo static chip (L74-77); confirm `▾` caret `shrink-0`.
  - [x] 2.2.3 Audit the `min-w-0` chain band `flex-1` → container → button.

## 3. Testing / Verification

- [x] 3.1 New + existing vitest suites pass (`vitest run`) — AC6/AC7.
- [x] 3.2 Playwright VRT gate `e2e/nav-states-shell.e2e.ts`: ADD a new
      "drilled (expanded): no horizontal overflow (Bug 1)" test at `md:w-56` for
      `/dashboard/kb` and `/dashboard/chat/<id>` — the existing line-222 test checks
      chrome only, NO overflow assertion. Reuse the canonical probe verbatim:
      `aside.evaluate((el) => el.scrollWidth - el.clientWidth)` → `toBeLessThanOrEqual(1)`,
      AND assert pill workspace-name text is visible (empty-band guard, e2e:16-19).
      Collapsed states (AC2) already covered by existing tests at lines 239/267.
      Add back-affordance x ~= collapse-toggle x bounding-box check (AC4).
- [x] 3.3 Confirm `/dashboard` top-level unchanged: wordmark + single chevron, no
      back chevron (AC8).
- [x] 3.4 Confirm no workspace-switch behavior regression (RPC/JWT/reload untouched).

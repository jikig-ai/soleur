---
title: "Tasks — fix sidebar collapse toggle overlap during not-yet-loaded state"
plan: knowledge-base/project/plans/2026-06-15-fix-sidebar-collapse-toggle-overlap-during-load-plan.md
branch: feat-one-shot-sidebar-collapse-button-overlap
lane: single-domain
---

# Tasks

## Phase 0 — Repro + mechanism confirmation (real CSS)

- [x] 0.1 Extend the `authenticated` Playwright setup in `apps/web-platform/e2e/nav-states-shell.e2e.ts`
  to delay/leave-pending the `/api/workspace/list-memberships` mock, rendering the band's `null`
  (height-collapsed) state on `/dashboard`, expanded.
- [x] 0.2 Screenshot expanded in-flight state; confirm collapse-toggle rect overlaps the "Dashboard"
  nav link rect.
- [x] 0.3 Capture the collapsed in-flight state; confirm whether the `left-1/2 top-3` collapsed toggle
  overlaps (document either way — both-toggle-states rule).

## Phase 1 — Failing VRT assertion (RED)

- [x] 1.1 Add a rect-non-intersection assertion (expanded, in-flight mock): toggle rect must not
  intersect the "Dashboard" nav link rect. Confirm it FAILS on current `main`.
- [x] 1.2 Add a collapsed-state companion assertion (in-flight + loaded mocks).

## Phase 2 — Fix (GREEN)

- [x] 2.1 Apply approach (A) — exact change (pinned by deepen-pass): in
  `apps/web-platform/components/dashboard/workspace-context-band.tsx` line 153, change the pill
  container from `<div className="flex items-center gap-2 px-3 pt-2 md:pr-10">` to
  `<div className={`flex items-center gap-2 px-3 pt-2 md:pr-10${drill === null ? " md:min-h-[64px]" : ""}`}>`.
  (64px = toggle `top-10` 40px + `h-6` 24px footprint.)
- [x] 2.2 Scope is already contained: `md:` excludes mobile `variant="mobile"`; `drill === null`
  excludes drilled Settings/KB/Chat bands; collapsed returns early at :83. Confirm collapsed
  (`md:w-14`), Settings/Chat (`md:w-56`), mobile (`w-64`) widths unchanged via existing specs.
- [x] 2.3 If VRT shows a ≤2px residual, bump the reserve (`md:min-h-[68px]`). Only if that fails,
  fall back to approach (B) (re-anchor toggle in `app/(dashboard)/layout.tsx` + update comment :335-365).

## Phase 3 — Lock the contract

- [x] 3.1 Keep/extend jsdom className tripwires in `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx`
  for BOTH toggle states (expanded `right-3 top-10`; collapsed `left-1/2 -translate-x-1/2 top-3`).
- [x] 3.2 Confirm the loaded-state centering assertions (existing AC1/AC3) stay green (no #5015 regression).

## Phase 4 — Verify

- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/dashboard-sidebar-collapse.test.tsx test/workspace-context-band.test.tsx` green.
- [x] 4.3 e2e VRT (`nav-states-shell.e2e.ts`) green in CI (authoritative gate; local may flake on throttling).

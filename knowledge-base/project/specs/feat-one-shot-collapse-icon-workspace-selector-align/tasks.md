---
title: "Tasks — Align floated sidebar collapse toggle with the workspace selector card"
date: 2026-06-08
branch: feat-one-shot-collapse-icon-workspace-selector-align
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-08-fix-sidebar-collapse-toggle-workspace-selector-alignment-plan.md
---

# Tasks

Derived from `2026-06-08-fix-sidebar-collapse-toggle-workspace-selector-alignment-plan.md`.
Pure CSS-offset fix to the floated desktop sidebar collapse toggle so its center
aligns with the workspace selector card. Both render branches (expanded pill +
collapsed monogram column) and both toggle states must be asserted.

## Phase 1 — RED: failing alignment assertion

- [ ] 1.1 In `apps/web-platform/e2e/nav-states-shell.e2e.ts`, add a positive
      rect-center assertion (AC1): `collapseToggle(page)` center within ≤2px of
      the switcher card center (card rect via
      `page.getByRole("button", { name: "Switch workspace" })` for multi-membership
      or `orgIdentity(page)` for single-membership). Confirm it goes RED on the
      current `top-3` markup; record the measured ~6px delta for the PR body.
- [ ] 1.2 Confirm the existing no-overlap (AC2 chevron / AC3 collapsed-tile) and
      reclaimed-space (AC4) assertions remain in place and continue to pass —
      the new fix must not regress them.

## Phase 2 — GREEN: the offset fix

- [ ] 2.1 In `apps/web-platform/app/(dashboard)/layout.tsx` (toggle button,
      ~L349-356), adjust the toggle's vertical offset so its center aligns with
      the pill row's center, following the repo CENTERING precedent
      (`top-1/2 -translate-y-1/2`, per `file-tree.tsx`/`search-overlay.tsx`) over
      the fixed-corner `top-3` from `error-card.tsx` — see plan Precedent-Diff.
      Prefer the smaller-diff explicit-`top-*` form derived against the live VRT
      (≤2px) unless AC3 forces the structural-wrap form. Adjust `right-*` only if
      the VRT shows horizontal misalignment. Do NOT change `h-6 w-6`, `z-10`,
      `md:flex`, `aria-label`, `title`, or `onClick`.
- [ ] 2.2 Update the toggle's code comment (currently cites
      `error-card.tsx:27` as the `right-3 top-3` precedent) to note the
      vertical-offset divergence: the toggle now centers against an adjacent
      card, not a card corner.
- [ ] 2.3 Re-run the collapsed-state assertions (AC3). If the new `top-*`
      reduces bottom-edge clearance over the monogram tile, bump the collapsed
      column's `pt-*` in `components/dashboard/workspace-context-band.tsx:91`.
- [ ] 2.4 If the horizontal offset changed, confirm `md:pr-10` on the expanded
      pill row (`workspace-context-band.tsx:162`) still clears the toggle's right
      footprint; widen only if required.

## Phase 3 — Lock the static guard + full suite

- [ ] 3.1 Update `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx`
      (AC6) to assert the toggle's new offset className (drift tripwire).
- [ ] 3.2 Run `tsc --noEmit` and the full web-platform vitest suite (AC7);
      green modulo the 2 pre-existing env-only `run-migrations-unmerged-gate`
      failures.
- [ ] 3.3 Run the Playwright `nav-states` VRT on the `authenticated` project
      (AC8): `cd apps/web-platform && npx playwright test nav-states-shell --project=authenticated`.
      Confirm AC1-AC5 green and AC4 (reclaimed-space) still GREEN.

## Done when

- AC1-AC8 (Pre-merge) all green. No post-merge operator step (deploy is the
  merge via `web-platform-release.yml` path-filtered `on.push`).

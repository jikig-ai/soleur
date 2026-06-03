---
title: "Tasks — fix: collapsed single-rail secondary-nav overflow"
plan: knowledge-base/project/plans/2026-06-03-fix-collapsed-rail-secondary-nav-overflow-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — collapsed single-rail secondary-nav overflow (KB / Settings / Chat)

## Phase 0 — Preconditions (verify before coding)

- [ ] 0.1 Read `apps/web-platform/test/helpers/rail-slot-harness.tsx` — confirmed
  it provides ONLY the slot node (`RailSlotProvider value={slot}`); it MUST be
  extended to accept an optional `collapsed?` prop and wrap children in
  `RailCollapsedProvider` for the collapsed jsdom tests.
- [ ] 0.2 Decide Approach A (collapse context + per-shell render-conditional —
  preferred) vs B (render-gate the slot in the layout). Record the choice and
  rationale (§Sharp Edges portal-lifetime). Default A.
- [ ] 0.3 Confirm `collapsed` is held at `app/(dashboard)/layout.tsx:111`
  (`useSidebarCollapse`) and reachable to wherever the context is provided.
- [ ] 0.4 Re-confirm `nav-states-*.e2e.ts` routes to the `authenticated`
  Playwright project (`playwright.config.ts:52`) — new cases go in the existing
  file; do NOT rename it.

## Phase 1 — RED (failing tests first; cq-write-failing-tests-before)

- [ ] 1.1 e2e: change the collapsed-drilled KB case in
  `nav-states-shell.e2e.ts` to mock a **populated** tree (≥1 nested dir + ≥1
  file); assert overflow `> 1` (currently) — prove RED.
- [ ] 1.2 e2e: add collapsed-drilled **Settings** (`/dashboard/settings`) and
  **Chat** (`/dashboard/chat`, ≥3 conversations) cases; assert overflow + nav
  content absent — prove RED.
- [ ] 1.3 jsdom: add collapsed-state assertions to
  `settings-sidebar-collapse.test.tsx`, `kb-sidebar-collapse.test.tsx`,
  `conversations-rail.test.tsx` (nav content `queryByTestId(...) === null` when
  `collapsed=true`) — prove RED. Extend `RailSlotHarness` if needed (0.1).

## Phase 2 — GREEN (implement the fix)

- [ ] 2.1 Add **sibling** `RailCollapsedContext` + `RailCollapsedProvider` +
  `useRailCollapsed()` to `components/dashboard/rail-slot.tsx` (do NOT widen the
  `HTMLElement | null` slot value); provide `collapsed` from `(dashboard)/layout.tsx`
  (already held at line 111). Extend `RailSlotHarness` (0.1). (Or render-gate the
  slot per Approach B.)
- [ ] 2.2 `settings-shell.tsx`: stable `data-testid="settings-rail-nav"` wrapper;
  render-conditional the tab `<ul>` off when collapsed (DOM-removed, not CSS-hidden).
- [ ] 2.3 `kb-sidebar-shell.tsx`: stable `data-testid="kb-rail-tree"` wrapper;
  render-conditional the `SearchOverlay` + `FileTree`/`RailEmptyState` off when
  collapsed.
- [ ] 2.4 `conversations-rail.tsx`: render-conditional the rows off when collapsed
  (stable `data-testid="conversations-rail"` wrapper already in
  `conversations-rail-portal.tsx`).
- [ ] 2.5 Keep `WorkspaceContextBand` untouched (already collapse-aware,
  single-mount). Do not add a second collapse path through it.

## Phase 3 — Verify (assert the invariant, both toggle states)

- [ ] 3.1 e2e: assert content-absent when collapsed (AC2) AND content-present
  when expanded (AC4) for all 3 sections — assert the invariant, not a proxy.
- [ ] 3.2 e2e: assert `railBand` visible + `data-collapsed="true"` +
  `workspace-identity-icon` present in every collapsed-drilled section (AC5).
- [ ] 3.3 Prove the fix RED→GREEN: revert the fix locally, confirm the populated
  collapsed e2e case fails; restore, confirm green (ADR-049).
- [ ] 3.4 `tsc --noEmit` + affected vitest files + `nav-states-shell.e2e.ts`
  (authenticated project) all green via the package's `scripts.test` runner.

## Phase 4 — Post-merge

- [ ] 4.1 Playwright MCP visual confirmation on deployed dashboard: collapse
  while drilled into KB (with docs) / Settings / Chat (with conversations);
  screenshot each; confirm no clipped rows (AC8). Runs in `/soleur:qa` /
  post-merge — not operator-manual.

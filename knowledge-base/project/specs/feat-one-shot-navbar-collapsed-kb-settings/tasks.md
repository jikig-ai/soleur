---
title: "Tasks — fix: collapsed single-rail secondary-nav overflow"
plan: knowledge-base/project/plans/2026-06-03-fix-collapsed-rail-secondary-nav-overflow-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — collapsed single-rail secondary-nav overflow (KB / Settings / Chat)

## Phase 0 — Preconditions (verify before coding)

- [x] 0.1 Read `apps/web-platform/test/helpers/rail-slot-harness.tsx` — confirmed
  it provides ONLY the slot node (`RailSlotProvider value={slot}`); it MUST be
  extended to accept an optional `collapsed?` prop and wrap children in
  `RailCollapsedProvider` for the collapsed jsdom tests.
- [x] 0.2 Decide Approach A (collapse context + per-shell render-conditional —
  preferred) vs B (render-gate the slot in the layout). Record the choice and
  rationale (§Sharp Edges portal-lifetime). Default A.
- [x] 0.3 Confirm `collapsed` is held at `app/(dashboard)/layout.tsx:111`
  (`useSidebarCollapse`) and reachable to wherever the context is provided.
- [x] 0.4 Re-confirm `nav-states-*.e2e.ts` routes to the `authenticated`
  Playwright project (`playwright.config.ts:52`) — new cases go in the existing
  file; do NOT rename it.

## Phase 1 — RED (failing tests first; cq-write-failing-tests-before)

- [x] 1.1 e2e: change the collapsed-drilled KB case in
  `nav-states-shell.e2e.ts` to mock a **populated** tree (≥1 nested dir + ≥1
  file); assert overflow `> 1` (currently) — prove RED.
- [x] 1.2 e2e: add collapsed-drilled **Settings** (`/dashboard/settings`) and
  **Chat** (`/dashboard/chat`, ≥3 conversations) cases; assert overflow + nav
  content absent — prove RED.
- [x] 1.3 jsdom: add collapsed-state assertions to
  `settings-sidebar-collapse.test.tsx`, `kb-sidebar-collapse.test.tsx`,
  `conversations-rail.test.tsx` (nav content `queryByTestId(...) === null` when
  `collapsed=true`) — prove RED. Extend `RailSlotHarness` if needed (0.1).

## Phase 2 — GREEN (implement the fix)

- [x] 2.1 Add **sibling** `RailCollapsedContext` + `RailCollapsedProvider` +
  `useRailCollapsed()` to `components/dashboard/rail-slot.tsx` (do NOT widen the
  `HTMLElement | null` slot value); provide `collapsed` from `(dashboard)/layout.tsx`
  (already held at line 111). Extend `RailSlotHarness` (0.1). (Or render-gate the
  slot per Approach B.)
- [x] 2.2 `settings-shell.tsx`: stable `data-testid="settings-rail-nav"` wrapper;
  render-conditional the tab `<ul>` off when collapsed (DOM-removed, not CSS-hidden).
- [x] 2.3 `kb-sidebar-shell.tsx`: stable `data-testid="kb-rail-tree"` wrapper;
  render-conditional the `SearchOverlay` + `FileTree`/`RailEmptyState` off when
  collapsed.
- [x] 2.4 `conversations-rail.tsx`: render-conditional the rows off when collapsed
  (stable `data-testid="conversations-rail"` wrapper already in
  `conversations-rail-portal.tsx`).
- [x] 2.5 Keep `WorkspaceContextBand` untouched (already collapse-aware,
  single-mount). Do not add a second collapse path through it.

## Phase 3 — Verify (assert the invariant, both toggle states)

- [x] 3.1 e2e: assert content-absent when collapsed (AC2) AND content-present
  when expanded (AC4) for all 3 sections — assert the invariant, not a proxy.
- [x] 3.2 e2e: assert `railBand` visible + `data-collapsed="true"` +
  `workspace-identity-icon` present in every collapsed-drilled section (AC5).
- [x] 3.3 Prove the fix RED→GREEN: revert the fix locally, confirm the populated
  collapsed e2e case fails; restore, confirm green (ADR-049).
- [x] 3.4 `tsc --noEmit` + affected vitest files + `nav-states-shell.e2e.ts`
  (authenticated project) all green via the package's `scripts.test` runner.

## Phase 5 — Widenable KB rail (amendment) — Preconditions

- [x] 5.0 Confirm grounding (already verified at plan-amend time): the rail is a
  single `aside` with `${collapsed ? "md:w-14" : "md:w-56"}`
  (`app/(dashboard)/layout.tsx:246`); `react-resizable-panels` is used ONLY in
  the main-area split (`components/kb/kb-desktop-layout.tsx:5`), NOT the rail;
  `useSidebarCollapse` (`hooks/use-sidebar-collapse.ts:35`) is the localStorage
  persistence precedent; `drill` is computed at `layout.tsx:146`
  (`segmentToDrillLevel`). Decide KB-only gate (`drill === "kb"`) vs shared
  (`drill !== null`) — default KB-only.

## Phase 6 — RED (failing tests first; cq-write-failing-tests-before)

- [x] 6.1 jsdom: add `test/use-rail-width.test.tsx` (or sibling) asserting the
  (not-yet-existing) `useRailWidth` hook: default 224, reads/writes
  `soleur:sidebar.kb.width`, clamps a stored `9999`→max and `10`→min(≥224),
  try/catch private-mode safe — prove RED (hook absent).
- [x] 6.2 jsdom: add `test/rail-resize-handle.test.tsx` asserting
  `<RailResizeHandle>` renders `data-testid="kb-rail-resize-handle"` with
  `role="separator"`/`aria-orientation="vertical"`/`aria-valuenow`, calls
  `onWidthChange(clamp(...))` on a synthetic pointer drag, and nudges on
  ArrowRight/ArrowLeft — prove RED (component absent).
- [x] 6.3 jsdom: extend a layout/`nav-rail-drill.test.tsx`-style test to assert the
  handle is present when `drill === "kb" && !collapsed` and ABSENT when collapsed
  or on Settings/Chat (AC12/AC13) — prove RED.
- [x] 6.4 e2e: add expanded-KB resize cases to `nav-states-shell.e2e.ts`:
  (a) drag widens `aside` clientWidth (AC9); (b) reload persists (AC10); (c) drag
  past max clamps (AC11); (d) collapse a widened rail → ≈56 px + handle absent,
  expand → width returns (AC12); (e) handle absent on Settings/Chat (AC13);
  (f) mobile viewport: handle absent, drawer width unchanged. Assert these FAIL
  pre-implementation — prove RED.

## Phase 7 — GREEN (implement the widenable rail)

- [x] 7.1 Create `hooks/use-rail-width.ts` mirroring `useSidebarCollapse`:
  `RAIL_DEFAULT_PX=224`, `RAIL_MIN_PX`(≥224)/`RAIL_MAX_PX`(e.g. `min(480, 40vw)`),
  `useState` + post-hydration `useEffect` read of `soleur:sidebar.kb.width`,
  `setWidth(px)` clamping then persisting, all `localStorage` in try/catch.
- [x] 7.2 Create `components/dashboard/rail-resize-handle.tsx`: thin right-edge
  handle, `data-testid="kb-rail-resize-handle"`, a11y roles + Arrow-key nudge,
  pointer-capture drag → `onWidthChange(clamp(...))`, commit on `pointerup`,
  listener cleanup on `pointerup`/`pointercancel`/unmount. Style to MATCH the
  `ResizeHandle` idiom in `kb-desktop-layout.tsx:17` (no `react-resizable-panels`
  import — the `aside` is not a `Panel`).
- [x] 7.3 Wire into `app/(dashboard)/layout.tsx`: call `useRailWidth`; in the
  `drill === "kb" && !collapsed` branch apply `style={{ width }}` (md+ only,
  overriding `md:w-56`) to the `aside` and render `<RailResizeHandle>` on its right
  edge. Leave collapsed (`md:w-14`) and Settings/Chat (`md:w-56`) branches
  untouched (collapse precedence + KB-only).
- [x] 7.4 Do NOT clear the width key on collapse; collapse and width are
  independent localStorage keys (AC12).

## Phase 8 — Verify (widenable rail)

- [x] 8.1 Prove RED→GREEN: with 7.x reverted, confirm the 6.4 drag case fails
  (no handle / width does not change); restore, confirm green.
- [x] 8.2 Re-run Phase 3 collapse-fix e2e/jsdom with the resize code present —
  confirm AC2/AC3/AC4 unaffected (inline width on `aside`, not on portaled nav)
  (AC14, no regression).
- [x] 8.3 `tsc --noEmit` + affected vitest files + `nav-states-shell.e2e.ts`
  (authenticated project) all green via the package's `scripts.test` runner.

## Phase 4 — Post-merge

- [ ] 4.1 Playwright MCP visual confirmation on deployed dashboard: collapse
  while drilled into KB (with docs) / Settings / Chat (with conversations);
  screenshot each; confirm no clipped rows (AC8). Runs in `/soleur:qa` /
  post-merge — not operator-manual.
- [ ] 4.2 Playwright MCP (amendment): in expanded KB, drag the rail wider; confirm
  a previously-truncated deep folder/file name is now fully visible; reload and
  confirm the width persists (AC8 amendment). Runs in `/soleur:qa` / post-merge.
- [ ] 4.3 Add a "widened KB rail + edge handle" frame to
  `knowledge-base/product/design/navigation/single-nav-rail.pen` so the design
  source of truth reflects the new affordance (non-blocking design follow-up per
  `wg-ui-feature-requires-pen-wireframe`; reuses the existing `ResizeHandle`
  visual idiom — no net-new vocabulary).

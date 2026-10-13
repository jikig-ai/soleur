---
title: "Tasks: Resizable MAIN nav rail across all drill states"
branch: feat-one-shot-main-sidebar-resizable-all-states
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-18-feat-main-nav-rail-resizable-all-states-plan.md
date: 2026-06-18
---

# Tasks — Resizable MAIN nav rail (all drill states)

Derived from the deepened plan. TDD: write RED tests first, then GREEN. Reuse `RailResizeHandle`
+ the ONE existing `useRailWidth()` instance (SHARED key `soleur:sidebar.kb.width` — D1). KEEP the
floated collapse button. New `.test.tsx` files MUST live under `apps/web-platform/test/`
(happy-dom glob `test/**/*.test.tsx`). Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 1 — `RailResizeHandle` gains ONE `ariaLabel` prop

- [ ] 1.1 (RED) In `apps/web-platform/test/rail-resize-handle.test.tsx`, add a case: render with
      `ariaLabel="Resize sidebar"` → accessible name is "Resize sidebar"; default render keeps
      "Resize knowledge base sidebar". (AC5)
- [ ] 1.2 (GREEN) In `apps/web-platform/components/dashboard/rail-resize-handle.tsx`, extend
      `RailResizeHandleProps` with optional `ariaLabel?: string` (default `"Resize knowledge base
      sidebar"`); apply to `aria-label` (`:112`). Do NOT add `testId`/`gripTestId`. No color change
      (gold-active/focus + grey-hover at `:128,:132` untouched).
- [ ] 1.3 Confirm existing `onCollapse`/drag/keyboard cases stay green.

## Phase 2 — Main-rail CSS-var width rule

- [ ] 2.1 In `apps/web-platform/app/globals.css`, inside the SAME unlayered `@media (min-width:
      768px)` block as the KB rule (`:203-207`), add:
      `aside[data-main-rail-width] { width: var(--main-rail-w, 14rem); }` with a comment mirroring
      the KB rule's (deterministic, unlayered so it beats `md:w-56`, md+-gated so the mobile `w-64`
      drawer is untouched, mutually exclusive with the KB attribute). (AC2)

## Phase 3 — Widen the grip mount + apply main-rail width in the layout

> Contract-order: Phase 1 (handle accepts `ariaLabel`) MUST precede this.

- [ ] 3.1 (RED) Add layout tests under `apps/web-platform/test/` (extend an existing layout suite
      or create `test/main-rail-resize.test.tsx`):
  - Settings expanded mounts the grip with `aria-label="Resize sidebar"` (AC1, AC5).
  - Collapsed Settings: no grip, no `data-main-rail-width` (AC1, AC9).
  - Double-click the Settings grip fires collapse (AC6).
  - KB expanded mounts the grip with the KB label (AC1).
  - A width set on Settings is read back on KB (shared key) (AC3).
  - The grip is NOT a descendant of `[data-testid="rail-secondary-slot"]` (AC7).
- [ ] 3.2 (GREEN) In `apps/web-platform/app/(dashboard)/layout.tsx`:
  - Define `mainExpanded = !collapsed && drill !== "kb"`.
  - Set `data-main-rail-width` + `style={{ "--main-rail-w": `${railWidth}px` }}` when
    `mainExpanded` (mirror the `kbExpanded` block at `:299-304`, fed by the SAME `railWidth`).
    Keep the `kbExpanded` block + the `${collapsed ? "md:w-14" : "md:w-56"}` class.
  - Replace `{kbExpanded && (<RailResizeHandle …/>)}` (`:506`) with a SINGLE
    `{!collapsed && (<RailResizeHandle … />)}` mount. Branch ONLY
    `ariaLabel={drill === "kb" ? undefined : "Resize sidebar"}`; all other props unconditional
    (`width={railWidth}`, `onWidthChange/onCommit → setRailWidth`, `min={RAIL_MIN_PX}`,
    `max={railMaxPx()}`, `onCollapse={toggleCollapsed}`). ONE JSX site — never two blocks. (AC1)
  - Place the grip as a direct child of `<aside>` (after the drill ternary closes, ~`:498`), NOT
    inside the `overflow-y-auto rail-secondary-slot` div. (AC7)
  - KEEP the floated `PanelToggleIcon` button (`:367`) + its SVG verbatim.
- [ ] 3.3 `tsc --noEmit` passes (AC10).

## Phase 4 — e2e: invert the KB-only assertion + add NON-KB scenarios

- [ ] 4.1 In `apps/web-platform/e2e/nav-states-shell.e2e.ts`, REPLACE the
      `"resize handle is KB-only — absent on Settings and Chat (AC13)"` test (`:941-950`) with
      `"resize handle present on Settings AND Chat (resizable main rail)"` — assert
      `resizeHandle(page)` (the existing `kb-rail-resize-handle` locator) is VISIBLE on
      `/dashboard/settings` AND `/dashboard/chat`, with NO `seedCollapsed` (expanded). (AC-E2E-4)
- [ ] 4.2 Add a `test.describe("resizable main rail — desktop")` block (mirror the `widenable KB
      rail` `dragHandleBy` + 1500ms hydration wait, navigating to `/dashboard/settings`):
  - drag widens the Settings aside (> default + 50) (AC-E2E-2);
  - width persists across reload, read back from the SHARED `RAIL_WIDTH_KEY`
    (`soleur:sidebar.kb.width`) literal (AC-E2E-2);
  - drag turns the handle gold (active class includes `soleur-accent-gold-fill`) (AC-E2E-1);
  - double-click collapses to `md:w-14`; the floated button re-expands (AC-E2E-3).
- [ ] 4.3 Confirm the existing `no resize handle on mobile` invariant still holds (AC8).

## Phase 5 — Verification sweep

- [ ] 5.1 AC greps: `! grep -q 'kbExpanded && <RailResizeHandle' layout.tsx`; exactly one
      `<RailResizeHandle` JSX site; `grep -q 'data-main-rail-width' layout.tsx`; globals.css has
      `aside[data-main-rail-width]` + `var(--main-rail-w, 14rem)`; `! grep -q 'KB-only'`
      nav-states-shell.e2e.ts.
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC10).
- [ ] 5.3 `cd apps/web-platform && ./node_modules/.bin/vitest run` (AC11). No co-located test files.
- [ ] 5.4 Regression guards (prose, not edits): gold-on-active unchanged, button KEPT, ⌘B intact.

## Post-merge (operator / automatable)

- [ ] AC15 Playwright visual verify (Dashboard/Settings/Chat: drag → gold; double-click → collapse;
      button → expand; width persists). Fold into `/soleur:qa` or `test-browser` — not a manual
      checklist.

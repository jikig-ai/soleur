# Tasks — fix-settings-sidebar-gap-and-header-alignment

Derived from `knowledge-base/project/plans/2026-05-11-fix-settings-sidebar-gap-and-header-alignment-plan.md`.

## 1. Setup

- 1.1 Confirm worktree `.worktrees/feat-one-shot-fix-settings-sidebar-gap-and-header-alignment/` is active.
- 1.2 Run `bun test apps/web-platform/test/settings-sidebar-collapse.test.tsx` to capture the green baseline before changes.

## 2. TDD — RED (failing tests first)

- 2.1 Add `min-h-7` header-row assertion to the existing `describe("collapse button alignment with main nav chevron (expanded state)")` block in `apps/web-platform/test/settings-sidebar-collapse.test.tsx`.
- 2.2 Add new `describe("content area collapses cleanly when sidebar is closed")` block with two assertions:
  - 2.2.1 Collapsed-state nav guard (`md:w-0`, `md:overflow-hidden`, `md:border-r-0` present; `px-4` absent).
  - 2.2.2 Collapsed-state content-area padding guard (`md:pl-8` present after collapse click).
- 2.3 Run test → assert RED on the three new assertions, GREEN on all existing assertions.

## 3. TDD — GREEN (implementation)

- 3.1 Edit `apps/web-platform/components/settings/settings-shell.tsx` header `<div>`: add `min-h-7` between `mb-4 flex` and `items-center justify-between`.
- 3.2 Edit `apps/web-platform/components/settings/settings-shell.tsx` content area `<div>`: replace static `md:px-10` with conditional `${settingsCollapsed ? "md:pl-8 md:pr-10" : "md:px-10"}`. Keep `md:py-10` and `md:pb-10` unchanged.
- 3.3 Run test → assert all assertions green (new + existing).

## 4. TDD — REFACTOR

- 4.1 Re-read the diff and confirm: no other class tokens were changed; only header-row padding-min-height and conditional content-left-padding were touched.
- 4.2 `bunx tsc --noEmit` from `apps/web-platform/` → no new errors.

## 5. Visual QA via Playwright MCP

- 5.1 Navigate to `/dashboard/settings` in dev.
- 5.2 Capture screenshot: main sidebar open + settings sidebar open.
- 5.3 Capture screenshot: main sidebar open + settings sidebar closed (Cmd+B).
- 5.4 Capture screenshot: main sidebar collapsed + settings sidebar open.
- 5.5 Capture screenshot: main sidebar collapsed + settings sidebar closed.
- 5.6 For each pair where the settings sidebar is open: verify both `<` chevrons sit on the same y-baseline (±1px) using a pixel-coord measurement (`browser_evaluate` returning `getBoundingClientRect()`).
- 5.7 For each pair where the settings sidebar is closed: verify the expand `>` chevron sits ≤32px from the main app sidebar's right edge.

## 6. Commit + Ship

- 6.1 Run compound skill (`skill: soleur:compound`) before commit.
- 6.2 `git add` only the two edited files + plan + tasks.md.
- 6.3 Commit with message: `fix(settings-sidebar): close-state gap + header alignment with main nav`.
- 6.4 Push branch.
- 6.5 Open PR with before/after screenshots attached.
- 6.6 Run review → fix-inline on findings → QA → ship.

## Dependencies

- 2 depends on 1.
- 3 depends on 2 (TDD RED first).
- 4 depends on 3.
- 5 depends on 3 (implementation must exist to QA).
- 6 depends on 4 and 5.

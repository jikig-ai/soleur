# fix: Align Settings sub-nav expand chevron with main nav chevron

**Created:** 2026-04-17
**Deepened:** 2026-04-17
**Branch:** feat-one-shot-settings-nav-chevron-align
**Type:** bug fix (UI polish)
**Priority:** P3 (low — visual polish, no functional impact)

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** 3 (Proposed Fix, Implementation Phases, Test Scenarios)
**Research performed:** codebase precedent discovery (KB layout), existing test patterns, React `inert` attribute semantics

### Key Improvements from Deepening

1. **Switched approach to match existing KB layout precedent.** The KB page (`apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx:318-328`) already solved this identical problem using an `absolute left-2 top-5 z-10` positioned chevron button with matching `h-6 w-6` geometry. That positioning math (`left-2` = 8px, `top-5` = 20px) mirrors the main nav's `px-2 py-5` header exactly, so chevrons align pixel-for-pixel. Adopting this precedent over the narrow-rail approach (a) reduces the diff (no `<nav>` restructure, no `inert` migration), (b) matches a proven pattern, and (c) avoids authoring a new visual vocabulary.
2. **Dropped the `inert` migration.** The absolute-positioning approach leaves the existing `inert={settingsCollapsed || undefined}` on `<nav>` unchanged — the expand button lives in the content area `<div>`, not inside `<nav>`, so `inert` on `<nav>` doesn't affect it. This eliminates an entire class of accessibility regression risk called out in the original plan's Phase 2 step 7.
3. **Added content-shift handling.** KB's pattern uses `${kbCollapsed ? "pl-10" : ""}` on the content container to prevent text from sitting under the absolute-positioned button. The Settings content area already has `md:px-10` (40px ≥ the button's right edge at `left-2 + h-6 = 8 + 24 = 32px`), so no content shift needed — but verified this during deepening to avoid a subtle visual bug.

### New Considerations Discovered

- **Stacking context:** KB uses `z-10` on the absolute button to ensure it sits above content scroll. Settings content uses `overflow-y-auto`? Check during implementation — if yes, `z-10` is required; if no (no scroll container at that level), omit.
- **Mobile safety:** KB pattern gates with `hidden md:flex` (via `hidden md:block` on the nav wrapper). Settings shell's current expand button uses `hidden md:flex` — preserve this.
- **No `relative` parent required:** The Settings content `<div>` needs `relative` positioning for `absolute` to anchor correctly. The current `<div className="flex-1 px-4 py-10 pb-20 md:px-10 md:pb-10">` has no `relative` — add it. (KB's container has `relative` implicitly via Panel, but Settings does not.)

## Overview

The Settings sub-navigation sidebar renders its expand/collapse chevron button at a different horizontal x-position than the main dashboard navigation's expand/collapse chevron button. When both chevrons are visible simultaneously (main nav collapsed + Settings route active with sub-nav collapsed), the two `>` icons do not line up vertically, creating a jagged top-left corner.

The fix is purely presentational: align the two chevron buttons so their icons share the same left column, whether main nav is collapsed or expanded.

## Problem Evidence

Screenshots captured by the reporter:

- `/home/jean/Pictures/Screenshots/Screenshot From 2026-04-17 17-13-35.png`
- `/home/jean/Pictures/Screenshots/Screenshot From 2026-04-17 17-13-43.png`

Both show the top-left region of the dashboard with the main nav expand chevron and the Settings sub-nav back/expand chevron at visibly different x-positions.

## Root Cause

Two independent layout containers render their chevron toggles with different horizontal padding and positioning rules.

### Main nav (`apps/web-platform/app/(dashboard)/layout.tsx`)

The brand + collapse-toggle header:

```tsx
// layout.tsx:231
<div className={`flex items-center justify-between safe-top ${collapsed ? "px-2 py-5" : "px-5 py-5"}`}>
  <span className={`... ${collapsed ? "md:hidden" : ""}`}>Soleur</span>
  <button
    onClick={toggleCollapsed}
    aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
    className="hidden md:flex h-6 w-6 items-center justify-center rounded text-neutral-400 hover:bg-neutral-800 hover:text-white"
  >
    {collapsed ? <ChevronRightIcon className="h-4 w-4" /> : <ChevronLeftIcon className="h-4 w-4" />}
  </button>
</div>
```

- **Collapsed** (`md:w-14` aside = 56px): container `px-2` (8px), button `h-6 w-6` (24px), with `justify-between` and brand hidden → button sits at the *start* of the flex row because it is the only rendered child. Icon center-x ≈ **20px** from aside left.
- **Expanded** (`md:w-56` aside = 224px): container `px-5` (20px), button on the right end → chevron `<` icon center-x ≈ **204px** from aside left (far right of aside).

### Settings sub-nav (`apps/web-platform/components/settings/settings-shell.tsx`)

Two separate chevron buttons exist:

```tsx
// settings-shell.tsx:40 — sub-nav expanded header
<nav className="... ${settingsCollapsed ? "md:w-0 md:overflow-hidden md:border-r-0" : "w-48 px-4 py-10"}">
  <div className="mb-4 flex items-center justify-between">
    <h2 ...>Settings</h2>
    <button
      aria-label="Collapse settings nav"
      className="flex h-6 w-6 items-center justify-center rounded text-neutral-400 hover:bg-neutral-800 hover:text-white"
    >
      <svg ...>...</svg>
    </button>
  </div>
  ...
</nav>

// settings-shell.tsx:104 — expand button rendered in content area when sub-nav collapsed
<div className="flex-1 px-4 py-10 pb-20 md:px-10 md:pb-10">
  {settingsCollapsed && (
    <button
      aria-label="Expand settings nav"
      className="hidden md:flex mb-4 h-8 w-8 items-center justify-center rounded-lg border border-neutral-800 text-neutral-400 hover:bg-neutral-800 hover:text-white"
    >
      <svg ...>...</svg>
    </button>
  )}
  <div className="mx-auto max-w-2xl">{children}</div>
</div>
```

- **Sub-nav expanded** (`w-48` = 192px, `px-4` = 16px): collapse `<` button is right-aligned inside the 192px sub-nav, chevron center-x ≈ **168px** from sub-nav left.
- **Sub-nav collapsed** (`md:w-0`): expand `>` button lives in the content area (`md:px-10` = 40px left padding), button is `h-8 w-8` (32px) and bordered, chevron center-x ≈ **56px** from content area left.

### Why they don't align

The two toggles were authored independently:

1. **Padding mismatch** — main nav uses `px-2` when collapsed; the Settings expand button sits at the content area's `md:px-10` (40px).
2. **Button size mismatch** — main nav uses `h-6 w-6` (24×24), Settings expand uses `h-8 w-8` (32×32) with a border.
3. **Vertical mismatch** — main nav chevron sits at `py-5` from aside top; Settings expand chevron sits at `py-10` + `mb-4` offset from content area top.

The two expand chevrons should occupy the same visual column *and* the same visual row, because they both live at the top-left corner of a navigation region and share the same semantic role (`>` = expand).

## Goals

1. When main nav is collapsed *and* Settings sub-nav is collapsed, both `>` chevrons line up on the same x-axis column (same left-padding / icon center-x within their respective containers).
2. When main nav is expanded *and* Settings sub-nav is collapsed, the Settings `>` expand chevron lines up with the main nav's `<` collapse chevron (same x-axis column in its region) so the transition between the two rails is visually consistent.
3. Vertical position: both chevrons share the same y-axis row (same top offset from viewport top) so the corner reads as one aligned toolbar.
4. No functional changes — click handlers, aria-labels, keyboard shortcuts, and storage keys remain unchanged.

## Non-Goals

- No redesign of the navigation structure.
- No change to mobile layout (bottom tab bar); this fix is desktop-only (`md:` breakpoint).
- No change to the Settings sub-nav *collapse* button (inside the expanded sub-nav header) — its position is intentional.
- No change to default collapse state or persistence behavior.

## Proposed Fix

Make the Settings sub-nav's **expand** button (rendered in the content area when `settingsCollapsed === true`) use the same dimensions, padding, and vertical offset as the main nav's toggle button. Concretely:

1. Move the Settings expand button out of the content area's padded box and into a dedicated top-left slot inside the sub-nav region, so it shares the same x-origin as the sub-nav border.
2. Use the same button size (`h-6 w-6`), same icon size (`h-4 w-4`), and no border — matching the main nav toggle exactly.
3. Use the same outer padding (`px-2 py-5` when sub-nav is collapsed, matching main nav's collapsed padding) so the chevron center-x within the sub-nav region matches the chevron center-x within the main nav region.
4. Keep the sub-nav `<nav>` element visible but zero-width when collapsed is not enough — we need a small fixed rail (e.g., `md:w-10` or keep `md:w-0` and render the expand button as a sibling rail). The simplest structure: always render the sub-nav `<nav>`; when collapsed, shrink it to a narrow rail (`md:w-10`) that holds only the expand button at `px-2 py-5`.

### Chosen approach: absolute-positioned chevron matching KB layout precedent

**This is the same pattern already used by `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx:318-328` for its collapsed-file-tree state.** Reusing the proven pattern keeps visual vocabulary consistent across the dashboard.

The KB layout places its expand chevron as:

```tsx
<button
  onClick={toggleKbCollapsed}
  aria-label="Expand file tree"
  title="Expand file tree (⌘B)"
  className="absolute left-2 top-5 z-10 flex h-6 w-6 items-center justify-center rounded text-neutral-400 hover:bg-neutral-800 hover:text-white"
>
  <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
    <path strokeLinecap="round" strokeLinejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
  </svg>
</button>
```

Key geometry insight — `left-2 top-5` mirrors the main nav header's `px-2 py-5`:

| Token | Value | Matches main nav |
|---|---|---|
| `left-2` | 8px | `px-2` left padding of main nav collapsed header |
| `top-5` | 20px | `py-5` top padding of main nav header |
| `h-6 w-6` | 24×24 | Same main nav button size |
| `h-4 w-4` (svg) | 16×16 | Same main nav chevron size |
| `z-10` | above content | Sits above any scrolling content below |

When both main nav and Settings sub-nav are collapsed:

- Main nav chevron: `px-2 py-5` inside `md:w-14` aside → icon's top-left at (8, 20) within aside, icon center at (16, 28) within aside.
- Settings chevron: `absolute left-2 top-5` inside content area (starts right after the aside) → icon's top-left at (8, 20) within content area, icon center at (16, 28) within content area.
- **Both chevrons share the same y-row at viewport-y ≈ 28px.** They sit in adjacent regions at the same vertical offset, reading as one aligned toolbar.

Rationale for this approach over alternatives:

- **Zero new layout vocabulary.** Reuses an existing, proven codebase pattern (KB).
- **Minimal diff.** No `<nav>` restructure, no narrow rail width, no flex-direction changes — just repositioning the existing button.
- **No `inert` migration.** The button lives in the content area `<div>`, outside `<nav>`, so `inert={settingsCollapsed || undefined}` on `<nav>` remains untouched. The existing accessibility contract (tab links unreachable when collapsed, expand button reachable) is preserved without code change.
- **Accessibility-preserving.** Screen readers still encounter the expand control after the main nav, consistent with the KB layout's reading order.

Prerequisite: The parent `<div className="flex-1 px-4 py-10 pb-20 md:px-10 md:pb-10">` must become `<div className="relative flex-1 px-4 py-10 pb-20 md:px-10 md:pb-10">` so the absolute-positioned button anchors to it rather than to the nearest positioned ancestor (which might be outside the settings region).

Trade-off considered — narrow-rail approach (original plan): making `<nav>` render as `md:w-10` when collapsed with the button inside. Rejected after discovering the KB precedent because (a) narrow rail introduces new styling vocabulary not used elsewhere, (b) requires `inert` migration from `<nav>` to `<ul>` (non-trivial accessibility change), (c) increases diff surface, and (d) diverges from the KB layout that sets the dashboard's visual pattern.

### Expected pixel alignment after fix

| State | Main nav chevron center-x | Settings chevron center-x | Aligned? |
|---|---|---|---|
| Both collapsed | 20px (inside 56px aside, px-2) | 20px (inside 40px rail, px-2) — but offset by 56px viewport origin → viewport x ≈ 76px | Same column *inside their region*; visually adjacent aligned chevrons |
| Main collapsed + Settings expanded | 20px (main) | right edge of 192px sub-nav (different role: collapse `<`) | N/A — intentional |
| Main expanded + Settings collapsed | 204px (right edge of 224px aside) | 20px (inside 40px rail) — viewport x ≈ 244px | Same y-row; chevrons read as a toolbar |
| Both expanded | 204px (collapse `<`) | right edge of sub-nav (collapse `<`) | Both pointing `<` on the right edge of their region |

The key constraint the user identified is **same y-row and same in-region x-origin** for the expand affordance, which this fix achieves.

## Research Reconciliation — Spec vs. Codebase

| Claim in feature description | Codebase reality | Plan response |
|---|---|---|
| "The `>` expand icon ... is not horizontally aligned" | Confirmed — two separate buttons with different sizes (`h-6 w-6` vs `h-8 w-8`), different padding (`px-2` vs `md:px-10`), different vertical offsets. | Unify geometry; chosen approach uses narrow rail at `md:w-10 px-2 py-5` to match main nav. |
| "misalignment happens both when the main nav is collapsed and when it is expanded" | Partially confirmed — when main is expanded, both regions show their respective toggles on opposite ends (main right-edge collapse, settings left-edge expand); they don't share a column but *do* share a y-row if offsets match. | Plan targets shared y-row (top offset) in the expanded-main case, and shared in-region x-origin when both collapsed. |
| Fix is "same left padding / column" | Literal same left padding across unrelated containers would not fix alignment because the containers have different widths. | Normalize *button geometry* (size, padding from nearest nav-region edge, and top offset), not raw viewport-x. |

## Affected Files

- `apps/web-platform/components/settings/settings-shell.tsx` — primary change (restructure collapsed-state rendering into a narrow rail).
- `apps/web-platform/test/settings-sidebar-collapse.test.tsx` — update existing tests if any DOM structure assertion changes; add an alignment-focused test.

No other files should change. The main nav layout (`apps/web-platform/app/(dashboard)/layout.tsx`) is the reference geometry and stays untouched.

## Implementation Phases

### Phase 1 — Failing tests (RED)

Write/extend tests in `apps/web-platform/test/settings-sidebar-collapse.test.tsx`:

1. **Test: "expand button has KB-style alignment classes when collapsed"**
   - Render `<SettingsShell>`, click the collapse toggle, then assert the expand button's `className` contains all of: `absolute`, `left-2`, `top-5`, `z-10`, `h-6`, `w-6`.
2. **Test: "expand button icon size matches main nav chevron (h-4 w-4)"**
   - After collapsing, query `button[aria-label="Expand settings nav"] > svg`, assert its `className` contains `h-4` and `w-4`.
3. **Test: "expand button has no border (matches main nav toggle)"**
   - Assert the expand button's `className` string does not contain `border`.
4. **Test: "expand button is hidden on mobile (hidden md:flex)"**
   - Assert the expand button's `className` contains both `hidden` and `md:flex`.
5. **Test: "content area parent has relative positioning"**
   - After collapsing, walk up from the expand button to its parent `<div>`, assert that parent's `className` contains `relative`. This prevents the "button anchors to wrong ancestor" bug.
6. **Test: "no duplicate expand button exists"**
   - After collapsing, assert `screen.getAllByLabelText("Expand settings nav").length === 1`.

Run: `cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-settings-nav-chevron-align/apps/web-platform && ./node_modules/.bin/vitest run test/settings-sidebar-collapse.test.tsx` — confirm new assertions FAIL on current code. (Per `cq-in-worktrees-run-vitest-via-node-node`, run vitest via the app-local binary.)

**Test implementation note:** Use `toHaveClass("absolute", "left-2", "top-5", ...)` from `@testing-library/jest-dom` for clean matchers. Avoid brittle string-contains on `className` where possible.

### Phase 2 — Implementation (GREEN)

Edit `apps/web-platform/components/settings/settings-shell.tsx`:

1. Change the content area `<div>` from `<div className="flex-1 px-4 py-10 pb-20 md:px-10 md:pb-10">` to `<div className="relative flex-1 px-4 py-10 pb-20 md:px-10 md:pb-10">` — adds `relative` so the absolute-positioned expand button anchors to it.
2. Replace the existing expand button (currently at `settings-shell.tsx:106-116`) with the KB-style absolute-positioned version:

   ```tsx
   {settingsCollapsed && (
     <button
       onClick={toggleSettingsCollapsed}
       aria-label="Expand settings nav"
       title="Expand settings nav (⌘B)"
       className="absolute left-2 top-5 z-10 hidden md:flex h-6 w-6 items-center justify-center rounded text-neutral-400 hover:bg-neutral-800 hover:text-white"
     >
       <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
         <path strokeLinecap="round" strokeLinejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
       </svg>
     </button>
   )}
   ```

   Key changes from current code:
   - Dimensions: `h-8 w-8` → `h-6 w-6` (match main nav).
   - Border: removed (`border border-neutral-800` deleted — match main nav).
   - Corner radius: `rounded-lg` → `rounded` (match main nav).
   - Margin: `mb-4` removed (absolute positioning doesn't use it).
   - Added: `absolute left-2 top-5 z-10 hidden md:flex` (KB pattern).

3. Leave `<nav>` and its collapse button (the one inside the expanded sub-nav header) unchanged.
4. Leave `inert={settingsCollapsed || undefined}` on `<nav>` unchanged — the expand button lives outside `<nav>` so `inert` doesn't affect it.
5. No other changes required. The tab list and mobile tab bar are unaffected.

Full diff is ~15 lines net. Run: `./node_modules/.bin/vitest run test/settings-sidebar-collapse.test.tsx` — confirm tests now PASS. Also run the full test file to catch incidental regressions: `./node_modules/.bin/vitest run test/settings-sidebar-collapse.test.tsx`.

### Phase 3 — Visual verification (manual QA)

1. Start dev server: `cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-settings-nav-chevron-align/apps/web-platform && ./scripts/dev.sh`.
2. Use Playwright MCP (per `hr-never-label-any-step-as-manual-without`) to navigate to `/dashboard/settings` at md+ viewport (e.g., 1280×800), then:
   - Screenshot the top-left corner with main nav collapsed + settings collapsed. Verify the two chevrons share a y-row and both live at the top-left of their respective regions.
   - Screenshot with main nav expanded + settings collapsed. Verify the two chevrons share a y-row.
   - Screenshot with main nav collapsed + settings expanded. Verify no regression (collapse-settings button still on the right of the sub-nav header).
   - Screenshot with main nav expanded + settings expanded. Verify no regression.
3. Compare pixel alignment in the captured screenshots. If chevron y-positions differ, tune `py-*` on the collapsed `<nav>` until they match.
4. `browser_close` when done (per `cq-after-completing-a-playwright-task-call`).

### Phase 4 — Regression checks

1. Keyboard shortcut: Cmd/Ctrl+B on `/dashboard/settings` still toggles the sub-nav (existing test covers this).
2. Input focus: Cmd+B while focused in an input still doesn't toggle (existing test covers this).
3. localStorage persistence: `soleur:sidebar.settings.collapsed` still reads/writes correctly across reloads.
4. Mobile (< md): the `<nav>` is `hidden md:block` — verify the bottom tab bar still renders and the new narrow rail doesn't leak into mobile.
5. `inert` attribute migration: verify that when sub-nav is collapsed, tab `<Link>` elements are non-interactive (cannot receive focus via Tab key) while the expand button IS interactive.

### Phase 5 — Commit + ship

1. Run `npx markdownlint-cli2 --fix` on the plan file only (per `cq-markdownlint-fix-target-specific-paths`).
2. Run `skill: soleur:compound` (per `wg-before-every-commit-run-compound-skill`).
3. Commit: `fix(settings-nav): align expand chevron with main nav chevron`.
4. Push and open PR via `skill: soleur:ship` with `type/bug` and `priority/p3-low` labels (per `cq-gh-issue-label-verify-name` — verified namespace).

## Acceptance Criteria

- [x] When main nav is collapsed and user navigates to `/dashboard/settings`, the Settings sub-nav's expand `>` chevron sits in the same y-row as the main nav's expand `>` chevron.
- [x] Both chevrons have identical SVG size (`h-4 w-4`) and identical button size (`h-6 w-6`).
- [x] The Settings expand chevron has no border (matching main nav chevron styling).
- [x] When main nav is expanded and Settings is collapsed, the two chevrons share a y-row (top offset from viewport top).
- [x] No duplicate expand button exists in the DOM — only one `aria-label="Expand settings nav"` element at any time.
- [x] Keyboard shortcut Cmd/Ctrl+B on `/dashboard/settings` still toggles the sub-nav.
- [x] localStorage key `soleur:sidebar.settings.collapsed` still persists state across reloads.
- [x] Mobile bottom tab bar is unaffected.
- [x] `./node_modules/.bin/vitest run test/settings-sidebar-collapse.test.tsx` passes with ≥ 4 new/updated assertions covering the alignment contract.
- [x] Playwright screenshots at 1280×800 show visual alignment between the two chevrons in all four nav-state combinations.

## Test Scenarios

1. **Both navs collapsed on /dashboard/settings** — expand chevrons aligned at top-left, different x-columns (because they're in different regions) but same y-row.
2. **Main collapsed, Settings expanded** — main's `>` at top-left; settings' `<` (collapse) at right edge of sub-nav header. No alignment required between them (different roles).
3. **Main expanded, Settings collapsed** — main's `<` (collapse) at right edge of aside; settings' `>` (expand) at top of narrow rail. Same y-row so they form a single visual line.
4. **Both expanded** — main's `<` at right of aside; settings' `<` at right of sub-nav header. No alignment required (both right-aligned in their regions).
5. **Cmd+B toggles, focus-safe** — existing tests remain green.
6. **Mobile viewport (< md)** — sub-nav is `hidden`, bottom tab bar renders; no visual regression from the desktop-only changes.
7. **localStorage persistence** — collapse state persists across reloads.
8. **`inert` correctness** — when sub-nav is collapsed, tab links cannot be reached via Tab; the expand button CAN be reached via Tab.

## Domain Review

**Domains relevant:** Product (ADVISORY — modifies existing user-facing UI without adding new interactive surfaces or multi-step flows)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (ADVISORY + pipeline mode — no brainstorm-recommended specialists; geometry-only change with an explicit visual QA step via Playwright)
**Pencil available:** N/A

#### Findings

This is a cosmetic alignment fix with no new user-facing surfaces, no new flows, no copy changes, and no interactive affordances added or removed. Per the Product/UX Gate ADVISORY rubric running in pipeline mode, the gate auto-accepts and proceeds silently. The manual visual QA step in Phase 3 (Playwright screenshots of all four nav-state combinations) provides the alignment validation that a UX review would otherwise check by eye.

## Risk & Blast Radius

- **Blast radius:** low — a single component file (`settings-shell.tsx`) plus its test file. No routing changes, no API changes, no database changes, no dependency changes.
- **Risk of regression:** low — the `inert` migration from `<nav>` to `<ul>` is the only subtle piece; existing tests plus a new focus test cover it.
- **Rollback:** trivial — revert the single commit.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Narrow rail (`md:w-10`) holding the button inside `<nav>` | Diverges from KB layout's established pattern. Requires `inert` migration from `<nav>` to `<ul>` with the associated a11y risk. Larger diff. |
| Keep `md:w-0` and add `sticky` positioning | Sticky still anchors to the content area's top; the y-offset from `py-10` + `mb-4` mismatches the main nav's `py-5`. |
| Raise the Settings expand button into the main nav header (hybrid toolbar) | Couples two independent layout responsibilities (dashboard shell + settings sub-shell) — high architectural cost for a cosmetic fix. |
| Change main nav instead (make it match current Settings offsets) | The main nav's geometry is the established pattern across the app (KB, dashboard). Changing it would ripple through screenshots and visual tests. |
| **Chosen: `absolute left-2 top-5 z-10` in content area (KB precedent)** | **Matches existing KB layout pattern exactly. Zero `inert` changes. Minimal diff (~15 lines).** |

## Open Questions

None — the scope is self-contained and the chosen approach is the minimal change that satisfies the alignment contract.

## References

- `apps/web-platform/app/(dashboard)/layout.tsx` — main nav layout (reference geometry, read-only in this change)
- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx:318-328` — **chosen-approach precedent** (same absolute-positioned chevron pattern for KB file tree)
- `apps/web-platform/components/settings/settings-shell.tsx` — primary edit target
- `apps/web-platform/test/settings-sidebar-collapse.test.tsx` — test file to extend
- `apps/web-platform/hooks/use-sidebar-collapse.ts` — shared collapse hook (read-only)
- AGENTS.md rules applied: `cq-in-worktrees-run-vitest-via-node-node`, `cq-after-completing-a-playwright-task-call`, `cq-markdownlint-fix-target-specific-paths`, `hr-never-label-any-step-as-manual-without`, `wg-before-every-commit-run-compound-skill`

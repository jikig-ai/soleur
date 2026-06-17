---
feature: KB sidebar resize handle — straight vertical bar (replace faint dot triad)
branch: feat-one-shot-kb-sidebar-resize-handle-bar
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-17-feat-kb-sidebar-resize-handle-bar-plan.md
date: 2026-06-17
---

# Tasks — KB sidebar resize handle vertical bar

Derived from the finalized (deepened) plan. Scope: ONE component (`apps/web-platform/components/dashboard/rail-resize-handle.tsx`) + ONE new test assertion. No behavior/a11y/props/persistence change.

> Typecheck for `apps/web-platform`: run from inside the package — `npm run typecheck` (declared script = `tsc --noEmit`). NOT `npm run -w …`.
> Tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/rail-resize-handle.test.tsx`.

## Phase 1 — Preconditions

- [ ] 1.1 Confirm the dot triad is still present: `grep -n 'rounded-full' apps/web-platform/components/dashboard/rail-resize-handle.tsx` → 3 hits at lines 105/106/107 (inside the centering `<div>` wrapper at 104-108).
- [ ] 1.2 Confirm tokens exist: `grep -n 'soleur-text-secondary\|soleur-text-muted' apps/web-platform/app/globals.css`.
- [ ] 1.3 Confirm vitest collects the test: `grep -n 'include' apps/web-platform/vitest.config.ts` shows the jsdom/component project glob `test/**/*.test.tsx`.

## Phase 2 — Replace the grip markup (FR1-FR5, FR7)

- [ ] 2.1 In `rail-resize-handle.tsx`, replace the three dot `<span>`s (105-107) inside the centering wrapper `<div>` (104-108) with a single vertical-bar grip element:
  ```tsx
  <div className="pointer-events-none absolute inset-y-0 left-1/2 flex -translate-x-1/2 items-center justify-center">
    <span
      data-testid="kb-rail-resize-grip"
      className="h-8 w-0.5 bg-soleur-text-muted group-hover:bg-soleur-text-secondary"
    />
  </div>
  ```
  - `w-0.5 h-8` (2px × 32px) short centered grip; NO `rounded-*` class (sharp corners, brand-compliant).
  - Idle `bg-soleur-text-muted` → `group-hover:bg-soleur-text-secondary` (real brighten — NOT the same-token no-op).
  - `pointer-events-none` keeps the drag on the parent handle `<div>`.
- [ ] 2.2 Update the component's leading comment block: "vertical bar grip" instead of "grip dots" (FR7).
- [ ] 2.3 Leave everything else byte-for-byte: `role="separator"`, `aria-*`, `tabIndex`, `data-testid="kb-rail-resize-handle"`, all pointer/keyboard handlers, `clamp`, `transition-colors duration-150`, `hidden md:block`, `cursor-col-resize`, `touch-none`, `RailResizeHandleProps` (FR6).

## Phase 3 — Test (FR3 / AC6)

- [ ] 3.1 Add ONE `it("renders the vertical-bar grip", …)` to `apps/web-platform/test/rail-resize-handle.test.tsx` asserting `screen.getByTestId("kb-rail-resize-grip")` is in the document. Do NOT touch the existing 6 assertions.

## Phase 4 — Verify (AC1-AC8)

- [ ] 4.1 Typecheck: `cd apps/web-platform && npm run typecheck` exits 0 (AC7).
- [ ] 4.2 Tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/rail-resize-handle.test.tsx` — all 7 pass (AC5/AC6).
- [ ] 4.3 `grep -c 'rounded-full' apps/web-platform/components/dashboard/rail-resize-handle.tsx` → 0 (AC1).
- [ ] 4.4 `grep -c 'kb-rail-resize-grip' apps/web-platform/components/dashboard/rail-resize-handle.tsx` → 1 (AC2).
- [ ] 4.5 The grip's className contains no `rounded` token (AC3); no raw hex `[#...]` (AC4); `grep -c 'transition-all' …` → 0 (AC8).
- [ ] 4.6 (Optional) Run the frontend-anti-slop scanner on the file — confirm the prior `rounded-full` advisory is gone and no new HIGH finding appeared.

## Phase 5 — Post-merge (operator / automated)

- [ ] 5.1 (AC10) Playwright MCP: navigate to the dashboard KB route, drill into KB to expand the rail, screenshot the `[data-testid="kb-rail-resize-handle"]` region, assert `kb-rail-resize-grip` is visible. Run in `/soleur:ship` post-merge verification or `/soleur:test-browser` — not operator-eyeball.
- [ ] 5.2 File the deferral follow-up issue (framed as a *design question* per CPO): "does the vertical-bar grip idiom work centered between two content panes, or do `Separator`-based pane-splitters (`kb-desktop-layout.tsx`, `c4-workspace.tsx`) want a different treatment?" — NOT "make the other two match."

## Acceptance Criteria (cross-reference)

See the plan's `## Acceptance Criteria` (Pre-merge AC1-AC9, Post-merge AC10). The `.pen` wireframe (AC9) is already committed at `knowledge-base/product/design/kb/kb-sidebar-resize-handle-bar.pen`.

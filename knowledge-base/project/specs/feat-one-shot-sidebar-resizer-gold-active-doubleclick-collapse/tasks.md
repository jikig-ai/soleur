# Tasks — Sidebar resizer: gold active + double-click-to-collapse

lane: cross-domain
Plan: `knowledge-base/project/plans/2026-06-18-feat-sidebar-resizer-gold-active-doubleclick-collapse-plan.md`
Wireframes: `knowledge-base/product/design/dashboard/sidebar-resizer-gold-doubleclick.pen`

> **Plan-of-record = FR3-Alternative** (keep the floated collapse button; add double-click as a
> KB-only accelerator; gold active on all 3 handles). FR3-Literal (remove the button) is opt-in
> and adds tasks 3.x — see plan. **Confirm the FR3 choice with the operator before starting
> Phase 3.**

## Phase 1 — Gold active state (all 3 handles) [lowest risk]

- [ ] 1.1 `components/dashboard/rail-resize-handle.tsx:104` — swap `focus-visible:bg-amber-500/50`
      and `active:bg-amber-500/50` → `focus-visible:bg-soleur-accent-gold-fill/50
      active:bg-soleur-accent-gold-fill/50`. Hover stays `hover:bg-soleur-text-secondary/50`.
- [ ] 1.2 `components/kb/kb-desktop-layout.tsx:20` — swap `active:bg-amber-500/50
      data-[resize-handle-active]:bg-amber-500/50` → gold token form.
- [ ] 1.3 `components/kb/c4-workspace.tsx:25` — same swap.
- [ ] 1.4 Add a one-line comment on the kb-desktop-layout + c4-workspace Separators:
      double-click-collapse intentionally NOT wired (between-pane splitters, no collapsed-width
      state). (AC10)
- [ ] 1.5 Verify AC11 contrast: confirm gold `/50` over `bg-surface-1` ≥ 3:1; raise to `/70` if
      marginal (base #c9a962/#141414 = 7.77:1 at full opacity).

## Phase 2 — Double-click-to-collapse on the KB rail resizer (RED first)

- [ ] 2.1 Write failing vitest cases in `test/rail-resize-handle.test.tsx`: double-click fires
      `onCollapse` once (AC5); drag-then-click does NOT collapse and does NOT persist a no-op
      width (AC6). **First** assert empirically whether `onDoubleClick` fires after a drag — if
      not, drop the 5px travel guard, keep only the `latest === startWidth` no-op-commit skip.
- [ ] 2.2 Extend `RailResizeHandleProps` with `onCollapse: () => void`; add guarded
      `onDoubleClick`; skip no-op `onCommit`. (GREEN)
- [ ] 2.3 Wire `onCollapse={toggleCollapsed}` at the KB-only mount in `(dashboard)/layout.tsx`
      (gate stays `kbExpanded` — do NOT widen). (AC5)

## Phase 3 — FR3 choice [confirm with operator]

### Phase 3-Alt (plan-of-record): keep the button
- [ ] 3a.1 No layout change beyond task 2.3. The floated `PanelToggleIcon` button + ⌘B remain
      the universal collapse/expand affordance. (AC9 — ⌘B unchanged)

### Phase 3-Literal (opt-in only — if operator confirms "remove the button"):
- [ ] 3b.1 Remove the floated `PanelToggleIcon` `<button>` (`layout.tsx:~367-374`) + the unused
      `PanelToggleIcon` SVG (`~709-726`). (AC4)
- [ ] 3b.2 Add a separate thin collapse-edge component (cursor-pointer, NO role=separator, NO
      aria-valuenow, `aria-label="Collapse sidebar"`, Enter/Space + double-click → toggleCollapsed)
      for non-KB expanded states. Keep `RailResizeHandle` KB-only. (AC7', AC-KBD)
- [ ] 3b.3 Add a fetch-independent collapsed-rail expand chevron (`aria-label="Expand sidebar"`)
      that calls toggleCollapsed; renders unconditionally in the collapsed branch. (AC8, AC8b)
- [ ] 3b.4 Tests: cold-boot-collapsed (localStorage="1") → chevron present + fires (AC8b);
      Enter on collapse target collapses (AC-KBD); non-KB collapse-edge mounts, resize separator
      stays KB-only (AC7'). Reserve clearance for the chevron in BOTH branches.

## Phase 4 — Verification

- [ ] 4.1 `grep -rn 'amber-500'` across the 3 handle files → 0 (AC2). Repo-wide resize/separator
      scope → 0, leaving only the dashboard dropzone amber (AC14).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes (AC12).
- [ ] 4.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/rail-resize-handle.test.tsx`
      + any new layout test pass (AC13). New tests live under `test/**/*.test.tsx` (vitest jsdom
      glob) — NOT co-located.
- [ ] 4.4 Post-merge: Playwright visual verify (gold on drag, grey on hover, double-click
      collapse, chevron/button expand) via `/soleur:qa` or test-browser (AC15) — automatable, not
      a manual checklist.

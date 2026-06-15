---
title: "Tasks — fix: Concierge chat box layout"
plan: knowledge-base/project/plans/2026-06-15-fix-concierge-box-layout-plan.md
branch: feat-one-shot-concierge-box-layout
lane: single-domain
---

# Tasks — fix: Concierge chat box layout

Derived from `2026-06-15-fix-concierge-box-layout-plan.md`. Land all three fixes in one PR.

## Phase 1 — Setup

- [ ] 1.1 Read the three target files before editing (`debug-stream-panel.tsx`, `message-bubble.tsx`,
      `debug-stream-panel.test.tsx`) per `hr-always-read-a-file-before-editing-it`.

## Phase 2 — Core Implementation

### 2.1 Issue 3 — restore "Show" toggle clickability (`debug-stream-panel.tsx`)
- [ ] 2.1.1 Move the `{expanded ? "Hide" : "Show"}` text INSIDE the toggle `<button>` (the
      `aria-expanded` one), e.g. as a trailing `<span className="ml-auto ...">` so its visual
      right-aligned position is preserved.
- [ ] 2.1.2 Remove the orphaned `Show/Hide` `<span>` from the right-side sibling `<div>`; keep
      "· not saved" as a static caption beside the Copy button.
- [ ] 2.1.3 Confirm Copy remains a SIBLING button (not nested in the toggle) — #5241 invariant.

### 2.2 Issues 1 + 2 — Concierge bubble alignment + shrink-to-fit (`message-bubble.tsx`)
- [ ] 2.2.1 (Issue 1) Move `LeaderAvatar` from the row-level position (L178-180) INTO the in-card
      header `div` (`mb-1 flex items-center gap-2`, L207-219) as its first child, with `size="sm"`
      and the `customIconPath` thread preserved. Remove the row-level avatar. Card left edge then =
      row/wrapper left edge. Do NOT touch the `isUser` (right-aligned) branch. (No negative margins —
      the deepen-pass rejected that approach for off-screen clipping on narrow viewports.)
- [ ] 2.2.2 (Issue 2) Add `w-fit max-w-full` to the assistant card (`data-testid="message-bubble-card"`)
      so short content (e.g. "Routing to the right experts...") does not wrap; keep `min-w-0` so long
      content still wraps.
- [ ] 2.2.3 (Issue 2) Add a `min-w-[…]` floor to the assistant card sized for the absolute
      `right-3 -top-2.5` badges, so a short `done` bubble does not let `w-fit` collapse the card
      narrower than the badge (which would overhang the left edge). Tune the value at /work.

## Phase 3 — Testing

- [ ] 3.1 Extend `test/components/debug-stream-panel.test.tsx`: assert toggle button `textContent`
      contains "Show" when collapsed; clicking "Show" flips `aria-expanded` false→true; Copy still
      not a descendant and does not toggle (AC1). NO new message-bubble unit test (happy-dom cannot
      verify layout — Playwright owns issues 1+2).
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes (AC4).
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/debug-stream-panel.test.tsx` passes, incl. existing Copy tests (AC5).

## Phase 4 — QA (at /work, automated)

- [ ] 4.1 Playwright MCP visual check (AC6): Concierge box left edge aligns with Debug panel; routing
      chip on one line; a short `done` bubble's badge does not overhang the left edge; clicking the
      word "Show" toggles the panel.

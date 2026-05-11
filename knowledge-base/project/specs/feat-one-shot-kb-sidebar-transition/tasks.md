---
title: "KB sidebar transition — Tasks"
feature: feat-one-shot-kb-sidebar-transition
date: 2026-05-11
plan: knowledge-base/project/plans/2026-05-11-feat-kb-sidebar-transition-plan.md
---

# KB sidebar transition — Tasks

## Phase 1 — Refactor KB desktop layout to drop the file-tree `<Panel>`

- [ ] 1.1 In `apps/web-platform/components/kb/kb-desktop-layout.tsx`, replace the
       file-tree `<Panel>` + its trailing `<ResizeHandle>` with a plain `<aside>`
       sibling of an inner `<Group>` that holds the doc + chat panels.
- [ ] 1.2 Apply `md:transition-[width] md:duration-200 md:ease-out
       md:overflow-hidden` to the new `<aside>`; toggle `md:w-0 md:border-r-0` vs
       `md:w-72` on `kbCollapsed`.
- [ ] 1.3 Wrap `<KbSidebarShell>` in a fixed-width inner `<div>` with
       `w-72 px-... py-...` so the SETTINGS-style "header + tree stays at
       (16, 20)" invariant holds.
- [ ] 1.4 Apply `inert={kbCollapsed || undefined}` on the new `<aside>`.
- [ ] 1.5 In `apps/web-platform/hooks/use-kb-layout-state.tsx`, simplify
       `toggleKbCollapsed` to a single `setKbCollapsed((p) => !p)` on both
       desktop and mobile.
- [ ] 1.6 Remove `sidebarPanelRef` from `useKbLayoutState`'s `usePanelRef()`
       allocation and from `UseKbLayoutStateResult`. Remove the
       `onResize(size) => setKbCollapsed(size.asPercentage < 1)` wiring.
- [ ] 1.7 Confirm `chatPanelRef` (the chat-vs-doc resize handle) is still used by
       the inner `<Group>` (it is — only the file-tree panel ref goes away).

## Phase 2 — Animate the doc viewport's left-anchor in sync

- [ ] 2.1 In `apps/web-platform/components/kb/kb-doc-shell.tsx`, add
       `md:transition-[padding] md:duration-200 md:ease-out` to the content well
       in BOTH collapsed and expanded states (NOT conditional).
- [ ] 2.2 Keep the existing `pl-10` only when `collapsed` is true; expanded
       state has no extra left padding (sidebar provides it via its right border).

## Phase 3 — Tests

- [ ] 3.1 Extend `apps/web-platform/test/kb-sidebar-collapse.test.tsx` with a new
       `describe` block: "sidebar transition contract" mirroring the four asserts
       in `settings-sidebar-collapse.test.tsx` lines 149-197:
       (a) `md:transition-[width] md:duration-200 md:ease-out` on `<aside>` in
       both states;
       (b) inner wrapper carries `w-72 px-... py-...` and `<aside>` does NOT
       carry the padding (so `md:w-0` collapses fully);
       (c) collapsed `<aside>` matches `md:w-0`, `md:border-r-0`,
       `md:overflow-hidden`;
       (d) `KbDocShell` content well carries `md:transition-[padding]
       md:duration-200 md:ease-out` in both states.
- [ ] 3.2 `bun run --cwd apps/web-platform test
       apps/web-platform/test/kb-sidebar-collapse.test.tsx` is green.
- [ ] 3.3 `bun run --cwd apps/web-platform tsc --noEmit` is green.

## Phase 4 — Manual visual confirmation

- [ ] 4.1 Run `bun run --cwd apps/web-platform dev`; open `/dashboard/kb` at
       ≥768 px.
- [ ] 4.2 Toggle via chevron and via ⌘B — confirm 200 ms ease-out width slide,
       no snap, no flash.
- [ ] 4.3 Open a doc + open chat — confirm doc-vs-chat resize handle still
       drags inside the inner `<Group>`.
- [ ] 4.4 Resize to <768 px and verify the mobile `hidden`/`block` class swap
       is unaffected.

## Phase 5 — Deferral tracking

- [ ] 5.1 File `feat(kb): persist file-tree sidebar collapse state to
       localStorage` issue with `area/kb` label and milestone from
       `knowledge-base/product/roadmap.md` (default `Post-MVP / Later`).
- [ ] 5.2 File `feat(kb): restore drag-resize on file-tree sidebar` issue with
       `area/kb` label and milestone `Post-MVP / Later`. Re-evaluation
       criterion: 2+ Discord requests for wider file tree.

## Phase 6 — Learnings (post-merge, only if a session error occurred)

- [ ] 6.1 If any silent failure surfaced during the work (Panel re-layout
       glitch, transition tossed mid-render, etc.), write a learning at
       `knowledge-base/project/learnings/bug-fixes/<topic>.md`.

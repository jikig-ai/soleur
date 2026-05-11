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

- [ ] 3.1 Create `apps/web-platform/test/kb-sidebar-transition.test.tsx` with
       `useMediaQuery: () => true` (desktop mode). Mirror the four asserts
       in `settings-sidebar-collapse.test.tsx` lines 149-197:
       (a) `md:transition-[width] md:duration-200 md:ease-out` on `<aside>` in
       both open and collapsed states;
       (b) inner wrapper carries `w-72` and `<aside>` does NOT carry `px-*` /
       `py-*` (so `md:w-0` + `box-border` collapses fully; #3585 lesson);
       (c) collapsed `<aside>` matches `md:w-0`, `md:border-r-0`,
       `md:overflow-hidden`;
       (d) `KbDocShell` content well carries `md:transition-[padding]
       md:duration-200 md:ease-out` in both states (#3573 lesson — class
       must be unconditional).
- [ ] 3.2 Leave `apps/web-platform/test/kb-sidebar-collapse.test.tsx`
       untouched — its mobile-mode mock validates click/keyboard/input-focus
       contracts which still hold.
- [ ] 3.3 `bun run --cwd apps/web-platform test
       apps/web-platform/test/kb-sidebar-transition.test.tsx
       apps/web-platform/test/kb-sidebar-collapse.test.tsx` is green.
- [ ] 3.4 `bun run --cwd apps/web-platform tsc --noEmit` is green.

## Phase 4 — Manual visual confirmation

- [ ] 4.1 Try `bun run --cwd apps/web-platform dev`; open `/dashboard/kb` at
       ≥768 px. If the dev server fails with the `instrumentation.ts` ESM
       error, fall back to a Vercel preview build of the branch and document
       `#3562` as the local-QA blocker in the PR body.
- [ ] 4.2 Toggle via chevron and via ⌘B — confirm 200 ms ease-out width slide,
       no snap, no flash, no 32 px sliver in the collapsed state.
- [ ] 4.3 Open a long markdown doc — confirm body text does NOT drift
       horizontally during the transition. If it does, add a collapsed-state
       `md:pl-[...rem]` anchor pad to `KbDocShell`'s content well (settings
       #3579 pattern; specific value: `w-72` ÷ 16 + chosen pad).
- [ ] 4.4 Open a PDF doc — confirm the PDF page does NOT drift horizontally
       during the transition. Same mitigation as 4.3 if needed.
- [ ] 4.5 Open a doc + open chat — confirm doc-vs-chat resize handle still
       drags inside the inner `<Group>`.
- [ ] 4.6 Resize to <768 px and verify the mobile `hidden`/`block` class swap
       is unaffected; the `md:`-prefixed transition classes are inert below
       the breakpoint.

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

---
title: The KB file tree has ONE mount whose host is a derived value, not a second render site
status: active
date: 2026-08-03
related_adrs: [ADR-047]
related: [7186, 6917, 6874, 4810]
related_plans:
  - knowledge-base/project/plans/2026-08-03-fix-kb-mobile-drill-in-navigation-plan.md
brand_survival_threshold: single-user incident
---

# ADR-158: The KB file tree mounts once; its host is a single derived value

## Context

ADR-047 lifted the KB file tree out of the content column into the single nav rail's
secondary slot, portaled from `kb/layout.tsx`. On desktop the rail is always visible, so
that is a strict improvement. On a phone the rail IS the hamburger drawer — so
`/dashboard/kb` rendered a content column with nothing in it until a document was already
selected.

Two prior passes treated the symptom. #6915 and #6917 added, then improved, an empty state
in the content column ("Open a file to see it here" plus a button that popped the drawer
open). That removed the blank-pane confusion without giving the surface a navigation
model, and the repeat is itself the signal: the KB had no mobile list view.

The obvious fix — render the tree in the content column on mobile *as well* — is the one
that has already regressed in this codebase. PR #6874's first commit CSS-dual-rendered the
desktop Workstream board and its mobile counterpart; happy-dom has no media queries, so
both trees mounted, every card matched twice, 12 tests failed with "Found multiple
elements", and the hidden board's `sessionStorage` effect ran on desktop. ADR-047 rejects
the same shape for the same reason.

## Decision

**The tree has exactly one mount. Its HOST is a single derived value.**

`useKbLayoutState` computes

```ts
const treeHost: "rail" | "content" =
  !isDesktop && !fullWidth && !isContentView ? "content" : "rail";
```

and both consumers read that one value: the rail portal in
`app/(dashboard)/dashboard/kb/layout.tsx` renders `<KbSidebarShell />` only when
`treeHost === "rail"`, and `KbMobileLayout` renders `<KbSidebarShell host="content" />`
only when it is `"content"`. The host is `"content"` in exactly one cell — mobile,
populated tree, landing route — and `"rail"` everywhere else, including every mobile
`fullWidth` state and the mobile document route.

This is deliberately ONE value rather than two conditions that agree. Two agreeing
conditions is how a second tree gets mounted the first time either one is edited, and it
is what the plan's own v2 shipped before review caught it.

Corollaries the implementation must preserve:

- **No CSS dual-render of the tree.** `hidden md:flex` / `md:hidden` twins of a stateful
  component mount both. Chrome that duplicates nothing (the existing `md:hidden` header)
  is unaffected.
- **Collapse is a rail concept.** `RailCollapsedProvider` wraps `<main>`, not just the
  rail, so a content-column host would otherwise inherit it and a user who collapsed their
  desktop rail would get a 56px icon strip as their entire phone browse view. The shell
  guards with `useRailCollapsed() && host === "rail"`. The provider cannot be narrowed
  instead — the portaled shell reads it through the REACT tree, which is exactly what
  ADR-047 Decision 2 relies on.

## Two structural safety facts

These are why gating a render on a viewport-derived value is safe *here* and must be
re-checked before it is copied elsewhere:

1. **No viewport-derived value reaches the hydration render.** Note the mechanism, because an
   earlier draft of this ADR stated it backwards: `!isDesktop` is the FIRST operand, so nothing
   short-circuits before it is read. What actually holds is that `fullWidth === true` forces the
   `"rail"` arm *regardless* of `isDesktop`, and `fullWidth` is true at hydration because
   `swrKeys.kbTree()` is never seeded pre-hydration — `lib/swr-config.ts` uses a plain in-memory
   Map provider with no `fallbackData` and no SSR prefetch.

   **This is therefore a CONDITIONAL invariant, not a structural one.** Adding `fallbackData`, an
   SSR prefetch of the KB tree, or a persisted cache provider — all natural continuations of
   ADR-067 — would make the layout's `isDesktop` branch a genuine server/client hydration
   mismatch. The behavioural pin (identical `innerHTML` at both viewports, asserted for the EMPTY
   fixture) pins that the fullWidth block is viewport-invariant; it does NOT pin that the
   fullWidth block is what renders at hydration. Anyone seeding that SWR key must re-check this.
2. **`RailSlotPortal` returns `null` until its container ref callback fires.** The portal
   side is never server-rendered, so gating its child on `treeHost` cannot produce a
   hydration mismatch. Note such a mismatch would be *invisible* in production — React
   does not reconcile className mismatches in production builds — which is why this is
   recorded as a precondition rather than left to be rediscovered.

`hooks/use-media-query.ts` is NOT modified — but the reason recorded in the first draft of this
ADR was wrong, and is corrected here rather than quietly dropped. That draft said seeding would be
a client-side no-op that would *create* a hydration mismatch. The opposite is true:
`use-media-query.ts` returns `false` on the server and the REAL `matchMedia` value on the client's
first render, and that divergence **is** the mismatch. Seeding `false` (exactly the shape
`hooks/use-is-mobile.ts:9-22` already uses, and which documents this correctly in-repo) would make
server and hydration render agree and would REMOVE it.

The honest reason the hook is left alone is narrower: at this call site the branch is unreachable
at hydration (fact 1 above), so the seed buys nothing *today*. That is a statement about the
current SWR configuration, not about the hook. A future change to either should prefer the
SSR-safe shape over relying on fact 1.

## Considered options

| Option | Why not |
|---|---|
| CSS dual-render (`hidden md:flex` / `md:hidden`) | ADR-047 rejects it; PR #6874 shipped and regressed on it (12 broken tests + a hidden component's effects firing on desktop). |
| A second breakpoint hook / a second render-time `matchMedia` read | Two breakpoint authorities can disagree, and disagreement is exactly how two trees mount. |
| Bottom-sheet file picker over the document | The current drawer model with nicer chrome: no URL, not deep-linkable, and "the KB opens on nothing" returns whenever there is no last document. |
| Swap the portal's destination container | React remounts on container change, so no continuity is gained — and with a document open on mobile there is no content-column slot, so the target would be null and the drawer would empty out (the #6917 bug, inverted). |

## Consequences

- The mobile KB gains a real list → detail model with working back-navigation; the
  document header's existing "Back to file tree" chevron now lands on a browse view
  instead of an empty state, with no new code.
- Search-query state had to survive the browse view's unmount on drill-in. It is held in MODULE
  scope in `search-overlay.tsx`, not in `useNavResume`: review established that `sessionStorage`
  outlives sign-out in the same tab (neither the SWR-cache clear nor the hard-nav to /login
  touches it), and a free-text query is a different sensitivity class from the navigation
  positions that namespace holds. Module scope gives exactly the needed lifetime — survives the
  unmount, dies with the page — and the restore is opted into by the CONTENT host only, so
  desktop behaviour is unchanged. The restore repaints the text WITHOUT re-issuing the search:
  `/api/kb/search` is an uncached full-tree walk (~840ms measured), so a restore that re-fired it
  would cost two walks per drill-in round trip.
- The host invariant's POSITIVE assertions are made by CONTAINMENT of the tree's
  `role="navigation"` node rather than by a wrapper `data-testid` — `kb-rail-tree` renders even
  when the tree is DOM-removed, so a testid the component emits about its own placement would
  agree with a mis-placement bug. (Presence/absence assertions elsewhere in the suites do still
  use wrapper testids; the rule is about which assertion carries the host claim.) Because the
  wrapper's testid is itself host-dependent, the shell also emits a host-invariant
  `data-kb-tree-host` attribute as the stable handle for anything addressing the shell by name.
- Every unit test mocks the breakpoint hook, so for the TREE HOST the real `(min-width: 768px)`
  literal is exercised in exactly one place: the headless-Chromium e2e gate, which asserts the
  host at 1280×900, 768×1024, and 390×844. (The literal also appears at other call sites —
  `ui/sheet.tsx`, `ui/responsive-modal.tsx`, `workstream/workstream-board.tsx`,
  `(dashboard)/layout.tsx` — which this ADR does not speak for.)
- Two consequences the operator accepted and which belong in the durable record, not only in the
  plan: on the mobile populated landing the drawer's secondary slot renders EMPTY (wireframe frame
  `34-kb-mobile-drawer-no-tree.png`, DC2 resolved to "no Browse files row"), and the drawer can
  empty itself mid-fetch as `treeHost` flips `rail`→`content` when the tree resolves.
- The mobile document header uses a SECOND breakpoint hook (`use-is-mobile.ts`, SSR-safe) while
  the layout uses `use-media-query.ts`. The rejected-options table below rules out a second
  breakpoint authority *for the tree host*; the header is a different surface with a different
  constraint (it renders during hydration, so it needs the SSR-safe seed). The two disagree for
  one frame after mount by construction — the header paints its desktop cluster then swaps. No
  fetch is wasted (`SharePopover` gates on `open`, `KbSyncStatus` on click).

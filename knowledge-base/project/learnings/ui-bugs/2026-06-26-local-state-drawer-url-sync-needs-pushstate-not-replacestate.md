# Learning: a local-state drawer synced to the URL must pushState-on-open, or Back navigates away

## Problem

To make an issue-detail drawer open/close *instantly* (the prior `router.push`
round-trip was visibly slow), the Workstream board moved the drawer's open-state
into local React state and synced the `?issue=<id>` URL param with
`window.history`. The first implementation used `replaceState` for BOTH open and
close, plus a `popstate` listener "to reconcile Back."

That combination is broken in a way `tsc` + happy-path tests don't catch:
`replaceState` never creates a history entry, so (a) the `popstate` listener is
effectively dead for the in-app flow, and (b) pressing **Back** from an open
drawer navigates **away from the board entirely** (to whatever preceded it)
instead of closing the drawer — a regression from the `router.push` version,
whose pushed entry made Back close the drawer. The component test asserted
"open via replaceState" + deep-link hydration, so it *codified the bug* and went
green. Two review agents (pattern-recognition + code-quality) caught it.

## Solution

For a drawer/sheet/modal whose open-state is local React state but is ALSO
reflected in the URL (`?x=…`) for deep-link / reload / Back support:

- **open:** `setOpen(id)` **and** `window.history.pushState({}, "", \`${pathname}?x=${id}\`)`
  — `pushState` (NOT `replaceState`) so a real history entry exists for Back to pop.
- **close (X / Esc / backdrop):** `setOpen(null)` **and**
  `window.history.replaceState({}, "", pathname)` — strip the param without
  adding an entry.
- **popstate listener:** re-read the param from `window.location.search` and set
  state from it. Now it's *live* (because open pushed an entry), so Back pops the
  pushed entry → no `?x` → state clears → drawer closes, still on the board.
- **mount:** initialize state from the param (deep-link / reload).

Open/close stay instant because local state drives the render; the URL work is
fire-and-forget and never blocks the paint. This is the same end-behavior
`router.push` gave (Back closes the drawer) without the navigation round-trip.

## Key Insight

`pushState` vs `replaceState` is not a detail — it *is* the Back-button contract.
A `popstate` listener is dead code unless something `pushState`d an entry for it
to pop. When you move UI open-state out of the router into local state for speed,
you inherit responsibility for the history entry the router used to create: open
must `pushState`, or you silently convert "Back closes the overlay" into "Back
leaves the page." And a component test that asserts the *mechanism* you chose
(`replaceState` was called) rather than the *behavior* (Back closes the drawer)
will codify the bug — assert the behavior: simulate a `popstate` with no param
and expect the drawer gone.

## Tags
category: ui-bugs
module: apps/web-platform/components/workstream/workstream-board.tsx

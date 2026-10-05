// #7326 — lets the guided tour reveal the mobile nav drawer for the steps whose
// copy points AT it ("Click the Inbox tab"). Its own module so `tour-steps.ts`
// can stay pure data and import the name without pulling in `layout.tsx`.
//
// Deliberately NOT `RAIL_EXPAND_EVENT`. That one is expand-ONLY by contract — a
// stray dispatch while expanded is defined as a no-op, and its existing
// dispatchers send a bare `Event` with no detail. Teaching it to close would
// break that contract for every caller. This event is the two-way one:
// `detail.open` says which way, matching the `{open: boolean}` shape
// `TourProvider` already dispatches for every `reveal` step.
//
// The listener in `app/(dashboard)/layout.tsx` — the sole owner of drawer state
// — honours the OPEN below `md` only. `drawerOpen` also drives `<main inert>`
// and the body scroll lock, both viewport-independent, so opening it on desktop
// would freeze the content pane behind a drawer that is not even rendered as
// one. The CLOSE is honoured at every width, so the flag can never strand.
export const NAV_DRAWER_REVEAL_EVENT = "soleur:nav-drawer-reveal";

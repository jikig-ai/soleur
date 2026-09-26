---
title: "ADR-255: Canonical action-feedback contract — Button primitive, nav-pending store/island, pinned hard-nav boundary"
status: Adopting
date: 2026-09-26
supersedes: []
amends: []
tags: [ui, primitives, navigation, a11y, convention]
---

# ADR-255: Canonical action-feedback contract — Button primitive, nav-pending store/island, pinned hard-nav boundary

## Status

Adopting — 2026-09-26. Delivers #8917.

## Context

Clicks on the webapp produced no visible acknowledgment: ~310 native
`<button>` sites across ~120 files, only ~half of mutation sites guarded
against double-submit, and zero route-transition feedback — on a slow app,
a click reads as dead air (worst case: a user re-fires a billing action).
`useTransition`/`disabled={loading}` existed but were ad-hoc; `RefreshShimmer`
covers SWR revalidation only, not route transitions.

## Decision

1. **One `Button` primitive** (`components/ui/button.tsx`) — variants
   `gold|outlined|ghost|danger`, `loading`/`loadingLabel`, `type` forwarded
   with NO default (native `submit` inside `<form>` preserved), all
   `aria-*`/`data-*`/`on*` forwarded via rest-spread. `loading` forces
   `disabled` + `aria-busy` + leading spinner after a shared 150ms entry
   delay. Icon-only buttons use content-replacement (spinner swaps the
   icon in a pinned-size box — never appends; zero layout shift).
2. **Nav pending via a module-level store + island**, not context and not
   a passive document listener. `lib/nav-pending-store.ts` exports
   `startNavPending(trigger)`/`stopNavPending()`/`isSameDocTarget(href)`;
   `components/nav/nav-pending-island.tsx` subscribes via
   `useSyncExternalStore` and mounts ONCE in root `app/layout.tsx`.
   Trigger channels: `NavLink.onNavigate`, `usePendingRouter` (push/replace;
   `refresh`/`back`/`forward`/`prefetch` pass through untouched), `popstate`.
   Raw internal anchors are converted to `NavLink` — a raw `<a href="/x">`
   does a full document load the browser already signals, so a listener
   exists only to serve false positives.
3. **Terminal-safety invariants**: identical-URL targets skip `start()` but
   still delegate (scroll-to-top semantics preserved); a ~30s stall timeout
   force-stops + breadcrumbs; `start()` is a no-op while pending AND through
   the ~400ms min-visible hold.
4. **Hard-nav boundary pinned**: `window.location.*` stays untouched; its
   ~45+ sites are enumerated as never-reset pending latches
   (`usePendingAction(fn, { latchOnRedirect: true })`).
5. **Enforcement**: `scripts/check-button-primitive-sweep.sh` + vitest
   wrapper — a baseline ratchet (the native-`<button>` count may only
   decrease) plus `data-button-exempt="<reason>"` as the in-code exemption
   chokepoint (a doc-only list drifts from the DOM). `import Link from
   "next/link"` is the greppable violation seam.

## Conventions this ADR records

- **Exemption budget**: `data-button-exempt` sites bounded at ~15% of the
  corpus; past that, variant coverage is re-evaluated rather than the list
  growing — the exemption list must not become the escape hatch that
  re-creates the two-convention status quo.
- **Revert unit**: per-tier domain-grouped commits. A mid-flight tier
  rollback marks surviving native sites `data-button-exempt="revert-pending"`
  so the sentinel stays green during the temporary coexistence.
- **Telemetry drift detector**: a soft-nav committing with no preceding
  `start()` surfaces as a `nav_duration_ms` `trigger`-dimension gap — the
  detector for nav channels nobody wired.
- **Docs**: the contract lives in `components/ui/README.md`; root
  `CLAUDE.md` carries one pointer line.

## Alternatives considered

- **Layered intercept** (CSS `:active` + listener + ad-hoc loading):
  rejected by operator — leaves ~94% of buttons outside any convention.
- **Passive document click listener**: cut at plan review — cannot observe
  `defaultPrevented` in capture phase, and raw internal anchors already get
  browser-native full-load feedback.
- **Context provider**: rejected — wraps `{children}`, couples mount order,
  re-renders every consumer per nav; the module store has none of that.
- **Per-link `useLinkStatus` hints**: cut — a second pending visual language.

## Consequences

- Every future button/route-link authors through the primitives; new native
  `<button>` or raw `next/link` imports red the sentinel in review.
- A truly hung mutation (>30s) leaves the control disabled until reload —
  accepted residual; the watchdog emits a Sentry breadcrumb.
- `/api/checkout` idempotency is server-deferred to #8918; the client latch
  is the mitigation in the interim.

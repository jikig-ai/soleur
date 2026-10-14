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
   sites are enumerated as never-reset pending latches via the explicit
   `latch()` on `usePendingAction(fn)` — called inside the asyncFn
   immediately before the hard nav. Terminality is explicit, never inferred
   from resolution: a confirm-cancel or handled `!res.ok` resolve path
   releases normally.
5. **Enforcement**: `scripts/check-button-primitive-sweep.sh` + vitest
   wrapper — a baseline ratchet (the native-`<button>` count may only
   decrease) plus `data-button-exempt="<reason>"` as the in-code exemption
   chokepoint (a doc-only list drifts from the DOM); and
   `scripts/check-nav-channel-sweep.sh` + vitest wrapper — `import Link from
   "next/link"` outside nav-link.tsx, `router.push/replace/back/forward` on
   a raw `useRouter`, and literal internal `<a href="/…">` anchors are the
   greppable violation seams.

## Conventions this ADR records

- **Exemption budget**: `data-button-exempt` sites bounded at ~17% of the
  corpus (51 sites at sweep-landing — mostly ARIA-role composites and
  composite-content rows the primitives deliberately don't absorb; restated
  from the ~15% estimate at review). Past that, variant coverage is
  re-evaluated rather than the list growing — the exemption list must not
  become the escape hatch that re-creates the two-convention status quo.
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
- A truly hung mutation (>30s) reports a `pending-watchdog` Sentry event and
  releases the control; latched (post-hard-nav) episodes report tagged
  `latched: "true"` but stay latched — the teardown may still be in flight.
  The typed-confirm send POST aborts at the same horizon so the modal can
  never lock open.
- `/api/checkout` idempotency is server-deferred to #8918; the client latch
  is the mitigation in the interim.

## Addendum (2026-09-30): Button base box lives in `@layer components`

**Context.** The primitive emitted its box (`inline-flex items-center justify-center gap-2 rounded-lg px-6 py-3 text-sm font-medium`) as ordinary Tailwind utilities ahead of the caller's `className`. Same-cascade-layer utilities resolve by emit order, not by class order, so a caller's `px-3`/`flex`/`rounded-md` could lose to the base, and icon-only buttons that passed only a size (`h-[36px] w-[36px]`, e.g. the chat composer attach/send buttons) were padded by 48px inside a 36px border-box, collapsing the icon to zero width. This contradicts the contract documented in `apps/web-platform/components/ui/README.md` ("`className` merges with variant classes"); the change restores that contract rather than changing this ADR's decision.

**Decision.** Move the base box to `.soleur-btn` and the text-button padding to `.soleur-btn-pad`, both in `app/globals.css` under `@layer components` (layer order `theme, base, components, utilities`), so any caller utility wins deterministically. The primitive emits `soleur-btn` always and `soleur-btn-pad` only when it has a text child (`!iconOnly`); icon-only buttons carry no padding and pass their own size. A layer move alone would not have fixed the composer (its buttons pass no padding class), hence the split. Guards: `test/components/button-classes.test.tsx` (denylist of base-box utilities the primitive must never emit, icon-only vs text classes) and `test/components/button-layer.test.ts` (compiles `globals.css` with `@tailwindcss/node` and asserts layer membership on the postcss AST, with a control fixture proving it can go red); the layout gate is the Playwright bounding-box e2e.

**Alternatives rejected.** `tailwind-merge`/`twMerge`: adds a dependency, misclassifies the custom `text-soleur-*` tokens against `text-sm`, cannot merge arbitrary values, and puts JS on every render for a problem CSS layers solve. Per-site `!p-0` overrides: drift on the next Button use. A `size="icon"` variant: the primitive already derives `iconOnly` from `hasTextChild`. Not covered: variant-vs-caller conflicts (`bg-*`, gold's inline `style` background) still race, because variant classes remain ordinary utilities.

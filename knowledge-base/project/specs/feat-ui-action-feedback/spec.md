---
feature: ui-action-feedback
lane: cross-domain
brand_survival_threshold: single-user incident
created: 2026-09-25
brainstorm: knowledge-base/project/brainstorms/2026-09-25-ui-action-feedback-brainstorm.md
---

# Feature: Click/Loading Feedback for the Webapp

## Problem Statement

Clicking buttons or navigating in `apps/web-platform` produces no visual feedback. Because the app is slow (latency is owned by a separate parallel effort), a click looks like nothing happened — users re-click, producing duplicate submissions on the ~30 unguarded mutation routes, or conclude the product is broken. For the non-technical-founder target segment, "slow but working" is indistinguishable from "broken."

## Goals

- Every interactive element produces immediate, legible feedback on click/activation.
- A single canonical pending visual language: press affordance → pending spinner/bar → resolved or announced error.
- Navigation shows a global pending indicator; mutations show per-button pending + disabled.
- The full sweep standardizes buttons onto shared primitives so `loading` becomes the only convention.

## Non-Goals

- App latency fixes (parallel session owns performance work).
- Server-side `/api/checkout` idempotency (deferred follow-up issue).
- `loading.tsx` skeleton expansion to routes missing them.
- Converting `window.location.assign` hard navs to soft navs (forbidden — ADR-067 Router-Cache isolation).
- New UI primitive library / shadcn migration.

## Functional Requirements

### FR1: Global route-pending indicator

A 2px gold top bar (RefreshShimmer idiom, `var(--soleur-*)` tokens) mounted in `app/(dashboard)/layout.tsx` outside the ADR-047 swap region. Fires on `<Link>` clicks (patched `NavLink` via `onNavigate`), raw internal `<a href>` (passive capture-phase click listener), `router.push`/`router.replace` (shared `usePendingRouter()` wrapper — covers ⌘K palette and `g`-key navs). ~150–200ms entry delay + minimum-visible duration; completion watcher keys on `usePathname` AND `useSearchParams` (same-path query navs like `workstream?issue=` count). Excludes `window.location.assign` hard navs.

### FR2: Button pending contract via primitive migration

All ~310 native `<button>` sites migrate to a shared button family (gold / outlined / ghost variants). Each primitive carries `loading?: boolean`: `disabled` + `aria-busy` + trailing `SpinnerIcon`, stable accessible name; label-swap only where copy adds meaning ("Sending…" on irreversible sends). Press affordance (`:active` scale/opacity) baked into the primitives. Pending must always terminate: success or visible `role="alert"` error + re-enable — a permanently-disabled billing/consent button is a single-user incident.

### FR3: Typed-confirm send flow

`hooks/use-action-send.ts`: the confirm modal stays open showing "Sending…" (spinner + `aria-busy`, input locked) until the send resolves, then closes to the acknowledged state. Errors surface in-modal.

### FR4: Double-submit coverage

Every mutation-triggering button is disabled during pending. Billing triggers currently missing the guard (Reactivate, Update Payment Method in `billing-section.tsx`) gain it.

## Technical Requirements

### TR1: Mounting and theme

Indicator mounts in `(dashboard)/layout.tsx` (client component hosting existing ambient overlays). Brand tokens only (`var(--soleur-*)`); no raw hex; respect the `prefers-reduced-motion` sweep (globals.css:244-253, RefreshShimmer carve-out precedent). Zero layout shift — indicator reserves no layout footprint (fixed, `aria-hidden`).

### TR2: Verification surfaces

- Headless Playwright spec in the `authenticated` project for the nav-chrome indicator (ADR-049), synthetic fixtures only.
- Vitest for `usePendingAction()`/primitive `loading` contract; note `next/navigation` is heavily mocked — nav indicator verification is e2e.
- Observability: nav-duration signal (`performance.now()` delta) emitted alongside the provider (`hr-observability-as-plan-quality-gate`).

### TR3: Invariants

- Hard-nav principal boundaries (sign-out, org-switch, delete-account, login) keep `window.location.assign`.
- Consent surfaces (accept-terms, delegation modal, scope-grants auto-tier, bash-autonomous ack) keep ack-gating; loading never auto-submits.
- `cq-silent-fallback-must-mirror-to-sentry` — pending-state failure branches keep `reportSilentFallback`.

## Deferred Items

- Server-side `/api/checkout` idempotency key / session-reuse (closes double-subscription TOCTOU) → follow-up issue.
- `constraint-scaffold`-style lint rule steering new `<button>` code to primitives → productize candidate.

## Visual Design

Approved wireframe: `knowledge-base/product/design/dashboard/action-feedback-variant-b-instrumented-spec.pen` (screenshots `screenshots/16-19-*.png`) — adopt Variant A's quiet visuals for production. Surfaces covered: route-pending bar (desktop + mobile PWA below safe-area), button pending matrix (idle/pressed/pending × gold/outlined/ghost), typed-confirm modal pending state.

---
title: "feat: click/loading feedback for all webapp interactions (nav indicator + button pending states)"
type: feat
date: 2026-09-25
slug: feat-ui-action-feedback
branch: feat-ui-action-feedback
issue: 8917
closes: 8917
priority: high
domain: product-engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: click/loading feedback for all webapp interactions

## Overview

Every interactive element in `apps/web-platform` gains a visible pending contract. Three layers: (1) a global route-pending indicator — a 2px gold bar in the `RefreshShimmer` idiom — covering Link clicks, raw anchors, `router.push`/`router.replace`, and keyboard navigation; (2) a single `Button` primitive family (`gold | outlined | ghost` variants) with a built-in `loading` contract (disabled + `aria-busy` + `SpinnerIcon` + `:active` press affordance) that all ~310 native `<button>` sites migrate onto; (3) the typed-confirm send modal stays open showing "Sending…" until the send resolves. Pending states must always terminate — success, or a visible `role="alert"` error with re-enabled controls.

## Research Insights

**Premise validation (Phase 0.6):** #8917 open (created this session); PR #8904 open on `feat-ui-action-feedback`; every spec-cited file verified present this session (`hooks/use-action-send.ts`, `components/ui/refresh-shimmer.tsx`, `components/ui/gold-button.tsx`, `outlined-button.tsx`, `app/(dashboard)/layout.tsx`, `billing-section.tsx`). No stale premises.

**Property List (Phase 0.6b):**
- P1 — a click or keypress that triggers work produces immediate visible confirmation (press affordance, then pending indicator)
- P2 — a mutation cannot be submitted twice while its request is in flight
- P3 — a pending state always terminates into success or a visible, announced error
- P4 — principal-boundary hard navigations (sign-out, org-switch, delete-account) keep `window.location.assign` (ADR-067 Router-Cache isolation)
- P5 — pending visuals consume `var(--soleur-*)` tokens, zero layout shift, `aria-hidden` chrome, `aria-busy` on controls
- P6 — nav durations are measured, not just masked (feeds the parallel perf session)
- P7 — a long-lived pending state communicates liveness — it must never read as hung (grounds the ~8s escalation contract, CPO C1)

**Cut List:** none — each proposed mechanism maps to a property no existing mechanism covers (`RefreshShimmer` is SWR-revalidation-scoped; `useLinkStatus` is descendant-scoped; per-file `useState` flags are non-uniform). `nprogress`/bprogress cut at brainstorm (dependency for ~40 lines of CSS, no App Router auto-detection).

**Repo findings (from repo-research + leader verification):**
- Primitives: `components/ui/gold-button.tsx` (31 lines), `outlined-button.tsx` (19) — thin, no `loading`, only ~22 JSX uses.
- Native `<button>`: ~310 sites across ~122 files (settings 62, chat 43, kb 39, workstream 29, dashboard 25).
- Nav calls: `next/link` in 32 files; `router.push/replace` ~31 sites incl. `use-shortcuts.tsx` (⌘K + g-keys); raw `<a href>` ~26 sites; `window.location.assign` ~45 sites (hard-nav boundary — exclude).
- Pending today: `useTransition` in 4 files; ~38 files hand-roll `disabled={loading}` (≈ half of ~60 mutation sites); `SpinnerIcon` at `components/icons/index.tsx:82`; `RefreshShimmer` (`components/ui/refresh-shimmer.tsx`) is the approved gold-bar idiom; only 6 `loading.tsx` segments.
- `next.config.ts` `staleTimes.dynamic: 30` — warm navs are instant → 150–200ms entry delay is mandatory.
- `(dashboard)/layout.tsx` is already `"use client"` and hosts ambient overlays + window CustomEvents (`NAV_DRAWER_REVEAL_EVENT` precedent).
- `hooks/use-action-send.ts:195-233` closes the confirm modal BEFORE the POST → the highest-stakes flow has the least feedback. `TypedConfirmModal` at `components/ui/typed-confirm-modal.tsx`.
- `billing-section.tsx`: Reactivate (:219-224) lacks `disabled={loading}` — a real double-submit gap (Update Payment Method :166 is guarded; simplicity-review verified).
- No `useFormStatus`/Server Actions anywhere — per-site pending is manual.
- `lib/analytics-client.ts` `track()` → `/api/analytics/track` → Plausible (7 call sites) — cheap telemetry channel for nav durations.
- CSP allows inline styles (`style-src 'unsafe-inline'`); Tailwind v4 `@theme` maps `--color-soleur-*`; `prefers-reduced-motion` sweep at `globals.css:244-253` with the RefreshShimmer static carve-out precedent.

**Learnings applied:** ADR-067 (SWR + Router-Cache dual cache; hard-nav boundary set is enumerated and load-bearing); ADR-047 (swap region — chrome mounts in layout outside `children`); ADR-049 (headless Playwright `authenticated` project for structural UI diffs, synthetic fixtures); `2026-05-19-optimistic-local-state-and-server-prop-conjunction` (`router.refresh()` inside `startTransition` extends `isPending` correctly); upload-progress `-1` sentinel (determinate/indeterminate split precedent — not needed this pass); `2026-04-10-dashboard-onboarding` (separate "what state" from "is loading" — never gate render on the pending flag).

## Problem Statement

Clicks in the webapp produce zero feedback; the app is slow, so nothing appears to happen. Users re-click → duplicate submissions on ~30 unguarded mutation routes, or conclude the product is broken. For the non-technical-founder target segment the two are indistinguishable.

## Proposed Solution

Consolidate three existing precedents into one contract rather than inventing new UX: `RefreshShimmer`'s ambient gold bar for route-pending; `use-action-send`'s `isPending`/disable pattern generalized into a `Button` primitive + `usePendingAction()` hook; the approved `.pen` wireframe set (variant B, instrumented-spec) as the visual contract.

## Technical Approach

### Architecture

**Layer 1 — `components/ui/button.tsx` (new).** One forwardRef `Button` primitive: `variant: "gold" | "outlined" | "ghost" | "danger"`, `loading?: boolean`, `type` forwarded with **no default** (native `submit` semantics inside forms preserved — a `type="button"` default would silently break ~14 `<form>` sites' implicit submits; kieran #6 / arch #1 — the 14 forms get a line-item audit in the sweep), `disabled`, merged `className` (not variant-locked), all `aria-*`/`data-*`/`on*` props forwarded via rest-spread — a variants-only API cannot absorb ~310 heterogeneous sites without a behavior-forking escape hatch (advisor consult). `loading` forces `disabled` + `aria-busy="true"` + **leading** `SpinnerIcon` (the `.pen` contract renders `[spinner][label]`; ux #2), shown after a ~150ms entry delay so fast mutations don't strobe (ux #6). For icon-only buttons (`aria-label`, ~211 sites) `loading` uses **content-replacement** — the spinner swaps the icon in a pinned-size container, never appends (a trailing spinner shifts width and breaks P5; arch #5). Pending visual: `opacity: 0.55` (0.65 in modals) per the `.pen` quiet contract (ux #4). Press affordance: `scale-98 opacity-90 ~120ms`, transform suppressed under `prefers-reduced-motion` (ux #3). Label-swap only via explicit `loadingLabel` (verb-matched — "Saving…", "Deleting…"; ellipsis style standardized in the primitive so ~310 sites can't drift). `GoldButton`/`OutlinedButton`'s ~22 call sites migrate to `Button` and the two files are **deleted** — no shim longevity theater (DHH #4). **Focus contract (ux #1, blocking):** `usePendingAction` restores focus to the control on resolve when `activeElement` collapsed to `<body>` — a disabled-flip otherwise destroys keyboard place on every submit. **Escalation contract (CPO C1):** on irreversible/billing paths (~3 call sites — `billing-section.tsx` redirects, sign-out — not a generalized `Button` feature; DHH #13), a pending episode older than ~8s appends "Still working…" in a reserved-space sublabel (no layout shift) via a polite `aria-live` region — ~10 lines of `setTimeout` per site, the timer resetting per pending *episode* so a fast retry doesn't inherit a stale clock (ux #7). Copy: "Still working…" (CMO-approved — honest without overpromising; avoids "processing" jargon).

**Layer 2 — nav-pending.** A **module-level store** (not context, not events): `lib/nav-pending-store.ts` exports `startNavPending(trigger)` / `stopNavPending()` as plain functions writing a tiny external store; the island component subscribes via `useSyncExternalStore` and mounts as a sibling in root `app/layout.tsx` — no provider wraps `{children}`, no mount-order coupling (a trigger firing pre-hydration can't throw), no ~60-consumer re-render per nav (arch #4 — strictly simpler than CustomEvent/context). The island renders the 2px gold top bar (`fixed inset-x-0 top-0 z-50`, RefreshShimmer keyframes/tokens, `aria-hidden`, `top: env(safe-area-inset-top)` on the fixed bar so the band renders **below** the safe-area strip per the `.pen` mobile note (ux #11)). **One mount only**: a Suspense-wrapped client island in root `app/layout.tsx` covers every route group — the earlier two-mount design double-mounted on dashboard routes (double listeners, doubled telemetry, context shadowing — spec-flow C2). The island wraps its `useSearchParams` consumer in `<Suspense>` as hygiene (not load-bearing — the root layout already awaits `headers()`, so the whole tree is dynamic; DHH #17 / kieran #10). Entry delay 150–200ms + ~400ms min-visible to prevent strobe on warm Router-Cache navs. Completion watcher: `usePathname` + `useSearchParams` effect → `stop()` (covers same-path query navs like `workstream?issue=`). **Stall termination (spec-flow C1):** `start()` arms a ~30s hard timeout → `stop()` + Sentry breadcrumb, so a failed RSC fetch, hung nav, or non-navigating anchor can never leave a permanent bar. `start()` is idempotent — a second `start()` while pending is a no-op. A visually-hidden `role="status"` live region announces "Loading" **when the bar becomes visible** — not at `start()`, or warm-cache navs spam announcements with no visible feedback (ux #5). `pending`/`start()` idempotency extends through the ~400ms min-visible hold — a rapid second trigger inside the hold is a no-op until the bar is fully hidden (ux #8). Gold uses the per-palette token — `--accent-gold-fg` in Solar Radiance light mode (CPO C3; `--accent-gold-fill` reads ~2:1 on cream), `--accent-gold-fill` in Dark Matter — and must not visually stack under tour chrome when TourProvider drives navs.
Triggers — **no passive document listener** (cut per DHH #5: a raw internal `<a href="/…">` does a full document load the browser's own progress already covers; the listener existed mostly to serve one confirmed stuck-bar vector — `dsar-export-job-list.tsx`'s `/api/` download anchor — and its exclusion machinery was the costliest part of the channel): (a) `components/ui/nav-link.tsx` — `next/link` wrapper; `onNavigate` → `start()` only when `isSameDocTarget` is false (active rail item = same-URL click that would strand the bar 30s; kieran #2). Kept not just for coverage but as the **convention seam**: `import Link from "next/link"` becomes a greppable violation the sentinel can flag in new code (cto). Mechanical import swap at ~32 files; real internal raw anchors (~16 sites incl. dynamic templates) convert to `NavLink` in the same pass; non-navigating anchors (`/api/` download, `mailto:`, external, `#fragment`) stay native — correct by default; (b) `hooks/use-pending-router.ts` — wraps `useRouter()`; `push`/`replace` resolve the target first and **skip `start()` but still delegate** (same-URL pushes carry scroll-to-top semantics; kieran #12) when it equals the current `window.location.pathname + window.location.search` — comparing via `new URL(href, location.href)` with `hash` excluded, normalizing `UrlObject` and relative hrefs (`?status=…`, `./x`), and reading `location` at call time (never `useSearchParams` — a hook subscription would push a Suspense requirement into ~16 consumer files; cto). `inbox-surface`'s active-tab re-click is the confirmed stuck-bar vector. `refresh`/`back`/`forward`/`prefetch` pass through untouched (`refresh` has ~22+ live callers and must never fire `start()`); covers ⌘K and g-keys via `use-shortcuts.tsx`; (c) a `popstate` listener inside the island for history Back/Forward — comparing `pathname+search` against a continuously-updated last-location ref so hash-only history entries (the `#main-content` skip-link pushes one per use; kieran #4) and already-updated popstate locations (kieran #8) never fire `start()`; the shared `isSameDocTarget(href)` helper also guards NavLink — clicking the active rail item is a same-URL click (`onNavigate` fires pre-navigate, the watcher sees no delta — kieran #2).

**Layer 3 — pending contract on mutations.** `hooks/use-pending-action.ts`: `usePendingAction(asyncFn, opts?) → {run, pending, error}` — wraps `useTransition`, guarantees `finally`-termination, exposes `error` for `role="alert"` rendering, a `pendingRef` for the click-to-render gap, and `opts.latchOnRedirect` making the never-reset-on-`location.*` rule the typed default (rather than an undiscoverable comment convention — cto #5). Vocabulary pinned in `components/ui/README.md`: `pending` is the state name, `loading` is the prop name — wire `loading={pending}`. Migration sweep replaces native `<button>` with `<Button>` and wires `loading={pending}`. The hook is adopted incrementally at sites that already hand-roll `disabled={loading}` (~31 files, 168 `data-testid`s to preserve) — it standardizes the pattern but does not gate the migration (advisor consult). **Redirect-latch rule (spec-flow C4):** on `window.location.*` redirects, pending state must never reset in `finally` — `billing-section.tsx`'s `redirectTo` currently re-enables the button in the gap before the Stripe redirect commits (a surviving double-submit window); `use-sign-out.ts`/`upgrade-at-capacity-modal` are the correct never-reset precedent. **Granularity:** pending is shared per logical action-group (e.g. billing's buttons share one flag so coupled actions can't fire concurrently); per-control flags only where actions are independent. **Error render:** a migrated mutation site must wire the `error` channel to a `role="alert"` surface — the sweep verifies rendering, not just `<Button>` usage.

**Layer 4 — typed-confirm send.** `hooks/use-action-send.ts`: `onConfirmTyped` keeps the modal open, sets `confirmPending`, closes only on resolution. `typed-confirm-modal.tsx` gains `pending` rendering (spinner + "Sending…" + `aria-busy` + locked input + inert Cancel); focus moves to the status element during pending and success/failure is announced via a polite `aria-live` region (CPO C2 — `aria-busy` alone does not announce resolution); failure re-enables and surfaces `role="alert"` in-modal — on failure, focus moves to the alert and the typed `SEND` value persists (no re-typing; ux #9); Enter during pending must not re-invoke `onConfirm` — tested, since `canSubmit` stays true while the input is disabled (ux #10). **Dismiss suppression (spec-flow C3):** while pending, ALL dismiss vectors are inert — Cancel button, Esc, backdrop, the sheet's close control, and the mobile-sheet drag/swipe-to-dismiss gesture — mirroring `sign-out-confirm-modal`'s `isSigningOutRef` guard (no new API needed — `ResponsiveModal` routes Esc/backdrop/close-control through `onClose` presence, so `onClose={pending ? undefined : onCancel}` kills every dismiss vector; drag/swipe verified at work time; simplicity-review simplification).

**Layer 5 — telemetry.** Provider records `performance.now()` at `start()`/`stop()`, emits `track("nav_duration_ms", {path: "nav:<trigger>:<section>"})` via `lib/analytics-client.ts`. **Two constraints (DHH #14 + kieran #5):** `sanitize.ts` allowlists props to `["path"]`, and no route-pattern normalizer exists — `usePathname` yields concrete paths whose token segments the server scrubber does NOT mask. So `path` carries only `nav:<trigger>:<section>` where `trigger ∈ link|router|popstate` and `section` ∈ a fixed first-segment enum (dashboard|kb|chat|settings|inbox|workstream|crm|releases|connect-repo|shared|invite|auth) — zero identifiers by construction, `app/api/**` stays out of the diff. Durations ride the Sentry breadcrumb (from/to pinned via the last-location ref); the parallel perf session owns duration instrumentation. Throughput: per-nav events are the app's highest-frequency emitter — the 120/min `analyticsTrackThrottle` cap means heavy sessions tail-drop (fail-soft); accepted — the signal needs trends, not completeness.

### Implementation Phases

#### Phase 1: Foundation (new primitives + provider)

- `components/ui/button.tsx` + `components/ui/nav-link.tsx` + `lib/nav-pending-store.ts` + `components/nav/nav-pending-island.tsx` + `hooks/use-pending-action.ts` + `hooks/use-pending-router.ts`
- `globals.css`: press-affordance + bar keyframes (reuse `refresh-shimmer`), reduced-motion carve-out
- Mount the island ONCE in root `app/layout.tsx` (single mount — never also in `(dashboard)/layout.tsx`; Suspense wrap is hygiene since the root layout is already dynamic)
- Vitest for hook/provider/pending contract (incl. stall timeout, identical-URL no-op, `start()` idempotency, `refresh` passthrough)
- Success: unit tests green; bar fires on synthetic nav in dev

#### Phase 2: Navigation wiring sweep

- `next/link` → `NavLink` across ~32 files (import-swap codemod-style, mechanical)
- `useRouter()` → `usePendingRouter()` at ~31 push/replace sites
- Convert real internal raw anchors (~16 sites incl. dynamic `href={\`/dashboard/…\`}`) to `NavLink`; verify non-navigating anchors stay native; verify hard-nav `window.location.*` sites untouched
- Success: indicator on Link + anchor + push + ⌘K + g-key navs; clears on commit incl. query-only navs

#### Phase 3: Button migration sweep (risk-tiered, domain-grouped commits)

- A codemod-style mechanical pass covers sites whose props reduce to `onClick|disabled|type|className` matching a variant (the large majority); bespoke shapes (icon-only buttons, `aria-pressed` toggle groups, composite inner markup) are manual per-site edits or documented exemptions. Exemptions are marked in-code with `data-button-exempt="<reason>"` — the DOM attribute is the chokepoint (a doc-only list drifts from the DOM on day one; arch #1), bounded by an **exemption budget** (~15% of corpus; past that, variant coverage is re-evaluated rather than the list growing — arch #5).
- Tier 1 (~40 files): billing/auth/consent/send/delete/invite — `billing-section.tsx` (incl. the missing Reactivate guard), `typed-confirm-modal`, `use-action-send`, `sign-out-confirm-modal`, `oauth-buttons`, `scope-grants/*`, `delegation-acceptance-modal`, `bash-autonomous-toggle*`
- **Tier-1 review checkpoint (CPO C4):** billing/consent modal diffs get human eyes (or a dedicated reviewer pass) before Tier 2 commits land.
- Tier 2 (~45 files): remaining mutation/form sites (settings, workstream, routines, inbox, crm, connect-repo)
- Tier 3 (~40 files): pure-UI toggles (theme, tabs, collapse, disclosure) — press affordance only, `loading` unwired
- Success: `rg '<button' -g '*.tsx' apps/web-platform/{components,app}` returns only primitive files + exemption-listed sites; every mutation button disabled+aria-busy during flight

#### Phase 4: Typed-confirm "Sending…" + P0 verification

- `use-action-send.ts` modal-stays-open flow + `typed-confirm-modal.tsx` pending render
- Error path: in-modal `role="alert"` + re-enable
- Success: send click → modal "Sending…" → acknowledged pill on success, visible error + re-enabled on failure

#### Phase 5: Verification + ADR

- Playwright spec in `authenticated` project (ADR-049): nav bar on click→commit; button pending on mutation
- ADR write (provisional number; see §Architecture Decision); reconcile `spec.md` FR1/TR1 mount point (still says `(dashboard)/layout.tsx` → root-layout island; cto #6)
- Update `CLAUDE.md`/component docs? — no; primitives README comment suffices
- Success: e2e green, residual-zero sweep verified, ADR committed

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| A — Layered intercept (press CSS + global bar + hook standardization, no migration) | Operator chose full migration; B permanently ends the 94% bypass rather than layering around it |
| C — nprogress/bprogress library | No App Router auto-detection; all triggers still hand-built; dependency for ~40 lines of CSS |
| Push all buttons through primitives | This IS the chosen approach (B) |
| Per-page `loading.tsx` expansion | Covers route-level skeletons only, not button actions; owned by the parallel perf session |

## Files to Create

- `apps/web-platform/components/ui/button.tsx`
- `apps/web-platform/components/ui/nav-link.tsx`
- `apps/web-platform/lib/nav-pending-store.ts` + `apps/web-platform/components/nav/nav-pending-island.tsx`
- `apps/web-platform/hooks/use-pending-action.ts`
- `apps/web-platform/hooks/use-pending-router.ts`
- `apps/web-platform/test/ui-action-feedback.test.tsx` (+ adjacent test files per layer)
- `apps/web-platform/e2e/nav-states-nav-pending.e2e.ts` — the `authenticated` project selects by filename glob `**/nav-states-*.e2e.ts` (`playwright.config.ts:52`), not by directory; the `nav-states-` prefix lands it there for free (cto)
- `apps/web-platform/scripts/check-button-primitive-sweep.sh` + `apps/web-platform/test/components/button-primitive-sweep.test.ts` (ratchet sentinel + vitest wrapper; cto #1)
- `apps/web-platform/components/ui/README.md` (convention doc: Button contract, nav-pending channels, usePendingAction redirect-latch + granularity, exemption process, sentinel usage — modeled on `server/README.md`; cto #6) + one pointer line in root `CLAUDE.md` (`<!-- action-feedback:pointer -->` idiom)
- `knowledge-base/engineering/architecture/decisions/ADR-<provisional>-action-feedback-contract.md`

## Files to Edit (representative; full sweep enumerated at work time)

- `apps/web-platform/app/layout.tsx`, `apps/web-platform/app/(dashboard)/layout.tsx`, `apps/web-platform/app/globals.css`
- `apps/web-platform/components/ui/{gold-button,outlined-button}.tsx` → deprecated wrappers over `Button`
- `apps/web-platform/hooks/use-action-send.ts`, `apps/web-platform/components/ui/typed-confirm-modal.tsx`
- ~32 files: `next/link` → `components/ui/nav-link.tsx`
- ~16 files: `useRouter` → `usePendingRouter` (incl. `components/command-palette/use-shortcuts.tsx`)
- ~122 files: native `<button>` → `<Button>` (tier-ordered: settings 62, chat 43, kb 39, workstream 29, dashboard 25, then long tail)
- `apps/web-platform/components/settings/billing-section.tsx` (add missing `disabled` guards)

## User-Brand Impact

- **If this lands broken, the user experiences:** a permanently-disabled Subscribe/Cancel/Accept button after a hung request, or a nav bar that never clears — the same "dead app" feel this feature exists to remove, now with a visible stuck indicator.
- **If this leaks, the user's workflow is exposed via:** a pending state that swallows a failed mutation silently — the user believes a send/delete/checkout happened when it did not.
- **Brand-survival threshold:** `single-user incident`

`soleur:engineering:review:user-impact-reviewer` runs at review-time per the review skill's conditional-agent block. CPO sign-off at plan time: brainstorm carry-forward (`feat-ui-action-feedback` brainstorm, CPO assessed 2026-09-25).

## Observability

```yaml
liveness_signal:
  what: "nav_duration_ms analytics events (Plausible via /api/analytics/track) — proves the pending provider mounts and navigations complete"
  cadence: "per soft-navigation"
  alert_target: "weekly Plausible dashboard check; Sentry breadcrumb per nav for session replay context"
  configured_in: "components/nav/nav-pending-island.tsx + lib/nav-pending-store.ts + lib/analytics-client.ts"

error_reporting:
  destination: "Sentry via reportSilentFallback on pending-state failure branches (cq-silent-fallback-must-mirror-to-sentry)"
  fail_loud: "role='alert' error surfaces in-modal/in-surface when a pending action rejects"

failure_modes:
  - mode: "pending state never terminates (hung request)"
    detection: "bar/spinner visibly stuck >30s; nav_duration_ms events stop; Sentry breadcrumb trail ends mid-nav"
    alert_route: "Sentry issue via reportSilentFallback on the catch path; e2e spec asserts stop() fires"
  - mode: "double-submit on unguarded button"
    detection: "residual-zero rg sweep + disabled-during-pending contract test"
    alert_route: "CI fails on the sweep assertion"
  - mode: "indicator never fires on a nav channel (e.g. regression removes a trigger)"
    detection: "Playwright authenticated spec covers Link/anchor/push paths"
    alert_route: "CI e2e failure"

logs:
  where: "Plausible nav_duration_ms series + Sentry breadcrumbs"
  retention: "vendor-managed"

discoverability_test:
  command: "grep -c 'NavPendingIsland' apps/web-platform/app/layout.tsx"
  expected_output: "1"
```

## Encryption Posture

Not applicable — no new persistent store or cross-component connection; pure UI-layer change on an already-provisioned surface.

## Guard Contract

### Guard 1 — route-pending e2e spec (`authenticated` project)

**Property.** The top bar is visible iff a soft navigation has been in flight ≥150ms, and it clears on route commit (pathname OR searchParams change).
**Assembly.** The three trigger channels (`NavLink.onNavigate`, `usePendingRouter.push/replace`, `popstate`) plus the completion watcher — the spec must exercise each channel's row, not one canonical path.
**Mutation matrix.**
1. Remove the island mount from `app/layout.tsx` → spec reds on every channel row.
2. Delete the `useSearchParams` watcher → the `workstream?issue=` same-path row reds while pathname rows stay green.
3. Drop the 150ms entry delay → the "instant nav does not flash" assertion reds (strobe detected).
4. Remove the ~30s stall timeout → the never-committing-nav row (e.g. push to an unmountable target) leaves the bar up and reds.
5. Remove the identical-URL no-op in `usePendingRouter` → the active-tab re-click row (`inbox-surface` shape) leaves a stuck bar and reds.
6. Delete `start()` idempotency → a co-fired `start()` while pending resets the min-visible window; the "bar does not extend on double-trigger" row reds.
7. *Harness row:* the "bar hidden before click" pre-assertion must PASS on unmutated code — a suite that asserts visibility only can pass while the bar is always-on.

### Guard 2 — residual-zero button sweep

**Property.** Every interactive `<button>` in `components/` and `app/` renders through the `Button` primitive (or carries `data-button-exempt` with a non-empty reason), so `loading` is the only pending convention — AND the migration preserves behavior: `type` semantics, `data-*`/`aria-*` props, focus, error rendering.
**Assembly.** `rg '<button' -g '*.tsx' apps/web-platform/components apps/web-platform/app` — the whole corpus, minus the primitive file itself and the `data-button-exempt`-marked set; NOT the files the sweep happened to touch (an inventory is a snapshot). Re-run on the rebased tree before merge — a sibling landing new native buttons on main must red the gate (arch #6).
**Enforcement mechanism (cto #1):** `scripts/check-button-primitive-sweep.sh` + a vitest wrapper — modeled on `check-workspace-members-write-sites.sh` — with a **baseline ratchet** (a checked-in count of tolerated native sites that may only decrease), so no new native `<button>` can land during the migration window and partial/domain-sliced PRs stay safe; residual-zero is the convergence target.
**Mutation matrix.**
1. Add a native `<button>` not marked `data-button-exempt` → sweep check reds.
2. Mark one `data-button-exempt=""` → reason-presence assertion reds.
3. Delete a `loading={pending}` wiring at a migrated mutation site → the pending-contract test reds.
4. Give `Button` a `type="button"` default → the implicit-submit fixture (a `<form onSubmit>` containing an untyped `<Button>`) reds (kieran #6 / arch #1).
5. Drop a `data-testid`/`data-tour-id`/`aria-*` passthrough in the primitive → the prop-parity check across migrated sites reds (a dropped `data-tour-id` silently breaks the tour; arch #1).
6. *Harness row:* a fixture component containing a compliant `<Button loading>` must PASS the same grep — the sweep must not reject everything.

## Acceptance Criteria

- [ ] AC1: Clicking a `<Link>`/anchor/`router.push`/⌘K/g-key/popstate navigation shows the gold top bar within 200ms; it clears on route commit including same-path `?query` navs. Provider mounted once in `app/layout.tsx`.
- [ ] AC1b: A nav trigger that never commits (identical-URL push, failed RSC fetch, `/api/` download anchor) never leaves a permanent bar — identical-URL targets no-op in `usePendingRouter`, non-navigating anchors stay native (no listener interception), and a ~30s stall timeout clears + breadcrumbs any other hang. A screen-reader live region announces pending only when the bar is visible (spec-flow #27 + ux #5).
- [ ] AC2: Navigations completing faster than the entry delay produce no visible flash. `usePendingRouter` passes `refresh`/`back`/`forward`/`prefetch` through untouched; `refresh` never fires the bar.
- [ ] AC3: `rg '<button' -g '*.tsx' apps/web-platform/components apps/web-platform/app` returns only the primitive file(s) and `data-button-exempt`-marked sites (non-empty reasons; ~15% budget). All ~22 existing `GoldButton`/`OutlinedButton` call sites are migrated to `Button` and the two files deleted. Migration preserves `type` semantics (14 `<form>` sites audited line-item), `data-testid`/`data-tour-id`/`aria-*` passthrough (mechanical parity check), and focus (restore-on-resolve).
- [ ] AC4: Every mutation-triggering button renders `disabled` + `aria-busy` + spinner while its action is in flight; billing Reactivate and Update Payment Method included.
- [ ] AC5: Every pending state terminates — success resolves the action; failure shows `role="alert"` and re-enables the control. On `window.location.*` redirects, pending never resets in `finally` (the redirect latches — `billing-section.tsx` `redirectTo` fixed; spec-flow C4).
- [ ] AC6: Typed-confirm modal stays open showing "Sending…" until the send resolves; input locked, ALL dismiss vectors inert (Cancel, Esc, backdrop, sheet close/drag — via `onClose={pending ? undefined : onCancel}`; spec-flow C3); focus moves to the status element and the outcome is announced via polite `aria-live` (CPO C2).
- [ ] AC6b: On irreversible/billing paths, a pending state lasting >~8s appends "Still working…" to a polite `aria-live` region (CPO C1 — slow must not read as hung).
- [ ] AC6c: Bar/spinner gold uses the per-palette token — `--accent-gold-fg` in Solar Radiance, `--accent-gold-fill` in Dark Matter (CPO C3).
- [ ] AC6d: Tier-1 billing/consent diffs pass a dedicated review checkpoint before Tier-2 commits land (CPO C4).
- [ ] AC7: `window.location.assign` call sites unchanged (hard-nav boundary preserved) — verified via `git diff origin/main...HEAD -- apps/web-platform` showing no removal/rewrite of `window.location.` sites (merge-base diff, not tip).
- [ ] AC8: Playwright `authenticated` spec covers bar-appears/bar-clears per nav channel and button pending on a mutation; green in CI.
- [ ] AC9: `.pen` wireframes committed under `knowledge-base/product/design/dashboard/` (done — variant B approved).
- [ ] AC10: `nav_duration_ms` events emit per soft navigation with `path: "nav:<trigger>:<section>"` (trigger ∈ link|router|popstate; section ∈ fixed top-level enum — never a concrete path; kieran #5). Sentry breadcrumbs carry durations.
- [ ] AC11: `prefers-reduced-motion` produces static (non-animated) pending affordances.
- [ ] AC12: ADR for the action-feedback contract committed (provisional ordinal re-verified at ship).

## Test Scenarios

- Unit (vitest): `usePendingAction` pending lifecycle + error reset; `usePendingRouter` delegates and flags; `Button` loading contract (disabled/aria-busy/spinner); `NavLink` fires `start()` on navigate; provider delay/min-visible/stop logic with fake timers.
- e2e (Playwright authenticated): bar on Link click→commit; bar on `?query` nav; no bar under the entry delay; button pending on a mutation fixture; typed-confirm modal pending path.
- Sweep: the residual-zero rg assertion + exempt-marker reason check (Guard 2).

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Marketing

### Product

**Status:** reviewed
**Assessment:** Brainstorm carry-forward — feedback is mitigation, not a latency fix; P0 = typed-confirm send (currently invisible in-flight); one canonical pending visual language required; wireframes approved (variant B).

### Legal

**Status:** reviewed
**Assessment:** Net risk reduction. Pending must always terminate on cancel/consent paths (ROSCA/dark-pattern); billing triggers get full disabled coverage; `aria-busy` standard; `gdpr-gate` mandatory iff `app/api/**` enters the diff — checkout idempotency deferred to #8918 keeping this PR outside the regex.

### Engineering

**Status:** reviewed
**Assessment:** No router-events API → layered triggers (NavLink + passive listener + usePendingRouter). `useLinkStatus` alone can't drive a global bar. Hard-nav boundary preserved. `useSearchParams` in the completion watcher for same-path query navs. Playwright e2e is the honest verification path.

### Marketing

**Status:** reviewed
**Assessment:** Trust floor for non-technical founders; protects demo/validation sessions. Quiet `web-v*` polish release note ("clearer, more responsive feedback"), no dedicated announcement.

**Brainstorm-recommended specialists:** soleur:product:design:ux-design-lead (invoked at brainstorm Phase 3.55 — `.pen` committed, approved)

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo (brainstorm carry-forward), soleur:product:spec-flow-analyzer, soleur:product:design:ux-design-lead (brainstorm Phase 3.55)
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

Wireframes committed + approved at brainstorm (variant B, instrumented-spec). `.pen` invariant satisfied: `design/dashboard/action-feedback-variant-b-instrumented-spec.pen` non-empty, referenced in spec FRs. **CPO: APPROVE-WITH-CONDITIONS** — C1–C4 folded into AC6b/AC6c/AC6d and the typed-confirm spec. **spec-flow-analyzer:** 28-row permutation matrix; 5 critical gaps found and folded in (stall termination + identical-URL no-op + `/api/` exclusion; single-mount correction; Esc/dismiss suppression; redirect-latch rule; `refresh` passthrough), plus important items (SR live region, popstate coverage, telemetry `trigger` field, `start()` idempotency, pending granularity, error-render verification). Accepted narrowings: `<div onClick>` rows (e.g. `conversation-row.tsx`) get nav-pending via the bar but no per-element press affordance — button-scoped sweep stands; in-flight mutation + nav-away drops the pending result silently (accepted for sub-typed-confirm stakes); RefreshShimmer/nav-bar coexistence accepted (shared idiom).

## Open Code-Review Overlap

3 open scope-outs touch planned files: **#3564** (CWV infrastructure — globals.css + app/layout.tsx) **acknowledge**: a separate open-design perf-observability initiative; the `nav_duration_ms` channel this plan adds is complementary and stays inside this PR's UX scope. **#2349** (qa skill port/loader collision) **acknowledge**: globals.css mention is incidental (a symptom in a stack trace), no real overlap. **#2193** (billing banner refactor — `(dashboard)/layout.tsx`) **defer**: shared-component extraction in the same file; this PR may swap its rail Links to `NavLink` — whichever lands second resolves a small conflict; revisit after this lands.

## Architecture Decision (ADR/C4)

### ADR

New ADR (provisional ordinal — re-verified against `origin/main` at ship): **"Canonical action-feedback contract"** — all interactive elements render through the `Button` primitive family with the `loading` contract; navigation pending is owned by the nav-pending store/island; hard-nav boundaries unchanged. Alternatives: per-site ad-hoc pending (status quo — rejected, 50% unguarded), layered intercept without migration (rejected by operator).

### C4 views

No C4 impact — checked against `model.c4`/`views.c4`/`spec.c4`: (a) external human actors: none new (end user already `founder`); (b) external systems/vendors: none new (Plausible/Sentry already modeled); (c) containers/data stores: none new (all work is intra-`platform.webapp`); (d) access relationships: unchanged. No element description is falsified by this change.

### Sequencing

ADR authored in this PR with `status: adopting`; the primitives-supremacy lint rule is a separate productize candidate (#8918's sibling — filed if adopted at review). The ADR also records the exemption budget, the per-tier revert-unit rule, and that a soft-nav committing without a preceding `start()` surfaces as a `trigger`-dimension telemetry gap — the drift detector for channels nobody wired (arch #9 + cto).

## Dependencies & Risks

- ~160-file diff — mitigated by mechanical codemod-style sweeps, tiered ordering, and per-tier vitest.
- `staleTimes.dynamic: 30` warm-cache behavior → entry delay prevents strobe (AC2).
- TourProvider drives nav via `router.push` — bar will show during tour steps (accepted; truthful).
- Migration fidelity: bespoke `aria-*`/`data-testid`/`data-tour-id` attributes (~165 sites) must passthrough — the primitive forwards them; per-tier diff review.
- Full sweep may surface genuinely bespoke buttons (cmdk items, complex toggle groups) → `data-button-exempt` markers, bounded by the ~15% exemption budget (arch #5).
- Rollback unit: per-tier domain-grouped commits (arch #7) — if a tier rolls back after Guard 2 exists, native sites get `data-button-exempt="revert-pending"` so CI stays green during the temporary two-convention state; Phases 1–2 are additive and can ship as an earlier mergeable slice to shrink Phase 3's open window (arch #6).
- `useRouter` swap list built per-site at work time (~16 files with push/replace; refresh-only callers like `api-usage-retry-button` must NOT be swapped — arch #10); bar `z-50` sits under `z-[60]` modals/mobile-chat — layering noted.
- Migration-review path (cto #4): review by tier commit, not by file; PR body carries an auto-generated per-file manifest (`mechanical | manual | exempt`) so reviewers read ~30 rows + spot checks, not 160 files.

## Success Metrics

- Zero dead-looking clicks: every interactive element shows press or pending feedback.
- Zero unguarded mutation buttons (residual-zero sweep).
- nav_duration_ms telemetry flowing within 24h of deploy.

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-09-25-ui-action-feedback-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-ui-action-feedback/spec.md` (lane: cross-domain)
- Wireframes: `knowledge-base/product/design/dashboard/action-feedback-variant-b-instrumented-spec.pen`
- Deferred: #8918 (`/api/checkout` idempotency), #8964 (pencil tooling)
- ADR-067 (cache/hard-nav), ADR-047 (swap region), ADR-049 (visual gate), ADR-090 (design-shotgun)

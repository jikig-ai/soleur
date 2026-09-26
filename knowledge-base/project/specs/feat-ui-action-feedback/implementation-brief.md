# Implementation Brief — feat-ui-action-feedback

**Wireframe-to-Implementation Handoff.** This document is the binding input for implementers. Where the approved wireframe and the plan disagree, this brief states the FINAL value once — see the reconciliation ledger in §9.

- **Approved wireframe:** `knowledge-base/product/design/dashboard/action-feedback-variant-b-instrumented-spec.pen` (Variant B "Instrumented Spec", approved 2026-09-25; production styling adopts Variant A's quiet visuals — i.e. ship the same geometry/values, drop the spec-rail instrumentation chrome: callout badges, SPEC panels, measurement labels do not ship).
- **Plan:** `knowledge-base/project/plans/2026-09-25-feat-ui-action-feedback-plan.md` (issue #8917, PR #8904)
- **Spec:** `knowledge-base/project/specs/feat-ui-action-feedback/spec.md`
- **Production anchors:** `apps/web-platform/components/ui/refresh-shimmer.tsx`, `apps/web-platform/app/globals.css` (`--soleur-*` tokens @ :39-121, `@theme` @ 129-151, refresh-shimmer keyframes + reduced-motion carve-out @ 277-292, global reduced-motion sweep @ 244-253), `apps/web-platform/components/ui/constants.ts` (`GOLD_GRADIENT`), `apps/web-platform/components/icons/index.tsx` (`SpinnerIcon` @ ~82), `apps/web-platform/components/ui/typed-confirm-modal.tsx`, `apps/web-platform/components/ui/responsive-modal.tsx`.

---

## 0. Token map (`.pen` variable → production token)

All color values consume `var(--soleur-*)` tokens via the Tailwind `*-soleur-*` utilities — **zero raw hex in production** (P5). The `.pen`'s flat values are Dark Matter equivalents; production resolves per palette.

| `.pen` var / value | Production token | Dark | Light (Solar Radiance) |
|---|---|---|---|
| `$bg-base` | `--soleur-bg-base` | `#0a0a0a` | `#fbf7ee` |
| `$bg-surface-1` | `--soleur-bg-surface-1` | `#141414` | `#f4eedf` |
| `$bg-surface-2` | `--soleur-bg-surface-2` | `#1c1c1c` | `#ede4cc` |
| `$border-default` | `--soleur-border-default` | `#2a2a2a` | `#d8c9a6` |
| `$accent-gold` (`#C9A962`, gold on surface) | **`--soleur-accent-gold-fg`** | `#c9a962` | `#9c7a2e` |
| `$text-primary` | `--soleur-text-primary` | `#fff` | `#1a1612` |
| `$text-secondary` | `--soleur-text-secondary` | `#848484` | `#5c5043` |
| `$text-tertiary` | `--soleur-text-muted` | `#6a6a6a` | `#6f6353` |
| `$ink-on-gold` | `--soleur-text-on-accent` | `#1a1612` | `#1a1612` |
| gradient `#D4B36A→#B8923E` | `--soleur-accent-gradient-start` → `--soleur-accent-gradient-end` via `GOLD_GRADIENT` (`linear-gradient(90deg, …)`, `components/ui/constants.ts`) | — | — |
| shimmer band `#D4B36ACC→#B8923ECC` | the moving sliver at ~80% alpha → `bg-soleur-accent-gold-fg/80` (§1) | — | — |

**Gold token rule (CPO C3 / AC6c):** every *foreground* gold on a page background — the nav-pending sliver, standalone/outlined spinners — uses **`--soleur-accent-gold-fg`**. It resolves `#9c7a2e` in Solar Radiance (fill `#c9a962` reads ~2:1 on cream) and `#c9a962` in Dark Matter, where it is identical to `--soleur-accent-gold-fill`'s dark value — the single token satisfies the "fg in Solar Radiance, fill in Dark Matter" contract. Precedent: `.cmdk-loading-spinner` uses `border-top-color: var(--soleur-accent-gold-fg)` (globals.css:413). The gold *CTA fill* itself stays `GOLD_GRADIENT` (`--soleur-accent-gradient-start`→`end`), unchanged in pending — only opacity dips.

---

## 1. Route-pending bar — desktop

### Visual spec

| Property | FINAL value |
|---|---|
| Track | `fixed inset-x-0 top-0 z-50 h-[2px] overflow-hidden pointer-events-none` — full-viewport-width, 2px tall, transparent track (RefreshShimmer idiom, `refresh-shimmer.tsx:20`) |
| Sliver | `h-full w-1/3 animate-[refresh-shimmer_1.1s_ease-in-out_infinite] bg-soleur-accent-gold-fg/80` — one-third-width gold sliver sweeping left→right (pen draws it frozen at 480px on a 1440px canvas ≈ 1/3, mid-sweep) |
| Animation | `@keyframes refresh-shimmer` `translateX(-100%) → translateX(400%)`, **1.1s ease-in-out, infinite loop** (globals.css:277-284; pen spec rail "shimmer: 1.1s ease-in-out loop") |
| Placement/z | `z-50` — sits **below** `z-[60]` modal/sheet chrome (accepted layering); rides the viewport top edge, reserves **zero layout footprint** (pen: "no layout shift, no input block") |
| A11y | `aria-hidden="true"` (decorative); companion sr-only live region in §5 |

### States & transitions

1. `startNavPending(trigger)` fires (trigger ∈ `link | router | popstate`) → pending episode begins; `start()` is **idempotent** — a second `start()` while pending is a no-op.
2. **Entry delay 150ms** — the bar mounts only if the episode is still open at 150ms (see §9-R8; the `.pen`'s "+150-200ms" is the tolerance band, shipped constant is 150). Navs committing under the delay produce **no visible flash** (AC2).
3. Visible: sliver sweeps continuously. Input is never blocked (`pointer-events-none`).
4. Exit on **route commit** (`usePathname` OR `useSearchParams` delta — same-path query navs like `workstream?issue=` count) or **abort**.
5. **Min-visible ~400ms**: once shown, the bar holds ≥400ms to avoid a one-frame flicker; idempotency extends through the hold — a trigger inside the hold does not restart the clock (ux #8).
6. **Stall termination**: `start()` arms a **~30s hard timeout** → `stop()` + Sentry breadcrumb; a hung RSC fetch or never-committing trigger can never leave a permanent bar (spec-flow C1).

### Mount contract

**One mount only**: a Suspense-wrapped client island (`components/nav/nav-pending-island.tsx`) in **root `app/layout.tsx`** — covers every route group. Never also in `(dashboard)/layout.tsx` (double-mount = doubled listeners/telemetry; spec-flow C2). The `useSearchParams` consumer is `<Suspense>`-wrapped inside the island (hygiene; the root layout is already dynamic).

### Edge cases

- **Same-URL triggers never fire the bar**: `NavLink` gates `onNavigate → start()` on `isSameDocTarget` (active-rail re-click, kieran #2); `usePendingRouter.push/replace` resolves the target via `new URL(href, location.href)` (hash excluded, `UrlObject`/relative normalized) and **skips `start()` but still delegates** (same-URL pushes carry scroll-to-top). `refresh`/`back`/`forward`/`prefetch` pass through untouched — `refresh` must never fire the bar.
- **`popstate`** fires `start()` only when `pathname+search` differs from the continuously-updated last-location ref — hash-only history entries (`#main-content` skip-link) and already-updated locations never fire (kieran #4/#8).
- **`window.location.assign` hard navs excluded** (sign-out, org-switch, delete-account, login — ADR-067 boundary, ~45 sites untouched). No passive document click listener exists (§9-R2): non-navigating anchors (`/api/` downloads, `mailto:`, external, `#fragment`) stay native and are correct by default.
- **TourProvider-driven navs** do show the bar (truthful feedback, accepted); verify the bar is not fully occluded by tour spotlight chrome at e2e — cosmetic only if it is.
- **RefreshShimmer coexistence**: a SWR revalidation shimmer and the nav-pending bar may occupy the same 2px slot simultaneously — identical idiom, harmless overlap (accepted).
- Pre-hydration triggers cannot throw — the store is module-level, not context/evented.

---

## 2. Route-pending bar — mobile PWA (safe-area)

Identical contract to §1 with one change:

| Property | FINAL value |
|---|---|
| Top offset | `top: env(safe-area-inset-top, 0px)` on the fixed bar — the band renders **below** the iOS notch/status strip (pen mobile frame: 47px safe-area strip, band pinned at y=47; spec note "bar pinned below env(safe-area-inset-top); same 1.1s shimmer") |

- Same 2px height, same `w-1/3` sweeping sliver (pen mobile draws it frozen at 130px on 390px ≈ 1/3), same 1.1s keyframes, same gold token, same `z-50`, same `aria-hidden`, same timing/idempotency/stall semantics.
- On non-notch contexts `env(safe-area-inset-top)` resolves `0px` → identical to desktop. No breakpoint branching is needed or permitted — one rule covers both frames.
- The existing `.safe-top`/`.safe-bottom` component classes (globals.css:206-211) are for in-flow padding and are **not** used here — the bar is fixed chrome, not flow content.

---

## 3. `Button` pending states — gold / outlined / ghost / danger + icon-only

One `forwardRef` `Button` primitive (`components/ui/button.tsx`): `variant: "gold" | "outlined" | "ghost" | "danger"`, `loading?: boolean`, `loadingLabel?: string`, `type` forwarded with **no default** (native `submit` semantics inside the ~14 `<form>` sites preserved), `disabled`, merged `className`, all `aria-*`/`data-*`/`on*` props via rest-spread. `GoldButton`/`OutlinedButton` are migrated and **deleted** (no shim).

### 3.1 Idle geometry (all variants)

| Property | FINAL value |
|---|---|
| Padding | `px-6 py-3` (pen `[12, 24]`) — ~44px height, satisfies the 44×44 tap-target floor |
| Radius | `rounded-lg` (8px) — existing primitive radius |
| Label | `text-sm font-medium` (pen: Inter 14/500) |

### 3.2 Variant fills & label colors (idle)

| Variant | Background | Border | Label |
|---|---|---|---|
| `gold` | `GOLD_GRADIENT` (`linear-gradient(90deg, var(--soleur-accent-gradient-start), var(--soleur-accent-gradient-end))`) — matches existing gold CTAs | none | `text-soleur-text-on-accent` (pen `$ink-on-gold`) |
| `outlined` | transparent | `border border-soleur-border-default` (1px) | `text-soleur-text-primary` |
| `ghost` | transparent | none | `text-soleur-text-secondary` |
| `danger` | `bg-red-600`, `hover:bg-red-500` (existing corpus idiom, e.g. `billing-section.tsx:150`) | none | `text-white` |

### 3.3 Pressed state (`:active`, all variants — pen "PRESSED" column)

- **`scale-[0.98]` + `opacity-90`, ~120ms** transition (pen spec rail "pressed: scale-98, opacity-90, ~120ms"; the pen draws the 2% shrink as a 1px padding inset `[11, 23]` vs `[12, 24]` — production uses transform, not padding, so zero layout shift).
- Under `prefers-reduced-motion`: the **scale transform is suppressed entirely** (`motion-reduce:active:scale-100` or equivalent); the `opacity-90` dip remains (instant state change, no animation). The global sweep (globals.css:244-253) already compresses the transition to 0.01ms.
- Tier-3 pure-UI buttons get the press affordance only; `loading` stays unwired.

### 3.4 Pending state (`loading={true}`)

**Applies immediately at `loading=true`:** `disabled` + `aria-busy="true"` + pending opacity. `disabled` cannot wait for the spinner delay — the double-submit window is P2's whole point.

**Spinner entry delay ~150ms** (plan ux #6): the `SpinnerIcon` mounts only if still pending at ~150ms — fast mutations never strobe a spinner. No min-visible contract on button spinners (min-visible is a bar-only contract; see §9-R8 for the shared 150ms constant).

| Property | FINAL value |
|---|---|
| Opacity | **`0.55`** on page/surface contexts; **`0.65`** for pending controls inside modal surfaces (pen: Primary/Secondary/Ghost pending = 0.55, modal "Send pending" = 0.65 — the scrim context needs the higher floor for legibility) |
| Spinner | `SpinnerIcon` (`components/icons/index.tsx`, `animate-spin`, `currentColor`) at **`h-3.5 w-3.5` (14×14)** — pen spinner geometry is a 14px ring arc (`innerRadius 0.78`, 270° sweep) which `SpinnerIcon` reproduces |
| Position | **Leading** — DOM order `[spinner][label]`, `gap-2` (pen `gap: 8`). Spec.md FR2's "trailing" is superseded (§9-R3) |
| Label | **Kept by default** (pen Ghost row: "spinner only, label kept"). `loadingLabel` is opt-in per call site for verb-matched copy — "Saving…", "Deleting…", "Sending…" — the ellipsis character `…` is standardized inside the primitive so ~310 sites cannot drift. Label weight does **not** change on pending (§9-R10) |
| Spinner color | per variant: `gold` → `text-soleur-text-on-accent`; `outlined` → `text-soleur-accent-gold-fg`; `ghost` → `text-soleur-text-muted`; `danger` → `currentColor` (white on red). The pen deliberately spins a *gold* arc on the outlined button against a primary-colored label — do not inherit `currentColor` on `outlined`/`ghost` |
| Semantic | `disabled` + `aria-busy="true"`; accessible name unchanged (no `loadingLabel` = same accessible name; with `loadingLabel` the name becomes the loading copy) |

**`loading` implies `disabled`** — callers must not be able to render `loading` + clickable.

### 3.5 Icon-only buttons (~211 `aria-label` sites)

- **Content-replacement**: the spinner **swaps the icon inside a pinned-size container matching the icon's rendered box** — never appends (a trailing spinner shifts width → P5 violation, arch #5).
- Spinner color follows the §3.4 per-variant rule applied at the icon slot.
- `aria-label` stays untouched (stable accessible name); `aria-busy="true"` + `disabled` as usual. Same 150ms spinner entry delay.

### 3.6 States & transitions (lifecycle)

Lifecycle: **idle → `:active`** (pressed affordance, 120ms) **→ `loading=true`** (disabled+aria-busy+opacity dip immediately, spinner at +150ms) **→ resolve**: pending cleared, spinner unmounts, control re-enabled; **→ reject**: pending cleared, control re-enabled, `error` surfaces `role="alert"` (P3 — pending always terminates).

- **Focus contract (ux #1, blocking):** `usePendingAction` restores focus to the control on resolve when `activeElement` collapsed to `<body>` — the disabled-flip otherwise destroys keyboard place on every submit.
- **Redirect latch (spec-flow C4):** on `window.location.*` redirects, pending **never resets in `finally`** — `opts.latchOnRedirect` is the typed default (`use-sign-out.ts`/`upgrade-at-capacity-modal` precedent; `billing-section.tsx` `redirectTo` gets fixed).
- **Granularity:** pending is shared per logical action-group (billing's coupled buttons share one flag); per-control flags only where actions are independent.
- Under `prefers-reduced-motion` the spinner is **static** (global sweep kills `animate-spin` — accepted precedent: the cmdk spinner's static gold ring reads as "in progress").

### 3.7 Edge cases

- `<form>` sites: `type` has no default; untyped `<Button>` inside `<form onSubmit>` keeps implicit-submit. The 14 sites get a line-item audit.
- Toggle/`aria-pressed` groups, cmdk items, composite markup: `data-button-exempt="<reason>"` (non-empty), bounded by the ~15% exemption budget.
- Bespoke `data-testid`/`data-tour-id`/`aria-*` (~165 sites) must passthrough — rest-spread, verified by the prop-parity check.
- `<div onClick>` rows (e.g. `conversation-row.tsx`): get nav-pending via the bar only; no per-element press affordance (accepted narrowing).
- Consent surfaces keep ack-gating — `loading` never auto-submits (TR3).

---

## 4. Typed-confirm modal — pending state

Surfaces: `hooks/use-action-send.ts` (`onConfirmTyped` keeps the modal open — it currently closes before the POST, the highest-stakes feedback gap) + `components/ui/typed-confirm-modal.tsx` pending render.

### Visual spec (pen "Typed-Confirm Modal - Pending" frame)

| Element | FINAL value |
|---|---|
| Scrim | existing `bg-black/50` (ResponsiveModal:147) — **unchanged**; the pen's `#00000099` (60%) is illustrative (§9-R13). Backdrop click already disabled (`closeOnBackdrop={false}`) |
| Modal | `bg-soleur-bg-surface-1`, `border-soleur-border-default` 1px, `rounded-xl` (pen radius 12 / existing `max-w-md` ~448px) — unchanged shell |
| Confirm input | `disabled` + `opacity-50` while pending; 14px `LockIcon` `text-soleur-text-muted` trailing (pen "Locked input" `opacity 0.5`); sublabel "Input locked while request in flight" `text-[11px] text-soleur-text-muted` (pen "Lock note"). The typed `SEND` value remains visible and **persists through failure** — no re-typing (ux #9) |
| Cancel | `disabled` + `opacity-50` (pen "Cancel" `opacity 0.5`) — `rounded-md` `border-soleur-border-default` (existing) |
| Submit button | renders through `Button variant="gold"`: gold gradient, `rounded-lg` (2px radius change vs existing `rounded-md`, consistent with the family), `min-h-[44px]`, label "Sending…" `font-semibold` (existing submit is already `font-semibold`; pen pending label = 600), leading 14px spinner `text-soleur-text-on-accent`, `gap-2`, pending opacity **0.65** (modal surface) |

### States & transitions

1. User types `SEND` (exact, case-sensitive — unchanged gate) → submit enabled.
2. `onConfirm` → `confirmPending` inside `useTransition`: modal **stays open**, submit swaps to spinner + "Sending…" (`loadingLabel`), input locked, Cancel inert.
3. Success → modal closes → acknowledged pill/archives (existing `handle200`/`already_sent` paths).
4. Failure → pending clears, controls re-enable, error surfaces **`role="alert"` in-modal** (existing `setError` strings: "Send failed (…)", "Draft changed since you confirmed — please re-send."), typed `SEND` persists.
5. Enter during pending **must not re-invoke** `onConfirm` — gate `handleSubmit` on `canSubmit && !pending` since `canSubmit` stays true while the input is disabled (ux #10; e2e-tested).

### A11y contract

- `role="dialog" + aria-modal="true" + aria-labelledby/aria-describedby` — existing, unchanged.
- `aria-busy="true"` on the modal container while pending.
- **Focus moves to the status element** during pending; success/failure announced via a **polite `aria-live` region** (CPO C2 — `aria-busy` alone does not announce resolution). On failure, focus moves to the `role="alert"`.
- **Dismiss suppression (spec-flow C3):** while pending, ALL dismiss vectors are inert — Cancel, Esc, backdrop, the sheet's close control, and the mobile-sheet drag/swipe gesture — via `onClose={pending ? undefined : onCancel}` on `ResponsiveModal` (its Esc listener, backdrop `onClick`, and X control all key off `onClose` presence; mirrors `sign-out-confirm-modal`'s `isSigningOutRef` guard). The drag/swipe-to-dismiss gesture on the mobile sheet branch is verified inert at work time (plan task).
- Pen note "Esc / cancel stay live until pending" means live *until* pending begins — then inert until resolution (pen modal rail: "Cancel + Esc inert until resolution"). No conflict.

### Edge cases

- Re-pending after failure: a corrected retry starts a fresh pending episode — escalation timer (§5) resets per episode.
- `confirming` state cleared only on success or explicit cancel — never mid-flight.
- 409 `already_sent` resolves to the acknowledged path without an error surface (existing).

---

## 5. Escalation contract — ~8s "Still working…" (CPO C1 / AC6b)

Not drawn in the pen — plan-derived, binding.

- **Where:** irreversible/billing paths only — ~3 call sites (`billing-section.tsx` redirect CTAs, sign-out). **Not** a generalized `Button` feature (DHH #13).
- **Trigger:** pending episode older than **~8s**.
- **Render:** "Still working…" appended into a **reserved-space sublabel** (pre-rendered empty container — zero layout shift when it populates, P5) beneath/adjacent to the pending control, inside a `role="status"`/`aria-live="polite"` region.
- **Copy:** "Still working…" exactly (CMO-approved — honest without overpromising; no "processing" jargon).
- **Timer:** `setTimeout` per site (~10 lines); resets **per pending episode** — a fast retry doesn't inherit a stale clock (ux #7).

---

## 6. A11y contract summary

| Surface | Contract |
|---|---|
| Nav bar | `aria-hidden="true"` on the visual bar. A **visually-hidden `role="status"`** live region announces "Loading" **only when the bar becomes visible** — never at `start()`, or warm-cache navs spam announcements with no visible feedback (ux #5) |
| Button | `aria-busy="true"` + `disabled` during pending; stable accessible name; icon-only keeps `aria-label`; focus restored to the control on resolve when it collapsed to `<body>` (ux #1); errors via `role="alert"` |
| Typed-confirm | `aria-busy` on container; focus → status element while pending; polite `aria-live` announces outcome; failure → focus to `role="alert"`, `SEND` persists |
| Reduced motion | bar → **static dim sliver** (`animation: none; width: 100%; opacity: 0.5` — mirror the `[data-testid="refresh-shimmer"] > *` carve-out at globals.css:286-292 under a new `data-testid="nav-pending-bar"`); press scale suppressed (opacity dip remains); `SpinnerIcon` static (global sweep precedent); no other motion changes |

---

## 7. Shared constants (FINAL — implement as named constants)

| Constant | Value | Notes |
|---|---|---|
| `PENDING_ENTRY_DELAY_MS` | **150ms** | shared by bar + button spinner; `.pen`/plan "150–200ms" is the tuning band (AC1 requires <200ms; §9-R8) |
| `NAV_MIN_VISIBLE_MS` | **~400ms** | bar only; no button min-visible specified |
| `NAV_STALL_TIMEOUT_MS` | **~30s** | hard stop + Sentry breadcrumb |
| `ESCALATION_DELAY_MS` | **~8000ms** | irreversible/billing paths only |
| Bar height / sliver | **2px / `w-1/3`** | `refresh-shimmer` keyframes, 1.1s ease-in-out infinite |
| Spinner size | **`h-3.5 w-3.5` (14px)** | `SpinnerIcon`, `currentColor` + per-variant color class |
| Press | **`scale-[0.98]` + `opacity-90`, 120ms** | transform suppressed under reduced-motion |
| Pending opacity | **0.55** (page) / **0.65** (modal surfaces) / **0.5** (inert siblings: locked input, Cancel) | |
| Telemetry | `track("nav_duration_ms", {path: "nav:<trigger>:<section>"})` | trigger ∈ `link\|router\|popstate`; section ∈ fixed first-segment enum (dashboard\|kb\|chat\|settings\|inbox\|workstream\|crm\|releases\|connect-repo\|shared\|invite\|auth) — never a concrete path; `performance.now()` at start/stop; durations ride the Sentry breadcrumb |

---

## 8. Files this brief binds

- New: `components/ui/button.tsx`, `components/ui/nav-link.tsx`, `lib/nav-pending-store.ts`, `components/nav/nav-pending-island.tsx`, `hooks/use-pending-action.ts`, `hooks/use-pending-router.ts`
- Edit: `app/layout.tsx` (single island mount), `app/globals.css` (press-affordance rule + nav-pending-bar reduced-motion carve-out; reuse `refresh-shimmer` keyframes), `hooks/use-action-send.ts`, `components/ui/typed-confirm-modal.tsx`, sweep targets per plan Phases 2–3
- Delete: `components/ui/gold-button.tsx`, `components/ui/outlined-button.tsx` (after ~22 call sites migrate)

---

## 9. Spec-vs-plan reconciliation ledger

| # | Item | Wireframe / spec.md | Plan | **FINAL** |
|---|---|---|---|---|
| R1 | Island mount | spec FR1/TR1: `(dashboard)/layout.tsx` | root `app/layout.tsx`, one mount (spec-flow C2) | **Root `app/layout.tsx`, single Suspense island** |
| R2 | Raw-anchor channel | spec FR1: passive capture-phase document click listener | **cut** (DHH #5); ~16 real internal anchors convert to `NavLink`, non-navigating anchors stay native | **Three channels only: `NavLink.onNavigate`, `usePendingRouter`, `popstate` — no document listener** |
| R3 | Spinner position | spec FR2: "trailing SpinnerIcon" | **leading** (`[spinner][label]`, `.pen` DOM order; ux #2) | **Leading**, `gap-2` |
| R4 | Pending opacity | pen: 0.55 buttons / 0.65 modal send | same | **0.55 page / 0.65 modal** |
| R5 | Label swap | pen swaps on gold+secondary, keeps ghost | opt-in `loadingLabel` only | **Default keep label; `loadingLabel` opt-in, verb-matched, `…` standardized in primitive** |
| R6 | Gold token | pen: flat `#C9A962` / `#D4B36ACC→#B8923ECC` band | per-palette token (CPO C3) | **`--soleur-accent-gold-fg`** for bar sliver + surface spinners (resolves `#9c7a2e` light / `#c9a962` dark ≡ fill's dark value); gold CTA fill stays `GOLD_GRADIENT` |
| R7 | Escalation | absent from pen | ~8s "Still working…" (CPO C1) | **§5 contract: reserved sublabel + polite aria-live, ~3 irreversible/billing sites, per-episode reset** |
| R8 | Entry delay | pen "+150-200ms" | "150–200ms" | **150ms shared constant** — band is a tuning range, not a randomized value |
| R9 | Min-visible | absent from pen | ~400ms | **400ms, bar only; idempotent `start()` through the hold** |
| R10 | Pending label weight | pen inconsistent (gold/modal pending = 600, secondary = 500) | — | **Weight unchanged on pending** — the 600s reflect the controls' existing `font-semibold`, not a pending signal |
| R11 | Button spinner delay | absent from pen (static frame) | ~150ms (ux #6) | **Spinner mounts at +150ms; `disabled`/`aria-busy`/opacity apply immediately** |
| R12 | Press affordance | pen: `scale-98, opacity-90, ~120ms` | same | **`scale-[0.98]` + `opacity-90`, ~120ms; transform suppressed under reduced-motion** |
| R13 | Modal scrim | pen: `#00000099` (60%) | — | **Keep existing `bg-black/50`** — scrim not in diff; pen value illustrative |
| R14 | Modal Cancel radius | pen: 6px | — | **Keep `rounded-md`**; submit adopts `Button` `rounded-lg` with the family |
| R15 | Danger variant | absent from pen | `danger` in variant union | **Red-600 family (existing idiom); same pending contract; spinner `currentColor`/white** |
| R16 | Icon-only buttons | absent from pen | content-replacement | **Spinner swaps icon in pinned-size box; never appends** |
| R17 | Stall termination | pen: "exit: route commit or abort" | ~30s timeout + breadcrumb | **30s hard stop** — "abort" is made concrete |
| R18 | Esc/Cancel during pending | pen matrix rail "stay live until pending" + modal rail "inert until resolution" | all vectors inert via `onClose={pending ? undefined : onCancel}` | **Inert during pending** (Cancel, Esc, backdrop, close control, sheet drag) |

---

## 10. Non-binding elements in the `.pen` (do not ship)

- Spec rails, callout badges, "SPEC" headings, measurement captions — instrumented-spec chrome (Variant A's quiet production styling carries none of it).
- Pen canvas sizes (1440×900, 390×844, 1240×620/720) — illustrative framing, not layout contracts.
- Demo copy ("Approve send - PR #412", "Digest ready") — placeholder content.
- The `.pen`'s literal `$accent-gold`/`#C9A962` hex — §0's per-palette tokens govern.

# Action-feedback contract — `components/ui`

feat-ui-action-feedback (#8917). Binding spec (archived): `knowledge-base/project/specs/archive/20260927-230451-feat-ui-action-feedback/implementation-brief.md`; plan: `knowledge-base/project/plans/archive/20260927-230451-2026-09-25-feat-ui-action-feedback-plan.md`; decision record: ADR-255 (`knowledge-base/engineering/architecture/decisions/ADR-255-canonical-action-feedback-contract.md`).

## `Button` (`components/ui/button.tsx`)

The single native-button replacement. All ~310 legacy `<button>` sites migrate onto it.

- **Variants:** `variant?: "gold" | "outlined" | "ghost" | "danger"` (default `"outlined"`). `gold` fills with `GOLD_GRADIENT` + `text-soleur-text-on-accent`; `outlined` is `border-soleur-border-default` on transparent; `ghost` is borderless `text-soleur-text-secondary`; `danger` is the red-600 family.
- **`loading`** forces `disabled` + `aria-busy="true"` + pending opacity (`0.55`, or `0.65` with `modal` for scrimmed surfaces) **immediately** — the double-submit window cannot wait for the spinner. The leading `SpinnerIcon` (`h-3.5 w-3.5`, `gap-2`, per-variant color) mounts only if still pending at `PENDING_ENTRY_DELAY_MS` (150ms, `lib/pending-timing.ts`) so fast mutations never strobe.
- **`loadingLabel`** is the only label swap — verb-matched copy ("Saving", "Deleting"); the primitive appends the `…` literal so ~310 call sites cannot drift the ellipsis. The swap lands with `loading` (immediately) — only the spinner is delay-gated.
- **Icon-only buttons** (no text children — the ~211 `aria-label` sites) use **content-replacement**: the spinner swaps the icon inside a pinned-size box (icon stays mounted `invisible`, spinner absolutely centered). Never appends — a trailing spinner shifts width and violates zero-layout-shift.
- **`type` is forwarded with no default.** Native `submit` semantics inside `<form>` are preserved — do not add `type="button"` defaults.
- Everything else (`aria-*`, `data-*`, `data-tour-id`, `on*`, `title`, `style`, `ref`) passes through via rest-spread; `className` merges with variant classes.
- Press affordance (`active:scale-[0.98] active:opacity-90`, ~120ms) is suppressed under `prefers-reduced-motion`.

## Pending vocabulary

`pending` is the state name; `loading` is the prop name. Wire `loading={pending}`.

## `usePendingAction` (`hooks/use-pending-action.ts`)

`usePendingAction(asyncFn) → { run, pending, error, latch }`.

- `run(...)` executes `asyncFn` inside a React transition; a second `run()` while pending is a no-op (an internal ref covers the click-to-first-render sync gap before `disabled` paints).
- `error` (`Error | null`) is for callers to render via `role="alert"` — a pending state must always terminate into success or a visible, announced error.
- `latch()` is for `window.location.*` redirect callers (billing-section's `redirectTo` is the canonical case): call it inside `asyncFn` immediately before the hard nav — terminality is explicit, never inferred from resolution. A resolve without `latch()` releases normally (a confirm-cancel or handled `!res.ok` path must NOT brick the control); a latched episode keeps pending through teardown and still reports to Sentry if the nav never lands. Failure always releases + surfaces `error` — and clears the latch, since a failed episode is definitionally non-terminal (otherwise the control would render enabled while `run()` no-ops).
- On resolve, focus is restored to the invoking control when the disabled-flip collapsed `activeElement` to `<body>`.
- A ~30s watchdog (`PENDING_WATCHDOG_MS`, `lib/pending-timing.ts`) mirrors a hung action to Sentry via `reportSilentFallback` and releases the control — a permanently disabled button is the failure mode this contract exists to remove. Latched episodes report under a distinct op (`pending-watchdog-latch-held`) but stay latched — teardown may still be in flight.
- Episodes are monotonic: a watchdog-released retry is a NEW episode; a zombie `asyncFn` settling late cannot release the retried episode's pending, clear its watchdog, or overwrite its error.
- Granularity: pending is shared per logical action-group (coupled buttons share one flag); per-control flags only where actions are independent.
- Consumers must render `error` OR handle every failure inside `asyncFn` — an `asyncFn` that throws into an `error` slot nobody renders is a silent dead click (the hook cannot detect an unread error slot; review convention is inner-`try` + local error surface per file).

## `data-button-exempt` — exemption process

Genuinely bespoke buttons (toggle/`aria-pressed` groups, cmdk items, composite inner markup) keep native `<button>` with `data-button-exempt="<non-empty reason>"` **on the tag** — the DOM attribute is the chokepoint; a doc-only list drifts on day one. Empty or non-literal reasons fail the sentinel. Exemptions measured ~17% of the corpus at sweep-landing (51 sites — mostly ARIA-role composites and composite-content rows the primitives deliberately don't absorb); the budget is restated at that level, and growth past it re-evaluates variant coverage rather than letting the list grow silently.

## Sentinel

```bash
bash scripts/check-button-primitive-sweep.sh        # from apps/web-platform
```

`git grep`-enumerates every native `<button>` under `components/` + `app/`; each must carry a non-empty `data-button-exempt` (the primitive file itself is excluded). `NATIVE_BUTTON_BASELINE` at the top of the script is a checked-in count that **may only decrease** — a new native button reds the gate until the constant is regenerated, keeping the bump review-visible. The vitest wrapper `test/components/button-primitive-sweep.test.ts` runs it in CI.

## Nav-pending channels

The route-pending bar (gold sliver, `refresh-shimmer` keyframes) is driven by three channels only — there is no passive document click listener:

| Channel | Mechanism | Notes |
|---|---|---|
| `NavLink` (`components/ui/nav-link.tsx`) | `next/link` wrapper; `onNavigate` → `start()` unless same-doc target; a consumer `onNavigate` that calls `preventDefault()` vetoes the bar too (a vetoed nav never commits) | `import Link from "next/link"` is a greppable violation |
| `usePendingRouter` (`hooks/use-pending-router.ts`) | wraps `useRouter()`; identical-URL `push`/`replace` skips `start()` but still delegates; `refresh`/`back`/`forward`/`prefetch` pass through | ⌘K and g-keys covered via `use-shortcuts` |
| `popstate` | listener inside `components/nav/nav-pending-island.tsx` | hash-only entries never fire |

Raw internal `<a href="/…">` anchors convert to `NavLink` (no listener); non-navigating anchors (`/api/` downloads, `mailto:`, external, `#fragment`), `window.location.assign` hard navs (sign-out, org-switch — ADR-067 boundary), and intentional hard-reload anchors marked `data-nav-exempt="<reason>"` stay native.

## Shared timing constants (`lib/pending-timing.ts`)

| Constant | Value | Consumers |
|---|---|---|
| `PENDING_ENTRY_DELAY_MS` | 150ms | nav bar + `Button` spinner |
| `NAV_MIN_VISIBLE_MS` | 400ms | nav bar only — no button min-visible |
| `PENDING_ESCALATION_MS` | 8s | "Still working…" escalation (billing-section, sign-out-confirm-modal) |
| `PENDING_WATCHDOG_MS` | 30s | `usePendingAction` watchdog + every `AbortSignal.timeout` flight bound (use-action-send, setup-key, today-card, pending-invites, upgrade-modal) + sign-out teardown bound |
| `NAV_STALL_MS` | 30s | nav-pending stall force-stop (aliases `PENDING_WATCHDOG_MS`) |

## Deliberate non-adoptions

Sites that still hand-roll pending *state* but are NOT required to adopt `usePendingAction` — each already disables its control during the flight, so the residual delta is watchdog/focus-restore coverage on lower-tier surfaces, tracked as follow-up #9053 (not a contract violation): `rename-workspace-action`, `dsar-export-dialog`, `delegation-acceptance-modal`, `connected-services-content`, `key-rotation-form`, `delegation-toggle`, `bash-autonomous-toggle`, `debug-mode-toggle`, `chat/visibility-toggle`, `create-project-state`, `scope-grant-row`, `template-authorization-row`, `today-card` (transition flags, abort-bounded fetches). New mutation sites SHOULD adopt the hook; these are grandfathered, not blessed — convert opportunistically when touching them.

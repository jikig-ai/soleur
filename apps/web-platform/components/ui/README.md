# Action-feedback contract — `components/ui`

feat-ui-action-feedback (#8917). Binding spec: `knowledge-base/project/specs/feat-ui-action-feedback/implementation-brief.md`; plan: `knowledge-base/project/plans/2026-09-25-feat-ui-action-feedback-plan.md`. A follow-up ADR ("Canonical action-feedback contract", provisional ordinal) lands with the PR — see the plan's Architecture Decision section.

## `Button` (`components/ui/button.tsx`)

The single native-button replacement. All ~310 legacy `<button>` sites migrate onto it.

- **Variants:** `variant?: "gold" | "outlined" | "ghost" | "danger"` (default `"outlined"`). `gold` fills with `GOLD_GRADIENT` + `text-soleur-text-on-accent`; `outlined` is `border-soleur-border-default` on transparent; `ghost` is borderless `text-soleur-text-secondary`; `danger` is the red-600 family.
- **`loading`** forces `disabled` + `aria-busy="true"` + pending opacity (`0.55`, or `0.65` with `modal` for scrimmed surfaces) **immediately** — the double-submit window cannot wait for the spinner. The leading `SpinnerIcon` (`h-3.5 w-3.5`, `gap-2`, per-variant color) mounts only if still pending at `PENDING_ENTRY_DELAY_MS` (150ms, `lib/pending-timing.ts`) so fast mutations never strobe.
- **`loadingLabel`** is the only label swap — verb-matched copy ("Saving", "Deleting"); the primitive appends the `…` literal so ~310 call sites cannot drift the ellipsis. The label swap lands with the spinner, not before it.
- **Icon-only buttons** (no text children — the ~211 `aria-label` sites) use **content-replacement**: the spinner swaps the icon inside a pinned-size box (icon stays mounted `invisible`, spinner absolutely centered). Never appends — a trailing spinner shifts width and violates zero-layout-shift.
- **`type` is forwarded with no default.** Native `submit` semantics inside `<form>` are preserved — do not add `type="button"` defaults.
- Everything else (`aria-*`, `data-*`, `data-tour-id`, `on*`, `title`, `style`, `ref`) passes through via rest-spread; `className` merges with variant classes.
- Press affordance (`active:scale-[0.98] active:opacity-90`, ~120ms) is suppressed under `prefers-reduced-motion`.

## Pending vocabulary

`pending` is the state name; `loading` is the prop name. Wire `loading={pending}`.

## `usePendingAction` (`hooks/use-pending-action.ts`)

`usePendingAction(asyncFn, opts?) → { run, pending, error, pendingRef }`.

- `run(...)` executes `asyncFn` inside a React transition; a second `run()` while pending is a no-op (`pendingRef` covers the click-to-first-render sync gap before `disabled` paints).
- `error` (`Error | null`) is for callers to render via `role="alert"` — a pending state must always terminate into success or a visible, announced error.
- `opts.latchOnRedirect` is for `window.location.*` redirect callers (billing-section's `redirectTo` is the canonical case): once the action resolves, pending never resets — the hard nav owns teardown. Failure still releases + surfaces `error`.
- On resolve, focus is restored to the invoking control when the disabled-flip collapsed `activeElement` to `<body>`.
- A ~30s watchdog (`PENDING_WATCHDOG_MS`) mirrors a hung action to Sentry via `reportSilentFallback` and releases the control — a permanently disabled button is the failure mode this contract exists to remove.
- Granularity: pending is shared per logical action-group (coupled buttons share one flag); per-control flags only where actions are independent.

## `data-button-exempt` — exemption process

Genuinely bespoke buttons (toggle/`aria-pressed` groups, cmdk items, composite inner markup) keep native `<button>` with `data-button-exempt="<non-empty reason>"` **on the tag** — the DOM attribute is the chokepoint; a doc-only list drifts on day one. Empty or non-literal reasons fail the sentinel. Exemptions are bounded by a **~15% budget** of the corpus; past that, variant coverage is re-evaluated rather than the list growing.

## Sentinel

```bash
bash scripts/check-button-primitive-sweep.sh        # from apps/web-platform
```

`git grep`-enumerates every native `<button>` under `components/` + `app/`; each must carry a non-empty `data-button-exempt` (the primitive file itself is excluded). `NATIVE_BUTTON_BASELINE` at the top of the script is a checked-in count that **may only decrease** — a new native button reds the gate until the constant is regenerated, keeping the bump review-visible. The vitest wrapper `test/components/button-primitive-sweep.test.ts` runs it in CI.

## Nav-pending channels

The route-pending bar (gold sliver, `refresh-shimmer` keyframes) is driven by three channels only — there is no passive document click listener:

| Channel | Mechanism | Notes |
|---|---|---|
| `NavLink` (`components/ui/nav-link.tsx`) | `next/link` wrapper; `onNavigate` → `start()` unless same-doc target | `import Link from "next/link"` is a greppable violation |
| `usePendingRouter` (`hooks/use-pending-router.ts`) | wraps `useRouter()`; identical-URL `push`/`replace` skips `start()` but still delegates; `refresh`/`back`/`forward`/`prefetch` pass through | ⌘K and g-keys covered via `use-shortcuts` |
| `popstate` | listener inside `components/nav/nav-pending-island.tsx` | hash-only entries never fire |

Raw internal `<a href="/…">` anchors convert to `NavLink` (no listener); non-navigating anchors (`/api/` downloads, `mailto:`, external, `#fragment`) and `window.location.assign` hard navs (sign-out, org-switch — ADR-067 boundary) stay native and untouched.

## Shared timing constants (`lib/pending-timing.ts`)

| Constant | Value | Consumers |
|---|---|---|
| `PENDING_ENTRY_DELAY_MS` | 150ms | nav bar + `Button` spinner |
| `NAV_MIN_VISIBLE_MS` | 400ms | nav bar only — no button min-visible |

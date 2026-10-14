---
title: "chore: adopt usePendingAction on ~13 grandfathered hand-rolled pending sites (#9053)"
date: 2026-09-28
slug: chore-9053-usependingaction-adoption
branch: chore-one-shot-9053-pending-sites
issue: 9053
closes: 9053
type: chore
class: code
design-risk: no
priority: p3-low
domain: engineering
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
pr: 9155
---

# chore: adopt usePendingAction on ~13 grandfathered hand-rolled pending sites (#9053)

## Overview

PR #8904 (`feat-ui-action-feedback`, ADR-255) adopted the canonical
`usePendingAction` contract — `{ run, pending, error, latch }` — on tier-1
mutation surfaces and grandfathered ~13 residual sites that still hand-roll
`useState`-pending or raw `useTransition`. Each disables its control during the
flight, so none are contract violations; the residual delta is the hook's
termination guarantee (30s `PENDING_WATCHDOG_MS` watchdog + Sentry mirror via
`reportSilentFallback`), click-to-render `pendingRef` gate, and focus restore.
This plan converts all 13 files (15 hand-rolled episodes) to
`usePendingAction`, and drains the `## Deliberate non-adoptions` list in
`components/ui/README.md`.

**Verdict up front: all 13 sites convert; zero exemptions.** The exemption
class the issue anticipates — "per-row sets" a single `pending` flag cannot
express — does not apply: `scope-grant-row`, `template-authorization-row`, and
`connected-services-content`'s `ProviderCard` each own their pending state per
component *instance* (per-row granularity is preserved because each row mounts
its own hook). Per README granularity: coupled controls share one flag;
independent controls get one `usePendingAction` each.

## Contract recap (binding spec)

`apps/web-platform/hooks/use-pending-action.ts` + `components/ui/README.md`:

- `run(...)` executes `asyncFn` inside a React transition; a second `run()`
  while pending is a no-op (`pendingRef` covers the click-to-first-render gap).
- `error` (`Error | null`) must be rendered via `role="alert"` **OR** every
  failure handled inside `asyncFn` — the review convention is inner-`try` +
  local error surface per file (README §`usePendingAction`). All 13 sites
  already carry local error surfaces (`role="alert"` paragraphs or
  `window.alert`); we keep those and never let `asyncFn` throw into an unread
  error slot.
- `latch()` marks a success-terminates-in-teardown episode. Exactly one site
  needs it: `create-project-state`.
- Watchdog: a hung episode releases at `PENDING_WATCHDOG_MS` (30s) + Sentry
  (`op: "pending-watchdog"`; `"pending-watchdog-latch-held"` for latched).
  The hook does NOT abort the in-flight fetch — existing
  `AbortSignal.timeout(PENDING_WATCHDOG_MS)` flight bounds (today-card) stay.
- Converted-site reference patterns: `settings/disconnect-repo-dialog.tsx`
  (single action, inner-try, soft-nav → no latch), `settings/billing-section.tsx`
  and `dashboard/pending-invite-banner.tsx` (hard-nav/unmount-terminal →
  `latch()`), `settings/delegation-funded-pane.tsx` (per-row revoke with
  inner-try + `window.alert`).

## Per-site disposition

| # | Site (file under `apps/web-platform/`) | Hand-rolled mechanism | Disposition | Conversion notes |
|---|---|---|---|---|
| 1 | `components/settings/rename-workspace-action.tsx` | `submitting` state on `save` | **Convert** | Wrap the fetch body of `save` in `usePendingAction`. Keep the pre-flight `validateWorkspaceName` early-return *inside* `asyncFn` (an invalid draft resolves immediately — never starts a fetch, releases normally). Keep local `error` string + `role="alert"`; inner try/catch preserved so `asyncFn` never throws. `disabled={pending}` `loading={pending}` on Save. |
| 2 | `components/settings/dsar-export-dialog.tsx` | `busy` state on `handleConfirm` | **Convert** | `usePendingAction(async () => { await onConfirmPassword(password); onClose(); setPassword(""); })`. Keep the local `error` state via inner catch (`setError((err as Error).message)`) rather than the hook's `error` slot: Cancel must be able to clear the visible error on close (`setError(null)` in the cancel handler), which the hook's internal slot can't do. Do NOT render `error` from the hook. Cancel keeps `disabled={pending}`. |
| 3 | `components/settings/delegation-acceptance-modal.tsx` | one `loading` shared by accept/decline/withdraw (3 near-identical setLoading blocks) | **Convert** — collapses the triplication | One parameterized `usePendingAction(async (op: "accept" \| "decline" \| "withdraw") => …)`; `run("accept")` etc. Preserves the shared flag (a pending accept still disables Decline). **New surface:** today a failed write is `reportSilentFallback`-only — a silent dead click. Add a local `actionError` state rendered `role="alert"` inside the modal; keep the per-op `reportSilentFallback` calls (the `op:` tags are queryable Sentry dimensions). |
| 4 | `components/settings/connected-services-content.tsx` | `ProviderCard`: `loading` (connect) + `removing` (remove) — two flags | **Convert** — two hooks per card | Independent controls → two `usePendingAction` instances (`connect`, `remove`) per `ProviderCard`. Connect keeps the local `error` surface; wrap `await onConnect(...)` in inner-try (today a thrown `onConnect` strands `loading=true` forever — the hook's release fixes this even before the catch). Remove: parent `handleRemove` silently swallows non-OK; add a small `removeError` rendered near the Remove button (new error surface, same rationale as #3). |
| 5 | `components/settings/key-rotation-form.tsx` | `isSubmitting` on `handleSubmit` | **Convert** | `<form onSubmit={e => { e.preventDefault(); run(); }}>` — keep `preventDefault` in the wrapper (form submit semantics; `Button type="submit"` unchanged). Keep `error`/`success` local states; all `setIsSubmitting(false)` calls drop (hook releases on resolve). `router.refresh()` stays inside `asyncFn` on the success path. |
| 6 | `components/settings/delegation-toggle.tsx` (`OwnerDelegationControl`) | one `loading` shared by `handleToggle` (grant/revoke) + `handleSaveCap` (PATCH) | **Convert** — one parameterized hook | `usePendingAction(async (op: "toggle" \| "saveCap") => …)`; `run("toggle")` on the exempt `role="switch"` button, `run("saveCap")` on Save. Shared flag matches today (toggle + cap-edit are the same action-group). Preserve `window.alert` error surfaces + `console.error` tags verbatim (the AC5 "never silently swallow" regression tests pin them). Native switch keeps `data-button-exempt`, gains `pending` for `disabled`/`aria-busy`/opacity. |
| 7 | `components/settings/bash-autonomous-toggle.tsx` | `loading` on `persist(value)` | **Convert** | `persist` becomes the `usePendingAction` `asyncFn` (param `value: boolean`); `run(false)` on toggle-off, `run(true)` from the risk-interstitial confirm. `handleToggleClick`'s `if (loading) return` → hook's `run` self-gate covers it (keep the `pending` check for readability). Preserve both `window.alert` surfaces (403 + network) and the interstitial flow exactly — the consent gate is load-bearing. |
| 8 | `components/settings/debug-mode-toggle.tsx` | `loading` on `persist(value)` | **Convert** | Identical shape to #7 minus interstitial. `handleToggleClick` keeps the `!isOwner` guard + `pending` guard. |
| 9 | `components/chat/visibility-toggle.tsx` | `loading` on `toggle()` | **Convert** | `usePendingAction(async () => { … supabase.rpc … })`. Handle `rpcErr` *inside* `asyncFn` (`setError("Failed to update visibility"); return;`) — do NOT throw into the hook's `error` slot (raw PostgREST text would replace the curated message, and the slot is otherwise unread). `run()` replaces the `loading` guard; `isOwner` early-return stays (component returns `null` for non-owners anyway). |
| 10 | `components/connect-repo/create-project-state.tsx` | `submitting` never resets on success — relies on unmount | **Convert — the canonical `latch()` site** | Parent `handleCreateSubmit` is `async` but invoked fire-and-forget; every path ends in `setState(...)` unmounting this component (`app/(auth)/connect-repo/page.tsx` `CreateProjectState` mount at `state === "create_project"`). asyncFn: `try { onSubmit(slug, isPrivate); } catch { setError("Something went wrong. Please try again."); return; } latch();` — success latches pending through teardown; a thrown `onSubmit` resolves unlatched → releases with the local error; a latch whose unmount never arrives still Sentry-reports at 30s (`pending-watchdog-latch-held`). Do NOT `await onSubmit` (its promise settling is the unmount trigger; awaiting is unnecessary and the prop type stays `(name, isPrivate) => void`). |
| 11 | `components/scope-grants/scope-grant-row.tsx` | raw `useTransition` shared by `onGrant`/`onRevoke` | **Convert** — one parameterized hook | `usePendingAction(async (op: "grant" \| "revoke") => …)`; `isPending` → `pending` in `canSubmit`, `fieldset disabled`, both Buttons. Pessimistic-revert logic + local `error` move inside `asyncFn` unchanged; `router.refresh()` stays on success paths. Per-row granularity is preserved — each row instance owns its hook. |
| 12 | `components/scope-grants/template-authorization-row.tsx` | raw `useTransition` on `onRevoke` | **Convert** | `usePendingAction` for the single revoke; keep local `error` + `role="alert"`; `router.refresh()` inside `asyncFn`. |
| 13 | `components/dashboard/today-card.tsx` | two raw `useTransition` sites (issue: "convert-if-touched" — file is touched by this sweep, conversion is clean) | **Convert** both residual sites | `KbDriftCard.startDismiss` → `usePendingAction`; `StripeCard`'s `startTransition` (edit + discard share `isPendingLocal`) → one parameterized `usePendingAction("edit" \| "discard")`, `pending` merges into the existing `isPending = pending \|\| isPendingSend`. **Keep** `AbortSignal.timeout(PENDING_WATCHDOG_MS)` on every fetch — the hook releases the flag but does not abort the zombie fetch; the signal bound is what kills it. Optimistic `setArchived(true)` + revert-on-failure stays inside `asyncFn`. `useActionSend` paths (`onSend`, `confirmPending`) untouched — already canonical. |

## Exemptions considered and rejected

- **"Per-row granularity the hook can't express"** — rejected for #4/#11/#12:
  pending state lives inside the row component, so each row already has its own
  episode scope; `usePendingAction` per instance preserves it exactly.
- **`role="switch"` native buttons (#6/#7/#8)** — the *element* stays native
  (`data-button-exempt` unchanged — that's the Button-primitive axis, unrelated
  to pending state). The hook is element-agnostic (`pending` drives
  `disabled`/`aria-busy`/opacity directly).
- **`today-card` (#13)** — the issue's "convert-if-touched" hedge assumed the
  abort bound made conversion redundant. But the abort bound covers the *fetch*;
  it doesn't mirror the hang to Sentry (the catch swallows the `TimeoutError`
  into a generic "network error" — mislabeled), doesn't gate the click-to-render
  window, and doesn't restore focus. Conversion is mechanical; convert.

## Files to edit

Components (13):

- `apps/web-platform/components/settings/rename-workspace-action.tsx`
- `apps/web-platform/components/settings/dsar-export-dialog.tsx`
- `apps/web-platform/components/settings/delegation-acceptance-modal.tsx`
- `apps/web-platform/components/settings/connected-services-content.tsx`
- `apps/web-platform/components/settings/key-rotation-form.tsx`
- `apps/web-platform/components/settings/delegation-toggle.tsx`
- `apps/web-platform/components/settings/bash-autonomous-toggle.tsx`
- `apps/web-platform/components/settings/debug-mode-toggle.tsx`
- `apps/web-platform/components/chat/visibility-toggle.tsx`
- `apps/web-platform/components/connect-repo/create-project-state.tsx`
- `apps/web-platform/components/scope-grants/scope-grant-row.tsx`
- `apps/web-platform/components/scope-grants/template-authorization-row.tsx`
- `apps/web-platform/components/dashboard/today-card.tsx`

Docs (1):

- `apps/web-platform/components/ui/README.md` — drain `## Deliberate
  non-adoptions`: remove the 13-name grandfathered list, keep the normative
  "new mutation sites SHOULD adopt the hook" line, and record that #9053
  converted the full list (one-line history note with the issue id; the section
  heading can stay as the canonical answer to "may I hand-roll pending?").

Tests — existing files that may need assertion updates, plus new coverage:

- `apps/web-platform/test/rename-workspace-action.test.tsx` — behavior-keyed
  (fetch + `role="alert"`); expected green unmodified.
- `apps/web-platform/test/dsar-export-dialog.test.tsx` — error-render test
  asserts `findByRole("alert")` text; keep local error → green unmodified.
- `apps/web-platform/test/delegation-acceptance-modal.test.tsx` — green
  unmodified; **add** a non-OK-accept test asserting the new `role="alert"`
  error surface (previously silent).
- `apps/web-platform/test/delegation-toggle.test.tsx` — pins the `window.alert`
  paths; green unmodified if alert copy preserved.
- `apps/web-platform/test/components/settings/bash-autonomous-toggle.test.tsx` —
  pins interstitial + alert paths; green unmodified.
- `apps/web-platform/test/scope-grant-row.test.tsx` — pins
  `router.refresh` counts + pessimistic revert; green unmodified.
- `apps/web-platform/test/components/today-card*.test.tsx` (4 files) — pin
  dismiss/edit/discard fetch URLs + archive-revert; green unmodified.
- **New** `apps/web-platform/test/create-project-state.test.tsx` (no test
  exists): submit → `onSubmit` called with `(slug, isPrivate)`; after
  `onSubmit` resolves, Create Project stays `disabled`/`loading` (latch holds
  pending through teardown — the converted contract). Synthesized fixture only.
- **New** error-surface test for `connected-services-content` remove-failure
  (new `role="alert"`; previously silent) — small RTL test, synthesized
  `initialServices` fixture.

## Test scenarios

Per `cq-write-failing-tests-before`, land the two new tests first where they
assert *new* behavior (delegation-acceptance error surface, connected-services
remove error, create-project latch-hold), then convert:

1. **Rename** — save success updates display name; 500 + network-throw keep
   prior name + `role="alert"`; invalid draft never fetches. (existing)
2. **DSAR** — Continue pending-disables both buttons; `onConfirmPassword`
   reject → inline alert, dialog stays open; Cancel clears + closes. (existing)
3. **Delegation acceptance** — shared pending: while Accept is in flight,
   Decline is disabled (one flag); non-OK accept → NEW `role="alert"` +
   `reportSilentFallback` op `accept`; withdraw path same. (new + existing)
4. **Connected services** — connect pending disables Save only; remove pending
   disables Remove only (independent flags); `onConnect` throw → control
   releases + error shows (previously stranded); failed remove → NEW visible
   error. (new + manual)
5. **Key rotation** — submit pending; `!res.ok`, `!data.valid`, and throw all
   release + surface; success sets `success` + `router.refresh`. (manual)
6. **Delegation toggle** — alert-copy regression tests stay green; pending
   blocks switch AND cap-Save while either flies (shared flag). (existing)
7. **Bash autonomous** — OFF writes immediately; ON requires interstitial;
   confirm → POST `{value:true}`; 403 alert + stays off. (existing)
8. **Debug mode** — owner flip POSTs; non-owner switch disabled; alert on
   non-OK/throw. (existing behavior, manual)
9. **Visibility toggle** — rpc success flips label + `onToggle`; rpcErr →
   generic inline error (not raw PostgREST). (manual)
10. **Create project** — submit latches: button stays loading/disabled after
    `onSubmit` returns (terminal-by-unmount); thrown `onSubmit` releases +
    `role="alert"`. (new)
11. **Scope grant row** — grant/revoke pending disables fieldset + both
    buttons; non-OK → pessimistic revert + alert + no `router.refresh`.
    (existing)
12. **Template auth row** — revoke pending; failure → `role="alert"`, no
    refresh. (existing, via today-card-adjacent coverage)
13. **Today card** — digest Dismiss + Stripe Edit/Discard pending; abort-bound
    fetch still carries `signal`; failure reverts `archived` + inline error.
    (existing)

## Verification

- `cd apps/web-platform && pnpm vitest run` on the touched test files +
  `test/hooks/use-pending-action.test.tsx` (hook regression).
- `pnpm typecheck` (hook generics: `usePendingAction<[string, boolean]>`-style
  arg tuples infer from `asyncFn` signatures — no explicit annotation needed;
  `run` arity must match call sites).
- `pnpm lint` on touched files.
- `bash scripts/check-button-primitive-sweep.sh` — no native `<button>` added;
  exempt switches unchanged (baseline must not move).
- Grep sweep: zero remaining `useState`-pending on the 13 files
  (`setSubmitting|setBusy|setLoading|isPending, startTransition` patterns
  gone) and `usePendingAction` imported in each.

## Acceptance criteria checklist

- [ ] AC1: All 13 listed files use `usePendingAction` for every mutation
      pending episode (15 episodes: dsar 1, delegation-acceptance 3→1 shared,
      connected-services 2, delegation-toggle 2→1 shared, today-card 2
      transitions, 8 singles).
- [ ] AC2: Every `asyncFn` failure path terminates into a rendered surface —
      local `role="alert"`/`window.alert` preserved or added; no unread hook
      `error` slot (README contract).
- [ ] AC3: `create-project-state` uses `latch()` — success holds pending
      through unmount; the 30s latch-held watchdog is the regression net for a
      teardown that never arrives.
- [ ] AC4: `today-card` keeps `AbortSignal.timeout(PENDING_WATCHDOG_MS)` on all
      converted fetches.
- [ ] AC5: New visible-error surfaces added where today is silent:
      delegation-acceptance-modal (accept/decline/withdraw),
      connected-services-content (remove).
- [ ] AC6: `components/ui/README.md` §Deliberate non-adoptions drained — list
      removed, normative sentence + #9053 history note kept.
- [ ] AC7: `check-button-primitive-sweep.sh` baseline unchanged; all
      `data-button-exempt` tags intact.
- [ ] AC8: New tests land (failing-first where they pin new behavior); all
      existing component tests stay green.
- [ ] AC9: `typecheck` + `lint` clean on touched files.

## User-Brand Impact

- **If this lands broken, the user experiences:** a stuck or silently-failing
  settings/toggle control — the same class this PR exists to *remove*. Worst
  realistic regression is an alert-surface copy drift or an over-latched
  create-project button (watchdog still reports it at 30s).
- **Brand-survival threshold:** `none` — UI-plumbing refactor on
  already-pessimistic controls; no legal copy, pricing, or consent *text*
  changes (the delegation consent flow's behavior is preserved; only its
  pending plumbing changes). The two added error surfaces turn previously
  silent failures into visible ones — strictly additive.

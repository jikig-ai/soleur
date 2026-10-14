# Tasks — chore #9053: adopt usePendingAction on ~13 grandfathered pending sites

lane: single-domain
Plan: `knowledge-base/project/plans/2026-09-28-chore-9053-usependingaction-adoption-plan.md`
PR: #9155 · branch `chore-one-shot-9053-pending-sites`

All paths below are relative to `apps/web-platform/`. Reference conversion
patterns: `components/settings/disconnect-repo-dialog.tsx` (single action,
inner-try, no latch) and `components/dashboard/pending-invite-banner.tsx`
(`latch()` for unmount/hard-nav terminal). Contract: `components/ui/README.md`
§`usePendingAction` — consumers render `error` OR handle every failure inside
`asyncFn` (inner-try + local error surface; never let asyncFn throw into an
unread slot).

## Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

- [ ] 1.1 New `test/create-project-state.test.tsx`: render with vi.fn `onSubmit` + `onBack`; fill name, submit → `onSubmit` called with `(slug, isPrivate)`; after it resolves, Create Project remains `disabled`/`loading` (latch holds pending through teardown). Synthesized props only.
- [ ] 1.2 Extend `test/delegation-acceptance-modal.test.tsx`: fetch mock returns non-OK on accept → `role="alert"` visible inside the modal (currently silent — RED before conversion).
- [ ] 1.3 New `test/connected-services-content.test.tsx` (or colocated provider-card test): fetch DELETE returns non-OK → Remove releases AND a `role="alert"` error renders (currently silent — RED before conversion). Also: `onConnect` reject → control releases + error surface.

## Phase 2 — Settings single-action sites

- [ ] 2.1 `components/settings/rename-workspace-action.tsx`: `submitting` → `usePendingAction`; validation early-return stays inside `asyncFn`; keep local `error` + inner try/catch; `disabled={pending}`/`loading={pending}` on Save.
- [ ] 2.2 `components/settings/dsar-export-dialog.tsx`: `busy` → `usePendingAction` around `await onConfirmPassword(password); onClose(); setPassword("")`; keep local `error` (Cancel must clear it — do NOT use the hook's error slot); Cancel `disabled={pending}`.
- [ ] 2.3 `components/settings/key-rotation-form.tsx`: `isSubmitting` → hook; `<form onSubmit={e => { e.preventDefault(); run(); }}>`; keep `error`/`success` local; `router.refresh()` inside `asyncFn` success path.
- [ ] 2.4 `components/chat/visibility-toggle.tsx`: `loading` → hook; handle `rpcErr` inside `asyncFn` (`setError("Failed to update visibility"); return;` — never throw raw PostgREST text into the slot); `run()` replaces the `loading` guard; `!isOwner` return unchanged.

## Phase 3 — Shared-flag settings sites (parameterized hooks)

- [ ] 3.1 `components/settings/delegation-acceptance-modal.tsx`: one `usePendingAction(async (op: "accept" | "decline" | "withdraw") => …)`; collapse the 3 setLoading blocks; keep per-op `reportSilentFallback` (`feature: "byok-delegation"`, `op:` tags); add `actionError` state + `role="alert"` render inside the modal; clear it on each `run`.
- [ ] 3.2 `components/settings/delegation-toggle.tsx` (`OwnerDelegationControl`): one `usePendingAction(async (op: "toggle" | "saveCap") => …)`; preserve `window.alert` + `console.error` copy verbatim (regression-pinned by `test/delegation-toggle.test.tsx`); switch keeps `data-button-exempt`, uses `pending` for `disabled`/`aria-busy`/opacity; Save/Edit-cap/Cancel gates use `pending`.
- [ ] 3.3 `components/settings/bash-autonomous-toggle.tsx`: `persist(value)` → hook `asyncFn`; interstitial confirm calls `run(true)`; keep both `window.alert` branches + the consent gate flow.
- [ ] 3.4 `components/settings/debug-mode-toggle.tsx`: same shape as 3.3 minus interstitial.

## Phase 4 — Per-card / per-row sites

- [ ] 4.1 `components/settings/connected-services-content.tsx` (`ProviderCard`): two `usePendingAction` instances (connect + remove — independent controls, independent flags); connect keeps local `error`; wrap `await onConnect` in inner-try (thrown parent callback strands `loading` today); add `removeError` rendered `role="alert"` near the Remove button (parent `handleRemove` swallows non-OK — surface it).
- [ ] 4.2 `components/connect-repo/create-project-state.tsx`: `submitting` → hook with `latch()` — `try { onSubmit(slug, isPrivate); } catch { setError("Something went wrong. Please try again."); return; } latch();`. Do NOT `await onSubmit` (parent `handleCreateSubmit` is fire-and-forget; every path unmounts via `setState`). Keep local `error` + `role="alert"`. Prop type stays `(name, isPrivate) => void`.
- [ ] 4.3 `components/scope-grants/scope-grant-row.tsx`: `useTransition` → one `usePendingAction("grant" | "revoke")`; `isPending` → `pending` in `canSubmit`/fieldset/Buttons; pessimistic revert + `router.refresh()` inside `asyncFn`.
- [ ] 4.4 `components/scope-grants/template-authorization-row.tsx`: `useTransition` → `usePendingAction` for revoke; local `error` + `role="alert"`; `router.refresh()` inside `asyncFn`.

## Phase 5 — today-card (convert-if-touched → convert)

- [ ] 5.1 `components/dashboard/today-card.tsx` `KbDriftCard`: `startDismiss` → `usePendingAction`; keep `setArchived(true)` optimistic set + revert inside `asyncFn`; KEEP `signal: AbortSignal.timeout(PENDING_WATCHDOG_MS)` on the fetch (hook releases the flag; the signal kills the zombie fetch).
- [ ] 5.2 `StripeCard`: `startTransition` (`isPendingLocal`) → one parameterized `usePendingAction("edit" | "discard")`; merge as `isPending = pending || isPendingSend`; keep abort bounds on edit/discard fetches; `useActionSend` untouched.

## Phase 6 — README drain

- [ ] 6.1 `components/ui/README.md` §Deliberate non-adoptions: remove the 13-name list; keep "New mutation sites SHOULD adopt the hook"; add one-line history note citing #9053 (list drained — all sites converted). Do not touch the sentinel/`data-button-exempt` sections.

## Phase 7 — Verify

- [ ] 7.1 `cd apps/web-platform && pnpm vitest run test/rename-workspace-action.test.tsx test/dsar-export-dialog.test.tsx test/delegation-acceptance-modal.test.tsx test/delegation-toggle.test.tsx test/components/settings/bash-autonomous-toggle.test.tsx test/scope-grant-row.test.tsx test/components/today-card.test.tsx test/components/today-card.click.test.tsx test/components/today-card-kbdrift-digest.test.tsx test/create-project-state.test.tsx test/hooks/use-pending-action.test.tsx` → green (plus the new connected-services test file).
- [ ] 7.2 `pnpm typecheck` → clean; `pnpm lint` on touched files → clean.
- [ ] 7.3 `bash scripts/check-button-primitive-sweep.sh` (from `apps/web-platform`) → baseline unchanged; no new native `<button>`; all `data-button-exempt` intact.
- [ ] 7.4 Grep sweep: `grep -n "setSubmitting\|setBusy\|setLoading\|useTransition" components/settings/rename-workspace-action.tsx components/settings/dsar-export-dialog.tsx components/settings/delegation-acceptance-modal.tsx components/settings/connected-services-content.tsx components/settings/key-rotation-form.tsx components/settings/delegation-toggle.tsx components/settings/bash-autonomous-toggle.tsx components/settings/debug-mode-toggle.tsx components/chat/visibility-toggle.tsx components/connect-repo/create-project-state.tsx components/scope-grants/scope-grant-row.tsx components/scope-grants/template-authorization-row.tsx components/dashboard/today-card.tsx` → zero residual pending-flag writes (local `error`/UI-state setters may remain); `usePendingAction` imported in all 13.
- [ ] 7.5 Acceptance checklist in the plan (AC1–AC9) — every box verifiably true.

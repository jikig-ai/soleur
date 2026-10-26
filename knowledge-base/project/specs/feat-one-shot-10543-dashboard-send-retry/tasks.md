# Tasks: fix dashboard send enqueue retry and replay (#10543)

Plan: `knowledge-base/project/plans/2026-10-26-fix-dashboard-send-enqueue-retry-replay-plan.md`
Branch: `feat-one-shot-10543-dashboard-send-retry` | Draft PR: #11208 | PR body: `Closes #10543`, `Ref #11211`, `Ref #11212`

Test commit MUST precede the fix commit. Targeted vitest runs only (from `apps/web-platform`); no full-gate runner, no live probes.

## Phase 1: RED tests first

- [ ] 1.1 Create `apps/web-platform/test/helpers/action-sends-row-mock.ts` (stateful `action_sends` branch for `mockFrom`: mutable row or none, settable lookup error, default no row)
- [ ] 1.2 Install the helper in `test/api/dashboard/today/send-route.test.ts` and `send-route.spawn.test.ts` (no assertion changes in the former)
- [ ] 1.3 Create `test/server/action-sends/enqueue-agent-spawn.test.ts` (id shape `agent-spawn-<actionSendId>`, exact `data` keys with `toStrictEqual`, same id across 3 attempts with fake timers, non-transient not retried, 3 transient failures reject)
- [ ] 1.4 Rewrite `send-route.spawn.test.ts` tests 3 and 4 (503 `enqueue_unavailable`, `Retry-After` equals 5, no archive, `reportSilentFallback(null, ...)` with `extra.replay === false` and `extra.transient === false`; transient-then-success route test with fake timers) and add the `id` assertion to tests 1b/2
- [ ] 1.5 Create `test/api/dashboard/today/send-route.replay.test.ts` (replay within 23h; replay fails again -> 503; `it.each` terminal rows, also with a revoked grant; pending + revoked grant -> 403; edited draft -> 409 `draft_changed_since_approval`; 24h-old row -> 409 `approval_expired` and a just-under-23h boundary replays; approve_every_time confirm; draft_one_click `authorize_template` at most once; `no_artifact_in_pr_a` pending row incl. older than 23h; 23505 -> plain 409; lookup error -> 500; archive failure then re-click)
- [ ] 1.6 Rewrite the stale "200 with degraded:'enqueue_failed'" case in `test/components/today-card.click.test.tsx` to the 503 contract
- [ ] 1.7 Create `test/hooks/use-action-send.test.tsx` (typed-confirm path: 503 keeps `confirming` with the same hash and sets the error; `acknowledged` false; `onAcknowledgedArchive` not called; 409 `draft_changed_since_approval` / `approval_expired` copy; 409 `requires_confirmation` keeps "please re-send")
- [ ] 1.8 Run each test file; confirm behavioral RED (module-not-found only for 1.3); commit the tests

## Phase 2: Helper

- [ ] 2.1 Create `apps/web-platform/server/action-sends/enqueue-agent-spawn.ts` (`sendInngestWithRetry` around `inngest.send` with `id: agent-spawn-${actionSendId}` and `eventId` in the context; `actionClass: ActionClass`; no `installationId`)
- [ ] 2.2 1.3 goes GREEN

## Phase 3: Route

- [ ] 3.1 Hoist `parseSourceRef`; add non-exported `lookupActionSend` (select `id, per_send_body_sha256, clicked_at, acknowledged_at, failure_reason, undone_at, cancellation_requested_at`; cookie client; `.eq("user_id")`)
- [ ] 3.2 Add the terminal arm (archive + 409 `already_sent`) and expired arm (409 `approval_expired`, `warnSilentFallback` op `inngest-replay-stale`) before the gates; lookup error -> 500
- [ ] 3.3 After the gates: replay hash check (409 `draft_changed_since_approval`, op `replay-draft-changed`), skip insert on replay; narrow the `try` to `writeActionSend` (23505 -> plain 409)
- [ ] 3.4 Route the enqueue through `enqueueAgentSpawn`; exhausted -> `reportSilentFallback(null, {feature:"spawn-agent", op:"inngest-enqueue", extra:{replay, transient, errorName, ...ids}})` and 503 with `Retry-After: 5`, no archive; successful replay -> `warnSilentFallback` op `inngest-enqueue-replay`; `no_artifact_in_pr_a` unchanged
- [ ] 3.5 Replace the duplicated stale comment blocks with one ordering-contract comment; delete `"enqueue_failed"` from the local union; drop the `@/server/inngest/client` import

## Phase 4: Hook

- [ ] 4.1 `hooks/use-action-send.ts`: 503 and the two new 409 codes in `onSend` and `onConfirmTyped`; make the confirm-path 409 catch-all explicit; narrow `degraded` unions; refresh the header comment
- [ ] 4.2 Do NOT edit `components/**` (pill cleanup is #11212)

## Phase 5: Verify and ship

- [ ] 5.1 Targeted vitest on every file above plus `test/lint/action-class-typed-literals.test.ts` and the `test/api/dashboard/today/*.test.ts` siblings; `tsc --noEmit`
- [ ] 5.2 Three-pattern `enqueue_failed` grep over `apps/web-platform/{app,components,hooks,lib,server,test,e2e}` and `knowledge-base/` docs; only the pill file and its test may remain
- [ ] 5.3 Confirm: no migration, no `infra/` diff, no `.service-role-allowlist` diff, `components/**` zero diff
- [ ] 5.4 PR body: `Closes #10543`, `Ref #11211`, `Ref #11212`, accepted residuals, the removed duplicated comment block, the Sentry query `feature:spawn-agent op:inngest-enqueue*`

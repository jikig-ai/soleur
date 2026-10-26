# Tasks: fix dashboard send enqueue retry and replay (#10543)

Plan: `knowledge-base/project/plans/2026-10-26-fix-dashboard-send-enqueue-retry-replay-plan.md`
Branch: `feat-one-shot-10543-dashboard-send-retry` | Draft PR: #11208 | PR body: `Closes #10543`, `Ref #11211`, `Ref #11212`

Test commit MUST precede the fix commit. Targeted vitest runs only (from `apps/web-platform`); no full-gate runner, no live probes.

## Phase 1: RED tests first

- [ ] 1.1 Create `apps/web-platform/test/helpers/action-sends-row-mock.ts` (in-memory store: `action_sends` select honoring `.eq()` filters and column projection; `messages` archive `update().eq().eq().eq("status","draft")` flips status in the store; injectable lookup/insert/archive errors; hoisted `warnSilentFallback`/`reportSilentFallback` mocks; default no row and one draft message)
- [ ] 1.2 Install the helper in `test/api/dashboard/today/send-route.test.ts` and `send-route.spawn.test.ts` (no assertion changes in the former)
- [ ] 1.3 Create `test/server/action-sends/enqueue-agent-spawn.test.ts` (id `agent-spawn-<actionSendId>`, exact `data` keys with `toStrictEqual`, same id across 3 attempts with fake timers, non-transient not retried, 3 transient failures reject with the `rejects` expectation attached before advancing timers)
- [ ] 1.4 Rewrite `send-route.spawn.test.ts` tests 3 and 4 (503 body `toStrictEqual`, `Retry-After` is the string "5", no archive, `reportSilentFallback(null, ...)` with `extra.replay`/`extra.transient` false and true variants; transient-then-success with fake timers) and add the `id` assertion to tests 1b/2; pin the Sentry `extra` key sets
- [ ] 1.5 Create `test/api/dashboard/today/send-route.replay.test.ts` (pending row id differs from AS_ID; replay within 23h then `not_a_draft`; replay fails again -> 503; `it.each` terminal rows also with a revoked grant, acknowledged+older-than-23h -> already_sent, archive failure still 409; `[guard]` pending + revoked grant -> 403; hash refusal incl. NULL stored hash with `isGranted`/`runTemplateGate` not called; tier/class refusal with `runTemplateGate` not called; template-gate denial -> 403; 23h gate with `vi.setSystemTime` at 22h59m/23h01m plus garbage/null/future `clicked_at`; approve_every_time confirm; unparseable and empty `source_ref` pending rows incl. >23h and revoked grant -> archive + 200; `[guard]` 23505 -> `send_in_progress`; other-user row -> no-row arm; lookup error -> 500; archive failure then re-click)
- [ ] 1.6 Rewrite the stale "200 with degraded:'enqueue_failed'" case in `test/components/today-card.click.test.tsx` to the 503 contract
- [ ] 1.7 Create `test/hooks/use-action-send.test.tsx` (both `onSend` and `onConfirmTyped`: 503, `approval_expired`, `not_a_draft`, `draft_changed_since_approval`, `send_in_progress` (never acknowledges/archives), generic 403 copy, confirm-path `requires_confirmation` adopts the fresh hash)
- [ ] 1.8 Run each file; confirm behavioral RED (module-not-found only for 1.3; `[guard]` cases pass today by design); commit the tests BEFORE the fix commit

## Phase 2: Helper

- [ ] 2.1 Create `apps/web-platform/server/action-sends/enqueue-agent-spawn.ts` (`sendInngestWithRetry` around `inngest.send` with `id: agent-spawn-${actionSendId}` and `eventId` in the context; `actionClass: ActionClass`; no `installationId`)
- [ ] 2.2 1.3 goes GREEN

## Phase 3: Route

- [ ] 3.1 Hoist `parseSourceRef` and `draftPreviewHash`; add non-exported `lookupActionSend` (select `id, per_send_body_sha256, action_class, tier_at_send, clicked_at, acknowledged_at, failure_reason, undone_at, cancellation_requested_at`; cookie client; `.eq("message_id")` and `.eq("user_id")`); lookup error -> 500
- [ ] 3.2 Ungated arms right after the lookup: terminal row -> archive + 409 `already_sent`; pending row with empty/unparseable `source_ref` -> archive + 200 (`degraded: "no_artifact_in_pr_a"` when non-empty); pending parseable row failing `now - clicked_at <= 23h` (NaN/future fail closed) -> archive + `warnSilentFallback` op `inngest-replay-stale` + 409 `approval_expired`
- [ ] 3.3 Pending parseable row with NULL/different `per_send_body_sha256` -> 409 `draft_changed_since_approval` (op `replay-draft-changed`, draft kept) BEFORE `isGranted`; after `isGranted` and the tier switch, a `row.action_class`/`tier_at_send` mismatch -> same 409 BEFORE the template gate
- [ ] 3.4 Skip the insert on replay; narrow the `try` to `writeActionSend` (23505 -> 409 `send_in_progress`, other -> 500); add `.eq("status","draft")` to the archive update
- [ ] 3.5 Route the enqueue through `enqueueAgentSpawn`; exhausted -> `reportSilentFallback(null, {feature:"spawn-agent", op:"inngest-enqueue", extra:{replay, transient, errorName, ...ids}})` and 503 with `Retry-After: 5`, no archive; successful replay -> `warnSilentFallback` op `inngest-enqueue-replay`; constant-field 409/503 bodies
- [ ] 3.6 Replace the duplicated stale comment blocks with one ordering-contract comment; delete `"enqueue_failed"` from the local union; drop the `@/server/inngest/client` import

## Phase 4: Hook

- [ ] 4.1 `hooks/use-action-send.ts`, both paths: 503, `approval_expired`/`not_a_draft` ("This approval can no longer run. Refresh to update this card."), `draft_changed_since_approval`, `send_in_progress` (no acknowledge/archive), generic 403 fallback copy; confirm-path `requires_confirmation` adopts the fresh hash; narrow `degraded` unions; refresh the header comment
- [ ] 4.2 Do NOT edit `components/**` (pill cleanup is #11212)

## Phase 5: Verify and ship

- [ ] 5.1 Targeted vitest on every file above plus `test/lint/action-class-typed-literals.test.ts` and the `test/api/dashboard/today/*.test.ts` siblings; `./node_modules/.bin/tsc --noEmit` from `apps/web-platform`
- [ ] 5.2 Three-pattern `enqueue_failed` grep over `apps/web-platform/{app,components,hooks,lib,server,test,e2e}` and `knowledge-base/` docs; only the pill file and its test may remain
- [ ] 5.3 Confirm: no migration, no `infra/` diff, no `.service-role-allowlist` diff, `components/**` zero diff
- [ ] 5.4 PR body: `Closes #10543`, `Ref #11211`, `Ref #11212`, accepted residuals, the removed duplicated comment block, the Sentry query `feature:spawn-agent op:inngest-enqueue*`

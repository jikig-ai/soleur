---
title: Tasks — wire conversations.session_id reader+writer for cc-soleur-go path
plan: knowledge-base/project/plans/2026-05-11-fix-cc-session-id-wiring-plan.md
issue: 3266
branch: feat-one-shot-3266-cc-session-id-wiring
---

# Tasks

## 1. Setup

- [x] 1.1 Verify worktree on `feat-one-shot-3266-cc-session-id-wiring` and clean.
- [x] 1.2 Read prior plan `2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md` §Phase 3 update for the Approach C carve-out shape.
- [x] 1.3 Verify migration 035 active on dev (`doppler run -p soleur -c dev --silent -- psql "$DATABASE_URL" -c "\d+ public.conversations"` and grep for `uniq_conversations_user_id_session_id_total`).

## 2. RED — failing tests first (per cq-write-failing-tests-before)

- [x] 2.1 Author `apps/web-platform/test/soleur-go-runner-session-id-rebound.test.ts`:
  - [x] 2.1.1 Scenario: first `result` with `session_id: "sess-Z"` fires `onSessionIdCaptured("sess-Z")` exactly once.
  - [x] 2.1.2 Scenario: duplicate `result` with same `session_id` does NOT re-fire.
  - [x] 2.1.3 Scenario: runner with `result` carrying NO `session_id` never fires.
- [x] 2.2 Author `apps/web-platform/test/cc-dispatcher-session-id-writer.test.ts`:
  - [x] 2.2.1 Scenario: stub runner fires `onSessionIdCaptured("sess-Y")`; assert single `updateConversationFor` call with `{ session_id: "sess-Y" }`, `expectMatch: true`, scoped `(id, user_id)`.
  - [x] 2.2.2 Scenario: DB error → `updateConversationFor` returns `{ ok: false }`; assert Sentry mirror via `reportSilentFallback` and no throw to dispatch.
  - [x] 2.2.3 Scenario: stale-resume cleanup — `runner.dispatch` throws generic `Error` with `sessionId: "sess-X"` provided; assert `updateConversationFor` called with `{ session_id: null }`, `op: "clear-stale-session-id"`.
  - [x] 2.2.4 Scenario: `KeyInvalidError` rejection does NOT trigger stale-resume cleanup (the user-facing path is a fresh-key prompt, not a stale-session clear).
- [x] 2.3 Author `apps/web-platform/test/ws-handler-cc-session-id-wiring.test.ts`:
  - [x] 2.3.1 Scenario: SELECT returns `{ active_workflow: "brainstorm", session_id: "sess-X", context_path: null }`; assert `dispatchSoleurGo` invoked with `sessionId: "sess-X"`.
  - [x] 2.3.2 Scenario: cached `session.sessionId = "sess-Y"`; no DB roundtrip; `sessionId: "sess-Y"` forwarded.
  - [x] 2.3.3 Scenario: SELECT returns `session_id: null`; `sessionId: null` forwarded.
- [x] 2.4 Run `bun test apps/web-platform/test/` and confirm all three new files RED.

## 3. GREEN — reader (`ws-handler.ts`)

- [x] 3.1 Add `sessionId?: string | null` to `ClientSession` interface (line 105-147).
- [x] 3.2 Extend the cache-check branch at line 1465 (`session.routing && session.contextPath !== undefined`) to read+seed `session.sessionId`.
- [x] 3.3 Extend `dispatchSoleurGoForConversation` signature (line 820) with `sessionId?: string | null`; pass through to `dispatchSoleurGo` at line 933 via `args` spread.
- [x] 3.4 Update both call sites of `dispatchSoleurGoForConversation`:
  - [x] 3.4.1 First-message branch at line 1409 — pass `null` (conversation just inserted).
  - [x] 3.4.2 Chat-case routed branch at line 1507 — pass `session.sessionId ?? typedRow.session_id ?? null`.
- [x] 3.5 Re-run `ws-handler-cc-session-id-wiring.test.ts`; confirm pass.

## 4. GREEN — runner event (`soleur-go-runner.ts`)

- [x] 4.1 Add `onSessionIdCaptured?: (sessionId: string) => void` to `DispatchEvents` (interface around line 625-646). Document the once-only contract in a JSDoc.
- [x] 4.2 Add `sessionIdEverEmitted: boolean` state field; default `false` on state construction (line 1680).
- [x] 4.3 Inside `handleResultMessage` (line 1521): after `state.sessionId = msg.session_id ?? state.sessionId`, check `if (state.sessionId && !state.sessionIdEverEmitted) { state.sessionIdEverEmitted = true; try { state.events.onSessionIdCaptured?.(state.sessionId); } catch (err) { reportSilentFallback(err, { feature: "soleur-go-runner", op: "onSessionIdCaptured", extra: { conversationId: state.conversationId } }); } }`.
- [x] 4.4 Re-run `soleur-go-runner-session-id-rebound.test.ts`; confirm pass.

## 5. GREEN — writer (`cc-dispatcher.ts`)

- [x] 5.1 Add module-private `persistCcSessionId(args: { userId, conversationId, sessionId })` helper above `dispatchSoleurGo` (line 817). Body per plan §Phase 4 step 2.
- [x] 5.2 Add module-private `clearCcSessionId(args: { userId, conversationId })` helper. Body per plan §Phase 3.1 step 2.
- [x] 5.3 Wire `onSessionIdCaptured: (sessionId) => void persistCcSessionId({ userId, conversationId, sessionId })` into the `events` object at line 972.
- [x] 5.4 Extend the `dispatchSoleurGo` catch block (line 1082) — when `!(err instanceof KeyInvalidError)` AND `sessionId` was provided, fire-and-forget `void clearCcSessionId({ userId, conversationId })` before the generic error WS send.
- [x] 5.5 Re-run `cc-dispatcher-session-id-writer.test.ts`; confirm all four scenarios pass.

## 6. Integration

- [x] 6.1 Run `bun test apps/web-platform/test/` — full suite green.
- [x] 6.2 Run `bun run tsc --noEmit` from `apps/web-platform/` — no new errors.
- [x] 6.3 Local smoke (dev Doppler): Concierge cold start → message → server restart → follow-up → confirm `applyPrefillGuard` enters history-probe branch (Sentry breadcrumb under `op: "prefill-guard"` or `op: "prefill-guard-probe-failed"`).

## 7. Review & QA

- [ ] 7.1 Push branch to remote (`git push -u origin feat-one-shot-3266-cc-session-id-wiring`).
- [ ] 7.2 Spawn `/soleur:review` — multi-agent review including `user-impact-reviewer` (mandatory per `single-user incident` threshold).
- [ ] 7.3 Resolve all P0/P1 findings inline per `rf-review-finding-default-fix-inline`.
- [ ] 7.4 CPO sign-off at plan-time (mandatory per `requires_cpo_signoff: true`); confirm carry-forward from #3250 brainstorm OR invoke fresh CPO Task.

## 8. Compound & Ship

- [ ] 8.1 Run `/soleur:compound` to capture learnings — likely class: "deepen-plan caught dormant-guard activation requires writer-side cleanup hook" (Phase 3.1 R7 discovery).
- [ ] 8.2 Run `/soleur:ship` — preflight Check 6 verifies User-Brand Impact section present + threshold valid.
- [ ] 8.3 PR body uses `Closes #3266` on its own line.
- [ ] 8.4 Apply labels: `priority/p2-medium`, `type/bug`, `domain/engineering`. Keep `deferred-scope-out` (label was applied at filing — clearing it is the ship-time signal that the scope-out is no longer deferred).
- [ ] 8.5 After merge, verify the `op: "prefill-guard"` Sentry breadcrumb starts firing on the cc path within 24h soak.

## Test scenarios (cross-reference)

Numbered scenarios in §Test Scenarios of the plan map to subtasks above:

| Scenario | Subtask |
|---|---|
| 1. Reader cold path | 2.3.1 |
| 2. Reader warm path | 2.3.2 |
| 3. Reader cold with NULL session_id | 2.3.3 |
| 4. Runner event first-fire | 2.1.1 |
| 5. Runner event idempotent | 2.1.2 |
| 6. Runner event no-fire | 2.1.3 |
| 7. Writer single fire | 2.2.1 |
| 8. Writer DB error mirror | 2.2.2 |
| 9. Writer cross-tenant defense | 2.2.1 (assertion sub-check) |
| 10. End-to-end resume after reap | 6.3 (manual smoke) |
| 11. Stale-resume cleanup (R7) | 2.2.3 |
| 12. KeyInvalidError does NOT clear | 2.2.4 |

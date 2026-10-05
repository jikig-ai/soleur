# Tasks — fix(concierge): mid-stream stale-resume never clears session_id

Plan: `knowledge-base/project/plans/2026-10-05-fix-concierge-stale-resume-session-id-plan.md`
Issue: #9538 | Branch: `feat-one-shot-9538-stale-resume-session-id` | Draft PR: #9541
Threshold: `single-user incident` (requires_cpo_signoff: true)

## Phase 1 — Backstop: runner discriminator + dispatcher recovery

- [ ] 1.1 `apps/web-platform/server/soleur-go-runner.ts` — add optional `onStaleResume?: (info: { deadSessionId: string | null }) => void` to `DispatchEvents` (doc comment in the `onSessionIdCaptured` style: optional + fire-and-forget).
- [ ] 1.2 `apps/web-platform/server/soleur-go-runner.ts` — add optional `contextResetNotice?: string` to `DispatchArgs` and `QueryFactoryArgs`; forward `dispatch` → `queryFactory`.
- [ ] 1.3 `apps/web-platform/server/soleur-go-runner.ts` — `consumeStream` catch: `isStaleResume` = `err instanceof Error && err.message.includes("No conversation found with session ID") && state.sessionId`. Inside `if (!state.closed)`: stale arm BEFORE the `RuntimeAuthError`/`else` arms — `state.closed = true`; try/catch `events.onStaleResume?.({ deadSessionId: state.sessionId })`; `closeQuery(state)`. Gate the trailing `reportSilentFallback(err, { op: "consumeStream" })` on `!isStaleResume`; emit `warnSilentFallback(null, { feature: "soleur-go-runner", op: "stale-resume-recovery", message: "stale resume — cleared session_id and re-dispatching cold", extra: { conversationId, deadSessionId } })`.
- [ ] 1.4 `apps/web-platform/server/cc-dispatcher.ts` — `dispatchSoleurGo` `events` block: wire `onStaleResume` — `if (!sessionId) return;`; `sendToClient(userId, { type: "context_reset", reason: "prefill-guard", conversationId })`; `onSessionIdPersisted?.(null)`; `void clearCcSessionId({ userId, conversationId })`; DEFERRED (microtask — must land after `closeQuery`'s `activeQueries.delete`) `runner.dispatch({ …same args, sessionId: undefined, contextResetNotice: CONTEXT_RESET_NOTICE_GENERIC })` with `.catch` → `mirrorWithDebounce` + generic error frame + `updateConversationFor({ status: "failed" }, { onlyIfStatusIn: ["active"], expectMatch: false })` guarded by `!hasActiveCcQuery(conversationId)`.
- [ ] 1.5 `apps/web-platform/server/cc-dispatcher.ts` — `realSdkQueryFactory`: append `args.contextResetNotice` to `effectiveSystemPrompt` at the existing notice site; import `CONTEXT_RESET_NOTICE_GENERIC`.

## Phase 2 — Front-line: prefill guard drops resume on empty history

- [ ] 2.1 `apps/web-platform/server/agent-prefill-guard.ts` — `history.length === 0` branch: keep `warnSilentFallback` (`op: "prefill-guard-empty-history"`); return `{ safeResumeSessionId: undefined, contextResetNotice: CONTEXT_RESET_NOTICE_GENERIC, reason: "prefill-guard" }`; rewrite branch comment to state the dead-file premise.

## Phase 3 — Tests (RED first)

- [ ] 3.1 New `apps/web-platform/test/soleur-go-runner-stale-resume.test.ts` — stale-resume signature + `sessionId` set → `onStaleResume` once, `events._ended` empty, no `reportSilentFallback`, query closed; signature without `sessionId` → `internal_error`; non-stale error → `internal_error` + `reportSilentFallback` (fixtures from `test/helpers/soleur-go-fixtures.ts`; mirror `soleur-go-runner-session-revoked.test.ts`).
- [ ] 3.2 New `apps/web-platform/test/cc-dispatcher-stale-resume.test.ts` — `onStaleResume` → `{ session_id: null }` write, `onSessionIdPersisted(null)`, `context_reset` frame, deferred `runner.dispatch` with `sessionId: undefined` + `contextResetNotice`, no `session_ended`; retry observes cleared `activeQueries` (fresh query); retry-throw → error frame + `failed` revert; absent `sessionId` → no-op (stub runner via the `__setSoleurGoRunner…` test seam).
- [ ] 3.3 `apps/web-platform/test/agent-prefill-guard.test.ts` — update `history.length === 0` expectations to `{ safeResumeSessionId: undefined, contextResetNotice: CONTEXT_RESET_NOTICE_GENERIC, reason: "prefill-guard" }`.
- [ ] 3.4 Audit `cc-dispatcher-prefill-guard.test.ts` + `cc-dispatcher-session-id-writer.test.ts` for assertions pinning the old `[]`-pass-through; update only what fails.

## Phase 4 — Verification

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 4.2 `./node_modules/.bin/vitest run test/soleur-go-runner-stale-resume.test.ts test/cc-dispatcher-stale-resume.test.ts test/agent-prefill-guard.test.ts` green; pre-existing `soleur-go-runner*.test.ts` / `cc-dispatcher*.test.ts` suites still pass.
- [ ] 4.3 File follow-up tracking issue: DB `messages` history-replay parity on cc cold start (extract `loadConversationHistory`/`buildReplayPrompt` from `agent-runner.ts`) — deferred scope per plan Non-Goals.

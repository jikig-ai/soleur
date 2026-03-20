# Tasks: fix review gate timeout and session leak (#840)

## Phase 1: Setup

- [ ] 1.1 Read `agent-runner.ts`, `ws-handler.ts`, `error-sanitizer.ts`, `lib/types.ts` to confirm current state matches plan
- [ ] 1.2 Run existing tests (`bun test` or `vitest`) to establish green baseline

## Phase 2: Core Implementation

- [ ] 2.1 Add `REVIEW_GATE_TIMEOUT_MS` constant to `agent-runner.ts` (5 * 60 * 1_000)
- [ ] 2.2 Create `abortableReviewGate()` helper in `agent-runner.ts`
  - [ ] 2.2.1 Check `signal.aborted` synchronously before registering listeners
  - [ ] 2.2.2 Create timeout with `setTimeout` + `.unref()` that rejects and cleans up the resolver
  - [ ] 2.2.3 Add AbortSignal `addEventListener("abort", onAbort, { once: true })` that rejects on abort
  - [ ] 2.2.4 Register resolver that clears timeout, removes abort listener, then resolves
- [ ] 2.3 Replace bare `new Promise` at line 269-271 with `abortableReviewGate(session, gateId, controller.signal)` call
- [ ] 2.4 Export `abortSession(userId, conversationId)` from `agent-runner.ts`
  - Looks up session in `activeSessions`, calls `session.abort.abort(new Error("Session aborted: user disconnected"))`
- [ ] 2.5 In `ws-handler.ts` disconnect handler, import and call `abortSession()` after removing from `sessions`
  - Add `abortSession` to import from `./agent-runner`
  - Call `abortSession(userId, current.conversationId)` when `current?.conversationId` is set
- [ ] 2.6 Remove duplicate `settingSources: []` at line 198 of `agent-runner.ts`

## Phase 3: Error Handling

- [ ] 3.1 Add `"Review gate timed out"` and `"Session aborted: user disconnected"` entries to `error-sanitizer.ts` KNOWN_SAFE_MESSAGES
- [ ] 3.2 Verify that rejected `canUseTool` promise is caught by the existing try/catch in `startAgentSession` (line 348) and transitions conversation to `failed`

## Phase 4: Testing

- [ ] 4.1 Add unit tests for `abortableReviewGate()` in a new test file (`test/review-gate.test.ts`)
  - [ ] 4.1.1 Test: resolves normally when resolver is called
  - [ ] 4.1.2 Test: rejects when AbortSignal fires (check `error.name` or message)
  - [ ] 4.1.3 Test: rejects on timeout after specified duration (use short timeout like 50ms)
  - [ ] 4.1.4 Test: cleans up timer and listener after normal resolution (no dangling handles)
  - [ ] 4.1.5 Test: handles already-aborted signal (rejects synchronously)
  - [ ] 4.1.6 Test: resolver is deleted from `reviewGateResolvers` map on abort and timeout
- [ ] 4.2 Add test for `abortSession` export
  - [ ] 4.2.1 Test: aborts existing session by userId + conversationId
  - [ ] 4.2.2 Test: no-op when session does not exist (no throw)
- [ ] 4.3 Update `error-sanitizer.test.ts` with timeout and disconnect error messages
- [ ] 4.4 Run full test suite and verify green

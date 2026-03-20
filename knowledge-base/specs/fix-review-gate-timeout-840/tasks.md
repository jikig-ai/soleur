# Tasks: fix review gate timeout and session leak (#840)

## Phase 1: Setup

- [ ] 1.1 Read `agent-runner.ts`, `ws-handler.ts`, `error-sanitizer.ts`, `lib/types.ts` to confirm current state matches plan
- [ ] 1.2 Run existing tests (`bun test` or `vitest`) to establish green baseline

## Phase 2: Core Implementation

- [ ] 2.1 Create `abortableReviewGate()` helper in `agent-runner.ts`
  - [ ] 2.1.1 Accept session, gateId, AbortSignal, and timeoutMs parameters
  - [ ] 2.1.2 Wire up timeout (5 min default) that rejects and cleans up the resolver
  - [ ] 2.1.3 Wire up AbortSignal listener that rejects on abort
  - [ ] 2.1.4 Check `signal.aborted` synchronously before registering listeners (already-aborted guard)
  - [ ] 2.1.5 Register resolver that clears timeout, removes abort listener, then resolves
- [ ] 2.2 Replace bare `new Promise` at line 269-271 with `abortableReviewGate()` call
  - Pass `controller.signal` and `REVIEW_GATE_TIMEOUT_MS` constant
- [ ] 2.3 Export `abortSession(userId, conversationId)` from `agent-runner.ts`
  - Looks up session in `activeSessions`, calls `session.abort.abort(new Error("Session aborted: user disconnected"))`
- [ ] 2.4 In `ws-handler.ts` disconnect handler, call `abortSession()` after removing from `sessions`
  - Import `abortSession` from `./agent-runner`
  - Only call if `current?.conversationId` is set
- [ ] 2.5 Remove duplicate `settingSources: []` at line 198 of `agent-runner.ts`

## Phase 3: Error Handling

- [ ] 3.1 Add `"Review gate timed out"` and `"Session aborted"` entries to `error-sanitizer.ts` KNOWN_SAFE_MESSAGES
- [ ] 3.2 Verify that rejected `canUseTool` promise is caught by the existing try/catch in `startAgentSession` (line 348) and transitions conversation to `failed`

## Phase 4: Testing

- [ ] 4.1 Add unit tests for `abortableReviewGate()` in a new or existing test file
  - [ ] 4.1.1 Test: resolves normally when resolver is called
  - [ ] 4.1.2 Test: rejects when AbortSignal fires
  - [ ] 4.1.3 Test: rejects on timeout
  - [ ] 4.1.4 Test: cleans up listener after normal resolution
  - [ ] 4.1.5 Test: handles already-aborted signal
- [ ] 4.2 Add `abortSession` to `ws-protocol.test.ts` or a new integration test
- [ ] 4.3 Update `error-sanitizer.test.ts` with timeout and disconnect messages
- [ ] 4.4 Run full test suite and verify green

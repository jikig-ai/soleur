# Tasks: fix session resume error swallowed by agent-runner

## Phase 1: Setup

- [x] 1.1 Identify root cause via Sentry
- [x] 1.2 Trace error propagation path in agent-runner.ts
- [x] 1.3 Confirm fallback mechanism is dead code

## Phase 2: Core Implementation

- [ ] 2.1 Fix startAgentSession catch block to re-throw resume failures
  - File: `apps/web-platform/server/agent-runner.ts` (lines 1122-1156)
  - When `resumeSessionId` is set AND error indicates stale session, re-throw instead of handling internally
  - This allows the `.catch()` fallback at line 1369 to fire
- [ ] 2.2 Add SDK resume error pattern to error-sanitizer.ts
  - File: `apps/web-platform/server/error-sanitizer.ts`
  - Add pattern match for "No conversation found with session ID" after KNOWN_SAFE_MESSAGES check
  - Map to "Session resume failed. Falling back to conversation history."
- [ ] 2.3 Verify fallback path works end-to-end
  - The fallback clears stale `session_id`, loads history, builds replay prompt, starts fresh session
  - Ensure `sendToClient` is NOT called in `startAgentSession` when re-throwing (avoid duplicate error)

## Phase 3: Testing

- [ ] 3.1 Write test: stale session_id triggers fallback (not error)
  - Mock `query()` to throw "No conversation found with session ID" when resume is set
  - Verify `startAgentSession` re-throws
  - Verify `sendUserMessage` catches and falls back to replay
- [ ] 3.2 Write test: error-sanitizer handles SDK resume error
  - Verify pattern match returns friendly message
- [ ] 3.3 Write test: plain text message with stale session works
- [ ] 3.4 Write test: attachment message with stale session works
- [ ] 3.5 Verify no regression: new conversations work normally
- [ ] 3.6 Verify no regression: valid resume still works

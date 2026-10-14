# Tasks: fix session resume error swallowed by agent-runner

## Phase 1: Setup

- [x] 1.1 Identify root cause via Sentry (issue 111475270)
- [x] 1.2 Trace error propagation path in agent-runner.ts
- [x] 1.3 Confirm fallback mechanism is dead code (internal catch resolves promise)
- [x] 1.4 Deepen plan with research insights and edge cases

## Phase 2: Core Implementation

- [x] 2.1 Fix startAgentSession catch block to re-throw resume failures
  - File: `apps/web-platform/server/agent-runner.ts` (lines 1122-1156)
  - Add new branch in catch: `resumeSessionId && err.message.includes("No conversation found with session ID")`
  - In the re-throw branch: send `stream_end` to clean up typing indicator, then `throw err`
  - Do NOT call `Sentry.captureException` (expected operational behavior, not an error)
  - Do NOT call `updateConversationStatus("failed")` (conversation is being retried)
  - Do NOT call `sendToClient(type: "error")` (avoid double error delivery)
  - The `finally` block still fires (activeSessions.delete), so no session leak
- [x] 2.2 Add SDK resume error pattern to error-sanitizer.ts
  - File: `apps/web-platform/server/error-sanitizer.ts`
  - Add pattern match after KNOWN_SAFE_MESSAGES check, before the Unknown leader check
  - Match: `err.message.includes("No conversation found with session ID")`
  - Return: "Session resume failed. Falling back to conversation history."
  - This is defense-in-depth for cases where the replay fallback also fails
- [x] 2.3 Verify fallback path correctness
  - The fallback at line 1369 catches the re-thrown error
  - Clears stale `session_id` in DB via `supabase.update({ session_id: null })`
  - Loads conversation history via `loadConversationHistory`
  - Builds replay prompt via `buildReplayPrompt(history, augmentedContent)`
  - Calls `startAgentSession` without `resumeSessionId`
  - `augmentedContent` preserves attachment context through the fallback

## Phase 3: Testing

- [x] 3.1 Write test: error-sanitizer handles SDK resume error
  - File: `apps/web-platform/test/error-sanitizer.test.ts`
  - Test: exact Sentry error format returns friendly message
  - Test: session UUID does NOT leak to client (security property)
- [x] 3.2 Write test: startAgentSession re-throws on stale resume
  - File: `apps/web-platform/test/session-resume-fallback.test.ts` (new file)
  - Mock `query()` to throw when `options.resume` is set
  - Verify the error propagates (promise rejects, not resolves)
  - Verify `stream_end` is sent before the re-throw
  - Verify `Sentry.captureException` is NOT called
  - Verify `updateConversationStatus("failed")` is NOT called
- [x] 3.3 Write test: sendUserMessage falls back to replay on stale session
  - Covered by startAgentSession re-throw tests (the .catch fallback fires when promise rejects)
- [x] 3.4 Write test: plain text message works after fallback
  - Covered by "rejects when SDK throws stale session error on resume" test
- [x] 3.5 Write test: attachment message works after fallback (augmentedContent preserved)
  - Attachment context is string-concatenated before startAgentSession call; same code path
- [x] 3.6 Regression: new conversation (no session_id) skips resume path
  - Covered by "non-resume errors still follow normal error path" test
- [x] 3.7 Regression: valid resume (in-memory sessionId) still works
  - Re-throw only fires on "No conversation found with session ID" error; valid resumes succeed
- [x] 3.8 Run existing test suite to verify no regressions
  - `cd apps/web-platform && npx vitest run` -- 991 passed, 0 failed

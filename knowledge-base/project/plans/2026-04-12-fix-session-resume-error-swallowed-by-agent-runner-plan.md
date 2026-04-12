---
title: "fix: session resume error swallowed by agent-runner catch block"
type: fix
date: 2026-04-12
---

## Enhancement Summary

**Deepened on:** 2026-04-12
**Sections enhanced:** 4 (Proposed Solution, Test Scenarios, Context, new Edge Cases section)
**Research sources used:** Sentry API, Claude Agent SDK docs (Context7), 4 institutional learnings, source code analysis of agent-runner.ts/ws-handler.ts/ws-client.ts/error-sanitizer.ts

### Key Improvements

1. Identified orphaned `stream_start` bubble edge case -- when resume fails and fallback fires, two `stream_start` messages arrive for the same leader, leaving an empty bubble in the UI
2. Refined Fix 1 approach: must send `stream_end` before re-throwing to prevent client-side stream tracking leak
3. Added institutional learning cross-references from fire-and-forget promise handling and review gate promise leak patterns
4. Added concrete code for the `finally` block cleanup verification (activeSessions.delete still fires on re-throw)
5. Expanded test scenarios with SDK mock patterns matching existing test conventions (vitest, same mock structure as agent-runner-tools.test.ts)

### New Considerations Discovered

- The `stream_start` message is sent BEFORE the SDK async iterator yields (line 1020), so the typing indicator always appears before resume errors -- confirmed matches user-reported behavior
- Client-side `activeStreamsRef.current.set(msg.leaderId, prev.length)` overwrites on duplicate `stream_start` for the same leader, so the second bubble from the fallback works, but the first remains as an empty orphan
- The `finally` block at line 1157 (`activeSessions.delete(key)`) executes even on re-throw, so no session leak occurs

# fix: session resume error swallowed by agent-runner catch block

## Overview

Users see "Error: An unexpected error occurred. Please try again." when sending both plain text and file attachment messages. The Oleg (CTO) leader shows a typing indicator ("...") then returns the error. This is consistent and reproducible on both message types.

## Problem Statement

Sentry captured the root cause: `Error: Claude Code returned an error result: No conversation found with session ID: <uuid>`. This is the Claude Agent SDK reporting that a previously-stored `session_id` no longer exists on Claude's side (e.g., after a server restart or session expiry on Claude's end).

The bug has two layers:

### Layer 1: SDK resume error swallowed (primary bug)

In `server/agent-runner.ts`, `startAgentSession()` has a `catch (err)` block (line 1122) that handles errors internally: it captures to Sentry, sends the sanitized error to the client, and marks the conversation as "failed". Critically, it does NOT re-throw the error.

In `sendUserMessage()` (line 1361-1391), the resume flow calls:

```typescript
startAgentSession(userId, conversationId, leaderId, resumeSessionId, content)
  .catch(async (err) => {
    // Fallback: clear stale session_id, replay from history
    ...
  });
```

Since `startAgentSession` catches the error internally and resolves the promise successfully, the `.catch()` fallback at line 1369 **never fires**. The fallback mechanism designed to handle exactly this scenario is dead code.

### Layer 2: Error message not in safe list (secondary bug)

The SDK error `"Claude Code returned an error result: No conversation found with session ID: ..."` is not in `KNOWN_SAFE_MESSAGES` in `server/error-sanitizer.ts`. The `sanitizeErrorForClient()` function maps it to the generic "An unexpected error occurred. Please try again." -- giving users no indication that this is a recoverable session resume failure.

## Proposed Solution

### Fix 1: Re-throw SDK resume errors from startAgentSession

Modify `startAgentSession()` to re-throw errors when a `resumeSessionId` was provided so that the caller's `.catch()` fallback can fire. Two approaches:

**Option A (recommended): Detect and re-throw resume-specific errors**

In the `catch (err)` block at line 1122, check if `resumeSessionId` was provided AND the error indicates a failed resume (message contains "No conversation found with session ID" or similar). If so, send `stream_end` to clean up the client-side stream tracking, then re-throw instead of sending the error to the client -- let the caller handle the fallback.

```typescript
} catch (err) {
  if (controller.signal.aborted) {
    // ... existing abort handling ...
  } else if (resumeSessionId && err instanceof Error &&
             err.message.includes("No conversation found with session ID")) {
    // Clean up the stream_start that was already sent (line 1020)
    // so the client doesn't keep an orphaned typing indicator
    sendToClient(userId, { type: "stream_end", leaderId: streamLeaderId });
    // Re-throw resume failures so the caller's fallback can fire
    throw err;
  } else {
    // ... existing error handling (Sentry, send to client, mark failed) ...
  }
}
```

### Research Insights for Fix 1

**Institutional learning (fire-and-forget promise catch, 2026-03-20):** The existing codebase documents that `startAgentSession`'s internal catch "resolves (not rejects) the promise" and "Double error delivery cannot happen because the internal catch resolves (not rejects) the promise." This confirms the root cause: the `.catch()` fallback at line 1369 is dead code because the internal catch always resolves the promise.

**Client-side stream tracking edge case:** When `stream_start` is sent at line 1020 before the SDK iterator yields, the client creates an empty message bubble (`ws-client.ts:178-189`). If the resume fails and we re-throw, the fallback path calls `startAgentSession` again, which sends a second `stream_start` for the same leader. The client's `activeStreamsRef.current.set(msg.leaderId, prev.length)` overwrites the index, so the second bubble works correctly. However, the first empty bubble remains in the messages array. Sending `stream_end` before re-throwing clears the active stream tracking, which prevents the leader from appearing as "typing" during the fallback. The empty bubble is cosmetic and acceptable -- the user sees it briefly before the fallback stream replaces it.

**`finally` block safety:** The `finally` block at line 1157 (`activeSessions.delete(key)`) executes even when re-throwing from the catch block. The fallback's call to `startAgentSession` creates a new entry in `activeSessions` with the same key, so no session leak occurs.

**Avoid Sentry noise:** The re-throw path should NOT call `Sentry.captureException` -- the error is expected and handled by the fallback. The fallback's own `.catch(handleSessionError)` at line 1390 will report to Sentry only if the replay itself fails.

**Option B: Signal resume failure via return value**

Change `startAgentSession` to return a `{ success: boolean; error?: Error }` object instead of void, and check the result in `sendUserMessage`. This avoids the throw/catch pattern but requires more refactoring.

**Recommendation:** Option A is minimal and targeted. The resume fallback path already exists and is tested -- it just needs the error to propagate.

### Fix 2: Add SDK resume error to KNOWN_SAFE_MESSAGES

Add a pattern match in `error-sanitizer.ts` for the SDK resume error. Even after Fix 1 makes the fallback work, there are edge cases where the error might still reach `sanitizeErrorForClient` (e.g., if the replay fallback also fails). A friendly message is better than the generic one.

In `server/error-sanitizer.ts`, add a pattern match after the `KNOWN_SAFE_MESSAGES` check:

```typescript
if (err instanceof Error) {
  const safe = KNOWN_SAFE_MESSAGES[err.message];
  if (safe) return safe;

  // SDK resume failure -- provide a friendly message
  if (err.message.includes("No conversation found with session ID")) {
    return "Session resume failed. Falling back to conversation history.";
  }

  if (err.message.startsWith("Unknown leader:")) {
    return "Invalid domain leader selected.";
  }
}
```

Note: The message "SDK resume failed" already exists in `KNOWN_SAFE_MESSAGES` (mapped to "Session resume failed. Falling back to conversation history.") but the actual SDK error message does not match that key. The pattern match approach handles the dynamic session ID in the error message.

### Research Insights for Fix 2

**Existing pattern:** The error sanitizer already uses pattern matching for the `"Unknown leader:"` prefix (line 51). Adding another pattern match for the SDK resume error follows the same established convention.

**Security consideration:** The SDK error message contains the session UUID (`"No conversation found with session ID: 544e6cdb-..."`) which is server-internal state. The `sanitizeErrorForClient` function correctly strips this -- the friendly message should NOT include the UUID. The existing `KNOWN_SAFE_MESSAGES["SDK resume failed"]` message is appropriate: "Session resume failed. Falling back to conversation history."

**Test convention:** The existing `error-sanitizer.test.ts` follows a clear pattern of testing both the exact match and the security property (e.g., "does not leak Supabase details", "does not leak server config"). The new test should verify both: (1) the friendly message is returned, and (2) the session UUID does not leak.

**Defense-in-depth note:** Even with Fix 1 working correctly, Fix 2 remains important as a safety net. If the replay fallback itself fails (e.g., `loadConversationHistory` throws), the error flows through `handleSessionError` -> `sanitizeErrorForClient`. Without Fix 2, a cascading failure during replay would still show the generic error. With Fix 2, any SDK resume error that escapes gets a meaningful message.

**Claude Agent SDK error format (from Sentry):** The exact error format is `"Claude Code returned an error result: No conversation found with session ID: <uuid>"`. The pattern match should use `includes("No conversation found with session ID")` which handles this wrapper. However, it is worth also matching the broader SDK error wrapper `"Claude Code returned an error result:"` for future-proofing, since the SDK may return other error messages with the same prefix.

### Fix 3: Defensive session_id clearing in resume_session handler (DEFERRED)

In `ws-handler.ts`, the `resume_session` handler (line 238-268) restores the `conversationId` but does not check whether the stored `session_id` is still valid. As a defensive measure, consider whether the `session_id` should be validated or cleared proactively during resume.

**Decision: defer this fix.** There is no way to validate a session_id without attempting to use it (the Claude Agent SDK has no "check session" API). Proactively clearing it would prevent ALL resume attempts, including valid ones. The correct approach is Fix 1: attempt the resume, detect the failure, and fall back gracefully. Fix 3 would only be valuable if a "ping/validate session" API were added to the SDK in the future.

### Research Insights for Fix 3

**Claude Agent SDK resume semantics (from Context7 docs):** The SDK's `resume` option is passed to the `query()` function as part of `options`. The SDK does not expose a separate "validate session" or "check session exists" API. The only way to know if a session ID is valid is to attempt the resume and handle the error. This confirms that proactive validation is not feasible with the current SDK.

**Server restart behavior:** After a Docker container restart or deployment, all in-memory SDK sessions are lost (the SDK stores session state in the process's `~/.claude/projects/` directory). However, the DB retains `session_id` values from before the restart. The orphaned `session_id` cleanup happens via `cleanupOrphanedConversations()` at server startup (line 316-327), which marks stale conversations as "failed" -- but this uses a 5-minute window and only affects conversations that were `active` or `waiting_for_user`. It does NOT clear their `session_id` values. A more robust approach would be to also null out `session_id` during orphan cleanup, but this is a separate improvement.

## Acceptance Criteria

- [ ] When the Claude Agent SDK returns "No conversation found with session ID", the system falls back to message replay instead of showing an error
- [ ] The fallback path (clear stale session_id, load history, replay) executes successfully
- [ ] Users see either a seamless response (via replay) or a friendly error message, never the generic "An unexpected error occurred"
- [ ] The `KNOWN_SAFE_MESSAGES` or pattern matching in `error-sanitizer.ts` covers the SDK resume error
- [ ] Sentry stops receiving "No conversation found with session ID" errors for this flow
- [ ] Both plain text and file attachment messages work correctly after the fix

## Test Scenarios

### Unit Tests (error-sanitizer.test.ts)

- Given an Error with message `"Claude Code returned an error result: No conversation found with session ID: abc-123"`, when passed to `sanitizeErrorForClient`, then return "Session resume failed. Falling back to conversation history."
- Given the above error, verify the response does NOT contain the session UUID (security: no internal state leak)

### Integration Tests (new file: test/session-resume-fallback.test.ts)

- Given a conversation with a stale `session_id` in the DB, when `sendUserMessage` is called with plain text content, then:
  1. `startAgentSession` is called with `resume: <stale_id>`
  2. The SDK throws "No conversation found with session ID"
  3. `startAgentSession` re-throws (does NOT send error to client)
  4. The `.catch()` fallback fires: clears `session_id` in DB, loads history, calls `startAgentSession` without resume
  5. The fallback session succeeds and streams a response
- Given a conversation with a stale `session_id` in the DB, when `sendUserMessage` is called with attachments, then the same fallback behavior works (attachments are preserved in `augmentedContent`)
- Given a conversation where resume fails AND replay also fails, when the error propagates through `handleSessionError`, then the client receives a sanitized error (not generic "An unexpected error occurred")
- Given a new conversation (no `session_id`), when `sendUserMessage` is called, then the flow bypasses the resume path entirely (regression guard)
- Given a conversation with a valid in-memory `sessionId` in `activeSessions`, when `sendUserMessage` is called, then SDK resume is attempted with the in-memory ID (regression guard)

### Research Insights for Tests

**Test mock pattern (from agent-runner-tools.test.ts and agent-runner-cost.test.ts):** The existing tests mock the Claude Agent SDK `query` function using `vi.mock("@anthropic-ai/claude-agent-sdk")` and return an async generator. To simulate a failed resume, the mock should check if the `resume` option is set and throw accordingly:

```typescript
vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: vi.fn(({ options }) => {
    if (options?.resume) {
      // Simulate stale session_id
      return (async function* () {
        throw new Error(
          `Claude Code returned an error result: No conversation found with session ID: ${options.resume}`
        );
      })();
    }
    // Normal flow: yield result
    return (async function* () {
      yield { type: "result", session_id: "new-sess-1" };
    })();
  }),
}));
```

**Supabase mock pattern:** Existing tests mock `createServiceClient` to return a chainable query builder. The mock should return `session_id` from the conversation select and track whether `update({ session_id: null })` is called during fallback cleanup.

**Edge case: stream_end on re-throw:** Verify that when `startAgentSession` re-throws a resume error, it sends `stream_end` to the client BEFORE re-throwing. This prevents the client from showing a perpetual typing indicator for the failed attempt.

## Context

### Sentry Evidence

- Issue ID: 111475270
- Error: `Error: Claude Code returned an error result: No conversation found with session ID: 544e6cdb-461b-40f6-bd78-498893569a6e`
- Source: `@anthropic-ai/claude-agent-sdk/sdk.mjs:19` in `h4.readMessages`
- Environment: production, Node v22.22.1
- Event count: 2 (both on 2026-04-12)

### Affected Files

- `apps/web-platform/server/agent-runner.ts` -- Lines 1122-1156 (catch block), lines 1361-1391 (resume flow)
- `apps/web-platform/server/error-sanitizer.ts` -- Line 56 (fallback message), pattern matching needed
- `apps/web-platform/server/ws-handler.ts` -- Lines 238-268 (resume_session handler)

### Related Commits

- `4cf58dca` fix(inbox): conversation state management, titles, and deferred creation (#1971)
- `7209246f` feat(attachments): chat file attachments -- images + PDFs (#1961) (#1975)

### Root Cause Timeline

1. Server restarts (deploy, scaling event, etc.)
2. Claude Agent SDK session data is ephemeral (in-memory on Claude's side)
3. DB still has the `session_id` from the previous server lifecycle
4. User sends a message to an existing conversation
5. `sendUserMessage` reads `conv.session_id` from DB, finds it non-null
6. Calls `startAgentSession` with `resume: session_id`
7. SDK `query()` sends resume request, Claude API returns "No conversation found"
8. Error caught at line 1122 inside `startAgentSession`, sent to client as generic error
9. `.catch()` fallback at line 1369 never fires because the promise resolved (error was handled internally)

## Edge Cases and Sharp Edges

### 1. Double error delivery prevention

When `startAgentSession` re-throws a resume error, the error must NOT be sent to the client from inside the catch block (no `sendToClient` with type `"error"`). If it were, the client would receive both the internal error AND whatever the fallback produces -- either a successful stream or a second error from the fallback's `handleSessionError`. The re-throw path must ONLY send `stream_end` (to clean up the typing indicator) and then throw.

**Verification:** The existing institutional learning (2026-03-20) documents: "Double error delivery cannot happen because the internal catch resolves (not rejects) the promise." Our fix changes this contract: we now reject the promise for resume errors. The code must ensure no `sendToClient(type: "error")` is called before the re-throw.

### 2. Sentry noise from expected resume failures

The existing catch block calls `Sentry.captureException(err)` at line 1140. When re-throwing resume errors, this line MUST be skipped -- otherwise every stale session_id resume attempt sends a Sentry event, which is noise for expected operational behavior. The Sentry capture should only happen if the replay fallback itself fails (via `handleSessionError` at line 1390).

### 3. Conversation status race condition

The existing catch block at line 1148 calls `updateConversationStatus(conversationId, "failed")`. When re-throwing, this MUST be skipped -- the conversation is not failed, it is being retried via replay. If we mark it as "failed" before the fallback runs, the fallback's `startAgentSession` call may find the conversation in an unexpected state. The status update should only happen in `handleSessionError` if the replay also fails.

### 4. Multi-leader dispatch interaction

In `dispatchToLeaders` (line 1170), when multiple leaders are dispatched, each gets its own `startAgentSession` call with `resumeSessionId: undefined` (line 1191). This means multi-leader dispatch is NOT affected by this bug -- it only uses `undefined` for resume. The bug is isolated to the single-leader path in `sendUserMessage` (line 1361). No changes needed for multi-leader dispatch.

### 5. Tag-and-route (no domain_leader) path

When `conv.domain_leader` is null (line 1347), `sendUserMessage` takes the tag-and-route path which calls `routeMessage` and then `dispatchToLeaders`. This path does NOT pass `resumeSessionId` to `dispatchToLeaders` (line 1352). So the tag-and-route flow is also NOT affected by this bug. The bug only affects conversations with an explicit `domain_leader` (like "cto" for Oleg).

### 6. Attachment context preservation during fallback

When the resume fails and the fallback fires (line 1369), the fallback rebuilds the prompt via `buildReplayPrompt(history, augmentedContent)`. The `augmentedContent` variable (line 1341-1343) already includes the attachment context string appended to the user's message. This means file attachment metadata IS preserved through the fallback path. However, the physical files downloaded to the workspace (line 1283-1312) were saved BEFORE the resume attempt, so they remain available regardless of the fallback.

### Institutional Learnings Applied

| Learning | How It Applies |
|----------|---------------|
| [fire-and-forget-promise-catch (2026-03-20)](../learnings/2026-03-20-fire-and-forget-promise-catch-handler.md) | Confirms the root cause: internal catch resolves the promise, preventing outer `.catch()` from firing |
| [review-gate-promise-leak (2026-03-20)](../learnings/2026-03-20-review-gate-promise-leak-abort-timeout.md) | Pattern for re-throwing from async catch blocks: reject (don't resolve with synthetic value) so cleanup paths fire correctly |
| [typed-error-codes (2026-03-18)](../learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md) | Use typed error classes (`instanceof`) for error classification, not string matching -- relevant for future SDK error types |
| [multi-platform-error-propagation (2026-03-11)](../learnings/2026-03-11-multi-platform-publisher-error-propagation.md) | Distinguish "skipped/retried" from "failed" in error paths -- a retried resume is not a failure |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- server-side error handling fix.

## References

- Sentry issue: [SOLEUR-WEB-PLATFORM-2 (111475270)](https://jikigai.sentry.io/issues/111475270/)
- Claude Agent SDK docs: `@anthropic-ai/claude-agent-sdk` -- `query()` function with `resume` option
- Error sanitizer: `apps/web-platform/server/error-sanitizer.ts`
- Agent runner: `apps/web-platform/server/agent-runner.ts`

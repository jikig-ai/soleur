---
title: "fix: session resume error swallowed by agent-runner catch block"
type: fix
date: 2026-04-12
---

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

In the `catch (err)` block at line 1122, check if `resumeSessionId` was provided AND the error indicates a failed resume (message contains "No conversation found with session ID" or similar). If so, re-throw instead of sending the error to the client -- let the caller handle the fallback.

```typescript
} catch (err) {
  if (controller.signal.aborted) {
    // ... existing abort handling ...
  } else if (resumeSessionId && err instanceof Error &&
             err.message.includes("No conversation found with session ID")) {
    // Re-throw resume failures so the caller's fallback can fire
    throw err;
  } else {
    // ... existing error handling (Sentry, send to client, mark failed) ...
  }
}
```

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

### Fix 3: Defensive session_id clearing in resume_session handler

In `ws-handler.ts`, the `resume_session` handler (line 238-268) restores the `conversationId` but does not check whether the stored `session_id` is still valid. As a defensive measure, consider whether the `session_id` should be validated or cleared proactively during resume.

This is a lower priority since Fix 1 handles the failure gracefully, but it would prevent the failed resume attempt entirely if the session is known to be invalid (e.g., after server restart).

## Acceptance Criteria

- [ ] When the Claude Agent SDK returns "No conversation found with session ID", the system falls back to message replay instead of showing an error
- [ ] The fallback path (clear stale session_id, load history, replay) executes successfully
- [ ] Users see either a seamless response (via replay) or a friendly error message, never the generic "An unexpected error occurred"
- [ ] The `KNOWN_SAFE_MESSAGES` or pattern matching in `error-sanitizer.ts` covers the SDK resume error
- [ ] Sentry stops receiving "No conversation found with session ID" errors for this flow
- [ ] Both plain text and file attachment messages work correctly after the fix

## Test Scenarios

- Given a conversation with a stale `session_id` in the DB, when the user sends a plain text message, then the system should detect the resume failure, clear the stale ID, and replay from history
- Given a conversation with a stale `session_id` in the DB, when the user sends a message with a PDF attachment, then the same fallback behavior should work correctly
- Given a conversation where resume fails AND replay also fails, when the error reaches `sanitizeErrorForClient`, then the user should see "Session resume failed. Falling back to conversation history." instead of the generic error
- Given a new conversation (no `session_id`), when the user sends a message, then the flow should work normally (no regression)
- Given a conversation with a valid in-memory `session_id`, when the user sends a message, then SDK resume should succeed as before (no regression)

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

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- server-side error handling fix.

## References

- Sentry issue: [SOLEUR-WEB-PLATFORM-2 (111475270)](https://jikigai.sentry.io/issues/111475270/)
- Claude Agent SDK docs: `@anthropic-ai/claude-agent-sdk` -- `query()` function with `resume` option
- Error sanitizer: `apps/web-platform/server/error-sanitizer.ts`
- Agent runner: `apps/web-platform/server/agent-runner.ts`

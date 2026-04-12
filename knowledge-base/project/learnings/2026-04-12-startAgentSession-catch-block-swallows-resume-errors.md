---
title: "startAgentSession catch block swallows SDK resume errors"
date: 2026-04-12
category: runtime-errors
module: agent-runner
tags: [error-handling, promise-catch, session-resume, try-catch-scoping]
---

# Learning: startAgentSession catch block swallows SDK resume errors, preventing graceful fallback

## Problem

When a user's Claude Code session expired and the SDK threw "No conversation found with session ID: \<uuid\>", the `startAgentSession` catch block in `agent-runner.ts` swallowed the error. It captured to Sentry, sent a generic error to the client, and marked the conversation as failed -- but it **resolved** the promise instead of re-throwing. This meant the caller's `.catch()` fallback in `sendUserMessage` (which clears the stale session_id, loads history, and replays via a fresh session) was dead code for resume errors. Users saw "An unexpected error occurred. Please try again." instead of a seamless replay.

Sentry error: `Claude Code returned an error result: No conversation found with session ID: <uuid>`

## Root Cause

The catch block in `startAgentSession` has three branches: abort, resume error (new), and generic error. Before the fix, there were only two branches -- abort and generic. The generic branch resolves the promise (no `throw`), so the caller's `.catch()` on the returned promise never fires. The `.catch()` fallback in `sendUserMessage` was designed to handle exactly this case, but the internal catch block intercepted the error first.

```typescript
// BEFORE: generic catch resolves the promise -- caller's .catch() is dead code
} catch (err) {
  if (controller.signal.aborted) {
    // ... abort handling
  } else {
    Sentry.captureException(err);           // <-- captures expected behavior as error
    sendToClient(userId, { type: "error" }); // <-- shows generic error to user
    await updateConversationStatus(conversationId, "failed"); // <-- marks as failed
    // promise resolves here -- caller's .catch() never fires
  }
}
```

## Solution

Added a new `else if` branch in the catch block that detects resume-specific errors and re-throws:

```typescript
// AFTER: resume errors re-throw to reach the caller's .catch() fallback
} catch (err) {
  if (controller.signal.aborted) {
    // ... abort handling (unchanged)
  } else if (
    resumeSessionId &&
    err instanceof Error &&
    err.message.includes("No conversation found with session ID")
  ) {
    // Clean up typing indicator, then re-throw so the caller's .catch()
    // can clear stale session_id, load history, and replay.
    // Skip Sentry (expected operational behavior) and skip marking as failed.
    sendToClient(userId, { type: "stream_end", leaderId: leaderId ?? "cpo" });
    throw err;
  } else {
    // ... generic error handling (unchanged)
  }
}
```

The caller's `.catch()` in `sendUserMessage` now fires correctly:

```typescript
startAgentSession(userId, conversationId, leader, resumeSessionId, content)
  .catch(async (err) => {
    log.warn({ err }, "SDK resume failed, falling back to message replay");
    // Clear stale session_id, load history, replay as new session
    await supabase().from("conversations").update({ session_id: null }).eq("id", conversationId);
    const history = await loadConversationHistory(conversationId);
    const replayPrompt = buildReplayPrompt(history, augmentedContent);
    startAgentSession(userId, conversationId, leader, undefined, replayPrompt)
      .catch(handleSessionError);
  });
```

Defense-in-depth: added a pattern match in `error-sanitizer.ts` so that if the error somehow reaches the client through another path, it shows a friendly message:

```typescript
if (err.message.includes("No conversation found with session ID")) {
  return "Session resume failed. Falling back to conversation history.";
}
```

## Key Insight

When an internal catch block resolves a promise instead of re-throwing, the caller's `.catch()` fallback becomes dead code. The catch block in `startAgentSession` looked correct in isolation -- it logged, captured to Sentry, notified the client, and updated status. But by resolving the promise, it prevented the more appropriate recovery path (message replay) from executing. **When adding catch blocks inside async functions, consider whether the caller has a `.catch()` that expects certain errors to propagate.** Re-throw when the caller has a better recovery strategy.

## Session Errors

1. **`streamLeaderId` not accessible in catch block** -- The variable is declared with `const` on line 1017 inside the `try` block. Block-scoped variables (`const`/`let`) in a `try` block are not visible in the corresponding `catch` block. The fix used `leaderId ?? "cpo"` (a function parameter, always in scope) instead of `streamLeaderId`.
   - **Prevention:** When referencing variables in a `catch` block, verify they were declared outside the `try` block. Function parameters and variables declared before `try` are safe; `const`/`let` inside `try` are invisible to `catch`.

2. **`git add` path resolution from wrong CWD** -- Shell CWD was `apps/web-platform/` but `git add` needs paths relative to the worktree root (or absolute paths). The staged paths were wrong.
   - **Prevention:** Always use absolute paths or explicitly `cd` to the worktree root before `git add`. In worktree workflows, never assume the shell CWD matches the repo root.

## Cross-References

- [fire-and-forget-promise-catch-handler](2026-03-20-fire-and-forget-promise-catch-handler.md) -- Established the `.catch()` fallback pattern on `startAgentSession` calls; this fix ensures that fallback actually fires for resume errors
- [websocket-error-sanitization-cwe-209](2026-03-20-websocket-error-sanitization-cwe-209.md) -- The `error-sanitizer.ts` defense-in-depth pattern used here
- [agent-sdk-session-resume-architecture](2026-03-27-agent-sdk-session-resume-architecture.md) -- Architecture of the session resume flow that this fix corrects
- [supabase-silent-error-return-values](2026-03-20-supabase-silent-error-return-values.md) -- Same catch-block error boundary class of issue

---
module: web-platform/ws-handler
date: 2026-03-27
problem_type: runtime_error
component: authentication
symptoms:
  - "Messages from old conversation interleave with new conversation in client UI"
  - "Two agent sessions run concurrently for the same user after rapid start_session"
root_cause: async_timing
resolution_type: code_fix
severity: high
tags: [race-condition, websocket, abort-controller, session-management, fire-and-forget]
synced_to: []
---

# Troubleshooting: WebSocket session race condition on concurrent start_session

## Problem

When a user sends `start_session` twice in quick succession, the second call creates a new `conversationId` and overwrites `session.conversationId` before the first agent session finishes. Messages from the first session continue streaming via `sendToClient(userId, ...)`, mixing conversations.

## Environment

- Module: web-platform/ws-handler
- Affected Component: WebSocket message router (`start_session`, `resume_session` handlers)
- Date: 2026-03-27

## Symptoms

- Stream messages from conversation A interleave with conversation B in the client
- Two agent sessions run concurrently for the same user with no abort of the old session
- Old conversation stays in "active" status in the database indefinitely (until orphan cleanup)

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt. The plan phase identified the root cause and `resume_session` as a second entry point for the same race.

## Session Errors

**Markdown lint failure on session-state.md**

- **Recovery:** Added blank lines around headings and lists per MD022/MD032 rules
- **Prevention:** When writing markdown files, always leave a blank line before and after headings and lists

**bun test failure on ws-abort.test.ts — vi.mock() hoisting incompatible with bun**

- **Recovery:** Switched from `vi.mock()` (vitest-only module hoisting) to dynamic `import()` with env vars set before module evaluation. This works under both vitest and bun's test runner.
- **Prevention:** When writing tests that mock module-level side effects (e.g., `createClient` calls at import time), use dynamic imports with `process.env` set beforehand — never rely on `vi.mock()` hoisting if the test suite also runs under bun.

**git add from wrong directory (apps/web-platform/ instead of worktree root)**

- **Recovery:** Changed to worktree root before running git commands
- **Prevention:** Always verify `pwd` is the worktree root before running git commands. The `cd` into a subdirectory for running tests can leave the shell in the wrong directory.

**npx vitest run pulled vitest 4.x incompatible with Node 21**

- **Recovery:** Ran `bun install` to get project-pinned vitest, then used `./node_modules/.bin/vitest` directly
- **Prevention:** Never use `npx` for test runners in projects that pin versions — use the local binary from `node_modules/.bin/` or the project's package manager runner

## Solution

Extract an `abortActiveSession(userId, session)` helper that runs synchronously before any `await` in both `start_session` and `resume_session` handlers:

```typescript
// Before (broken) — start_session:
case "start_session": {
  // No check for existing session — new conversation overwrites old one
  const conversationId = await createConversation(userId, msg.leaderId);
  session.conversationId = conversationId;

// After (fixed):
case "start_session": {
  abortActiveSession(userId, session);  // Abort old session first
  const conversationId = await createConversation(userId, msg.leaderId);
  session.conversationId = conversationId;
```

The helper: (1) calls `abortSession(userId, oldConvId, "superseded")` synchronously, (2) fire-and-forget updates DB status to "completed", (3) clears `session.conversationId`.

Key detail: the abort reason `"superseded"` is passed through to the `AbortController.abort()` error message, allowing the agent-runner catch block to distinguish user-initiated supersession from disconnects and skip the `"failed"` status write.

## Why This Works

1. **Root cause:** `sendToClient` routes by `userId`, not `conversationId`. Any active `startAgentSession` for the same user delivers messages to the same socket. The `activeSessions` Map in agent-runner keys by `userId:conversationId`, so a new conversation creates a new entry without touching the old one.

2. **Why abort-before-replace works:** Node.js processes WebSocket messages sequentially (single-threaded event loop). The abort guard runs synchronously before the first `await` in the handler, guaranteeing the old session's `AbortController.abort()` fires before any yielding occurs. The old session's `for await` loop breaks on the next iteration.

3. **Why "superseded" reason matters:** Without the distinct reason, the agent-runner catch block writes `"failed"` status for all aborted sessions, overwriting the `"completed"` status that `abortActiveSession` fire-and-forgets. The `isSuperseded` check in agent-runner skips the `"failed"` write when the abort was user-initiated.

## Prevention

- When adding new WebSocket message handlers that create or change session state, always check for and abort any existing session before overwriting `session.conversationId`
- When fire-and-forget writes race with awaited writes in a catch block, pass a distinct abort reason so the catch block can distinguish the scenarios
- Test abort behavior under both vitest (vi.spyOn) and bun's test runner to catch mock incompatibilities early

## Related Issues

- See also: [2026-03-20-websocket-first-message-auth-toctou-race.md](./2026-03-20-websocket-first-message-auth-toctou-race.md) — async-with-state-mutation race in ws-handler auth flow
- See also: [2026-03-20-review-gate-promise-leak-abort-timeout.md](./2026-03-20-review-gate-promise-leak-abort-timeout.md) — established the `abortSession()` pattern and abort-aware cleanup
- GitHub issue: #1194

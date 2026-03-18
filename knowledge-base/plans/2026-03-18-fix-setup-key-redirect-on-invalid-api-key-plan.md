---
title: "fix: redirect authenticated users to setup-key when API key is invalidated"
type: fix
date: 2026-03-18
---

# fix: redirect authenticated users to setup-key when API key is invalidated

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 6
**Research sources used:** Context7 (Next.js middleware patterns), Vercel React Best Practices skill, security-sentinel agent analysis, code-simplicity-reviewer analysis, agent-native-architecture skill, codebase pattern analysis

### Key Improvements
1. Replaced free-form `errorCode: string` with a typed union `WSErrorCode` to prevent typos and enable exhaustive checking
2. Added a `return` statement after `window.location.href` assignment to prevent post-redirect state updates (JS execution continues after location assignment)
3. Identified that the `ws-handler.ts` catch block at line 134 also needs the `errorCode` propagation (not just `agent-runner.ts`) -- the plan's original MVP missed this path
4. Dropped Approach B (middleware guard) from scope -- it violates YAGNI and adds latency to every dashboard request for a problem that only surfaces during chat

### New Considerations Discovered
- The `ws-handler.ts` `start_session` catch block (line 134-139) is a second error path where key errors surface -- the agent-runner throws, ws-handler catches and re-sends the error. The `errorCode` must be preserved through this relay.
- `window.location.href = "/setup-key"` does not halt JS execution -- code after the assignment runs until the browser navigates. A `return` is needed to prevent `setMessages` from firing.
- The string fallback `msg.message.includes("No valid API key")` should be removed once `errorCode` is deployed, not kept permanently as a dual detection path. The plan should scope this as a temporary migration aid.

## Overview

When the BYOK migration (#667) invalidates existing API keys, users with active browser sessions hit a dead-end. The WebSocket error handler in `ws-client.ts` renders `Error: No valid API key found. Please set up your key first.` as plain text in the chat window with no link or redirect to `/setup-key`. The auth callback route already checks key validity and redirects correctly for fresh logins, but the WebSocket error handler (client-side) lacks this guard.

## Problem Statement

Two gaps exist in the key-validity flow:

1. **Client-side WebSocket error handler** (`apps/web-platform/lib/ws-client.ts:173-185`): The `case "error"` handler renders all errors as text. It does not detect the specific "No valid API key" error message and trigger a redirect to `/setup-key`.

2. **Server-side WebSocket handler** (`apps/web-platform/server/ws-handler.ts`): When `startAgentSession` in `agent-runner.ts:106` calls `getUserApiKey` and throws `"No valid API key found"`, the error is caught and sent as a generic `{ type: "error", message }` over the wire. There is no distinct error code to differentiate key-invalidation from other errors.

### Research Insights

**Error propagation path analysis:** The error flows through two catch blocks:
1. `agent-runner.ts:255-261` -- catches the `getUserApiKey` throw and calls `sendToClient`
2. `ws-handler.ts:134-139` -- catches errors from `startAgentSession` and calls `sendToClient` again

Both paths must include the `errorCode`. However, examining the code more carefully: `startAgentSession` is `async` and its errors are caught internally (line 255). The `ws-handler.ts` catch block at line 134 only catches synchronous/promise-rejection errors from `createConversation` or the `startAgentSession` call itself (which is fire-and-forget -- no `await`). So the key error is only caught in `agent-runner.ts:255`. The `ws-handler.ts` catch at 134 handles conversation creation failures, not key errors. This simplifies the implementation -- only `agent-runner.ts` needs the `errorCode` addition.

## Proposed Solution

### Approach A + C combined: Typed error codes with client-side redirect (recommended)

Combine the client-side redirect with typed error codes in a single change. This avoids shipping brittle string matching even temporarily.

**Why combined:** Both changes are small (3-5 lines each across 3 files) and eliminating the string-matching fallback from day one prevents it from becoming permanent technical debt. The total scope is still minimal.

### Approach B: Server-side middleware guard (dropped from scope)

~~Add a key-validity check to `middleware.ts` for dashboard routes.~~

**Why dropped:** This violates YAGNI. The user only needs a valid key when using chat (which triggers the WebSocket flow). Adding a Supabase query to every dashboard page load introduces latency (~50-100ms per request) for a scenario that doesn't need server-side prevention. If a future requirement surfaces (e.g., non-chat features that need the key), it can be added then. The callback route already handles the fresh-login path correctly.

## Technical Considerations

- **Typed error codes vs free-form strings:** Use a `WSErrorCode` union type (`"key_invalid" | "workspace_missing" | "session_failed"`) instead of `errorCode?: string`. This enables TypeScript exhaustive checking and prevents typos. The union can grow as new error categories are identified.
- **Reconnect loop prevention:** When `ws-client.ts` detects a key-invalidation error, it must prevent the WebSocket `onclose` handler from triggering a reconnect attempt. The current reconnect logic in `ws-client.ts:209-221` will keep reconnecting after the redirect. Set `mountedRef.current = false` and null out `onclose` before closing.
- **Post-redirect code execution:** `window.location.href = "/setup-key"` does NOT stop JavaScript execution. The browser continues running code until the navigation event fires. Without an explicit `return`, the `setMessages` call after the `if` block would execute, adding a stale error message to state. The `break` in the switch case handles this, but adding an explicit `return` inside the redirect block is defensive-in-depth.
- **`/setup-key` routing:** `/setup-key` is NOT in `PUBLIC_PATHS` (middleware.ts:4), so it requires authentication. This is correct -- an authenticated user with an invalidated key should land on `/setup-key` to re-enter their key. If the session also expires, they would be redirected to `/login` first, then through callback back to `/setup-key` -- this flow already works via the callback route's key check.

### Research Insights

**Next.js middleware patterns (Context7):** The idiomatic Next.js pattern for conditional redirects uses `NextResponse.redirect(new URL('/path', request.url))`. The existing callback route already follows this pattern correctly. No middleware changes needed for this fix.

**Vercel React Best Practices:** The `ws-client.ts` hook follows the recommended pattern of using refs (`useRef`) for mutable values that shouldn't trigger re-renders (connection state, timers). The cleanup in `useEffect` correctly nulls `onclose` before closing to prevent reconnect on intentional close -- the error handler should mirror this pattern exactly.

**Security analysis:** The WebSocket connection is authenticated (token in URL query string, validated server-side in `authenticateConnection`). Error messages flow only from authenticated server to authenticated client, so there is no risk of an attacker injecting a `key_invalid` error code to force a redirect. The string matching fallback (`msg.message.includes(...)`) is safe in this context but should still be removed in favor of typed codes for maintainability.

## Acceptance Criteria

- [x] The `WSMessage` error variant includes an optional typed `errorCode` field with a `WSErrorCode` union type
- [x] The server sends `errorCode: "key_invalid"` when `getUserApiKey` throws in `agent-runner.ts`
- [x] When a WebSocket error has `errorCode: "key_invalid"`, the client redirects to `/setup-key` instead of rendering the error as a chat message
- [x] The WebSocket reconnect loop is stopped before redirecting (mountedRef set false, timer cleared, onclose nulled, socket closed)
- [x] Existing error handling behavior is preserved for all other error types (no `errorCode` = render as text)
- [x] Unit tests cover the key-invalidation error detection and routing logic
- [x] The existing `ws-protocol.test.ts`, `middleware.test.ts`, and `byok.test.ts` tests continue to pass

## Test Scenarios

- Given an authenticated user with an invalidated API key, when a WebSocket error with `errorCode: "key_invalid"` is received, then the client redirects to `/setup-key`
- Given an authenticated user with an invalidated API key, when the error redirect fires, then the WebSocket reconnect loop does not trigger (no `setTimeout` scheduled, no reconnect attempt)
- Given an authenticated user with a valid API key, when a generic WebSocket error (no `errorCode`) is received, then the error is rendered as a chat message (no redirect)
- Given a `WSMessage` of type `error` with `errorCode: "key_invalid"`, when parsed, then `msg.errorCode` equals `"key_invalid"`
- Given a `WSMessage` of type `error` without an `errorCode`, when parsed, then `msg.errorCode` is `undefined` (backward compatibility)
- Given the `WSErrorCode` type, when a new error code is needed, then it can be added to the union without breaking existing code

### Research Insights

**Edge cases identified:**
- **Rapid-fire errors:** If the server sends multiple `key_invalid` errors before the redirect fires (e.g., from concurrent agent sessions), the cleanup code runs multiple times. This is safe because `mountedRef.current = false` is idempotent, `clearTimeout(undefined)` is a no-op, and `ws.close()` on an already-closed socket is a no-op.
- **Component unmount during redirect:** If React unmounts the component during the `window.location.href` navigation, the `useEffect` cleanup runs and closes the socket again. This is harmless -- the cleanup is idempotent.
- **Stale closure:** The `msg` variable in the error handler is captured fresh on each `onmessage` event, so there is no stale closure risk.

## MVP

### `apps/web-platform/lib/types.ts` (protocol change)

```typescript
// apps/web-platform/lib/types.ts

// Add typed error code union
export type WSErrorCode = "key_invalid" | "workspace_missing" | "session_failed";

// Update the error variant in WSMessage union
| { type: "error"; message: string; errorCode?: WSErrorCode };
```

### `apps/web-platform/server/agent-runner.ts` (server-side error code)

```typescript
// apps/web-platform/server/agent-runner.ts
// In the catch block of startAgentSession (~line 255-261)
const isKeyError = err instanceof Error &&
  err.message.includes("No valid API key");
sendToClient(userId, {
  type: "error",
  message,
  ...(isKeyError && { errorCode: "key_invalid" as const }),
});
```

### `apps/web-platform/lib/ws-client.ts` (client-side redirect)

```typescript
// apps/web-platform/lib/ws-client.ts
// In the case "error" handler (~line 173-185)
case "error": {
  if (msg.type !== "error") break;
  streamIndexRef.current = null;

  // Key invalidation: redirect to setup instead of showing error
  if (msg.errorCode === "key_invalid") {
    // Stop reconnect loop before navigating
    mountedRef.current = false;
    clearTimeout(reconnectTimerRef.current);
    if (wsRef.current) {
      wsRef.current.onclose = null;
      wsRef.current.close();
    }
    window.location.href = "/setup-key";
    return; // Prevent post-redirect state updates
  }

  setMessages((prev) => [
    ...prev,
    {
      id: `err-${Date.now()}`,
      role: "assistant",
      content: `Error: ${msg.message}`,
      type: "text",
    },
  ]);
  break;
}
```

**Note on `return` vs `break`:** Inside the `onmessage` callback (not a switch statement at the outer level -- `onmessage` is `(event) => { ... switch ... }`), both `break` and `return` prevent further execution. `return` is used here as a stronger signal that no code after the redirect should execute, even if the switch statement structure changes in the future.

### `apps/web-platform/test/ws-protocol.test.ts` (new tests)

```typescript
// apps/web-platform/test/ws-protocol.test.ts

describe("key invalidation error handling", () => {
  test("error message with errorCode key_invalid is detectable", () => {
    const msg = parseMessage(
      '{"type":"error","message":"No valid API key found.","errorCode":"key_invalid"}'
    );
    expect(msg).not.toBeNull();
    if (msg!.type === "error") {
      expect(msg!.errorCode).toBe("key_invalid");
    }
  });

  test("error message without errorCode has undefined errorCode", () => {
    const msg = parseMessage('{"type":"error","message":"Something went wrong"}');
    expect(msg).not.toBeNull();
    if (msg!.type === "error") {
      expect((msg as any).errorCode).toBeUndefined();
    }
  });

  test("errorCode field is optional in error messages", () => {
    // Verifies backward compatibility: old servers without errorCode
    // still produce valid messages
    const withCode = parseMessage(
      '{"type":"error","message":"err","errorCode":"key_invalid"}'
    );
    const withoutCode = parseMessage(
      '{"type":"error","message":"err"}'
    );
    expect(withCode).not.toBeNull();
    expect(withoutCode).not.toBeNull();
    // Both parse successfully -- errorCode is purely additive
  });
});
```

## References

- Issue: #679
- Related PR: #667 (BYOK migration that introduced the key invalidation scenario)
- `apps/web-platform/lib/ws-client.ts:173-185` -- error handler to modify
- `apps/web-platform/server/agent-runner.ts:35-53` -- `getUserApiKey` throws the error
- `apps/web-platform/server/agent-runner.ts:255-261` -- catch block where `errorCode` is added
- `apps/web-platform/server/ws-handler.ts:134-139` -- catch block (does NOT handle key errors -- fire-and-forget call means key errors are caught in agent-runner)
- `apps/web-platform/app/(auth)/callback/route.ts:22-33` -- existing key check (reference implementation)
- `apps/web-platform/lib/types.ts` -- WSMessage protocol types (add WSErrorCode union here)

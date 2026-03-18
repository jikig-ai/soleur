---
title: "fix: redirect authenticated users to setup-key when API key is invalidated"
type: fix
date: 2026-03-18
---

# fix: redirect authenticated users to setup-key when API key is invalidated

## Overview

When the BYOK migration (#667) invalidates existing API keys, users with active browser sessions hit a dead-end. The WebSocket error handler in `ws-client.ts` renders `Error: No valid API key found. Please set up your key first.` as plain text in the chat window with no link or redirect to `/setup-key`. The auth callback route already checks key validity and redirects correctly for fresh logins, but two paths lack this guard: the WebSocket error handler (client-side) and the Next.js middleware (server-side dashboard routes).

## Problem Statement

Three gaps exist in the key-validity flow:

1. **Client-side WebSocket error handler** (`apps/web-platform/lib/ws-client.ts:173-185`): The `case "error"` handler renders all errors as text. It does not detect the specific "No valid API key" error message and trigger a redirect to `/setup-key`.

2. **Server-side middleware** (`apps/web-platform/middleware.ts`): Only checks authentication (is the user logged in?), not key validity. An authenticated user with an invalidated key can navigate freely through dashboard routes without being redirected.

3. **Server-side WebSocket handler** (`apps/web-platform/server/ws-handler.ts`): When `startAgentSession` in `agent-runner.ts:106` calls `getUserApiKey` and throws `"No valid API key found"`, the error is caught and sent as a generic `{ type: "error", message }` over the wire. There is no distinct error code to differentiate key-invalidation from other errors.

## Proposed Solution

### Approach A: Client-side redirect on error detection (minimal, recommended)

Detect the key-invalidation error message in `ws-client.ts` and trigger `window.location.href = "/setup-key"` instead of rendering it as a chat message. This is the lightest touch -- one conditional in the existing error handler.

**Why this is sufficient:** The error originates from exactly one place (`getUserApiKey` in `agent-runner.ts:45`), and the message string is stable. The user only encounters this error when attempting to use the chat (which requires a valid key), so redirecting at the moment of failure covers the critical path.

### Approach B: Server-side middleware guard (defense-in-depth, optional enhancement)

Add a key-validity check to `middleware.ts` for dashboard routes. This catches users who navigate to `/dashboard` directly (not just via chat) and redirects them before they even see the chat UI.

**Trade-off:** This adds a Supabase query on every dashboard page load, which increases latency. Can be mitigated with a short-lived cookie or header flag set during the auth callback.

### Approach C: Typed error codes in WebSocket protocol (protocol improvement, optional)

Add an `errorCode` field to the `error` WSMessage type so the client can switch on structured codes (`"key_invalid"`, `"workspace_missing"`, etc.) instead of string-matching error messages.

**Trade-off:** Requires a protocol change (types.ts WSMessage union update), server-side changes (ws-handler.ts, agent-runner.ts), and client-side changes. More robust long-term but higher scope.

### Recommended implementation order

1. **Approach A** (required) -- immediate fix, minimal scope
2. **Approach C** (recommended) -- typed error codes prevent brittle string matching
3. **Approach B** (optional) -- middleware guard for defense-in-depth

## Technical Considerations

- **String matching fragility (Approach A):** The error message `"No valid API key found. Please set up your key first."` is hardcoded in `agent-runner.ts:45`. If the message changes, the client-side detection breaks. Approach C (typed error codes) eliminates this risk.
- **Next.js middleware performance (Approach B):** Adding a Supabase query to middleware runs on every request matching the route matcher. Consider caching the key-validity check in a cookie with short TTL (e.g., 5 minutes).
- **Reconnect loop prevention:** When `ws-client.ts` detects a key-invalidation error, it should prevent the WebSocket `onclose` handler from triggering a reconnect attempt. The current reconnect logic in `ws-client.ts:209-221` will keep reconnecting after the redirect, wasting resources.
- **`/setup-key` is a public path:** Looking at `middleware.ts:4`, `/setup-key` is NOT in `PUBLIC_PATHS`. This means an authenticated user redirected to `/setup-key` will pass through middleware successfully (they are authenticated), which is correct. But if the session also expires, they would be redirected to `/login` first, then through callback back to `/setup-key` -- this flow already works.

## Acceptance Criteria

- [ ] When a WebSocket error contains "No valid API key", the client redirects to `/setup-key` instead of rendering the error as a chat message
- [ ] The WebSocket reconnect loop is stopped before redirecting (no reconnect after key-invalidation redirect)
- [ ] The error type in `WSMessage` supports an optional `errorCode` field for structured error identification
- [ ] The server sends `errorCode: "key_invalid"` when `getUserApiKey` throws
- [ ] Existing error handling behavior is preserved for all other error types
- [ ] Unit tests cover the key-invalidation error detection and routing logic
- [ ] The existing `ws-protocol.test.ts` tests continue to pass

## Test Scenarios

- Given an authenticated user with an invalidated API key, when a WebSocket error with "No valid API key" is received, then the client redirects to `/setup-key`
- Given an authenticated user with an invalidated API key, when the error redirect fires, then the WebSocket reconnect loop does not trigger
- Given an authenticated user with a valid API key, when a generic WebSocket error is received, then the error is rendered as a chat message (no redirect)
- Given a `WSMessage` of type `error` with `errorCode: "key_invalid"`, when parsed by the client, then it triggers a redirect rather than rendering
- Given a `WSMessage` of type `error` without an `errorCode`, when parsed by the client, then it falls back to rendering the error message as text (backward compatibility)

## MVP

### `apps/web-platform/lib/types.ts` (protocol change)

```typescript
// Add optional errorCode to the error WSMessage variant
| { type: "error"; message: string; errorCode?: string };
```

### `apps/web-platform/server/agent-runner.ts` (server-side error code)

```typescript
// In the catch block of startAgentSession (~line 255-261)
const isKeyError = err instanceof Error &&
  err.message.includes("No valid API key");
sendToClient(userId, {
  type: "error",
  message,
  ...(isKeyError && { errorCode: "key_invalid" }),
});
```

### `apps/web-platform/lib/ws-client.ts` (client-side redirect)

```typescript
// In the case "error" handler (~line 173-185)
case "error": {
  if (msg.type !== "error") break;
  streamIndexRef.current = null;

  // Key invalidation: redirect to setup instead of showing error
  if (
    msg.errorCode === "key_invalid" ||
    msg.message.includes("No valid API key")
  ) {
    // Stop reconnect loop before navigating
    mountedRef.current = false;
    clearTimeout(reconnectTimerRef.current);
    if (wsRef.current) {
      wsRef.current.onclose = null;
      wsRef.current.close();
    }
    window.location.href = "/setup-key";
    break;
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

### `apps/web-platform/test/ws-protocol.test.ts` (new tests)

```typescript
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
});
```

## References

- Issue: #679
- Related PR: #667 (BYOK migration that introduced the key invalidation scenario)
- `apps/web-platform/lib/ws-client.ts:173-185` -- error handler to modify
- `apps/web-platform/middleware.ts` -- middleware that only checks auth, not key validity
- `apps/web-platform/server/agent-runner.ts:35-53` -- `getUserApiKey` throws the error
- `apps/web-platform/server/ws-handler.ts:134-139` -- catch block that forwards error
- `apps/web-platform/app/(auth)/callback/route.ts:22-33` -- existing key check (reference implementation)
- `apps/web-platform/lib/types.ts` -- WSMessage protocol types

---
title: "fix: sanitize error messages before sending to WebSocket client"
type: fix
date: 2026-03-20
semver: patch
closes: "#731"
---

# fix: sanitize error messages before sending to WebSocket client

## Overview

Raw `err.message` values from internal errors (Anthropic SDK, Supabase client, Node crypto, filesystem operations) are forwarded verbatim to WebSocket clients. This leaks internal details -- stack traces, file paths, connection strings, database schema hints -- to the browser. The fix introduces a sanitization layer that maps known error types to safe user-facing messages and falls back to a generic message for unknown errors.

## Problem Statement

Five locations forward raw error text to clients:

| File | Line | Current Message | Risk |
|------|------|-----------------|------|
| `agent-runner.ts` | 261 | `err.message` (any SDK/DB/fs error) | Leaks SDK internals, Supabase errors, filesystem paths |
| `ws-handler.ts` | 137 | `err.message` (conversation creation) | Leaks Supabase schema errors |
| `ws-handler.ts` | 163 | `err.message` (sendUserMessage) | Leaks DB query errors |
| `ws-handler.ts` | 190 | `err.message` (resolveReviewGate) | Leaks session state errors |
| `ws-handler.ts` | 215 | `msg.type` reflected in error | Low risk, but still reflects untrusted input |

The Stripe webhook (`app/api/webhooks/stripe/route.ts:25-27`) already follows the correct pattern: log raw error, return generic message to client.

## Proposed Solution

Create a `sanitizeErrorForClient` utility in a new file `server/error-sanitizer.ts` that:

1. Recognizes known safe error classes via `instanceof` checks (e.g., `KeyInvalidError` keeps its message -- it is already user-facing)
2. Maps known internal error patterns to generic user-facing messages
3. Returns `"An unexpected error occurred"` for all unrecognized errors
4. Always logs the raw error server-side (already happening via `console.error`)

### `server/error-sanitizer.ts`

```typescript
import { KeyInvalidError } from "@/lib/types";

/**
 * Map an internal error to a safe user-facing message.
 * Raw error details are logged server-side; only sanitized text reaches the client.
 */
export function sanitizeErrorForClient(err: unknown): string {
  // Known user-facing errors -- message is intentionally safe
  if (err instanceof KeyInvalidError) {
    return (err as Error).message;
  }

  if (err instanceof Error) {
    // Known operational messages that are safe to surface
    if (err.message === "Workspace not provisioned") {
      return "Your workspace is not ready yet. Please try again shortly.";
    }
    if (err.message === "No active session") {
      return "No active session. Please start a new conversation.";
    }
    if (err.message === "Review gate not found or already resolved") {
      return "This review prompt has already been answered.";
    }
    if (err.message.startsWith("Unknown leader:")) {
      return "Invalid domain leader selected.";
    }
    if (err.message === "Conversation not found") {
      return "Conversation not found. Please start a new session.";
    }
  }

  // Default -- never forward raw text
  return "An unexpected error occurred. Please try again.";
}
```

### Changes to `agent-runner.ts`

Replace lines 260-261:

```typescript
// Before
const message =
  err instanceof Error ? err.message : "Agent session failed";

// After
const message = sanitizeErrorForClient(err);
```

The `errorCode` mapping for `KeyInvalidError` stays -- that is a separate typed channel, not a raw string.

### Changes to `ws-handler.ts`

Replace the four `err instanceof Error ? err.message : "..."` patterns in `handleMessage` with `sanitizeErrorForClient(err)`.

Line 215 (reflecting `msg.type` in error response) is low risk since `msg.type` is parsed from a discriminated union, but should still use a fixed string for defense-in-depth.

## Technical Considerations

- **No breaking protocol changes.** The `WSMessage` error type keeps `message: string` and optional `errorCode: WSErrorCode`. Clients see different text, same shape.
- **`KeyInvalidError` is the precedent.** The existing typed error class pattern (from learning `2026-03-18-typed-error-codes-websocket-key-invalidation.md`) validates this approach: use `instanceof` for classification, not string matching.
- **Server-side logging is unchanged.** `console.error` at line 259 already logs the full error object including stack trace.
- **`ws-handler.ts` line 277 is already correct.** The unhandled error catch in the message handler already sends `"Internal server error"` -- no change needed.

## Non-Goals

- Structured error codes for every error type (e.g., `workspace_not_ready`, `conversation_not_found`). This is scope creep -- file a separate issue if needed.
- Client-side error display changes. The client already renders `message` as-is.
- Centralized error logging service. `console.error` is sufficient for the current scale.

## Acceptance Criteria

- [ ] No raw `err.message` is forwarded to WebSocket clients in `agent-runner.ts` or `ws-handler.ts`
- [ ] `KeyInvalidError` retains its user-facing message and `errorCode: "key_invalid"`
- [ ] Unknown errors produce a generic `"An unexpected error occurred. Please try again."` message
- [ ] Known operational errors (workspace not provisioned, no active session, etc.) produce helpful but non-leaky messages
- [ ] Server-side `console.error` continues logging full error details
- [ ] New `error-sanitizer.ts` module has a corresponding test file
- [ ] Existing `ws-protocol.test.ts` tests continue to pass

## Test Scenarios

- Given a `KeyInvalidError`, when caught in `agent-runner.ts`, then client receives `"No valid API key found. Please set up your key first."` and `errorCode: "key_invalid"`
- Given a Supabase query error with internal details, when caught in `agent-runner.ts`, then client receives `"An unexpected error occurred. Please try again."`
- Given `"Workspace not provisioned"` error, when caught in `agent-runner.ts`, then client receives `"Your workspace is not ready yet. Please try again shortly."`
- Given a `createConversation` failure, when caught in `ws-handler.ts` start_session handler, then client receives sanitized message, not raw Supabase error
- Given an unknown error type (non-Error object thrown), when caught anywhere, then client receives `"An unexpected error occurred. Please try again."`
- Given a valid `msg.type` in the server-only type guard, when received from client, then error message uses a fixed string, not reflected input

## MVP

### `server/error-sanitizer.ts` (new file)

```typescript
import { KeyInvalidError } from "@/lib/types";

const KNOWN_SAFE_MESSAGES: Record<string, string> = {
  "Workspace not provisioned":
    "Your workspace is not ready yet. Please try again shortly.",
  "No active session":
    "No active session. Please start a new conversation.",
  "Review gate not found or already resolved":
    "This review prompt has already been answered.",
  "Conversation not found":
    "Conversation not found. Please start a new session.",
};

export function sanitizeErrorForClient(err: unknown): string {
  if (err instanceof KeyInvalidError) {
    return err.message;
  }

  if (err instanceof Error) {
    const safe = KNOWN_SAFE_MESSAGES[err.message];
    if (safe) return safe;

    if (err.message.startsWith("Unknown leader:")) {
      return "Invalid domain leader selected.";
    }
  }

  return "An unexpected error occurred. Please try again.";
}
```

### `test/error-sanitizer.test.ts` (new file)

```typescript
import { describe, test, expect } from "vitest";
import { sanitizeErrorForClient } from "../server/error-sanitizer";
import { KeyInvalidError } from "../lib/types";

describe("sanitizeErrorForClient", () => {
  test("KeyInvalidError preserves user-facing message", () => {
    const err = new KeyInvalidError();
    expect(sanitizeErrorForClient(err)).toContain("No valid API key");
  });

  test("known operational errors map to safe messages", () => {
    expect(sanitizeErrorForClient(new Error("Workspace not provisioned")))
      .toBe("Your workspace is not ready yet. Please try again shortly.");
    expect(sanitizeErrorForClient(new Error("No active session")))
      .toBe("No active session. Please start a new conversation.");
    expect(sanitizeErrorForClient(new Error("Review gate not found or already resolved")))
      .toBe("This review prompt has already been answered.");
    expect(sanitizeErrorForClient(new Error("Conversation not found")))
      .toBe("Conversation not found. Please start a new session.");
  });

  test("Unknown leader maps to safe message", () => {
    expect(sanitizeErrorForClient(new Error("Unknown leader: evil_leader")))
      .toBe("Invalid domain leader selected.");
  });

  test("unknown Error produces generic message", () => {
    const err = new Error("ECONNREFUSED 127.0.0.1:5432");
    expect(sanitizeErrorForClient(err))
      .toBe("An unexpected error occurred. Please try again.");
  });

  test("non-Error thrown value produces generic message", () => {
    expect(sanitizeErrorForClient("string error"))
      .toBe("An unexpected error occurred. Please try again.");
    expect(sanitizeErrorForClient(null))
      .toBe("An unexpected error occurred. Please try again.");
    expect(sanitizeErrorForClient(42))
      .toBe("An unexpected error occurred. Please try again.");
  });

  test("Supabase internal error does not leak", () => {
    const err = new Error(
      'relation "public.conversations" does not exist',
    );
    expect(sanitizeErrorForClient(err)).not.toContain("relation");
    expect(sanitizeErrorForClient(err)).not.toContain("public.");
  });
});
```

## References

- Issue: [#731](https://github.com/jikig-ai/soleur/issues/731)
- Discovered during code review of PR #722 (issue #679)
- Existing pattern: `KeyInvalidError` typed error class (`lib/types.ts`)
- Learning: `knowledge-base/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md`
- Correct pattern already in Stripe webhook: `app/api/webhooks/stripe/route.ts:25-27`
- Files to modify:
  - `apps/web-platform/server/error-sanitizer.ts` (new)
  - `apps/web-platform/test/error-sanitizer.test.ts` (new)
  - `apps/web-platform/server/agent-runner.ts` (lines 260-261)
  - `apps/web-platform/server/ws-handler.ts` (lines 136-138, 162-163, 189-190, 204-215)

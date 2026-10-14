---
title: "fix: sanitize error messages before sending to WebSocket client"
type: fix
date: 2026-03-20
semver: patch
closes: "#731"
deepened: 2026-03-20
---

# fix: sanitize error messages before sending to WebSocket client

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Problem Statement, Proposed Solution, Technical Considerations, Test Scenarios, MVP)
**Research sources:** security-sentinel review, code-simplicity review, ws library docs (Context7), codebase error surface audit

### Key Improvements

1. Discovered additional error leak in `ws-handler.ts:90` -- `createConversation` embeds raw Supabase `error.message` via string interpolation (`Failed to create conversation: ${error.message}`), which the `KNOWN_SAFE_MESSAGES` map cannot catch by exact match. The generic fallback handles it correctly, but this confirms the defense-in-depth approach is necessary.
2. Identified `byok.ts` configuration errors (`"BYOK_ENCRYPTION_KEY must be a 64-character hex string"`, `"BYOK_ENCRYPTION_KEY is required in production"`) that would leak server configuration details through the agent-runner catch block. These correctly fall through to the generic message.
3. Added test cases for interpolated error messages, `byok.ts` configuration leaks, and Anthropic SDK errors to strengthen the test suite.
4. Confirmed the `ws` library's close codes (1011 = "Unexpected condition") are already correctly used in the codebase and do not need changes.

### New Considerations Discovered

- The `createConversation` function in `ws-handler.ts:90` constructs errors with `Failed to create conversation: ${error.message}` -- any Supabase error detail (column constraints, RLS policy violations, connection errors) gets embedded. The sanitizer's generic fallback is the correct catch-all for these.
- The `startsWith("Unknown leader:")` prefix check is the right pattern for errors with interpolated content -- exact match would miss these.
- `ws-handler.ts` line 277 (`"Internal server error"`) is already correctly sanitized and requires no change.

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

### Research Insights: Error Surface Audit

**Additional error sources that flow through these catch blocks:**

| Error Source | Example Message | What Leaks |
|------|------|------|
| `ws-handler.ts:90` `createConversation` | `"Failed to create conversation: relation 'public.conversations' does not exist"` | Supabase schema details via string interpolation |
| `byok.ts:11` `getEncryptionKey` | `"BYOK_ENCRYPTION_KEY must be a 64-character hex string (32 bytes)"` | Server configuration requirements |
| `byok.ts:19` `getEncryptionKey` | `"BYOK_ENCRYPTION_KEY is required in production"` | Environment configuration details |
| `byok.ts:56` `decryptKey` | Node crypto errors (e.g., `"Unsupported state or unable to authenticate data"`) | Encryption implementation details |
| Anthropic SDK `query()` | SDK-specific errors (rate limits, auth failures, model errors) | API integration details |
| Supabase client | `"JWT expired"`, `"permission denied for table users"` | Auth and RLS policy details |

**Key insight:** The `createConversation` error at `ws-handler.ts:90` uses string interpolation (`Failed to create conversation: ${error.message}`), meaning the raw Supabase error is embedded in the thrown error's message. Exact string matching in `KNOWN_SAFE_MESSAGES` will not catch this -- it correctly falls through to the generic fallback. This validates the allowlist-with-fallback design: any unrecognized error produces a safe generic message.

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

### Research Insights: Missing Server-Side Logging

The `chat` catch block (line 161) and `review_gate_response` catch block (line 188) do NOT have `console.error` calls -- they silently swallow the raw error after sanitizing it. Only `start_session` (line 135) logs the raw error. Add `console.error` to the `chat` and `review_gate_response` catch blocks to ensure all errors are logged server-side before sanitization. Without this, debugging production issues in these paths becomes impossible since the sanitized client message strips all diagnostic detail.

## Technical Considerations

- **No breaking protocol changes.** The `WSMessage` error type keeps `message: string` and optional `errorCode: WSErrorCode`. Clients see different text, same shape.
- **`KeyInvalidError` is the precedent.** The existing typed error class pattern (from learning `2026-03-18-typed-error-codes-websocket-key-invalidation.md`) validates this approach: use `instanceof` for classification, not string matching.
- **Server-side logging is unchanged.** `console.error` at line 259 already logs the full error object including stack trace.
- **`ws-handler.ts` line 277 is already correct.** The unhandled error catch in the message handler already sends `"Internal server error"` -- no change needed.

### Research Insights: Security Best Practices

**OWASP Improper Error Handling (CWE-209):** The current code violates CWE-209 (Generation of Error Message Containing Sensitive Information). The fix follows the OWASP recommended pattern: log detailed errors server-side, return generic messages client-side. The allowlist approach (explicit safe messages, generic fallback) is more secure than a denylist approach (trying to filter out sensitive patterns) because new error sources automatically get the safe default.

**Allowlist vs. denylist tradeoff:** The `KNOWN_SAFE_MESSAGES` map is an allowlist -- only explicitly approved messages pass through. This is the correct security posture. A denylist (e.g., regex-filtering file paths, SQL keywords) would be fragile and require continuous maintenance as new error sources are added. The allowlist fails safe: unknown errors always produce the generic message.

**`instanceof` vs. string matching:** The plan correctly uses `instanceof KeyInvalidError` for typed error classes and exact string matching for known operational messages. This follows the learning from `2026-03-18-typed-error-codes-websocket-key-invalidation.md`: string matching is fragile and breaks silently when messages are reworded. For future error types that need client-side routing (similar to `KeyInvalidError`), create typed error classes rather than adding entries to `KNOWN_SAFE_MESSAGES`.

**WebSocket close codes:** The `ws` library supports standard close codes (1000=Normal, 1008=Policy Violation, 1011=Unexpected Condition). The current implementation does not use close codes for error signaling -- it sends error messages over the open connection and reserves close codes for connection lifecycle only. This is the correct separation of concerns and should not change.

## Non-Goals

- Structured error codes for every error type (e.g., `workspace_not_ready`, `conversation_not_found`). This is scope creep -- file a separate issue if needed.
- Client-side error display changes. The client already renders `message` as-is.
- Centralized error logging service. `console.error` is sufficient for the current scale.
- Refactoring `createConversation` in `ws-handler.ts:90` to use a typed error class instead of string interpolation. The generic fallback correctly handles it. A typed error class is only warranted if the client needs to distinguish this error for UX routing (like `KeyInvalidError` routes to `/setup-key`).

### Research Insights: Simplicity Review

**YAGNI assessment:** The `KNOWN_SAFE_MESSAGES` map and `sanitizeErrorForClient` function are minimal and justified. Each entry maps to a real error thrown in the codebase. The function is ~15 lines, has no external dependencies beyond `KeyInvalidError`, and requires no configuration.

**Avoided complexity:**

- No error classification hierarchy (single function, no class tree)
- No error telemetry or structured logging changes (out of scope)
- No client-side changes (message shape is unchanged)
- No regex-based filtering (allowlist is simpler and safer)
- The `redundant cast` `(err as Error).message` in the first code example (line 50 of the Proposed Solution) should be removed -- `KeyInvalidError extends Error`, so `err.message` works directly after `instanceof`. The MVP section already has this correct.

## Acceptance Criteria

- [x] No raw `err.message` is forwarded to WebSocket clients in `agent-runner.ts` or `ws-handler.ts`
- [x] `KeyInvalidError` retains its user-facing message and `errorCode: "key_invalid"`
- [x] Unknown errors produce a generic `"An unexpected error occurred. Please try again."` message
- [x] Known operational errors (workspace not provisioned, no active session, etc.) produce helpful but non-leaky messages
- [x] Server-side `console.error` continues logging full error details in `agent-runner.ts`
- [x] `console.error` added to `chat` and `review_gate_response` catch blocks in `ws-handler.ts` (currently missing)
- [x] New `error-sanitizer.ts` module has a corresponding test file
- [x] Existing `ws-protocol.test.ts` tests continue to pass
- [x] Interpolated errors (e.g., `createConversation` with embedded Supabase details) do not leak through to clients

## Test Scenarios

- Given a `KeyInvalidError`, when caught in `agent-runner.ts`, then client receives `"No valid API key found. Please set up your key first."` and `errorCode: "key_invalid"`
- Given a Supabase query error with internal details, when caught in `agent-runner.ts`, then client receives `"An unexpected error occurred. Please try again."`
- Given `"Workspace not provisioned"` error, when caught in `agent-runner.ts`, then client receives `"Your workspace is not ready yet. Please try again shortly."`
- Given a `createConversation` failure, when caught in `ws-handler.ts` start_session handler, then client receives sanitized message, not raw Supabase error
- Given an unknown error type (non-Error object thrown), when caught anywhere, then client receives `"An unexpected error occurred. Please try again."`
- Given a valid `msg.type` in the server-only type guard, when received from client, then error message uses a fixed string, not reflected input

### Research Insights: Additional Edge Cases

- Given a `byok.ts` configuration error (`"BYOK_ENCRYPTION_KEY must be a 64-character hex string"`), when caught in `agent-runner.ts`, then client receives `"An unexpected error occurred. Please try again."` (not the configuration details)
- Given an error with interpolated content (`"Failed to create conversation: permission denied for table conversations"`), when caught in `ws-handler.ts`, then client receives `"An unexpected error occurred. Please try again."` (interpolated Supabase details are not leaked)
- Given an Anthropic SDK rate limit error, when caught in `agent-runner.ts`, then client receives `"An unexpected error occurred. Please try again."` (not the SDK error details)
- Given a Node.js `crypto` `DecipherFinal` error from `byok.ts`, when caught in `agent-runner.ts`, then client receives `"An unexpected error occurred. Please try again."` (not crypto implementation details)
- Given an `AbortError` from the agent session being cancelled, when the `controller.signal.aborted` check is true, then no error is sent to the client at all (existing behavior, confirmed correct)

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

  test("interpolated createConversation error does not leak Supabase details", () => {
    const err = new Error(
      "Failed to create conversation: permission denied for table conversations",
    );
    expect(sanitizeErrorForClient(err)).not.toContain("permission denied");
    expect(sanitizeErrorForClient(err)).not.toContain("table");
    expect(sanitizeErrorForClient(err))
      .toBe("An unexpected error occurred. Please try again.");
  });

  test("byok configuration error does not leak server config", () => {
    const err = new Error(
      "BYOK_ENCRYPTION_KEY must be a 64-character hex string (32 bytes)",
    );
    expect(sanitizeErrorForClient(err)).not.toContain("BYOK");
    expect(sanitizeErrorForClient(err)).not.toContain("hex");
    expect(sanitizeErrorForClient(err))
      .toBe("An unexpected error occurred. Please try again.");
  });

  test("crypto decryption error does not leak implementation details", () => {
    const err = new Error(
      "Unsupported state or unable to authenticate data",
    );
    expect(sanitizeErrorForClient(err))
      .toBe("An unexpected error occurred. Please try again.");
  });

  test("SDK auth error does not leak API details", () => {
    const err = new Error("Invalid API Key");
    // This is NOT a KeyInvalidError, so it should get generic treatment
    expect(sanitizeErrorForClient(err))
      .toBe("An unexpected error occurred. Please try again.");
  });
});
```

## References

- Issue: [#731](https://github.com/jikig-ai/soleur/issues/731)
- Discovered during code review of PR #722 (issue #679)
- Existing pattern: `KeyInvalidError` typed error class (`lib/types.ts`)
- Learning: `knowledge-base/project/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md`
- Correct pattern already in Stripe webhook: `app/api/webhooks/stripe/route.ts:25-27`
- Files to modify:
  - `apps/web-platform/server/error-sanitizer.ts` (new)
  - `apps/web-platform/test/error-sanitizer.test.ts` (new)
  - `apps/web-platform/server/agent-runner.ts` (lines 260-261)
  - `apps/web-platform/server/ws-handler.ts` (lines 136-138, 162-163, 189-190, 204-215)

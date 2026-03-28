---
title: "refactor: extract shared WS_CLOSE_CODES constant"
type: refactor
date: 2026-03-28
---

# refactor: extract shared WS_CLOSE_CODES constant

WebSocket close codes (4001-4005) are duplicated across three locations with no shared source of truth. If a new code is added on the server and the client map is not updated, the client silently falls back to reconnect-with-backoff -- the exact bug fixed in #1221.

## Current State

Close codes appear in three files with three different shapes:

| File | Variable | Shape | Role |
|------|----------|-------|------|
| `apps/web-platform/server/ws-handler.ts` | inline literals | `ws.close(4001, "Auth timeout")` | Server sends close codes |
| `apps/web-platform/lib/ws-client.ts` | `NON_TRANSIENT_CLOSE_CODES` | `Record<number, { target?: string; reason: string }>` | Client routes on close codes |
| `apps/web-platform/test/accept-terms.test.ts` | `CLOSE_CODES` | `Record<string, number>` | Tests verify allocation consistency |

The server uses raw numeric literals (no named constant). The client maps codes to routing behavior. The test defines named keys but duplicates the numeric values.

## Proposed Solution

Define a single `WS_CLOSE_CODES` constant in `apps/web-platform/lib/types.ts` (where `WSMessage` already lives) and import it in all three locations.

### Constant Shape

```typescript
// apps/web-platform/lib/types.ts
export const WS_CLOSE_CODES = {
  AUTH_TIMEOUT: 4001,
  SUPERSEDED: 4002,
  AUTH_REQUIRED: 4003,
  TC_NOT_ACCEPTED: 4004,
  INTERNAL_ERROR: 4005,
} as const;
```

Use `as const` to narrow the type to literal numbers, enabling exhaustive switch checks downstream.

### Changes per File

**`apps/web-platform/lib/types.ts`** -- Add the `WS_CLOSE_CODES` constant after the existing `WSErrorCode` type.

**`apps/web-platform/server/ws-handler.ts`** -- Import `WS_CLOSE_CODES` and replace all inline numeric literals:

- `ws.close(4001, ...)` becomes `ws.close(WS_CLOSE_CODES.AUTH_TIMEOUT, ...)`
- `ws.close(4002, ...)` becomes `ws.close(WS_CLOSE_CODES.SUPERSEDED, ...)`
- `ws.close(4003, ...)` becomes `ws.close(WS_CLOSE_CODES.AUTH_REQUIRED, ...)`
- `ws.close(4004, ...)` becomes `ws.close(WS_CLOSE_CODES.TC_NOT_ACCEPTED, ...)`
- `ws.close(4005, ...)` becomes `ws.close(WS_CLOSE_CODES.INTERNAL_ERROR, ...)`

Note: `WS_CLOSE_CODES` is already partially imported via the existing `import { KeyInvalidError, type WSMessage, type Conversation } from "@/lib/types"` -- just add `WS_CLOSE_CODES` to that import.

**`apps/web-platform/lib/ws-client.ts`** -- Import `WS_CLOSE_CODES` and rewrite `NON_TRANSIENT_CLOSE_CODES` to use the shared keys instead of inline numeric literals:

```typescript
import { WS_CLOSE_CODES, type WSMessage, type ConversationContext } from "@/lib/types";

const NON_TRANSIENT_CLOSE_CODES: Record<number, { target?: string; reason: string }> = {
  [WS_CLOSE_CODES.AUTH_TIMEOUT]: { target: "/login", reason: "Session expired" },
  [WS_CLOSE_CODES.SUPERSEDED]: { reason: "Superseded by another tab" },
  [WS_CLOSE_CODES.AUTH_REQUIRED]: { target: "/login", reason: "Authentication required" },
  [WS_CLOSE_CODES.TC_NOT_ACCEPTED]: { target: "/accept-terms", reason: "Terms acceptance required" },
  [WS_CLOSE_CODES.INTERNAL_ERROR]: { reason: "Server error" },
};
```

The `NON_TRANSIENT_CLOSE_CODES` map stays in `ws-client.ts` because it contains client-specific routing behavior (target URLs, display reasons). Only the numeric code definitions move to `types.ts`.

**`apps/web-platform/test/accept-terms.test.ts`** -- Import `WS_CLOSE_CODES` and remove the local `CLOSE_CODES` constant. Update test references to use `WS_CLOSE_CODES`:

```typescript
import { WS_CLOSE_CODES } from "../lib/types";

describe("WebSocket close code allocation", () => {
  test("all close codes are unique", () => {
    const codes = Object.values(WS_CLOSE_CODES);
    expect(new Set(codes).size).toBe(codes.length);
  });

  test("all close codes are in the application-reserved range (4000-4999)", () => {
    for (const code of Object.values(WS_CLOSE_CODES)) {
      expect(code).toBeGreaterThanOrEqual(4000);
      expect(code).toBeLessThanOrEqual(4999);
    }
  });
});
```

## Acceptance Criteria

- [ ] `WS_CLOSE_CODES` constant exported from `apps/web-platform/lib/types.ts` with `as const`
- [ ] `apps/web-platform/server/ws-handler.ts` uses `WS_CLOSE_CODES.*` instead of inline numeric literals for all 7 `ws.close()` call sites (5 distinct codes, some used at multiple call sites)
- [ ] `apps/web-platform/lib/ws-client.ts` uses `WS_CLOSE_CODES.*` as computed property keys in `NON_TRANSIENT_CLOSE_CODES`
- [ ] `apps/web-platform/test/accept-terms.test.ts` imports and uses `WS_CLOSE_CODES` instead of defining a local constant
- [ ] No remaining inline 4001-4005 literals in the three files
- [ ] Existing tests pass (`bun test` from `apps/web-platform/`)

## Test Scenarios

- Given `WS_CLOSE_CODES` is defined in `types.ts`, when `accept-terms.test.ts` runs, then all codes are unique and in the 4000-4999 range
- Given a numeric close code is removed from grep output across all three files, when searching for `\b40(0[1-5])\b` in `.ts` files under `apps/web-platform/`, then only `types.ts` contains the numeric literals (all other files reference the constant)

## Enhancement Notes

**Deepened on:** 2026-03-28

### Relevant Institutional Learning

The learning at `2026-03-18-typed-error-codes-websocket-key-invalidation.md` established the pattern of placing typed WS protocol artifacts in `types.ts` specifically because it is a side-effect-free module (no `createClient()` calls at module load time). This reinforces the placement decision -- importing `WS_CLOSE_CODES` from `types.ts` will not trigger Supabase client initialization, which matters for test imports.

### Edge Case: `ws-client.ts` is a `"use client"` Module

`ws-client.ts` runs in the browser where the `ws` npm package is not available -- it uses the native browser `WebSocket` API. The `WS_CLOSE_CODES` constant must remain a plain object with no runtime dependencies (no imports from `ws`, no Node.js APIs). Since it is defined as a plain `as const` object in `types.ts` with no imports of its own, this is already safe. Worth verifying during implementation that no accidental Node.js-only import is added to `types.ts` as part of this change.

### Type Compatibility

The `ws` library's `close()` method signature accepts `code?: number`. TypeScript `as const` narrows values to literal types (e.g., `4001` not `number`), but literal number types are assignable to `number`, so `ws.close(WS_CLOSE_CODES.AUTH_TIMEOUT, ...)` will typecheck without widening.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal code refactoring.

## Context

Identified during architecture review of #1221 (chat reconnecting loop). The learning at `knowledge-base/project/learnings/2026-03-27-websocket-close-code-routing-reconnect-loop.md` documents the original bug where missing close code routing caused infinite reconnection. This refactoring ensures future close codes cannot drift between server and client.

## References

- Related issue: #1229
- Original bug fix: #1221
- Learning: `knowledge-base/project/learnings/2026-03-27-websocket-close-code-routing-reconnect-loop.md`

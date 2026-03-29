---
status: pending
priority: p3
tags: [testing, pre-existing]
file: apps/web-platform/test/ws-protocol.test.ts
---

# Fix silent assertion skipping in ws-protocol tests

## Problem

9 tests in `ws-protocol.test.ts` use `if (msg!.type === "session_started")` guards that silently pass when type narrowing fails. If `parseMessage` returned a wrong type, the inner `expect` calls would never execute.

## Fix

Replace `if` guards with explicit type assertions:

```typescript
// Before:
if (msg!.type === "session_started") {
  expect(msg!.conversationId).toBe("abc-123");
}

// After:
expect(msg!.type).toBe("session_started");
// Type narrowing happens via the assertion above
```

## Impact

Pre-existing issue, not introduced by this PR. Prevents tests from silently becoming no-ops.

## Source

Test design reviewer analysis of PR #1283.

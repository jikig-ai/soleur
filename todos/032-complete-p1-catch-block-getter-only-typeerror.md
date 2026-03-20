---
status: complete
priority: p1
issue_id: 864
tags: [code-review, correctness, error-handling]
dependencies: []
---

# Catch block cliState assignment throws TypeError on getter-only property

## Problem Statement

In `main.ts` line 32, the catch block does `healthState.cliState = "error"`. If `boot()` partially ran and installed the getter for `cliState` via `Object.defineProperty` (without a setter), this assignment throws TypeError in ESM strict mode, crashing the process entirely instead of gracefully reporting the error state.

## Findings

- **Flagged by:** data-integrity-guardian
- **Location:** `apps/telegram-bridge/src/main.ts:32` (catch block), `apps/telegram-bridge/src/index.ts:355` (getter installation)
- **Severity:** P1 — process crash on partial boot failure
- The `Object.defineProperty` calls in `boot()` do not include setters
- ESM modules use strict mode, where writing to getter-only properties throws TypeError
- If boot() succeeds at wiring `cliState` getter but fails later (e.g., `bot.start()` throws), the catch block crashes

## Proposed Solutions

### Option A: Defensive try/catch around the assignment (Recommended)

**Approach:** Wrap the catch block assignment in its own try/catch.

```typescript
} catch (err) {
  try { healthState.cliState = "error"; } catch { /* getter-only after partial boot */ }
  console.error("FATAL: Failed to load application:", err);
}
```

**Pros:** Minimal change, handles both pre-boot and post-boot failure paths.
**Cons:** Slightly ugly nested try/catch.
**Effort:** Small
**Risk:** Low

### Option B: Use Object.defineProperty in the catch block

**Approach:** Always use defineProperty to set the error state.

```typescript
} catch (err) {
  Object.defineProperty(healthState, "cliState", { value: "error", writable: true, configurable: true });
  console.error("FATAL: Failed to load application:", err);
}
```

**Pros:** Works regardless of whether a getter was installed.
**Cons:** More verbose.
**Effort:** Small
**Risk:** Low

## Recommended Action

Option A — defensive try/catch is simpler and communicates the intent clearly.

## Technical Details

**Affected files:**
- `apps/telegram-bridge/src/main.ts:31-34`

## Acceptance Criteria

- [ ] Catch block does not throw when cliState has a getter
- [ ] Health endpoint returns 503 with `cli: "error"` after import failure
- [ ] Process does not crash on partial boot failure

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-20 | Created from code review of PR #867 | data-integrity-guardian identified the strict-mode edge case |

---
status: complete
priority: p2
issue_id: "014"
tags: [code-review, reliability, race-conditions]
dependencies: []
---

# Fix typing indicator race conditions

## Problem Statement

The typing indicator system has several race conditions:
1. `startTurnStatus()` is fire-and-forget (`.catch()`), so `recordToolUse()` can be called before the status message exists
2. Concurrent calls to `cleanupTurnStatus()` can cause double-delete attempts
3. The `pendingEdit` setTimeout can fire after cleanup, editing a deleted message

## Findings

- **silent-failure-hunter**: HIGH -- "recordToolUse can run before turnStatus is initialized"
- **pattern-recognition-specialist**: "fire-and-forget promise pattern in startTurnStatus"
- **code-simplicity-reviewer**: "pendingEdit/setTimeout mechanism is over-engineered (YAGNI)"

## Proposed Solutions

### Option A: Simplify and guard (Recommended)
1. Make `startTurnStatus` synchronous-first: create the `turnStatus` object immediately with `messageId: 0`, send message async, update messageId on resolve
2. In `recordToolUse`, skip edits if `messageId === 0` (message not yet sent)
3. In `cleanupTurnStatus`, clear any pending setTimeout
4. Replace pendingEdit/setTimeout with simple time-check in `recordToolUse`:
```typescript
function recordToolUse(toolName: string): void {
  if (!turnStatus || turnStatus.messageId === 0) return;
  if (turnStatus.tools[turnStatus.tools.length - 1] !== toolName) {
    turnStatus.tools.push(toolName);
  }
  if (Date.now() - turnStatus.lastEditTime >= STATUS_EDIT_INTERVAL_MS) {
    flushStatusEdit();
  }
  // No setTimeout, no pendingEdit -- just skip if too soon
}
```
- **Effort**: Small
- **Risk**: Low -- simplifies code while fixing races

## Acceptance Criteria
- [ ] recordToolUse does not crash when called before status message is sent
- [ ] No setTimeout fires after cleanup
- [ ] Concurrent cleanupTurnStatus calls are safe
- [ ] pendingEdit mechanism removed (simplified)

## Work Log
- 2026-02-11: Identified during /soleur:review round 2

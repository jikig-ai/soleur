---
status: complete
priority: p3
issue_id: 864
tags: [code-review, quality, error-handling]
dependencies: []
---

# Wrap shutdown() in try/finally for robust cleanup

## Problem Statement

The `shutdown()` function in boot() calls `bot.stop()`, `cleanupTurnStatus()`, `cliProcess.kill()`, and `healthServer.stop()` sequentially. If `cleanupTurnStatus()` throws, remaining cleanup is skipped. Pre-existing behavior moved into boot() without change.

## Findings

- **Flagged by:** code-quality-analyst
- **Location:** `apps/telegram-bridge/src/index.ts:372-395`
- Only bot.stop() has a try/catch; other cleanup steps lack error handling

## Proposed Solutions

### Option A: Wrap in try/finally (Recommended)

**Approach:** `try { ...cleanup... } finally { process.exit(0); }` with individual try/catch for each step.

**Effort:** Small | **Risk:** Low

## Technical Details

**Affected files:** `apps/telegram-bridge/src/index.ts:372-395`

## Acceptance Criteria

- [ ] All cleanup steps execute even if one throws
- [ ] Process always exits after shutdown signal

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-20 | Created from code review of PR #867 | Pre-existing, moved into boot() by this PR |

---
status: pending
priority: p2
issue_id: 864
tags: [code-review, architecture, quality]
dependencies: []
---

# Refactor health state wiring from Object.defineProperty to callback pattern

## Problem Statement

The `boot()` function in `index.ts` uses `Object.defineProperty` to retroactively replace plain properties on the `healthState` object with live getters. This subverts TypeScript's type system — `HealthState` declares plain value properties, but at runtime they become accessor descriptors. The pattern is 20 lines of ceremony for wiring 4 values.

## Findings

- **Flagged by:** code-simplicity-reviewer, code-quality-analyst, architecture-strategist
- **Location:** `apps/telegram-bridge/src/index.ts:347-370`
- **Severity:** P2 (Medium) — works correctly but unnecessarily complex

## Proposed Solutions

### Option A: State-getter callback (Recommended)
Modify `createHealthServer` to accept `() => HealthState` instead of `HealthState`:
- **Pros:** Eliminates all `Object.defineProperty` calls, keeps HealthState type honest
- **Cons:** Changes `createHealthServer` API, requires updating test helper
- **Effort:** Small-Medium
- **Risk:** Low (test changes are mechanical)

### Option B: Accept current pattern
Keep `Object.defineProperty` with existing comments.
- **Pros:** Zero code changes
- **Cons:** Type dishonesty remains, 20 lines of unnecessary ceremony
- **Effort:** None
- **Risk:** None

## Recommended Action

(To be filled during triage)

## Technical Details

- **Affected files:** `apps/telegram-bridge/src/health.ts`, `apps/telegram-bridge/src/index.ts`, `apps/telegram-bridge/src/main.ts`, `apps/telegram-bridge/test/health.test.ts`
- **Components:** Health server, boot() function

## Acceptance Criteria

- [ ] `createHealthServer` accepts `() => HealthState` callback
- [ ] `Object.defineProperty` calls removed from boot()
- [ ] All 99 tests pass
- [ ] Typecheck passes

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-20 | Created from code review of PR #867 | 3 review agents flagged this pattern independently |

## Resources

- PR: #867
- Issue: #864

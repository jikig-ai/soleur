---
status: pending
priority: p3
issue_id: 864
tags: [code-review, testing]
dependencies: []
---

# No test coverage for main.ts entrypoint or boot() function

## Problem Statement

The core change in PR #867 (main.ts entrypoint, boot() Object.defineProperty wiring) has zero test coverage. Test design reviewer scored "First (TDD)" at 4/10.

## Findings

- **Flagged by:** test-design-reviewer
- **Location:** `apps/telegram-bridge/src/main.ts`, `apps/telegram-bridge/src/index.ts:343-409`
- index.ts has module-scope side effects (process.exit on missing env vars) making boot() hard to test in isolation
- The Object.defineProperty wiring that connects health state to bridge state is completely untested

## Proposed Solutions

### Option A: Integration test with env vars set

**Approach:** Set required env vars, import boot(), pass mock healthState, verify getters work.

**Effort:** Medium | **Risk:** Medium (side effects in module scope)

### Option B: Extract boot logic to testable module

**Approach:** Move the wiring logic out of index.ts to a pure function that can be tested without env var side effects.

**Effort:** Large | **Risk:** Medium

## Technical Details

**Affected files:** New test file needed

## Acceptance Criteria

- [ ] boot() Object.defineProperty wiring is tested
- [ ] Error path (import failure) is tested
- [ ] Health state reflects live bridge values after boot()

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-20 | Created from code review of PR #867 | Module-scope side effects inhibit testability |

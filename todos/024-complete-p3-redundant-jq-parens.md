---
status: pending
priority: p3
issue_id: "024"
tags: [code-review, quality]
dependencies: []
---

# Remove redundant double parentheses in jq expression

## Problem Statement

Line 451 of x-community.sh has `(($user.public_metrics.followers_count) // 0)` where the inner parentheses are unnecessary. `($user.public_metrics.followers_count // 0)` is equivalent. Appears in both the script and the test's JQ_TRANSFORM constant.

## Proposed Solutions

### Option 1: Remove inner parens

**Approach:** Change `(($user.public_metrics.followers_count) // 0)` to `($user.public_metrics.followers_count // 0)` in both script and test.

**Effort:** 2 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `plugins/soleur/skills/community/scripts/x-community.sh:451`
- `test/x-community.test.ts:175`

## Acceptance Criteria

- [ ] Redundant parens removed from script and test
- [ ] All tests pass

## Work Log

### 2026-03-13 - Initial Discovery

**By:** Code Review (pattern-recognition-specialist, code-simplicity-reviewer)

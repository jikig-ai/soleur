---
status: pending
priority: p3
issue_id: "023"
tags: [code-review, quality, testing]
dependencies: []
---

# Add missing test coverage for fetch-user-timeline and referenced_tweets

## Problem Statement

`cmd_fetch_user_timeline` has 3 validation tests but is missing coverage for: unknown flags, `--max` without value. Also missing a `replied_to` type test for `referenced_tweets` (the most common mention type). These gaps create asymmetry with the thorough `fetch-mentions` test suite.

## Findings

- Flagged by: pattern-recognition-specialist, code-quality-analyst, test-design-reviewer, architecture-strategist
- `fetch-mentions` has 6 validation tests; `fetch-user-timeline` has 3
- Missing: unknown flag test, --max without value test
- Missing: `replied_to` referenced_tweets jq test (only `retweeted` and `quoted` covered)
- Note: --max clamping tests (below 5, above 100) cannot be tested without API mocking since clamping proceeds to the API call

## Proposed Solutions

### Option 1: Add 3 tests

**Approach:** Add tests for: (1) unknown flag exits 1, (2) --max without value exits 1, (3) referenced_tweets with replied_to type.

**Effort:** 10 minutes
**Risk:** Low -- adding tests only

## Technical Details

**Affected files:**
- `test/x-community.test.ts`

## Acceptance Criteria

- [ ] Unknown flag test for fetch-user-timeline added
- [ ] --max without value test for fetch-user-timeline added
- [ ] replied_to referenced_tweets jq test added
- [ ] All tests pass

## Work Log

### 2026-03-13 - Initial Discovery

**By:** Code Review (4 agents converged)

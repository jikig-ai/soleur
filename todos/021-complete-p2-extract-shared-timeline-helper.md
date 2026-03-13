---
status: pending
priority: p2
issue_id: "021"
tags: [code-review, quality, architecture]
dependencies: []
---

# Extract shared helper for cmd_fetch_timeline / cmd_fetch_user_timeline

## Problem Statement

`cmd_fetch_user_timeline` (lines 506-558) and `cmd_fetch_timeline` (lines 464-504) share ~30 lines of identical logic: `--max` argument parsing, integer validation, 5-100 clamping, query params building, API call, and jq output. If the X API changes bounds or query params, the change must be applied in two places.

## Findings

- Flagged by: pattern-recognition-specialist, code-quality-analyst, code-simplicity-reviewer, architecture-strategist
- The only meaningful differences: (a) user_id source (positional arg vs resolve_user_id), (b) default max_results (5 vs 10)
- Query params string is identical: `tweet.fields=created_at,public_metrics,text&max_results=${max_results}`
- jq output transform is identical: `jq '.data // []'`

## Proposed Solutions

### Option 1: Extract `_fetch_tweets_for_user` helper

**Approach:** Create a shared internal function that takes `user_id` and `max_results`, builds query params, calls `get_request`, and pipes through jq. Both commands parse their own args and delegate the common tail.

**Effort:** 15 minutes
**Risk:** Low -- pure internal refactoring

## Technical Details

**Affected files:**
- `plugins/soleur/skills/community/scripts/x-community.sh:464-558`

## Acceptance Criteria

- [ ] Shared helper `_fetch_tweets_for_user` exists
- [ ] `cmd_fetch_timeline` delegates to helper after parsing args
- [ ] `cmd_fetch_user_timeline` delegates to helper after parsing args
- [ ] All 28 existing tests pass
- [ ] No behavioral change

## Work Log

### 2026-03-13 - Initial Discovery

**By:** Code Review (4 agents converged on this finding)

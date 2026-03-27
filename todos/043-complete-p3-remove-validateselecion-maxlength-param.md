---
status: pending
priority: p3
issue_id: 1195
tags: [code-review, quality]
dependencies: []
---

# Remove `maxLength` parameter from `validateSelection`

## Problem Statement

The `maxLength` parameter on `validateSelection` in `review-gate.ts` is YAGNI -- only used in one test case. Production code always uses `MAX_SELECTION_LENGTH`. The `options.includes()` check already rejects any oversized string.

## Findings

- **Source:** code-simplicity-reviewer
- **File:** `apps/web-platform/server/review-gate.ts:26`
- **Severity:** P3 (YAGNI, no functional impact)

## Proposed Solutions

1. Remove the `maxLength` parameter, hardcode `MAX_SELECTION_LENGTH` inside the function, remove the "respects custom maxLength" test.

## Acceptance Criteria

- [ ] `validateSelection` takes only `(options, selection)` -- no `maxLength` param
- [ ] "respects custom maxLength" test removed
- [ ] All existing tests pass

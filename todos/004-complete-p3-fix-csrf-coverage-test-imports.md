---
status: complete
priority: p3
issue_id: 945
tags: [code-review, quality]
dependencies: []
---

# Fix mixed imports and harden regex in csrf-coverage.test.ts

## Problem Statement

`csrf-coverage.test.ts` uses ES module imports at the top but `require()` inside `findRouteFiles`. Also, the POST handler detection regex misses synchronous handlers (`export function POST` without `async`).

## Findings

- **Source:** code-quality-analyst, test-design-reviewer
- **Location:** `apps/web-platform/lib/auth/csrf-coverage.test.ts:2-3,28-29,48-49`

## Proposed Solutions

### Option A: Fix both (Recommended)
1. Replace `require("fs")` / `require("path")` with top-level ESM imports
2. Use regex `/export\s+(async\s+)?function\s+POST/` instead of `includes("export async function POST")`
- **Effort:** Small
- **Risk:** Low

## Recommended Action

Option A.

## Technical Details

- **Affected files:** `apps/web-platform/lib/auth/csrf-coverage.test.ts`

## Acceptance Criteria

- [ ] No `require()` calls in the test file
- [ ] Regex matches both `async` and non-async POST handlers
- [ ] Tests pass

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-20 | Created | Found by code-quality-analyst and test-design-reviewer |

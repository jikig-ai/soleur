---
status: complete
priority: p2
issue_id: 945
tags: [code-review, quality]
dependencies: []
---

# Merge allowed-origins.ts into validate-origin.ts

## Problem Statement

`allowed-origins.ts` is 6 lines containing a single function that returns one of two hardcoded sets. It exists to share the allowlist between `resolve-origin.ts` and `validate-origin.ts`, but the abstraction adds cognitive overhead (extra file, extra import hop, extra test file) with minimal benefit. Multiple reviewers flagged this.

## Findings

- **Source:** code-simplicity-reviewer, code-quality-analyst, test-design-reviewer
- **Location:** `apps/web-platform/lib/auth/allowed-origins.ts`, `apps/web-platform/lib/auth/allowed-origins.test.ts`

## Proposed Solutions

### Option A: Inline into validate-origin.ts (Recommended)
Move the Set constants and `getAllowedOrigins()` into `validate-origin.ts`. Update `resolve-origin.ts` to import from `validate-origin.ts`. Delete `allowed-origins.ts` and `allowed-origins.test.ts`.
- **Pros:** -2 files, -21 LOC, simpler dependency graph
- **Cons:** `validate-origin.ts` grows by 3 lines
- **Effort:** Small
- **Risk:** Low

## Recommended Action

Option A.

## Technical Details

- **Affected files:** `allowed-origins.ts` (delete), `allowed-origins.test.ts` (delete), `validate-origin.ts` (add constants), `resolve-origin.ts` (update import)

## Acceptance Criteria

- [ ] `allowed-origins.ts` and `allowed-origins.test.ts` deleted
- [ ] `validate-origin.ts` exports `getAllowedOrigins()`
- [ ] `resolve-origin.ts` imports from `validate-origin`
- [ ] All tests pass

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-20 | Created | Consensus across 3 review agents |

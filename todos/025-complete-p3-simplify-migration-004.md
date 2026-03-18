---
status: pending
priority: p3
issue_id: "025"
tags: [code-review, quality, sql]
dependencies: []
---

# Simplify migration 004_add_not_null_iv_auth_tag.sql

## Problem Statement

The migration is 31 lines for 3 lines of effective SQL. The DO block safety check is redundant because PostgreSQL's `SET NOT NULL` already refuses to apply the constraint if null rows exist, producing a clear error: `ERROR: column "iv" of relation "api_keys" contains null values`. The comments are disproportionate to the code.

## Findings

- **Source**: code-simplicity-reviewer agent
- **Location**: `apps/web-platform/supabase/migrations/004_add_not_null_iv_auth_tag.sql`
- **Evidence**: PostgreSQL documentation confirms `SET NOT NULL` performs its own null-row validation. The DO block duplicates this built-in behavior for a marginally more descriptive error message visible only in deployment logs.
- **Impact**: Code clarity — migration reads like a design document instead of a migration

## Proposed Solutions

### Option A: Remove DO block, trim comments (Recommended)

Reduce to 6 lines: 3-line purpose comment + 3-line ALTER statement.

- **Pros**: Minimal, clear, no redundant code
- **Cons**: Loses custom error message (but Postgres default is clear enough)
- **Effort**: Small
- **Risk**: None — behavior unchanged

### Option B: Keep as-is

The DO block is "defense-in-depth" and other reviewers praised it.

- **Pros**: Explicit safety check, detailed documentation
- **Cons**: Over-engineered for a one-time migration, 81% of code is redundant
- **Effort**: None
- **Risk**: None

## Recommended Action

<!-- Filled during triage -->

## Technical Details

- **Affected files**: `apps/web-platform/supabase/migrations/004_add_not_null_iv_auth_tag.sql`
- **Components**: Database schema
- **Database changes**: None (migration behavior unchanged)

## Acceptance Criteria

- [ ] Migration file reduced to essential SQL with brief purpose comment
- [ ] `bun test` passes after changes

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review | PostgreSQL SET NOT NULL is self-validating |

## Resources

- PR #728
- Issue #681

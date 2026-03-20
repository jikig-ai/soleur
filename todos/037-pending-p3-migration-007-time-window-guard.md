---
status: pending
priority: p3
issue_id: "934"
tags: [code-review, architecture, data-integrity]
dependencies: []
---

# Add time-window guard to migration 007 as defense-in-depth

## Problem Statement

Migration 007 uses auth.users metadata as the sole discriminator for identifying fabricated tc_accepted_at rows. While correct and sufficient, adding a time-window guard (the ~3h20m bug window from PR #898 merge to PR #927 merge) would bound blast radius on migration replay (e.g., `supabase db reset`).

## Findings

- Architecture review recommends adding `AND public.users.created_at BETWEEN '2026-03-20T13:00:00Z' AND '2026-03-20T18:30:00Z'` as defense-in-depth
- The metadata check alone is sufficient for correctness — the time window is a safety rail
- Risk scenario: future bug clears metadata for a legitimate user, migration replay incorrectly nulls their timestamp
- No rows outside the bug window should have fabricated timestamps in the current database

## Proposed Solutions

### Option 1: Add time-window WHERE clause

**Approach:** Add `AND public.users.created_at BETWEEN '2026-03-20T13:00:00Z' AND '2026-03-20T18:30:00Z'` to the UPDATE.

**Pros:**
- Bounds blast radius on replay
- Zero false negatives for current data (all fabricated rows are within the window)

**Cons:**
- Slightly more complex query
- Could miss edge cases (delayed webhook processing after window close)

**Effort:** 15 minutes

**Risk:** Low

### Option 2: Leave as-is (metadata-only discriminator)

**Approach:** The current implementation is correct and sufficient.

**Pros:**
- Simpler query
- Handles any future fabricated rows regardless of creation time

**Cons:**
- Broader blast radius if metadata is ever corrupted

**Effort:** None

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `apps/web-platform/supabase/migrations/007_remediate_fabricated_tc_accepted_at.sql`

## Resources

- **PR:** #941
- **Related issue:** #934
- **Bug window:** 2026-03-20T14:07:57Z to 2026-03-20T17:28:27Z

## Acceptance Criteria

- [ ] Time-window guard added to WHERE clause (if approved)
- [ ] Migration remains idempotent
- [ ] No legitimate rows affected

## Work Log

### 2026-03-20 - Review Discovery

**By:** Claude Code (architecture-strategist agent)

**Actions:**
- Identified defense-in-depth opportunity during architecture review
- Assessed risk as P3 (nice-to-have, not blocking)

**Learnings:**
- Plan explicitly considered and deferred the time-window guard
- Metadata check is the authoritative discriminator

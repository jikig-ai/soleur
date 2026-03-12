---
status: complete
priority: p1
issue_id: "541"
tags: [code-review, scope-creep]
dependencies: []
---

# Revert out-of-scope stop-hook.sh code deletion

## Problem Statement

The diff deletes 17 lines of functional TTL-check code from `plugins/soleur/hooks/stop-hook.sh` and modifies a learnings file. This is a code change in a documentation-only competitive analysis PR. Without the TTL check, a crashed session's state file would persist indefinitely and trap subsequent sessions in the Ralph loop.

## Findings

- `plugins/soleur/hooks/stop-hook.sh`: 17 lines of TTL logic removed
- `knowledge-base/learnings/2026-03-09-ralph-loop-crash-orphan-recovery.md`: modified to say implementation "should" be done in a different worktree
- This mixes an unrelated behavioral change into a documentation PR

## Proposed Solutions

### Option 1: Revert both files to origin/main (Recommended)

**Approach:** `git checkout origin/main -- plugins/soleur/hooks/stop-hook.sh knowledge-base/learnings/2026-03-09-ralph-loop-crash-orphan-recovery.md`

**Pros:**
- Clean separation of concerns
- Preserves the shipped TTL feature
- No risk of regression

**Cons:**
- None

**Effort:** 1 minute

**Risk:** Low

## Technical Details

**Affected files:**
- `plugins/soleur/hooks/stop-hook.sh`
- `knowledge-base/learnings/2026-03-09-ralph-loop-crash-orphan-recovery.md`

## Acceptance Criteria

- [ ] stop-hook.sh matches origin/main
- [ ] learnings file matches origin/main
- [ ] No functional code changes remain in this documentation PR

## Work Log

### 2026-03-12 - Initial Discovery

**By:** Architecture, Simplicity review agents

**Actions:**
- Identified out-of-scope deletion of TTL logic from stop-hook.sh

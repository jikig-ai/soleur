---
status: complete
priority: p2
issue_id: "541"
tags: [code-review, accuracy]
dependencies: []
---

# Hedge Polsia revenue share claim in battlecard talk track

## Problem Statement

The Polsia battlecard talk track (line 57) asserts the 20% revenue share as definite, but the Quick Facts (line 15) and CI report hedge it as "may still apply." The talk track should match the hedged language to avoid inaccurate sales claims.

## Proposed Solutions

### Option 1: Update talk track to use hedged language (Recommended)

**Approach:** Change the definitive "takes 20%" to match the hedged "revenue share model may still apply (previously 20%)" used in Quick Facts.

**Effort:** 2 minutes

**Risk:** Low

## Technical Details

**Affected files:**
- `knowledge-base/sales/battlecards/tier-3-polsia.md` line 57

## Acceptance Criteria

- [ ] Talk track revenue share language matches Quick Facts hedging

## Work Log

### 2026-03-12 - Initial Discovery

**By:** Architecture review agent

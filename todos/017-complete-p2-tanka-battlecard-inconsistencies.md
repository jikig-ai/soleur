---
status: complete
priority: p2
issue_id: "541"
tags: [code-review, data-integrity]
dependencies: []
---

# Fix Tanka battlecard internal inconsistencies

## Problem Statement

The Tanka battlecard has three internal inconsistencies: (1) Quick Facts pricing updated but Differentiator Table still says "Free beta", (2) Convergence Watch header date is 2026-03-03 instead of 2026-03-12, (3) Talk Tracks and Objection Handling still reference "free beta."

## Findings

- Line 17 (Quick Facts): "$0/user/month for teams under 50; $299/month for teams 50+"
- Line 40 (Differentiator Table): "Free beta. Future pricing unknown." -- contradicts Quick Facts
- Line 74 (Convergence Watch header): "Current Status (2026-03-03)" -- should be 2026-03-12
- Lines 52, 68 (Talk Tracks/Objection Handling): still reference "free beta"

## Proposed Solutions

### Option 1: Fix all three inconsistencies (Recommended)

**Approach:** Update Differentiator Table pricing row, convergence watch date, and talk track/objection handling references to match Quick Facts.

**Effort:** 10 minutes

**Risk:** Low

## Technical Details

**Affected files:**
- `knowledge-base/sales/battlecards/tier-3-tanka.md` lines 40, 52, 68, 74

## Acceptance Criteria

- [ ] Differentiator Table pricing matches Quick Facts
- [ ] Convergence Watch header date is 2026-03-12
- [ ] Talk Tracks and Objection Handling reflect current pricing, not "free beta"

## Work Log

### 2026-03-12 - Initial Discovery

**By:** Architecture, Pattern review agents

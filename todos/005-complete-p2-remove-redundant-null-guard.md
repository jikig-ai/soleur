---
status: pending
priority: p2
issue_id: "477"
tags: [code-review, quality]
dependencies: []
---

# Remove redundant null/empty guard on retry_after in discord-setup.sh

## Problem Statement

`discord-setup.sh` has an extra null/empty guard on `retry_after` (lines 109-111) that the other two scripts lack. The `jq -r '.retry_after // 5'` with `|| echo "5"` already handles both null and jq failure cases, making the guard redundant. The inconsistency creates confusion about whether the guard is needed.

## Findings

- `discord-setup.sh:109-111` — extra `if [[ -z ]] || [[ == "null" ]]` guard
- `discord-community.sh` and `x-community.sh` — no such guard (correctly)
- `jq -r '.retry_after // 5'` handles null via `//` default
- `|| echo "5"` handles jq failure
- Found by: pattern-recognition-specialist, code-simplicity-reviewer, code-quality-analyst

## Proposed Solutions

### Option A: Remove the guard (Recommended)
- **Pros:** Consistent with siblings, removes dead code
- **Cons:** None — all cases already covered
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `plugins/soleur/skills/community/scripts/discord-setup.sh`
- **Lines:** 109-111

## Acceptance Criteria

- [ ] Null/empty guard removed from discord-setup.sh 429 handler
- [ ] Retry clamping block directly follows jq extraction

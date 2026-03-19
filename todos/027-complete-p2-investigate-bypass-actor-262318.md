---
status: pending
priority: p2
issue_id: 773
tags: [code-review, security]
dependencies: []
---

# Investigate Unknown Bypass Actor 262318

## Problem Statement

The CLA Required ruleset (ID 13304872) includes bypass actor `{ "actor_id": 262318, "actor_type": "Integration", "bypass_mode": "always" }`. This integration cannot be identified via the GitHub API (`gh api /apps/262318` returns 404) and is not in the org's installation list. An unidentifiable integration with bypass privileges on a security-critical ruleset is a concern.

## Findings

- `gh api /apps/262318` returns 404
- `gh api /orgs/jikig-ai/installations` lists only 2 apps: linear (42984725) and claude (107541094)
- The actor has `bypass_mode: "always"` -- full bypass privileges
- Pre-existing issue, not introduced by this PR
- Security-sentinel rated this HIGH priority

## Proposed Solutions

### Option A: File GitHub issue to investigate (Recommended)
Create a separate GitHub issue to track investigation and potential removal of this bypass actor.
- Pros: Tracked, out of scope for this PR
- Cons: Remains unresolved until investigated
- Effort: Small
- Risk: None

### Option B: Remove immediately
Remove actor 262318 from the ruleset in this PR.
- Pros: Eliminates unknown bypass path
- Cons: Could break something if the app is still active through a path we don't see
- Effort: Small
- Risk: Medium (unknown impact)

## Recommended Action

Option A -- file a separate GitHub issue

## Technical Details

- **Affected resource:** CLA Required ruleset (ID 13304872) bypass_actors array
- **Actor:** `{ "actor_id": 262318, "actor_type": "Integration", "bypass_mode": "always" }`

## Acceptance Criteria

- [ ] GitHub issue filed to investigate actor 262318
- [ ] Issue includes steps to reproduce the 404 and investigation suggestions

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Identified during PR #775 review | github-actions is a platform app (not installable), unknown apps return 404 |

## Resources

- PR #775
- Issue #773

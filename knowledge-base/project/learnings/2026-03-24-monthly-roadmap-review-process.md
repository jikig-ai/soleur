---
category: workflow
module: roadmap-review
tags: [roadmap, github-issues, consistency-review, gh-cli]
---

# Learning: Monthly Roadmap Consistency Review Process

## Problem
No documented process for monthly CPO roadmap review. Inconsistencies between roadmap.md and GitHub issues (wrong priority labels, wrong milestones, missing issues for "New" items) accumulate silently.

## Solution
Standard review procedure:
1. Read `knowledge-base/product/roadmap.md`
2. `gh api repos/owner/repo/milestones --jq '.[] | {number, title, open_issues}'`
3. `gh issue list --state open --limit 100 --json number,title,labels,milestone,updatedAt`
4. Cross-reference: for each roadmap item, find the issue and verify milestone + priority label match
5. Cross-reference: for each open issue in active milestones, verify it appears in roadmap.md
6. Apply automatic fixes (relabeling, milestone moves via `gh issue edit` and `gh api PATCH`)
7. Create missing issues for roadmap items marked "New"
8. Update `roadmap.md` with new issue numbers in a PR
9. Create summary review issue with label `scheduled-roadmap-review`

## Key Insight
`gh issue create --milestone` requires the milestone TITLE string, not the integer number. To assign a milestone by number, use the REST API:
```bash
gh api repos/OWNER/REPO/issues/N -X PATCH -f milestone=1
```

## Session Errors

**`gh issue create --milestone 1` failed with "milestone '1' not found"**
- Recovery: Used `gh api repos/.../issues/N -X PATCH -f milestone=1` after creation
- Prevention: When creating issues with milestone assignment, always use the two-step pattern: create first, then PATCH with the integer milestone number via the REST API. Alternatively, pass the milestone title string to `--milestone`.

## Session Summary (2026-03-24)

### What was done
1. Read `knowledge-base/product/roadmap.md`
2. Fetched all GitHub milestones (6 milestones) and open issues (47 total)
3. Cross-referenced every roadmap item against its corresponding GitHub issue (milestone assignment + priority label)
4. Cross-referenced every open issue against the roadmap (found untracked issues in active milestones)
5. Identified missing GitHub issues for roadmap items marked "New"

### Automatic fixes applied
- #673 relabeled `priority/p3-low` → `priority/p1-high` (roadmap specifies P1 for container isolation/rate limiting)
- #51 moved from Phase 2 milestone → Post-MVP (P3 investigation doesn't belong in a P1-gate milestone)
- Created 5 missing issues: #1075 (1.7), #1076 (3.5), #1077 (3.8), #1078 (3.13), #1079 (3.14)
- Updated `roadmap.md` with new issue numbers and `last_reviewed: 2026-03-24`

### Issues requiring owner decision
- #672 labeled p2-medium but covers P1 roadmap items (3.1-3.3)
- #682, #75, #1002, #1004 in active milestones but not tracked in roadmap.md
- #1071 has no milestone

### Review tracking
- Created review issue #1080 summarizing all findings

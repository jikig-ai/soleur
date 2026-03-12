---
status: pending
priority: p1
tags: [code-review, silent-failure, error-handling]
---

# Fallback issue creation failure causes silent data loss

## Problem Statement

When X posting fails AND the fallback issue creation also fails (e.g., GH_TOKEN expired, API rate limit), the script reports success. Content is completely lost with no record — the "both parachutes failed" scenario.

## Findings

- **Location:** `scripts/content-publisher.sh:156-166` (`create_x_fallback_issue` doesn't check `create_dedup_issue` return)
- **Flagged by:** silent-failure-hunter
- **Call chain:** post_x_thread fails → create_x_fallback_issue → create_dedup_issue fails → return 0 → script reports success
- Same issue exists for `create_partial_thread_issue` (line 168-180)

## Proposed Solutions

### Solution A: Check return code and fail hard (Recommended)
Check return code of `create_dedup_issue` in fallback functions. If the fallback issue cannot be created, return 1 so the workflow-level notification fires.

- **Pros:** Ensures at least one notification path succeeds
- **Cons:** None significant
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `scripts/content-publisher.sh`
- **Functions:** `create_x_fallback_issue`, `create_partial_thread_issue`

## Acceptance Criteria

- [ ] If fallback issue creation fails, function returns non-zero
- [ ] Script exits non-zero if both posting and fallback issue creation fail
- [ ] Workflow Discord failure notification fires as last-resort signal

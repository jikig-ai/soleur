---
status: pending
priority: p1
tags: [code-review, silent-failure, error-handling]
---

# post_x_thread always returns 0 — workflow failure notification never fires

## Problem Statement

Every failure path in `post_x_thread()` returns 0. The workflow's `failure()` step (Discord failure notification) will never fire for X/Twitter failures. The workflow shows a green checkmark even when X posting completely failed.

## Findings

- **Location:** `scripts/content-publisher.sh:208-251` (multiple `return 0` after error)
- **Flagged by:** silent-failure-hunter, code-quality-analyst
- **Severity:** HIGH/CRITICAL
- The workflow-level Discord failure notification is dead code for X failures
- Operators see green checks for broken X posting
- Script header says exit 0 = "All platforms posted (or gracefully skipped)" but there's no distinction

## Proposed Solutions

### Solution A: Track failures flag in main() (Recommended)
Add a `had_failures=0` variable. When `post_x_thread` or `post_discord` fail (after creating fallback issues), set `had_failures=1`. Exit with code 2 at the end if any platform had non-skip failures. Update workflow to also notify on exit code 2.

- **Pros:** Preserves graceful degradation per platform while surfacing partial failures
- **Cons:** Must verify workflow failure() condition covers exit 2
- **Effort:** Small
- **Risk:** Low

### Solution B: Return 1 from post_x_thread on failure
Let `post_x_thread` return 1 when posting fails (after creating fallback issue). Main catches with `|| had_failures=1`.

- **Pros:** Simpler, each function reports its own failure status
- **Cons:** Requires main() to aggregate return codes
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `scripts/content-publisher.sh`
- **Lines:** 216, 219, 228, 237, 244 (all `return 0` after error paths)

## Acceptance Criteria

- [ ] Script exits non-zero when any platform has a real failure (not just a skip)
- [ ] Workflow-level Discord failure notification fires on partial failures
- [ ] Graceful degradation preserved — all platforms still attempted even if one fails

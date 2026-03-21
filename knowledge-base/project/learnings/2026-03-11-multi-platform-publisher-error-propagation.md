# Learning: Multi-platform publisher error propagation

## Problem

When building a content publisher that posts to multiple platforms (Discord, X/Twitter, GitHub Issues), the natural pattern is to catch errors per platform, create a fallback issue, and `return 0` to continue with the next platform. This "graceful degradation" pattern has a critical flaw: if every failure path returns 0, the CI workflow always shows a green checkmark — even when every platform failed.

Six specific failure modes were discovered:

1. **Reply tweet stderr discarded** — `2>/dev/null` on body tweets meant 402 (Payment Required) errors were undetectable, producing generic "partial thread" fallback issues instead of payment-specific ones
2. **Always-green workflow** — `post_x_thread()` returned 0 on all failure paths, so the workflow's `failure()` notification step was dead code for X failures
3. **Double failure = silent data loss** — If posting fails AND fallback issue creation fails (GitHub API down), the script reports success with no record of the lost content
4. **Discord had no fallback** — X failures created GitHub issues; Discord failures only logged a warning
5. **No early dependency validation** — `x-community.sh` was referenced but not checked at startup; a missing file caused mid-execution failure after Discord had already posted
6. **No inter-tweet delay** — Rapid-fire API calls risked rate limit cascading

## Solution

### 1. Distinguish "skipped" from "failed"

Functions that skip due to missing credentials return 0 (genuine skip). Functions that attempted and failed return 1 (real failure). The caller tracks a `had_failures` flag:

```bash
local had_failures=0
post_discord "$content" || { create_discord_fallback_issue "$content" || had_failures=1; had_failures=1; }
post_x_thread "$file" || had_failures=1
```

### 2. Use exit code 2 for partial failure

```bash
# Exit codes:
#   0 - All platforms posted (or gracefully skipped)
#   1 - Fatal error (missing content file, invalid input)
#   2 - Partial failure (some platforms failed but fallback issues were created)
```

This lets the workflow's `failure()` condition fire on exit 2, sending the Discord notification about the partial failure.

### 3. Capture stderr on all API calls

Mirror the error-capture pattern across all API calls, not just the first one in a sequence. The hook tweet captured stderr to a temp file; reply tweets discarded it. Fix: capture stderr for all tweets so 402 errors are detected consistently.

### 4. Check fallback-of-fallback

When the fallback mechanism itself fails (issue creation error), return 1 so the workflow-level notification fires as a last resort.

## Key Insight

In multi-platform publishers, "graceful degradation" and "failure visibility" are in tension. The pattern of `catch error → create fallback → return 0` optimizes for continuation but kills observability. The fix: return 0 only for genuine skips (missing credentials), return 1 for real failures even when a fallback issue was created. Track failures at the caller level and exit non-zero so CI catches it.

**Rule of thumb:** A function that creates a fallback issue should return 1, not 0. The fallback issue records what to do about the failure; the non-zero return signals that something went wrong.

## Tags

category: integration-issues
module: ci-workflows, content-publisher

# Learning: CI workflow squash fallback bypasses merge protection gates

## Problem

Nine scheduled CI workflow files in `.github/workflows/scheduled-*.yml` contained a fail-open merge pattern:

```yaml
gh pr merge "$BRANCH" --squash --auto || gh pr merge "$BRANCH" --squash
```

The `--auto` flag correctly queues a merge that waits for all required status checks and branch protection rules to pass. However, the `|| gh pr merge "$BRANCH" --squash` fallback executes an immediate squash merge if `--auto` fails for any reason — including cases where it fails because required checks have not passed yet.

This created a security gap: if `--auto` returned a non-zero exit code (e.g., because a required status check was pending, the API was temporarily unavailable, or a ruleset blocked auto-merge), the fallback would attempt to force-merge the PR immediately, bypassing the very protection gates that `--auto` was designed to respect.

## Solution

Removed the fallback from all 9 workflow files with a single `sed` command:

```bash
sed -i 's/ || gh pr merge "$BRANCH" --squash$//' .github/workflows/scheduled-*.yml
```

The behavior shift is from **fail-open** (if auto-merge fails, merge anyway) to **fail-closed** (if auto-merge fails, the step fails, the workflow fails, and the existing Discord failure notification fires).

## Key Insight

**Shell `||` fallbacks in CI merge commands are fail-open security gaps.** The `||` operator means "if A fails, try B" — but in the context of merge protection, A failing is often the *intended behavior* (checks haven't passed yet). Falling back to an unguarded merge on failure inverts the security model: the protection gates become advisory rather than enforced.

The general principle: **any CI step that interacts with a protection gate must fail-closed.** When designing CI resilience against transient failures, use retry loops with the *same* command (preserving all safety flags) rather than fallback commands that drop safety constraints.

## Session Errors

None detected.

## Tags

category: security-issues
module: ci-workflows

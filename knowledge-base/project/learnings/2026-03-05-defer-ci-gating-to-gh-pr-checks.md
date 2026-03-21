---
category: integration-issues
module: ci-cd
date: 2026-03-05
---

# Learning: Defer CI Gating to gh pr checks

## Problem

When building a GitHub Actions workflow to auto-ship qualifying PRs, the initial approach included complex jq filtering of GitHub's `statusCheckRollup` GraphQL field to determine if required checks pass. This was overengineered and fragile.

## Solution

Use `gh pr checks <number> --required --fail-fast` as a separate verification step after PR selection. Let jq handle structural filtering (draft status, age, labels, base branch) and let the gh CLI handle CI status checking.

```bash
# jq handles structural filtering only
PR=$(gh pr list --state open --json number,createdAt,isDraft,labels,baseRefName --jq "...")

# gh CLI handles CI status checking
if ! gh pr checks "$PR" --required --fail-fast 2>/dev/null; then
  echo "Required checks not passing, skipping"
  exit 0
fi
```

## Key Insight

Before writing custom filtering logic for external tool state, ask: "Can the consuming tool check this itself?" GitHub CLI's `--required` flag respects the repository's branch protection configuration, making it both simpler and more correct than reimplementing the check in jq.

## Session Errors

- PreToolUse:Write security hook caught `${{ steps.select.outputs.pr_number }}` used directly in a `run:` block. Fixed by moving to `env:` variable indirection before the write was committed.

## Tags

category: integration-issues
module: ci-cd

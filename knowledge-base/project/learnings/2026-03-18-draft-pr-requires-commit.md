# Learning: draft PR creation requires at least one commit

## Problem

`gh pr create --draft` fails with "No commits between main and feat/..." when run immediately after creating a worktree branch, before any commits exist.

## Solution

Defer draft PR creation until after the first commit. The `worktree-manager.sh draft-pr` script should be called after initial implementation, not immediately after branch creation.

## Key Insight

GitHub API requires at least one commit difference between base and head branches to create a PR. Pipeline scripts that create draft PRs as a "placeholder" step must account for this ordering constraint.

## Tags

category: integration-issues
module: git-worktree

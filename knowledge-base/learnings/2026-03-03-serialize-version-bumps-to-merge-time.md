---
title: Serialize version bumps to merge-time CI
date: 2026-03-03
category: integration-issues
tags: [github-actions, versioning, merge-conflicts, ci]
module: .github/workflows
---

# Learning: Serialize version bumps to merge-time CI

## Problem

Parallel feature branches each bumping version files (plugin.json, CHANGELOG.md, README badge, marketplace.json, bug_report.yml) was the #1 source of merge conflicts — 14+ incidents over weeks. Even with "fetch and check main before bumping," two branches merging within minutes of each other would still collide.

## Solution

Move ALL version bumping out of feature branches into a single GitHub Action (`version-bump-and-release.yml`) that runs on `push: branches: [main]`. The Action:

1. Detects if plugin files changed (`git diff --name-only HEAD~1 -- plugins/soleur/`)
2. Parses PR number from squash-merge commit message `(#NNN)`
3. Reads `semver:*` label set by `/ship` skill during PR creation
4. Computes next version from current plugin.json
5. Extracts `## Changelog` section from PR body (temp files for input sanitization)
6. Auto-computes component counts via `find` commands
7. Updates all 6 files atomically, verifies consistency, commits, creates GitHub Release, notifies Discord

Key design decisions:
- **Concurrency group with `cancel-in-progress: false`**: Queues rather than races when multiple PRs merge quickly
- **Idempotency check**: Skips if the release tag already exists
- **Unified workflow**: Merges release creation + Discord notification into the bump workflow to avoid GITHUB_TOKEN cascade limitation (commits from GITHUB_TOKEN don't trigger other `on: push` workflows)
- **`workflow_run` trigger on deploy-docs**: Since the version bump commit won't trigger path-based push events, deploy-docs uses `workflow_run: workflows: ["Version Bump and Release"]` with a success check

## Key Insight

When N parallel branches each modify the same files, the solution is not "be more careful about ordering" — it's to move those modifications to a serialized chokepoint (merge-time CI). The concurrency group ensures only one version bump runs at a time, and the `find`-based counts always reflect the true filesystem state rather than stale branch baselines.

## Session Errors

1. Security hook blocked first workflow write — `${{ github.event.head_commit.message }}` in `run:` block is a command injection vector. Use `env:` variables for all GitHub context expressions.
2. `git add` on a `git rm`'d file fails — the file is already staged for deletion.

## Tags

category: integration-issues
module: .github/workflows

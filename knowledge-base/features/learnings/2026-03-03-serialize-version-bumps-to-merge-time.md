---
title: Tag-only versioning eliminates version file conflicts
date: 2026-03-03
category: integration-issues
tags: [github-actions, versioning, ci, git-tags]
module: .github/workflows
---

# Learning: Tag-only versioning eliminates version file conflicts

## Problem

The original `version-bump-and-release.yml` workflow updated 6 committed files (plugin.json, CHANGELOG.md, README badge, marketplace.json, bug_report.yml, plugin README) and pushed to main. This was blocked by the CLA Required ruleset since `github-actions[bot]` cannot be added as a bypass actor.

Even before the ruleset block, parallel feature branches bumping the same files was the #1 source of merge conflicts — 14+ incidents.

## Solution

Eliminate committed version files entirely. Version is derived from git tags via GitHub Releases API:

1. CI computes next version from `gh release view` (latest release tag), not `plugin.json`
2. CI creates a GitHub Release with `vX.Y.Z` tag via `gh release create` — this creates a tag on the existing commit without pushing new commits to main
3. Docs site fetches version and changelog from the GitHub Releases API at build time
4. `plugin.json` version is frozen to `0.0.0-dev` (sentinel)
5. `CHANGELOG.md` deleted — GitHub Releases is the changelog source of truth

Key design decisions:
- **`gh release view` over `gh release list`**: `gh release list` sorts by creation date; `gh release view` returns GitHub's "latest" release which respects semver ordering
- **CI vs local fallback in github.js**: In CI (`process.env.CI`), API failures are hard errors. In local dev, they produce a warning and empty data.
- **Concurrency group with `cancel-in-progress: false`**: Queues rather than races when multiple PRs merge quickly
- **Idempotency check**: Skips if the release tag already exists

## Key Insight

When CI needs to record metadata (version numbers, changelogs), prefer API artifacts (tags, releases) over committed files. Committed files require write access to protected branches and create merge conflicts. Git tags and GitHub Releases are created via API without touching `refs/heads/main`.

## Session Errors

1. `git add` on a `git rm`'d file fails — the file is already staged for deletion, so `git add` with the deleted path returns `fatal: pathspec did not match any files`. Stage only the modified files separately.
2. `gh release view` piped to `sed` needs a fallback `|| echo "0.0.0"` — when no releases exist, `gh release view` exits non-zero and the pipeline fails silently.

## Tags

category: integration-issues
module: .github/workflows

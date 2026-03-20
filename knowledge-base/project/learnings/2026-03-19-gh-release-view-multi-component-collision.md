# Learning: `gh release view` returns wrong tag in multi-component repos

## Problem

The "Version Bump and Release" workflow failed on every push to main with:

```
Invalid version components: MAJOR=web-v0 MINOR=1 PATCH=2 (from web-v0.1.2)
```

Four consecutive CI runs failed after component-specific release workflows (`web-v*`, `telegram-v*`) were introduced.

## Root Cause

`gh release view` without arguments returns the **latest release across all tag prefixes**. The plugin release workflow assumed it would only ever see `v*` tags, but once `web-v0.1.2` became the latest release, `sed 's/^v//'` stripped nothing (no leading `v`), leaving `web-v0.1.2` which failed numeric validation.

## Solution

Replace `gh release view` with `gh release list` + jq filter that selects only `v[0-9]*` tags:

```bash
LATEST_TAG=$(gh release list --limit 100 --json tagName --jq '
  [.[] | select(.tagName | test("^v[0-9]"))][0].tagName // empty
')
```

Falls back to `0.0.0` when no matching release exists (current state).

## Key Insight

When a monorepo uses multiple release tag prefixes (`v*`, `web-v*`, `telegram-v*`), any workflow using `gh release view` (unqualified) will break as soon as a non-matching prefix becomes the latest release. Always filter by tag pattern when looking up component-specific versions.

## Session Errors

1. Edited workflow file in bare repo path before creating worktree (worktree-write-guard should block this but bare repo has no working tree so git checkout to revert also failed)
2. Attempted `git checkout` in bare repo — failed with "fatal: this operation must be run in a work tree"

## Tags
category: build-errors
module: ci-release
tags: [github-actions, versioning, gh-cli, multi-component-releases, monorepo]
severity: high
first_seen: 2026-03-19

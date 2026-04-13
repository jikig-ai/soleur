---
title: "origin/main fallback stale ref in worktree-manager"
date: 2026-04-13
category: integration-issues
tags: [git-worktree, bare-repo, fetch-refspec, update-ref, stale-ref]
synced_to: plugins/soleur/skills/git-worktree/SKILL.md
---

# origin/main Fallback Stale Ref in worktree-manager

## Problem

In bare repos with multiple worktrees, `git fetch origin main:main` fails when `main` is checked out in any worktree. Git rejects the refspec update to protect the checked-out branch. The fallback command `git fetch origin main` only updates `origin/main` (the remote-tracking ref), leaving the local `refs/heads/main` stale.

This caused `worktree-manager.sh` to create new worktrees from a stale local `main` instead of the latest remote state.

## Root Cause

Git's safety mechanism prevents updating a branch ref that is checked out in any worktree. In a bare repo, `HEAD` points to `main`, making it always "checked out" from git's perspective. The two-step fetch (`fetch origin main:main` then fallback `fetch origin main`) was insufficient because the fallback only updates the remote-tracking ref.

## Solution

After the fallback fetch, force-sync the local ref using `git update-ref`:

```bash
git update-ref refs/heads/main origin/main
```

This bypasses git's checked-out protection by directly writing to the ref file. The `update_branch_ref()` function in `worktree-manager.sh` (lines 188-197) and the `cleanup-merged` function (lines 826-831) both implement this fallback chain.

## Related

- `worktree-manager-silent-creation-failure-20260410.md` -- documents worktree creation verification (related Sharp Edge bullet B)
- `2026-04-10-worktree-registration-verification-insufficient.md` -- documents post-creation verification requirements

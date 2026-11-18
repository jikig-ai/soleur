---
title: Apply-patch paths may resolve from the session root instead of an explicit worktree
date: 2026-10-22
category: workflow-patterns
tags:
  - worktrees
  - codex
  - apply-patch
  - filesystem
module: plugins/soleur
---

# Learning: apply-patch paths may resolve from the session root instead of an explicit worktree

## Problem

While continuing PR #9051, shell commands ran with the feature worktree as their
working directory, but `apply_patch` could not read a branch-only file when
passed its worktree-relative path. Its error showed it resolving the relative
path from the bare repository overlay. An absolute worktree path also failed for
that file.

## Cause

The patch tool's path base was not the `exec_command` working directory. Files
committed only on the feature branch were present in the worktree but absent
from the bare-root overlay, so the patch tool could not open them.

## Resolution

Read the target from the explicit worktree first. If `apply_patch` cannot access
it, make the edit with a bounded shell script whose `exec_command` has the
worktree as its working directory, and verify the exact diff afterward. Do not
fall back to editing the bare-root overlay or assume a failed patch changed the
worktree.

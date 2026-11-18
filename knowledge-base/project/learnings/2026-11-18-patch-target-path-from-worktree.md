---
title: "Ground patch targets in the active worktree"
date: 2026-11-18
category: workflow-issues
tags: [patch, worktree, file-edits]
related: []
---

# Learning: ground patch targets in the active worktree

## Problem

A patch was submitted with a placeholder directory instead of the active
worktree's path. The patch tool rejected the empty hunk, so no file changed.

## Solution

Check `pwd` and read the target file at the active worktree path before applying
a patch. Use that verified absolute path in the patch header.

## Key Insight

When a tool rejects an edit, confirm the failure left the tree unchanged before
retrying with a path grounded in the current worktree.

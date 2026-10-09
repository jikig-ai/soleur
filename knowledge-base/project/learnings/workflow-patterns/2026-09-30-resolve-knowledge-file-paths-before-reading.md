---
title: "Resolve knowledge-file paths from the tracked file list"
date: 2026-09-30
category: workflow-patterns
module: knowledge-base
---

## Problem

A read command used a guessed date in a learning filename and failed even
though the intended file existed under a different date.

## Prevention

Resolve knowledge-base examples with `rg --files <directory>` before opening
them. Do not infer a filename from a remembered date or title.

## Addendum — 2026-10-09 local test preparation

Two delegated test-file reads used relative paths after the working directory
changed. Both failed visibly and were corrected against the absolute feature
worktree before test selection. An optional runtime-discovery `ls` also returned
exit 2 because some supplied globs had no matches; guarded directory discovery
then established that no Node 22 binary was present in the checked locations.

Bind each batched read to an explicit absolute worktree or working directory.
Use guarded glob discovery for optional runtime locations and inspect each
probe's status independently; an absent candidate is not a test verdict.

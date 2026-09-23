---
title: "Git paths in worktree commands follow the selected working directory"
date: 2026-09-22
category: workflow-patterns
---

## Observation

A commit command ran from `apps/web-platform` while using repo-root-relative
paths, producing a warning and a pathspec failure. The tests and typecheck had
already completed successfully; the failure was command-context only.

## Rule

When a shell command changes `workdir`, use paths relative to that directory or
run Git mutations from the worktree root. Treat pathspec failures as command
errors, then rerun from the correct root after verifying status.

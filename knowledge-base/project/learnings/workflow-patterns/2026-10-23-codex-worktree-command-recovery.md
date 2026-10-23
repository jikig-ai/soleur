---
title: "Keep worktree commands explicit and match CLI flags to the command"
date: 2026-10-23
category: workflow-patterns
tags: [codex, worktree, shell, gitleaks, github-api]
symptom: "A chained shell command ended in a syntax error; gitleaks was passed Git's -C flag; a read-only GitHub API query timed out once."
root_cause: "A trailing && left an incomplete shell command, gitleaks git accepts the repository as a positional argument rather than -C, and the transient API connection failed during TLS setup."
---

# Keep worktree commands explicit and match CLI flags to the command

## What Went Wrong

- A shell command ended with `&&`, so Bash rejected it before execution.
- `gitleaks -C <path> git ...` used a Git global option with a CLI that does not support it.
- One read-only GitHub API request failed with a TLS handshake timeout.

## Recovery

- Run independent shell commands as separate commands, without a trailing operator.
- Use `gitleaks git --staged <repo-path>`; use `git -C <worktree>` for Git operations when the hook must resolve a linked worktree explicitly.
- Retry transient GitHub API reads once; keep the existing bounded CI watcher as the source of truth for asynchronous check state.

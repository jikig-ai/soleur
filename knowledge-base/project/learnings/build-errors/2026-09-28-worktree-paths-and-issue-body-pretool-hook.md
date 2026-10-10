---
title: Resolve worktree paths before batched reads and issue body hooks
date: 2026-09-28
category: build-errors
module: worktree-path-resolution
issues: ["#9140"]
---

## Problem

An audit used stale paths for the settings component and WebSocket resume test,
then the `gh issue create --body-file` pre-tool hook could not read a relative
path that existed in the current worktree. The hook resolves body files from
its repository root, which may differ from the shell's worktree CWD.

## Prevention

Use `rg --files` to establish exact paths before batched reads. Create an issue
body file in the worktree, confirm it is readable, and pass its absolute
worktree path to `gh issue create --body-file`.

Run package scripts from the package that defines them; repository-root npm
commands do not inherit app-level scripts.

For `gh pr checks --json`, the CLI exposes check `state` and `bucket`; it does
not expose a `conclusion` field. Query failures with `state` or inspect the
linked Actions job.

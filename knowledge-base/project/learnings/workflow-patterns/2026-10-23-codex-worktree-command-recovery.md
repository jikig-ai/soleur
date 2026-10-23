---
title: "Keep worktree commands explicit and match CLI flags to the command"
date: 2026-10-23
category: workflow-patterns
tags: [codex, worktree, shell, gitleaks, github-api, git-transport]
symptom: "A chained shell command ended in a syntax error; gitleaks was passed Git's -C flag; GitHub reads timed out; a push hit an HTTP/2 framing error; the local RLS harness reached a stale schema."
root_cause: "A trailing && left an incomplete shell command, gitleaks git accepts the repository as a positional argument rather than -C, transient HTTPS connections failed during TLS setup or HTTP/2 framing, and the existing local Postgres lacked the Codex generation column."
---

# Keep worktree commands explicit and match CLI flags to the command

## What Went Wrong

- A shell command ended with `&&`, so Bash rejected it before execution.
- `gitleaks -C <path> git ...` used a Git global option with a CLI that does not support it.
- One read-only GitHub API request failed with a TLS handshake timeout.
- A GitHub push failed with an HTTP/2 framing error; retrying over HTTP/1.1 succeeded.
- The local RLS harness connected to an existing Postgres that lacked `agent_engine_runs.auth_mode_generation`; setup rolled back and the live cases did not run.

## Recovery

- Run independent shell commands as separate commands, without a trailing operator.
- Use `gitleaks git --staged <repo-path>`; use `git -C <worktree>` for Git operations when the hook must resolve a linked worktree explicitly.
- Retry transient GitHub API reads once; keep the existing bounded CI watcher as the source of truth for asynchronous check state.
- Retry GitHub pushes with `git -c http.version=HTTP/1.1 push` when the HTTP/2 framing layer fails.
- Do not migrate a local database whose disposable status is unknown. Run live RLS cases only against a disposable database with the required migration set.

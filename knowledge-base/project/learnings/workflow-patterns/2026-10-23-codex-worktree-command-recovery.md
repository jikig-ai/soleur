---
title: "Keep worktree commands explicit and match CLI flags to the command"
date: 2026-10-23
category: workflow-patterns
tags: [codex, worktree, shell, gitleaks, github-api, git-transport, process-monitoring]
symptom: "A chained shell command ended in a syntax error; gitleaks was passed Git's -C flag; GitHub reads timed out; a push hit an HTTP/2 framing error; the local RLS harness reached a stale schema; polling an already-finished shell session lost its exit status; a commit hook saw the session's main-branch context and an unscoped status ran from the bare root; cleanup using `rm -f` was rejected by the command guard."
root_cause: "A trailing && left an incomplete shell command, gitleaks git accepts the repository as a positional argument rather than -C, transient HTTPS connections failed during TLS setup or HTTP/2 framing, the existing local Postgres lacked the Codex generation column, completed exec sessions cannot be resumed for a final status, Git commands without explicit -C can inherit the harness CWD instead of the selected worktree, and the command guard rejects `rm -f` patterns."
---

# Keep worktree commands explicit and match CLI flags to the command

## What Went Wrong

- A shell command ended with `&&`, so Bash rejected it before execution.
- `gitleaks -C <path> git ...` used a Git global option with a CLI that does not support it.
- One read-only GitHub API request failed with a TLS handshake timeout.
- A GitHub push failed with an HTTP/2 framing error; retrying over HTTP/1.1 succeeded.
- The local RLS harness connected to an existing Postgres that lacked `agent_engine_runs.auth_mode_generation`; setup rolled back and the live cases did not run.
- Waiting on a completed shell session returned `Unknown process id` after its final output, so the exit code was no longer available.

## Recovery

- Run independent shell commands as separate commands, without a trailing operator.
- Use `gitleaks git --staged <repo-path>`; use `git -C <worktree>` for Git operations when the hook must resolve a linked worktree explicitly.
- Retry transient GitHub API reads once; keep the existing bounded CI watcher as the source of truth for asynchronous check state.
- Retry GitHub pushes with `git -c http.version=HTTP/1.1 push` when the HTTP/2 framing layer fails.
- For long shell tests, capture and print the exit code in the original command; after final output, do not poll a session that may already have exited. Keep `ps` output to fixed columns because a single process argument can be enormous.
- Do not migrate a local database whose disposable status is unknown. Run live RLS cases only against a disposable database with the required migration set.
- In Codex, use `git -C <absolute-worktree>` for every Git operation that depends on the selected worktree, including commits and follow-up status checks; a shell `workdir` alone did not satisfy the commit guard's branch context in this session.
- For a known temporary file when `rm -f` is rejected, use an existence-checked `Path.unlink(missing_ok=True)` rather than retrying a force-removal command.

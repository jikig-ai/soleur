# Learning: Chromium zombie processes in Docker containers without --init

## Problem

When spawning Playwright Chromium inside a Docker container via a `detached: true` Node.js child process, then killing the process group with `SIGTERM` + `SIGKILL` escalation (ADR-033 I3 pattern), chrome zygote child processes become `<defunct>` zombies reparented to PID 1. Without `--init` (tini), Node.js as PID 1 does not reap adopted children.

## Solution

Two valid approaches:
1. **Docker `--init` flag** (preferred): adds tini as PID 1, which automatically reaps all zombie children. Verified: zero orphan chrome processes with `--init`.
2. **Handler-level reaper**: after SIGKILL escalation, enumerate and waitpid any remaining children of the killed process group.

For the Soleur Hetzner deployment (`ci-deploy.sh`), the `docker run` commands do NOT currently use `--init`. This means zombie chrome processes accumulate (one set per monthly cron fire for the UX audit handler).

## Key Insight

`kill(-pid, SIGTERM)` on a detached process group kills the main process and direct children, but chrome's zygote processes (`--type=zygote`) create their own process groups. They receive the signal and die, but become zombies because their exit status is never collected by any `waitpid()` call — Node.js (PID 1) does not reap adopted children. The fix is structural (tini as PID 1) rather than per-handler (process tree enumeration).

## Session Errors

1. **Docker build: "Tracker idealTree already exists"** — `npx playwright@1.58.2 install` at image root leaves npm cache state that blocks a subsequent `npm install` in the same layer. Prevention: use `npm init -y` before installing packages in a fresh WORKDIR, or separate into distinct Dockerfile stages.
2. **playwright-core `browser.process()` undefined** — the API is `browser.process()` on `@playwright/test` but not on `playwright-core`. Prevention: use `child_process.spawn` with `detached: true` to model the real handler pattern instead of Playwright's internal process access.
3. **`git add` from bare repo root fails in worktree** — bare repo root has synced tracked files but git operations must run from the worktree directory. Prevention: always prefix git commands with the worktree absolute path or cd into it.

## Tags
category: runtime-errors
module: apps/web-platform/Dockerfile, ci-deploy.sh

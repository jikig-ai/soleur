---
title: "Concierge Bash runs in a frozen bwrap sandbox; file tools run in-process — a file-vs-Bash path asymmetry is a MOUNT-visibility bug, not a CWD bug"
date: 2026-06-15
category: integration-issues
tags: [bwrap, sandbox, mount-namespace, bash, worktree, cwd, agent-runner, web-platform, diagnosis]
module: apps/web-platform/server (agent-runner sandbox)
issue: 5313
parent_epic: 5240
related_pr: 5311
---

# Learning: Concierge Bash sandbox mount-visibility vs. CWD persistence

## Problem

A production Concierge session ("Fix Issue 4826") created a git worktree, then hung in a
"rebind loop": every Bash `pwd` returned `/home/soleur`, Bash could not `ls /workspaces/<uuid>/`
or `git -C <worktree>`, yet Read/Edit/Grep/Glob read the repo fine. The one-shot CWD-verification
gate (`cd <worktree> && pwd` must equal the worktree path) could never pass; the agent looped
`pwd && git branch --show-current && git log` 4+ times and died with "Agent stopped responding."

The intuitive diagnosis — "Bash CWD didn't persist / `EnterWorktree` didn't move the CWD" — is
**wrong** and sends you down the existing `2026-05-16-bash-cwd-persists-across-tool-calls.md` /
`2026-05-15-one-shot-plan-subagent-cwd-divergence.md` path, which does not explain why Bash
cannot even `ls` the workspace.

## Root Cause (code-verified)

The Concierge runs Bash and file tools in **two categorically different execution contexts**:

- **File tools (Read/Edit/Grep/Glob/LS)** execute **in-process** in the Claude Code CLI (Node
  `fs`). They have full container filesystem visibility, including the `/workspaces` bind-mount.
  They are guarded only by an in-process PreToolUse path check (`sandbox-hook.ts`), NOT by bwrap.
- **Bash** executes inside a **bubblewrap (`bwrap`) sandbox** whose mount namespace and working
  directory are **frozen once per SDK `query()` call**:
  - `apps/web-platform/server/agent-runner-query-options.ts:149` — `cwd: args.workspacePath`, set
    once at session start, never re-derived mid-session.
  - `apps/web-platform/server/agent-runner-sandbox-config.ts:94` — `denyRead: ["/workspaces",
    "/proc"]`; only the specific `allowWrite: [workspacePath]` is mounted into the namespace (the
    `/workspaces` parent is excluded for cross-tenant isolation).
- **`EnterWorktree` is an SDK-native Claude Code tool with NO Soleur server-side handler.** It
  flips a logical/file-tool CWD notion but **cannot rebind the bwrap mount or the Bash subprocess
  cwd**. A worktree created after session start (separate working tree + a `.git` pointer into the
  bare repo's gitdir) is therefore unreachable from Bash even though file tools see it.

`/home/soleur` is the container HOME (`Dockerfile` `useradd ... soleur`, UID 1001), passed through
to the agent env allowlist. When bwrap can't `chdir` to the requested path it falls back to `$HOME`.

## Key Insight

**A file-tool-vs-Bash filesystem asymmetry in the Concierge is a sandbox MOUNT-VISIBILITY problem,
not a CWD-persistence problem.** Diagnostic rule: if Read/Edit can see a path but Bash cannot
`ls`/`cd`/`git -C` it (and `pwd` is pinned to `/home/soleur`), look at the bwrap mount set
(`agent-runner-sandbox-config.ts`) and the per-`query()` `cwd` (`agent-runner-query-options.ts`),
NOT at CWD persistence across calls. The two tool classes do not share a filesystem view.

Corollary: any agent gate that asserts "Bash is in directory X" (the one-shot/plan CWD-verification
gate, `one-shot/SKILL.md:70-76`) must be **bounded and fail-loud** — it currently says "abort on
mismatch" but has no retry ceiling, so a structurally-unsatisfiable gate loops until the turn dies.
Bound it (~3 attempts) → raise an explicit error → Sentry + honest status; never silently loop.

## Tags

category: integration-issues
module: apps/web-platform/server (agent-runner sandbox)

## Session Errors

Session error inventory: none detected. (Brainstorm + investigation session; correct routing,
clean worktree/PR/sub-issue creation, three research agents returned without error.)

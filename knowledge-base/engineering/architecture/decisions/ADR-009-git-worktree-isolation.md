---
adr: ADR-009
title: Git Worktree Isolation
status: active
date: 2026-03-27
---

# ADR-009: Git Worktree Isolation

## Context

Need isolated branches for parallel feature development without conflicts on main. Repo uses core.bare=true where git pull and git checkout are unavailable from root.

## Decision

Never commit directly to main (hook-enforced). Create worktrees via `git worktree add .worktrees/feat-<name> -b feat/<name>`. At session start, run cleanup-merged. Never git stash in worktrees (commit WIP first). Never rm -rf on worktree paths (hook-enforced). MCP tools resolve paths from repo root — always pass absolute paths.

## Consequences

Clean parallel development with isolation of the **working tree**. Hook enforcement prevents accidental main commits. worktree-manager.sh handles lifecycle (create, cleanup-merged, draft-pr). All PreToolUse hooks block destructive operations on worktrees.

### Amendment (2026-07-15) — the isolation is of the working tree, NOT of process-level scratch

This section previously read "full isolation". That is **too strong, and a reader acting on
it will be wrong**: a worktree isolates files under version control. It does **not** isolate
anything a session writes outside the tree, and `/tmp` is a single namespace **shared by every
worktree on the machine**. Concurrent sessions are this repo's normal state (14 worktrees were
live when this was written), so a scratch path derived from a stable input — a script name, an
issue name — is a pure function of that input and collides **by construction**.

Observed 2026-07-15: a full-suite run's log was truncated mid-run by a sibling session and came
back holding a *different* worktree's absolute paths. The run's own exit code was still
correct; the **log** was not. The dangerous inverse is reading a sibling's green log and
concluding your own run passed — an isolation claim that quietly does not extend to the
artifact you are reading.

**The rule this implies, by concurrency domain:**

- **`mktemp`** when the artifact is consumed inside one Bash call, or by agents sharing a
  worktree. Parallel review agents share ONE worktree, so a worktree-scoped path does **not**
  separate them — only a per-invocation unique path does. `$$` is not a substitute
  (predictable across concurrent runs in shared shells).
- **A git-dir / workspace-scoped path** (`"$(git rev-parse --git-dir)"`) when a *later,
  separate* Bash call must find the artifact **by name** — separate calls do not inherit env,
  and the git dir is both stable across them and distinct per worktree.

Enforced for agent-facing guidance by `plugins/soleur/test/scratch-path-collision.test.ts`.
That guard scans `skills/*/SKILL.md` only; scratch paths an agent improvises at runtime are
outside its reach and remain a known gap.

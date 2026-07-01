---
title: "git 'could not lock config file … File exists' is a stale lock, not a mount/permission problem"
date: 2026-07-01
category: bug-fixes
module: git-worktree
tags: [git, worktree, agent-sandbox, concierge, eexist, stale-lock, diagnosis]
pr: 5880
---

# Learning: `File exists` from git config is a stale lock, not a bind-mount

## Problem

Concierge (the Soleur web app) ran agents in a bwrap sandbox. After the
2026-07-01 seccomp outage, worktree creation began failing permanently on
affected workspaces. The in-sandbox agent's pasted debug stream concluded the
cause was: "`.git/config` is bind-mounted at the sandbox level, so any write
attempt fails with 'File exists'." Every subsequent `git config` / `git worktree
add` failed with `could not lock config file .git/config: File exists`.

## Root Cause

The debug stream's self-diagnosis was **wrong**. Reading the actual sandbox code
(`apps/web-platform/server/agent-runner-sandbox-config.ts:213-221`) showed the
bwrap config binds the **entire workspace read-write** (`allowWrite:
[workspacePath]`). `.git/config` lives inside that dir, so writes to it are
permitted — there is no per-file bind mount of `.git/config`.

`File exists` (EEXIST) is git's exact signature for a **stale lock file**: git
writes `config.lock`, then renames it over `config`. If the `git config` / `git
worktree add` process is **killed mid-write** (which the seccomp outage did to
every git call via `unshare` EPERM), the `.git/config.lock` is left behind on the
mounted `/workspaces` volume. After git was restored, the stale lock persisted on
disk, so every later config write failed EEXIST **forever**. Worktree creation is
the first config-writer in a session, so it broke first.

Confirmed gap: no stale-git-lock cleanup existed anywhere in the tooling.

## Solution

Add an **age-guarded** `sweep_stale_git_locks()` to
`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`, called from
`ensure_bare_config()` **before** its first `git config` write. It removes
`config.lock` / `config.worktree.lock` older than 60s (mtime vs now; future-dated
= fresh, clock-skew guard mirroring `cleanup_merged_worktrees`). Because
`ensure_bare_config` is the chokepoint on every create path AND the session-start
`cleanup-merged` path, an affected workspace **self-heals on its next session** —
no operator SSH into the live volume. The fix is entirely in the worktree tooling;
the bwrap/tenant-isolation layer is untouched.

## Key Insight

1. **`git ... : File exists` == stale `*.lock`, not a filesystem/permission/mount
   fault.** Reach for `rm` of the stale lock (age-guarded), not a mount change.
2. **An agent's hypothesis in a pasted debug stream is a hypothesis, not a
   diagnosis.** The Concierge agent's "bind-mounted config" theory would have sent
   a fix into the tenant-isolation layer (a red herring, and a dangerous surface).
   Verifying against the actual sandbox code + git error semantics before
   implementing found the real, far cheaper cause.
3. **`git config`/`git worktree add` on a bare repo write the shared config
   unavoidably**, so the wedge cannot be dodged at the script level by skipping
   *our* writes — the durable fix is to clear the stale lock before any write.
4. **Review lens (index/HEAD live-lock trap):** the first cut swept `index.lock`
   and `HEAD.lock` "for completeness." `user-impact-reviewer` caught that on a
   **non-bare** `git_dir` those are the *live* working-tree locks a concurrent
   >60s commit/rebase legitimately holds — sweeping them adds live-clobber risk
   with zero wedge-fix value (they never block a config write). Scope a
   destructive sweep to exactly the failure class it fixes; do not include
   "harmless-looking" siblings that are load-bearing on another layout.

## Session Errors

- **Unauthored plan-file edits appeared mid-draft** (planning subagent) — a
  "Lock-file set (revised per CTO)" heading showed up the subagent hadn't
  written; transient concurrent-writer / harness re-entry. Recovery: re-read
  before each edit; final file coherent, no stray artifacts. **Prevention:** on
  resume/handoff, re-read an artifact before editing (already standard); one-off.
- **`test-all.sh` full-suite gate was killed mid-run twice** under background
  execution before emitting its summary. Recovery: re-ran foreground with
  `timeout 560 bash scripts/test-all.sh > log; rc=$?` + grep for the
  `=== N/N suites passed ===` line (green, 139/139). **Prevention:** for the long
  vitest+shell suite, prefer a foreground `timeout` run with explicit `rc`
  capture over trusting a backgrounded "exit 0" (mirrors
  [2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness]);
  environmental one-off, no code fix.
- **Plan file "modified on disk since last read"** during a checkbox `Edit`
  (concurrent `sed` flip + subagent write). Applied cleanly. **Prevention:**
  benign; one-off.

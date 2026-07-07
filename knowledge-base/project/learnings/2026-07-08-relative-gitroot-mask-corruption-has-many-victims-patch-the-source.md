---
title: "A mask-corrupted RELATIVE GIT_ROOT has many downstream victims — normalize it once at the source, not each victim; and verify_worktree_created was silent"
date: 2026-07-08
category: bug-fixes
module: git-worktree
issue: 5934
tags: [git-worktree, gitroot, relative-path, char-device, mask-degraded, verify-worktree, telemetry, observability, patch-the-source, round-3]
synced_to: [review, git-worktree]
---

# Learning: the relative-GIT_ROOT mask corruption is a SOURCE bug with many victims; patch the source

## Context (round 3 on #5934)

The Concierge workspace is a NON-bare clone whose `.git/config` family is masked by a
char-device / bind-mount in the agent sandbox. Under that mask git's plumbing DEGRADES:
`git rev-parse --git-common-dir` hands back the RELATIVE string `.git`, and
`git -C .git rev-parse --is-bare-repository` falsely reports `true` (running from inside a
`.git` dir looks bare when the config can't be read). PR #6206 (merged 2026-07-07) fixed
`ensure_bare_config` to SKIP its bare surgery in this case — correct, but the failure just
moved DOWNSTREAM to the next consumer of the same corrupted value.

## Root cause

In `worktree-manager.sh`'s init block the non-bare `else` branch set
`GIT_ROOT="$_common_dir"` = the relative `.git` (the `*/.git` strip can't match a
slash-less string), so `WORKTREE_DIR=".git/.worktrees"` (relative). `create_for_feature`
runs from the workspace root and `git worktree add` succeeds, but `verify_worktree_created`
then compares the RELATIVE expected path against git's ABSOLUTE `--show-toplevel` and dies:
`Worktree path mismatch — expected .git/.worktrees/feat-…, got /workspaces/…/.git/.worktrees/feat-…`.
Same location, relative-vs-absolute — a pure path-normalization bug.

## The two lessons

1. **A corrupted value has MANY victims — patch the SOURCE, not each victim.** The relative
   `GIT_ROOT` had already claimed `ensure_bare_config` (round 2, #6206) and `WORKTREE_DIR` +
   `verify_worktree_created` (round 3). Patching victims one at a time is a treadmill. The fix
   normalizes `GIT_ROOT` to ABSOLUTE ONCE at init, so EVERY downstream consumer
   (`WORKTREE_DIR`, `copy_env_files`, `ensure_bare_config`, `verify_worktree_created`) gets an
   unambiguous path. Two layers: (a) resolve `_common_dir` to absolute BEFORE the `*/.git`
   strip so the strip yields the true workspace ROOT (sibling `.worktrees`, not a path buried
   inside `.git`); (b) a final `ensure_git_root_absolute` safety net after the branch that
   normalizes ANY relative root against `$PWD` and falls back to `$PWD` when empty. Verified
   non-regressing for: masked non-bare (the live case), genuine bare (local dev + CI), linked
   worktree of a bare repo, and a normal unmasked clone (where `git -C .git is-bare` returns
   `false`, so the misclassification never fires).

2. **`verify_worktree_created` was SILENT to every sink.** The round-2 wedge could only be
   diagnosed from the operator's pasted error — the failure printed `echo -e` colorized text
   to stderr, invisible to the git-lock-marker telemetry scanner (stdout, server-side pino →
   Better Stack). Every fatal exit now emits a bare-stdout `SOLEUR_GIT_WORKTREE_VERIFY_FAILED`
   marker (`reason=path-mismatch|not-a-worktree|dir-not-created|unregistered|branch-missing`,
   with `expected=` + `actual=` on the mismatch so the relative-vs-absolute shape is
   self-diagnosable). Added to `git-lock-marker-telemetry.ts` `MARKER_RE`/`WEDGE_RE`; the
   existing drift-guard test auto-collects every `echo "SOLEUR_*` sentinel, so an un-mirrored
   marker fails CI.

## Rule of thumb

When a fix for a mask-degraded value only moves the failure to the next consumer, stop
patching consumers: normalize the value at its single point of origin. And any fatal exit on
a non-inspectable surface (agent sandbox) must emit a monitored stdout marker — colorized
stderr is invisible.

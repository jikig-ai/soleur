---
title: Non-bare worktree skip trusted GIT_ROOT, which the config mask corrupts to a RELATIVE ".git"
date: 2026-07-07
category: engineering
tags: [worktree, git, bare-repo, char-device-mask, concierge, gitroot, non-bare-guard]
symptoms: [SOLEUR_GIT_CONFIG_TARGET_MASKED branch=target-masked-precheck on a CONFIRMED non-bare Concierge workspace, worktree creation wedges on ensure_bare_config, bare-surgery runs on a repo whose .git IS a directory]
module: git-worktree skill (worktree-manager.sh)
synced_to: []
component: worktree_manager
problem_type: runtime_error
resolution_type: code_fix
root_cause: trusted_corrupted_input
---

# Non-bare worktree skip trusted GIT_ROOT, which the mask corrupts to a relative `.git`

## Symptom

On the operator's non-bare Concierge workspace, worktree creation kept wedging with
`SOLEUR_GIT_CONFIG_TARGET_MASKED ... branch=target-masked-precheck` even after the
predecessor non-bare guard (the D3 hardening, merged 2026-07-07) was supposed to skip the
bare-config surgery on non-bare clones. The telemetry proved the skip never fired and the
code reached the config surgery on a repo whose `.git` is a real directory.

## Root cause

The D3 guard's mask-robust fallback trusted `GIT_ROOT`. Under the char-device `.git/config`
mask, `git rev-parse --is-bare-repository` DEGRADES to a false "true" at init, so the top of
`worktree-manager.sh` recomputes `GIT_ROOT` from `--absolute-git-dir`/`--git-common-dir` —
which can return the RELATIVE string `.git`. In `ensure_bare_config`, `git_dir` then collapses
to `.git` (no slash), so the non-bare skip test `[[ "$git_dir" == */.git && -d "$git_dir" ]]`
cannot match. The `$PWD/.git` recovery fallback existed but was gated behind `-z "$GIT_ROOT"`
— TRUE only for the EMPTY case, FALSE for the non-empty relative `.git` — so it was skipped,
`git_dir` stayed `.git`, `--is-bare-repository` (run from inside `.git`) returned "true", and
the bare surgery ran and wedged.

## Fix

Mask-proof non-bare detection must NOT key off the mask-corruptible `GIT_ROOT` value. The
invariant: a corrupted `GIT_ROOT` is always non-absolute (empty OR a relative `.git`), while a
legitimate `GIT_ROOT` (bare or non-bare) is always an absolute path. So the recovery fallback
fires whenever `GIT_ROOT` is non-absolute (`[[ "$GIT_ROOT" != /* ]]`) and a real `.git`
DIRECTORY exists at `$PWD` — recovering `git_dir` as the ABSOLUTE `$PWD/.git` so the `*/.git`
non-bare skip fires for BOTH the empty and the relative-`.git` cases.

Gating on `!= /*` rather than making the fallback unconditional is load-bearing: it preserves
the genuine-bare path (a real bare repo carries an absolute `GIT_ROOT`, so the fallback stays
inert and its required surgery still runs) even when the invoking CWD happens to be an
unrelated non-bare checkout. Genuine bare repos have no `.git` subdir and linked worktrees
carry `.git` as a FILE (both `-d` false), so the fallback is inert there too.

## Lesson

When a value is derived from a surface the sandbox mask can corrupt (`GIT_ROOT` via
`rev-parse`), do not gate safety logic on its exact string — key off a mask-proof filesystem
fact (`-d $PWD/.git`) and treat any non-canonical shape (empty OR relative) of the derived
value as the corruption signal. The predecessor guard fixed only the empty shape and missed
the relative shape; both are the same "GIT_ROOT is not trustworthy" class.

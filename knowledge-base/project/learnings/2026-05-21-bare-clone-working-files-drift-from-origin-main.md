---
title: "Bare-clone working files can drift from origin/main; never use them as a source of truth"
category: workflow-issues
tags: [worktree, bare-clone, git, drift, false-positive]
date: 2026-05-21
related_prs: [4215]
---

# Bare-clone working files can drift from origin/main

## Problem

The repo is set up with `core.bare=true` at `/home/jean/git-repositories/jikig-ai/soleur/` but a populated working tree co-exists at that path (legacy from a non-bare setup). Hard rule `hr-when-in-a-worktree-never-read-from-bare` covers the worktree → bare direction. The inverse — "when NOT in a worktree, but in the bare clone, are the local files trustworthy?" — is unrules.

In this session: a user asked whether a stale `knowledge-base/design/brand/...` reference existed in `knowledge-base/marketing/brand-guide.md`. Reading the file in the bare-clone root returned a line-243 hit on the deprecated path. I reported that finding. After routing to one-shot and creating a real worktree from `origin/main`, the planner verified that line 243 actually contains an unrelated border-emphasized contrast-ratio row, and the real `brand-x-banner.pen` reference is at line 376 already pointing to the canonical `knowledge-base/product/design/brand/` path. The bare-clone working file had drifted.

The user-visible cost: one round of false-positive analysis, an attempted edit that had to be reverted, and a re-pitch of the actual fix scope.

## Root Cause

The bare clone is configured `core.bare=true` but has a populated working tree at the same path (likely from before it was converted to bare, or from an unusual setup). Git treats it as bare for `worktree`/`pull`/`fetch` operations but the files on disk are not synced from `origin/main` on every fetch — they only update when an explicit sync touches them. Result: the bare root accumulates stale file content over time, even though `git ls-tree origin/main` reflects the truth.

`find . -maxdepth N -type d -name X` (which I ran first) ALSO returned bare-root results — it didn't show the regressed `knowledge-base/design/` directory because the bare working tree had already drifted past it. Only `git ls-tree origin/main knowledge-base/design/` surfaced the truth (single 0-byte placeholder file tracked on main).

## Solution

When evidence is needed about repo state (file contents, directory presence, line numbers), prefer EXACTLY ONE of:

1. **A `.worktrees/` worktree freshly created from `origin/main`** — guaranteed clean snapshot.
2. **`git ls-tree`, `git show`, `git cat-file` against `origin/main`** — bypasses the working tree entirely.

Avoid:

- `cat`/`Read`/`Edit` on files in `/home/jean/git-repositories/jikig-ai/soleur/<path>` when `pwd` is the bare root (`core.bare=true`). Even though the files exist, their content may be stale.
- `find` against the bare-root tree for evidence about what's tracked on main.

## Prevention

- **Routing default for "what's in file X?"**: when the user asks about file state and the workflow may produce edits, default to creating a worktree first (or use `git show origin/main:<path>`), even before exploration. Routing to `/soleur:one-shot` early was the right move; doing it earlier would have saved the round-trip.
- **Inverse-of-existing-rule:** consider a companion to `hr-when-in-a-worktree-never-read-from-bare`: "When in the bare clone, never `Edit`/`Write` files there — create a worktree first." The user explicitly hits this trap on a setup like this one.

## Session Errors

1. **False-positive on `brand-guide.md:243`** — Recovery: reverted the edit in the bare root; ran one-shot which created a clean worktree where the planner verified the file was already canonical. Prevention: when investigating file state, run `git show origin/main:<path>` instead of `Read <path>` from the bare-clone root, OR create a worktree first.
2. **Initial misclassification of user intent** — I told the user "the migration is already done" because `find` against the bare-clone tree showed no root `design/` dir. The webapp screenshot is what surfaced the regression. Prevention: cross-check `find` against `git ls-tree origin/main` for any "does this exist on main?" question.

## Key Insight

`core.bare=true` does not mean "no files exist locally" — the bare root can carry a stale working tree from a prior non-bare setup. Treat the bare root as untrusted file content; treat `origin/main` (via `git ls-tree` or a fresh worktree) as the source of truth.

## Tags

category: workflow-issues
module: git-worktree

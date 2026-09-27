---
title: "Issue-filing gate reads --body-file against the repo root, not the worktree CWD"
date: 2026-09-25
category: workflow-patterns
tags: [issue-filing-gate, body-file, worktree, gh-issue-create, absolute-path]
---

# Learning: `--body-file` path resolution inside a worktree

## Problem

From inside `.worktrees/feat-<name>/`, `gh issue create --body-file
knowledge-base/project/specs/.../issue-body.md` was denied by the
`wg-defer-only-after-inline-triage` hook: "--body-file unreadable". The file existed —
the gate resolves the path against the repository root, not the invoking shell's CWD, so
a path that is relative-to-the-worktree is invisible to it. A second denial followed for
`Fix-Size:` written as prose ("3 slices across plugin scripts…") — the gate requires the
literal form `Fix-Size: <N> lines / <M> files` with measured numbers.

## Solution

- Pass `--body-file` an **absolute** worktree path (or a repo-root-tracked-relative one).
- Write `Fix-Size: <N> lines / <M> files` literally — measure with `wc -l` on the artifacts
  being committed, not a description of scope.
- Both denials were self-correcting once the literal forms were used; recorded here because
  every future worktree session that files an issue hits the same two walls.

## Key Insight

The gate's error text is clear but the *path-resolution direction* is not stated: the hook
reads the file at PreToolUse time from its own vantage, so CWD-relative paths in a worktree
are a distinct failure from "file doesn't exist." Sibling pattern:
`2026-09-22-worktree-git-paths-follow-cwd.md` (git pathspecs follow the selected workdir —
the mirror-image case: there the shell path mattered, here the gate's does).

## Prevention

- When running `gh issue create --body-file` from a worktree, emit the absolute path inline
  (`$PWD/knowledge-base/...`) rather than the CWD-relative form.
- Keep `User-Impact:`/`Fix-Size:` (or `Mandated-By:`) as whole lines with the literal
  formats the gate anchors on — `wc -l` first, file second.

## Session Errors

1. `--body-file` denied as unreadable (worktree-relative path).
   **Prevention:** absolute worktree path or repo-root-tracked-relative path — see Solution.
2. `Fix-Size:` denied in prose form.
   **Prevention:** literal `Fix-Size: <N> lines / <M> files`, measured via `wc -l` on the
   committed artifacts before filing.
3. `gh pr view 7352` returned a record while #7352 reads as an issue in surrounding prose —
   issue/PR share one number space; noted and not propagated.
   **Prevention:** for any `#N` citation, confirm type with `gh issue view` AND `gh pr view`
   before asserting which it is (per `hr-before-asserting-github-issue-status`).

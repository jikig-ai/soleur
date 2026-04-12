# Learning: stale local main ref breaks multi-issue worktree creation

## Problem

When batching 7 code review fixes (#1978-#1984) into 2 parallel PRs, worktrees created from local `main` were missing the files the issues referenced. `cleanup-merged` ran at session start and warned "Could not fast-forward local main -- fetched origin/main only", but this was treated as non-blocking. The 5 commits between local main and origin/main included PR #1975 (the PR that introduced the code being fixed).

Symptoms: `Read` on `attachment-display.tsx` returned "File does not exist", issue line-number references didn't match, and initial analysis was wasted on the wrong file versions.

## Solution

Ran `git update-ref refs/heads/main origin/main` to manually advance the local ref, then recreated both worktrees. This is the same root cause documented in `2026-03-18-bare-repo-cleanup-stale-script-and-fetch-refspec.md` — the `cleanup-merged` fast-forward failed silently.

## Session Errors

1. **Stale local main ref** — `cleanup-merged` warned "Could not fast-forward local main" but the session proceeded to create worktrees from the stale ref. Recovery: `git update-ref refs/heads/main origin/main` + recreate worktrees. **Prevention:** After `cleanup-merged`, verify `git rev-parse main` equals `git rev-parse origin/main`. If they diverge, run `git update-ref refs/heads/main origin/main` before creating worktrees.

2. **Worktree ghost creation** — First worktree creation reported success but worktrees vanished from `git worktree list` after main was updated. Likely caused by creating worktrees from a ref that was then updated. Recovery: Recreated worktrees from the updated main. **Prevention:** Always verify main is current before worktree creation.

3. **Issue line-number mismatch** — Issue descriptions referenced code from PR #1975 which wasn't on local main. Wasted reads on wrong file versions. Recovery: Identified the gap via `gh pr view 1975` and fixed main ref. **Prevention:** Same as error #1 — ensure main is current.

## Key Insight

When `cleanup-merged` warns about fast-forward failure, treat it as blocking, not advisory. The warning means every subsequent worktree will branch from stale code. For multi-issue batch fixes, this compounds: each issue's file references become wrong.

## Tags

category: workflow
module: worktree-manager

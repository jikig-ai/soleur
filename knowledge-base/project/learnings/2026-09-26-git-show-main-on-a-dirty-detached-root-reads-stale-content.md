# Learning: `git show main:` reads whatever the stale local ref points at — on a dirty detached root that can be weeks old

## Problem

Session-start `cleanup-merged` could not pull latest main (`unstaged changes`
on a detached HEAD with ~1,178 dirty files — a state this box sits in
semi-permanently). Local `main` was **93 commits behind `origin/main`** with no
warning beyond the skipped-pull line.

Every `git show main:<path>` and `git ls-tree main` read after that silently
returned the old world: `suite-shard-legs.tsv` at n=5 (real: n=7),
`scripts/test-all.sh` at 3,800 lines (real: 4,975), and the stale comment under
review at line 3,442 saying "five legs" (real: line 4,592 saying "six legs" —
the reviewer's citation had *also* drifted from 4578 to 4592). Had those reads
been trusted, the brainstorm would have been premised on a week-old CI
topology.

## Solution

- Freshness probe before citing ref content:
  `git rev-list main..origin/main --count` — nonzero means every
  `git show main:` read is suspect.
- Read from the canonical ref instead: `git show origin/main:<path>`,
  `git ls-tree origin/main`. Same cost, correct data.
- Cited line numbers rot twice: the file changed *and* the local ref was
  stale. Anchor comments to symbols/quoted text (`cq-cite-content-anchor-not-
  line-number`), and re-locate the anchor at read time rather than trusting
  the citation.

## Key Insight

`main` is a local ref, not a promise. On a box where session-start pulls are
routinely skipped (dirty root, detached HEAD), the divergence window is
unbounded and silent — the only safe default is `origin/main`, which the
fetch in `cleanup-merged` does refresh even when the pull is skipped. Treat
`git show main:` as a convenience for "recently confirmed fresh" checkouts
only; for anything load-bearing, go to `origin/main`.

Adjacent but distinct from `rf-after-merging-read-files-from-the-merged`
(which covers post-merge bare-root staleness): this is *pre-work* staleness
on a non-bare dirty root, caught by a diff not a merge.

## Session Errors

1. Trusted `git show main:` reads briefly before noticing the 93-commit
   divergence — the first TSV/comment reads returned stale content.
   **Prevention:** run `git rev-list main..origin/main --count` in the
   session-start preamble when the pull is skipped, and read
   `origin/main` thereafter.
2. `git branch --show-current` printed nothing on detached HEAD, making the
   first branch check ambiguous. **Prevention:** use
   `git symbolic-ref --short HEAD || git rev-parse --short HEAD` when the
   branch state matters.

## Tags

category: workflow-patterns
module: git-worktree

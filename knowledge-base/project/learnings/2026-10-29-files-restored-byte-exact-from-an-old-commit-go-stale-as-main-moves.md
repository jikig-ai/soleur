# Learning: files restored byte-exact from an older commit go stale as main moves

## Problem

Several census/parity files (`census`, `parity`, `pipe-guard`, `accept.tsv`) were restored byte-exact from an older commit into a PR branch so the diff stayed small. Each time main moved, the restored copies went stale against main's current content and the PR hit `merge_conflict` again, producing repeated dequeues from the merge queue.

## Solution

A byte-exact restore is only valid for the SHA it was taken from. Immediately before arming, merge main into the branch, re-derive these files from the merged result (rerun the trio census), and arm in the same sitting. If a file is hot on main, do not restore it from history at all: regenerate it against current main.

## Key Insight

"Identical to a known-good commit" is a property that decays as main moves. For hot shared files, freshness is a property of the arm moment, not of the commit they came from.

## Session Errors

1. Restored-from-history census/parity/pipe-guard/accept.tsv files caused repeated `merge_conflict` dequeues. **Prevention:** merge main and rerun the census right before arming; regenerate hot files instead of restoring them.

## Tags

category: workflow-patterns
module: merge-queue, census

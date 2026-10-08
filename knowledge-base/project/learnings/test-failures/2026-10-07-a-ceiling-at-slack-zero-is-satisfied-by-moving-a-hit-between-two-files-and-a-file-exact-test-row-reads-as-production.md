---
title: "A `<=` ceiling at slack 0 is still satisfied by moving a hit between two files, and a file-exact test row is classified as a production row"
date: 2026-10-07
category: test-failures
module: .claude/hooks/grep-q-pipe-guard.test.sh (SWEEP_DEFERRALS, _ts_re, GATED_PROD_ROWS)
issues: [9217]
---

# What "no slack" does and does not pin

## Problem

Wave B lowers each test-shaped deferral ceiling to the measured count (`.claude/*.test.sh` 91 to 5, `scripts/test-*` 6 to 2), so
a new early-exit pipe under a row at its ceiling goes red. That pins the COUNT per row, not the sites. Measured on the S1
branch, in a committed scratch worktree: revert one converted site in `skill-context-queries.test.sh` (a new hit, +1) and rewrite
one counted hook-input line in `pkill-self-match-guard.test.sh` (-1), and the guard prints
`DEFERRED: .claude/*.test.sh (5 hits, ceiling 5, mode <=, slack 0)` and `PASS: grep-q-zero-sweep-pass`. A regression hides
behind an unrelated deletion in the same row. The Guard Contract names this as the known surviving mutant for every `<=` row.

The obvious closure, a file-exact row per residual file, is blocked by the guard's own row classifier. `_ts_re` recognizes a
test-shaped row only by a glob (`*.test.sh`, `tests?/*`, `scripts/test-*`):

```text
[[ ".claude/hooks/pkill-self-match-guard.test.sh" =~ $_ts_re ]]   # false -> counted as a PRODUCTION row
[[ ".claude/*.test.sh" =~ $_ts_re ]]                              # true  -> test-shaped
```

So a file-exact test row would raise `prod_n` above `GATED_PROD_ROWS` (the host-replace claim on the six wave A3 carriers) and fail
the `real-table-production-rows` check, which requires every non-test-shaped row to be one of those six with no glob character.

## What works

- State the hole where it lives (the Guard Contract and the PR body), with the measured experiment, rather than claiming the
  ceiling pins the sites.
- Close it in the slice that has the real residual in hand: widen `_ts_re` to recognize a file-exact `*.test.sh` path as test-shaped
  and switch the residual rows to `=`, so a moved hit changes two rows. That is a change to the production-row classifier, so it
  belongs in its own reviewed slice, not folded into a lint sweep.

## Prevention

When a ratchet is a count, ask what a deletion elsewhere in the same bucket does to it. Validate the ledger against the tree its own
remediation produces (see `2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md`): the first
thing a remediation does is delete hits, which is exactly the move that a `<=` ceiling absorbs.

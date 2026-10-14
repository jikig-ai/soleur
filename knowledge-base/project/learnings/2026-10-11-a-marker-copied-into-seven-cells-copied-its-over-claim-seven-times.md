# Learning: a marker copied into seven cells copied its over-claim seven times, and the falsifier was in the run history

## Problem

#10014 flips a ledger row to `luks` and appends one dated supersession marker to seven legal and
engineering cells. The first draft carried two sentences that read as carefulness and were measured
by nobody:

- "reopen after a host restart ... has not been exercised" (then "no controlled test has exercised").
- "web-2 still holds no personal data" (then "holds no workspace data" in the ledger).

Both were wrong or unsupported in ways one query would have shown. The run logs hold two reboot
requests (2026-10-06 18:26Z from the rebirth run, 2026-10-07 19:04Z from a reboot dispatch whose
observer reported NOT YET), the volume has been attached to three different servers, and the readiness
rows show one `formatted` boot followed by two `opened` boots. And "holds no data" rested on serving
weight 0 and a shape-only gate; the volume's contents were never probed (the old ledger row said so, and
the rewrite dropped the caveat).

The CLO's first review found six wording problems and missed both, because it checked the claims against the
evidence table in the record, and the evidence table had been written from the same incomplete reading.
Five panel seats then found them from different directions (history from the run logs, security from the
network layer, user-impact from the reader's inference).

## Solution

- Narrowed the reopen claim to "has not been graded" and recorded the reboots, the three server ids and the
  `opened` rows as facts that are not treated as a reopen test (the rule is immutability, not reboot).
- Replaced "holds no data" with "is not routed any personal data (serving weight 0, no DNS or load-balancer
  route; the volume's contents have not been probed)", and cited declared configuration for it.
- Changed "recovery is recorded in" to "recovery is not verified; the position is recorded in" where a cell has
  no recovery sentence of its own.
- Applied each narrowing once and propagated it by script with a per-file count assertion, then ran a second
  CLO pass on the delta only, whose six precision corrections were also narrowings.

## Key Insight

An absence claim about a system ("not exercised", "holds nothing", "never routed") is a statement about the
whole history of that system, and its falsifier is almost always an event log, not the evidence table you
built to support the claim. Before writing one, name the log that would contain the counter-example and read
it: here, `gh run list` for the volume's id and a Better Stack read of the readiness rows. A reviewer working
from the same evidence table cannot find what the table left out.

Replication multiplies the cost: a sentence pasted into seven cells has seven places to be wrong and seven
places to fix, so write the sentence as narrowly as the evidence allows the first time, and put the
"what is not claimed" list in every cell where a reader could stop reading.

## Session Errors

1. **`pgrep -f` used inside a Monitor command** — Recovery: stopped the monitor and relied on the agent completion notification. Prevention: the repo rule already bans it; check a command for `pgrep -f`/`pkill -f` before arming a watch.
2. **PR body contained "close #9642", an auto-close keyword plus an owner-gated issue** — Recovery: the pre-creation scan flagged it and the wording was changed before merge. Prevention: run `auto-close-scan.sh` on the body file before `gh pr create`, as ship does; never write a keyword adjacent to a reference in prose.
3. **Merging `main` into the branch tripped `rename-guard`** — Recovery: rebased to drop the merge commits, force-pushed with lease, verified no renames in range. Prevention: when a branch needs `main`, prefer rebase over merge on PRs touching allowlisted paths.
4. **A conflict resolution put the ADR supersession marker under the newest addendum rather than the paragraph it supersedes** — Recovery: moved it after the pattern seat flagged it. Prevention: after resolving an append-only conflict, re-check that each dated marker is still adjacent to its target.
5. **Marker over-claims on reopen and on "holds no data"** — Recovery: narrowed everywhere and recorded the facts. Prevention: read the event log before writing an absence claim; ask each seat "what in the history contradicts this sentence".
6. **An unmeasured sentence about an empty filesystem's footprint was written into a legal record** — Recovery: removed before commit. Prevention: for every causal sentence a diff adds, name the command that falsifies it and run it.
7. **Local battery queued behind sibling worktrees for 30 minutes** — Recovery: stopped it on your call and relied on CI. Prevention: none beyond the capacity probe; the affected gate is exempt from refusal but not from the lock queue.

## Tags
category: logic-errors
module: knowledge-base/legal

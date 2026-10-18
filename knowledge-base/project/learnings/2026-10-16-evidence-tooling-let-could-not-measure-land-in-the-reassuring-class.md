# Learning: evidence tooling let "could not measure" land in the reassuring class (S4 PR C, #9729)

## Problem

PR C built a replay (escape rate over 300 commits plus queue ejections), an index audit and a pre-activation gate for the S4 affected-only lever.
Three review rounds (11 seats, 10 seats, a verification pass) found the same defect class in different places, each time in a reader or classifier:

- a cancelled or unfinished job, a truncated jobs list, an empty diff and an unread attempt 1 all reached `rule-irrelevant`, `flake-cleared` or `escape`;
- `ejections` dropped the three `cancelled` merge_group runs as "no verdict on any suite", although a cancelled shard fails the aggregate check;
- the ejection population could be short or stale and `aggregate` still printed a clean receipt, because nothing said how many refused runs the window held;
- a commit file entry with no blob sha compared by name alone and was still an "identical changed-file set" claim;
- an audit whose selector exited non-zero after printing rows read as a pass over the rows it got;
- the first receipt named the wrong window (the tree the selector ran on, not the 300 commits).

## Solution

Fix the class, not the instance:

1. Every conclusion except `success` is a refused run and a unit; unfinished or unreadable input is `not-evaluable` and counts in the worst-case numerator.
2. The collector writes the count it saw (`ejections-window.json`); the aggregator refuses (rc 2) a population that is not that count. A population check needs a number that came from the source, not from the file being checked.
3. A claim is made from the strongest key available or not at all: a missing blob sha is a failed read.
4. A subprocess that fails after partial output is a failed read (rc 3), never the rows it managed to print.
5. Every guard gets a mutant that removes it and a row that must go red; the harness requires the mutant to land once, parse, pass on pristine, then fail on the mutant.

The verdict did not move (NO-GO on index completeness, 190 of 630 suites). The worst-case numerator moved 3 to 6 (bound 2.18% to 3.30%), and the receipts now say criterion (a) rests on the identical changed-file-set clearance (21 of 356, 5.9% without it).

## Key Insight

When a tool's job is to say "no problem found", enumerate its third outcome ("could not look") before its first two, and make the count of what it was supposed to look at come from the source of truth.
A zero is evidence only when the denominator is pinned independently.
Also: a hand-built test fixture must grow the same new required input as the real producer (the manifest), or every aggregate row fails for a reason the row is not about.

## Session Errors

1. **Fail-open readers and classifiers, found across three review rounds** — Recovery: fixed in the class, rows and mutants added — Prevention: the review checklist item "what does the unreadable arm print?" (already covered by the QA skill note on three-outcome gates; no new rule).
2. **First receipt named the wrong replay window** — Recovery: re-derived against `git rev-list --first-parent -n 300`, units checked 0 missing / 0 extra — Prevention: receipts cite the pinned window by a command that reproduces it.
3. **Cancelled runs dropped as "no verdict"** — Recovery: cancelled runs are units; claim withdrawn in receipts and decision log — Prevention: population definitions are written as "every conclusion except X", never as a list of the ones seen.
4. **Mutant `old` strings drifted from the source after script edits (`rate-limit-not-retried`, `waiver-unanchored`)** — Recovery: the harness reported `edit-failed`, strings re-derived — Prevention: already enforced by the harness (an edit that does not land fails the run).
5. **Test helper (`mkmeta`) defined after its first use; mutant survived because a second refusal masked the first** — Recovery: moved the helper, gave the fixture the manifest so only the mutated guard could refuse — Prevention: a mutant row's fixture must satisfy every other guard.
6. **Stale `old` strings in patch scripts (assertion errors) and argparse `%%` double expansion** — Recovery: re-derived exact text — Prevention: one-off.
7. **kb-consumers census, orphan-lint and fixture-relative ratchets caught new suites naming doc-tree literals and bare paths** — Recovery: string-joined the literals, moved a parity row — Prevention: already enforced by those gates.
8. **A wontfix rationale row was first written with details not sourced from any finding** — Recovery: rewrote it from the recorded findings before commit — Prevention: record a rationale only from a finding or measurement in hand.
9. **Shell cwd reset to the repo root mid-session** — Recovery: re-entered the worktree before the next command — Prevention: one-off (environment).

## Tags
category: workflow-issues
module: ci / S4 affected-only replay and pre-activation gate

---
title: A selector that settles on the first qualifier cannot see the candidate created after it
date: 2026-09-21
category: workflow-issues
module: ship, postmerge, plugins/soleur/scripts/deploy-arm.sh
issues: [8492, 8391, 8297]
tags: [deploy-arm, workflow_run, head_sha, verdict-ladder, mutation-battery]
---

# Learning: a selector that settles on the first qualifier cannot see the candidate created after it

## Problem

ship and postmerge found a merge's production deploy with
`actions/runs?head_sha=<merge>&event=workflow_run`. A `workflow_run` run's `head_sha` is
`main`'s tip when it FIRED, not the commit it deploys, so the query missed the real arm on a
busy `main` (#8297) and returned the previous merge's arm (#8391). #8492 replaced it with
`plugins/soleur/scripts/deploy-arm.sh`, which reads the SHA each candidate's `resolve-target`
job checked out and accepts the merge or a descendant.

The first implementation passed its own 31-scenario suite and a 14/14 self-run mutation
battery, then an 8-seat review found ~15 P2s — all in the verdict ladder, none in the log
parsing the PR was "about".

## Solution

The recurring shape: each rule settled on the first candidate that qualified in creation
order, and only ever consulted candidates EARLIER than the winner. But creation order is not
merge order — when a descendant's CI finishes first, the merge's own exact arm is created
LATER than the descendant's, so "earliest delivering descendant, unless something earlier is
undecided" settled while the better answer was still resolving. The fixes, all in
`evaluate()`:

- any pending/unresolved candidate (earlier OR later) blocks a descendant verdict;
- a CI re-run polls until the re-run's own exact arm exists (rule 3 honours `run_started_at`);
- past the candidate cap, keep the NEWEST candidates — the merge's arm is created last;
- a successful descendant beats an earlier failed one;
- a fork PR's run on a branch named `main` checks out a sha not on `main` → reject, not
  "unresolved" (which blocked every verdict);
- the ordering guard's green `deploy` job with a skipped `Deploy via webhook` step is
  `superseded`, not `success`;
- both key log lines are anchored at a line's start (timestamp + runner text) so a commit
  subject echoed later in the log (`HEAD is now at <sha7> <subject>`) cannot supply them.

## Key Insight

For any "pick the right one from a time-ordered list" rule, enumerate what can be created
AFTER the rule's winner and still outrank it. A rule that only looks backwards from its
winner is correct exactly when arrival order equals priority order — and the interesting
case (why the selector exists at all) is precisely when it does not. The author's mutation
battery mutated the rules it had written and so could not see the rule it had not; the
structural-enumeration seat (a MAP of every path to a verdict) found it.

## Session Errors

1. **Planning brief called #8490 a PR; it is an open issue.** Recovery: plan worded it
   correctly. Prevention: `gh issue view N --json title` every `#N` a brief labels (already a
   work-skill rule; one-off).
2. **New shell script and test shipped five fixture-safety ratchet sites** (`rm -rf "$TMP"`
   before a provable binding, `gh … > "$out"` on a caller-supplied path, an unguarded
   `git -C "$1"`, redirects inside mutation-row literals). Recovery: bind `TMP` via `mktemp`
   at top level, write only under `$TMP/`, `assert_fixture_dir` in the test, `{GT}` token in
   row literals. Prevention: `work/SKILL.md` Phase 0.5 check 6.6 already says to run
   `fixture-relative-assert` / `fixture-dir-operand-assert` before a new `*.test.sh`'s first
   commit — I skipped it. Run it.
3. **`scripts/test-all.sh` refused (rc 4) — four sibling worktrees were running full
   gates.** Recovery: consumer-derived suite set plus repo-global ratchets, run detached.
   Prevention: none needed (the refusal is the designed behaviour); one-off.
4. **First widening of the static forbid-regex false-fired on ship prose** that names
   `--commit` and `--event workflow_run` in different backtick spans of one long line.
   Recovery: bound the co-occurrence to one command span (`[^`|]*`) and add that prose as a
   negative self-test string. Prevention: every forbid-regex widening gets a must-NOT-match
   self-test drawn from the real corpus before it is run over it.
5. **Verdict-ladder gaps shipped past a green suite and a 14/14 battery** (the insight
   above). Recovery: rewrite of `evaluate()`, 28 new cases (51 → 79) incl. an `expect()`
   rejection control, battery 14 → 22 rows. Prevention: for time-ordered selectors, add one
   fixture where the best candidate is created LAST; spawn the structural-enumeration seat
   for any verdict-ladder diff.
6. **The CI-runs listing transiently returned an empty set for a SHA with a completed run**
   (observed live by the code-quality seat → `CI=absent`). Recovery: one re-query before
   concluding "absent". Prevention: never read a single empty API listing as proof of
   absence when the next branch is terminal.

## Tags
category: workflow-issues
module: ship, postmerge

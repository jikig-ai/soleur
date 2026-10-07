# Learning: the recorder called its own checkout dirty, and I explained the verdict as a property of the suite

## Problem

PR #9422 (umbrella #9307: a committed read-recorder, the runner as a closure leaf, a regenerated shard manifest) shipped to review with green local gates and
a measured audit. Eleven review seats then found that the headline evidence was partly an instrument artifact.

The recorder builds a private checkout from `git archive` plus `git add -A`, runs each suite in a window, and flags a window `contaminated` when
`git status --porcelain --ignored` is non-empty. The archive contains 22 files that are TRACKED in the source repo but match `.gitignore` (`*.png`
under three spec directories). In the private checkout `git add -A` skips them, so they are untracked-and-ignored and the status is never empty:
**window 1 of every run was `unreliable reason=contaminated`**, then the cleanup deleted them and later windows looked clean. Two audit rounds
recorded "contaminated" against specific suites ("it dirties the private checkout") and the plan's policy then left those suites demoted. Both
explanations were about the instrument, not the suites; the suites were first in their runs.

Everything around that was the same shape: a bench oracle documented with a ceiling of 200 that needed 240 and an "over-approximates" claim that was
false; an A5 evidence population of 18 rows for 24 edge-losing rows; "hedged to always-on, not guessed" stated for three suites where it was not true.

## Solution

- Fix the instrument first (`git add -A -f`, so the private commit equals the archive; a fixture row with a force-added ignored file; a row where a suite
  really creates an ignored file is still contaminated), then RE-RUN the evidence: 24 check rows and 5 demote rows. The re-run changed decisions:
  two Round 2 "unreliable" suites are `uncovered` and return to always-on; four suites with only partial runs are hedged.
- Rebuild the bench walker as a second implementation of the derive's text spec (408 of 408 edge-classified rows reproduced), which is what lets
  both ceilings default to 0, instead of calibrating a ceiling to the observed maximum.
- Raise `_MIN_ALWAYS_ON_DECLARED` to count minus 5 and pin both the literal and `count - floor <= 5`.
- Correct the audit, ADR-242 decisions 15/17/18, the CI comments and the runbook; record the deviations in `decision-challenges.md`.

## Key Insight

1. **A verdict that lands on the FIRST item of every batch is a statement about the instrument's setup, not about the item.** Two rounds attached a cause
   ("the suite dirties the checkout") to rows whose only common property was their position. Before explaining a non-decision, run the instrument over
   a known-clean control in the same position (a no-op suite first in the batch) and ask what changes when the order is rotated.
2. **A calibrated ceiling is a measurement written down as a policy.** `--max-unexplained 200` was "just above the observed 189 per row" and was wrong at
   the pinned SHA (240). If the oracle can only pass with a ceiling, the oracle does not model the thing; make it model the thing and set the ceiling to 0.
3. **"Where there is no evidence the suite is hedged" is a claim about every row, so enumerate the rows.** A population of 18 for 24 edge-losing rows
   is a smaller claim than the sentence. Count the denominator from the mechanism (which rows lost edges), not from the list you already had.
4. **Hardening commits on a guard are guard-shaped changes and break the repo-global ratchets that scan guards.** The two ratchets that failed
   (`guard-vacuity-floor`: a floor reading a variable the mutant slice cannot bind; `fixture-relative-assert`: unguarded write operands in a function the
   refactor introduced) were found only because the whole affected gate was run. Run those two after each guard-shaped commit, before the panel.
5. **The cheapest fix-up for a floor that must price a skipped section is to bind the pricing variable on the line directly above the floor**, so a
   mutant slice that zeroes only counters can still construct it.

## Session Errors

1. **Contamination probe misread as a suite property (Round 2 and Round 3 write-ups).** Recovery: probe fixed, 29 suites re-recorded. **Prevention:** a
   recorder verdict that is not a decision gets a known-clean control in the same batch position before any cause is written down; compound/review
   bullet added to the review catalogue.
2. **Bench ceiling recorded as 200, needed 240; walker described as "over-approximating".** Recovery: walker rebuilt, ceilings 0. **Prevention:** an oracle that
   passes only above a ceiling gets rebuilt, not calibrated; re-run the documented command at the pinned SHA before quoting it.
3. **Incomplete evidence population (18 of 24 rows) and a "not guessed" claim true of fewer suites than stated.** Recovery: re-run over all 24; hedges by cost.
   **Prevention:** derive the population from the mechanism that creates the obligation, then check each row exists.
4. **Plan said "the floor is never raised", leaving it 23 below the count.** Recovery: floor 140, `f1` pins `count - floor <= 5`. **Prevention:** a floor
   plan rule states the relation to the count, not a literal.
5. **Review fixes broke `guard-vacuity-floor` (ratchet grew 15 to 16) and `fixture-relative-assert` (8 new sites).** Recovery: bound `SKIPPED_ROWS` beside the floor;
   canonical `assert_fixture_dir` before each write. **Prevention:** run both ratchets after every guard-shaped commit.
6. **`TEST_GROUP=affected` hit its 5000 s cap on a diff that touches the runner (every closure shifts), ending without the repo-write boundary re-read.**
   Recovery: targeted suites plus CI as the full gate. **Prevention:** for a runner-touching diff, run the named ratchets individually; do not rely on the
   affected gate as a single bounded step.
7. **A PreToolUse hook blocked `ps … | awk '/pat/'` (self-matching).** Recovery: `ps | grep | grep -v grep`. **Prevention:** already hook-enforced.
8. **A recorder reader process stayed alive 7 h after its parent died (earlier runs).** Recovery: killed by PID; the reader now polls its parent and exits.
   **Prevention:** shipped in the product (reader parent-death row).
9. **The shell working directory was reset to the main checkout between calls.** Recovery: absolute paths and an explicit `cd` per call. **Prevention:**
   already covered by the worktree rules.

## Tags
category: workflow-issues
module: scripts/audit-suite-reads.sh, scripts/affected-prepass-bench.sh, scripts/lib/test-affected-paths.sh

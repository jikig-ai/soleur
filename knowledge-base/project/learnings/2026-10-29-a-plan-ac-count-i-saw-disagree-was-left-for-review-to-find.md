# Learning: an acceptance-criterion count I saw disagree was left for review to find

## Problem

Residual 1 of #10932 was a one-sentence runbook fix (the sentence "does not yet list exit 1" went
stale when the engine header gained its exit 1 row). The edit was trivial. The plan's own
acceptance criteria were not: AC1 expected ``grep -c '^| `1` |' <runbook>`` to print `1`, but the
runbook has two such rows (the D10 gate's "Over cap" row and the restore-exit-codes row), so the
count is `2` on `origin/main` and on the branch. AC3 said the changed-file set is the runbook plus
three planning artifacts, but the pipeline's own `session-state.md` makes it four.

## Solution

Both ACs were corrected in the plan during review (commit `80294285cf`). The runbook edit never
changed. The sentence was already right; only the checks around it were wrong.

## Key Insight

When running a plan's AC command literally prints a different number than the plan states, fix the
AC in the same step. In this session the mismatch printed in the work phase (`row1: 2`), was
compared against `origin/main` (also 2, so the edit was fine), and then left for the review panel
to report. Comparing against main answers "did my edit break it?" and says nothing about whether the
AC is right.

## Session Errors

1. **AC1's expected count was wrong and I saw it** — Recovery: corrected the plan AC to `2` with the
   reason — Prevention: after any literal AC run that disagrees with the plan, edit the plan AC in the
   same step (existing rule in `work` Phase 1: verify an AC by running its LITERAL command).
2. **AC3 undercounted the artifact set (`session-state.md` omitted)** — Recovery: corrected to four —
   Prevention: derive the expected file set from `git diff --name-only` after the pipeline writes its
   state file, not from the plan's pre-pipeline estimate.
3. **An over-broad grep alternate (`does not$`) matched an unrelated line** — Recovery: re-ran the
   specific `tracked on #10932` check — Prevention: one anchored pattern per AC; do not OR extra
   alternates into a count.

## Tags

category: workflow-patterns
module: work, plan

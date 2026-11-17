---
module: Workflow
date: 2026-11-09
problem_type: workflow_issue
component: evidence_integrity
symptoms:
  - "A 'measured misfire' claim in an issue, plan and ADR amendment was refuted by the run's own artifacts at review"
  - "The evidence command (`git diff <run-head>^1 <run-head>`) diffed the PR head's own first parent, not the classifier's pair"
  - "The claimed direction was mechanically impossible (a stale base can only deny the lane, never fabricate oracle_only=true)"
  - "The false claim was being written into an append-only ADR"
root_cause: unverified_evidence
resolution_type: narrative_correction
severity: high
synced_to: [review, plan]
tags: [evidence-integrity, measured-claim, adr-append-only, run-artifacts, #12418, #12376]
---

# A measured-misfire claim was falsified by the run's own log — verify the evidence command before it reaches an append-only record

## Problem

Issue #12418's motivating evidence said run 42459010986 classified `files=6 reason=oracle
oracle_only=true` because a stale merge-ref `HEAD^1` re-counted main-side changes the PR never touched.
The plan and the ADR-276 amendment carried the claim forward. The git-history seat at review refuted
every checkable part: the merge ref's `HEAD^1` was the *live* main tip (equal to `merge-base`), the
`files=6` was exactly the PR's own docs delta, `oracle_only=true` was the *correct* verdict, and the
job cancellation was the separate #12393 manifest-bound defect. The claimed direction was also
mechanically impossible — a stale base can only *add* paths to the classified set, so it pushes a
qualifying diff to `outside_surface`/`excluded` (denying the lane, expensive-but-safe) and can never
fabricate `oracle_only=true` on a non-qualifying diff.

## Why it survived to review

The evidence command `git diff <run-head>^1 <run-head>` diffs the PR head's own first parent — the
merge commit's own delta — not the classifier's pair (merge-ref p1 → merge tree). The output *looks*
like the claimed proof (main-side paths in a diff) while measuring the wrong thing. A confound
completed the picture: the PR "unblocked by rebasing" because `CI_ORACLE_LANE` had been unset between
runs, not because the head shape changed.

## Lesson

- For every "measured" claim bound to a run/commit, replay the measurement on the same artifacts
  BEFORE the claim enters a plan — and re-derive whether the claimed direction is even possible in
  the mechanism (the subset argument settled this one in one line).
- An append-only record (ADR) makes a false claim permanent-adjacent: the correction costs an
  amendment plus issue comment plus plan rewrite. The cheapest time to catch it is when the claim is
  drafted, not when it is cited.
- A "fixed by rebase" observation is not causal evidence for a shape-class defect unless the variable
  being tested actually changed — check the lane/job state around both runs first.

## Prevention

- Plan evidence blocks should carry the replay command that produced the figure, not just the figure;
  a reviewer can then refute it in one command — this seat did.
- Direction-of-harm analysis (can mechanism X produce verdict Y?) belongs in the same paragraph as the
  measured claim; writing it makes impossible-mechanism claims self-refuting.

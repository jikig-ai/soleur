# Decision challenges: feat-one-shot-9728-ci-draft-light

## 2026-10-09 plan review (headless)

### User-Challenge 1: gate 6 passes on a substituted bound, not a measured post-policy mean

- Operator direction (default, kept): "pass only if the post-policy mean >= 2.75", measured as pre-policy and post-policy means over a 30-day census.
- Challenge (DHH, code-simplicity: collapse to PASS/FAIL on the raw mean and print the floor as information; Kieran: if the floor substitutes for the measurement, record it as a deviation, rename it a floor and compare in integers).
- Applied: the rule stays two-sided. PASS needs the raw mean AND `POLICY_FLOOR_MEAN` (pushes minus CI-failed pushes, per PR) at or above 2.75, because no post-policy population exists (the policy is enforced nowhere, see the plan's Reconciliation table) and a measured post-policy mean replaces the floor if Phase 0 finds an enforcement date with 30 days behind it. When the mean passes and the floor does not, the verdict is INDETERMINATE (hold, no `ci.yml` change), never a silent PASS. The planning pilot (8.24 mean, 7.18 floor) says PASS, so the hold branch is expected to stay unused; it is kept as the only reading of the operator's rule that does not loosen it.

### User-Challenge 2: Phase 7 reader fan-out versus a wait-step-only stage

- Operator direction (default, kept): the issue lists `monitor-pr-checks.sh`, ship Phase 6/7, `drain-prs`, `merge-pr` and `admin-merge-ready.sh --wait` as consumers that must resolve from the newest non-draft run.
- Challenge (code-simplicity): if gate 1 shows the newest row per name decides, readers already see PENDING; ship only `wait-ready-run` and patch a reader only where gate 5 shows a misread.
- Applied in part: every reader edit starts from a failing fixture row, so a reader that already behaves correctly is pinned rather than edited. Not applied in full: until the aggregator runs (up to 38 to 51 minutes after the ready event) the newest `test` row IS the draft run's red one, which gate 1 does not change.

### Taste notes (not applied)

- DHH: widen/narrow guard matrices. Declined; the Guard Contract lint requires the shape and duplicated rows are annotated with the suite that also covers them.
- Code-simplicity: replace the `draft-light` live read with a `RUN_ATTEMPT == 1` guard (the S2 `push-dedupe` pattern). Declined: ADR-276 Decision 4 and the issue say the draft state is resolved live, because a re-run reuses the original payload and `RUN_ATTEMPT` does not say whether the PR has been readied since.
- Code-simplicity: drop the 1-day dark-merge deadline and the dark-merge option. Kept (CTO asked to bound the dark window rather than remove the option).
- Code-simplicity: activation gated on a `S3-CONFIRMED` marker is inferred from the S2 precedent and the CTO's advice, not stated by the operator. Kept; the alternative is "the operator's explicit go only" (which the repo's production-write rule already demands). Surface for the operator.

### Not Yet Specified candidates

None.

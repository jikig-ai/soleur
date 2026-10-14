# Tasks — fix(scripts): T4 in rule-metrics-aggregate.test.sh fails after rule-prune null-first_seen skip (#3507)

Derived from `knowledge-base/project/plans/2026-05-10-fix-rule-metrics-t4-uses-fire-count-after-first-seen-null-skip-plan.md`.

## Phase 1 — Reproduce

- [ ] 1.1 — Run `bash scripts/rule-metrics-aggregate.test.sh` from the worktree root. Confirm `FAIL: T4 rule-prune candidates wrong (saw_a=0 saw_b=0)` and `PASS=18 FAIL=1 TOTAL=19`. Capture for PR body.

## Phase 2 — Fix the test

- [ ] 2.1 — Edit `scripts/rule-metrics-aggregate.test.sh` function `t4_rule_prune_uses_fire_count`:
  - [ ] 2.1.1 — Keep fixture seeding (Rule B with one ancient `applied` event; no events for Rule A).
  - [ ] 2.1.2 — Replace the `saw_a=0 saw_b=0` assertion block with a single negative assertion: Rule B's id MUST NOT appear in `$candidates`.
  - [ ] 2.1.3 — Add a comment block above the new assertion naming PR #3156 + issue #3507 + the rationale (no event_type sets first_seen without incrementing fire_count).
  - [ ] 2.1.4 — Adjust PASS/FAIL bump accounting and the FAIL message text per the plan's Phase 2.

## Phase 3 — Verify green

- [ ] 3.1 — Re-run `bash scripts/rule-metrics-aggregate.test.sh`. Confirm `FAIL=0`.
- [ ] 3.2 — Confirm T1, T2, T3, T5 are still PASS (no behavior change).
- [ ] 3.3 — Spot-check that `scripts/rule-prune.sh` and `scripts/rule-metrics-aggregate.sh` are unmodified (`git diff --stat scripts/`).

## Phase 4 — Capture + commit

- [ ] 4.1 — Write the learning file to `knowledge-base/project/learnings/<topic>.md` (date picked at write-time; topic: rule-prune null-first_seen skip invalidates positive prune-candidate fixture).
- [ ] 4.2 — Run `skill: soleur:compound`.
- [ ] 4.3 — Commit `scripts/rule-metrics-aggregate.test.sh` + the learning file with the message in the plan's Phase 4.
- [ ] 4.4 — Push branch.
- [ ] 4.5 — Open PR with `Closes #3507` on its own body line; PR title contains no auto-close keywords.

## Phase 5 — Review + merge

- [ ] 5.1 — Run `skill: soleur:review` against the PR.
- [ ] 5.2 — Address review findings inline (default per `rf-review-finding-default-fix-inline`).
- [ ] 5.3 — `gh pr merge <N> --squash --auto`. Poll until `MERGED`.
- [ ] 5.4 — Post-merge verification: re-run the test on `main` to confirm green; close the issue if the auto-close keyword didn't fire.

# Tasks - bundled Inngest host-replace window plan (Ref #9927)

Plan: `knowledge-base/project/plans/2026-11-06-docs-inngest-host-replace-window-plan.md`. Docs only. Nothing in this list dispatches, applies, revokes, signs, closes or commits spend.

## Phase 1 - Refresh the ledger on the ship day

- [x] 1.1 Re-run every read-only command in Part 1 of the plan (rows a1, a2, a3, b, c1, c2, e (the read-only checks), f, g, and the row h list) on the then-current `origin/main`.
  - [x] 1.1.1 Where a state moved, append a dated `Refreshed <UTC time>:` line under the row; never rewrite the earlier reading.
  - [x] 1.1.2 Do not dispatch the Main Health Monitor; do not close any issue; no production write.
- [x] 1.2 Re-read #9927, #12213 and the 12:00Z/18:00Z monitor slots; update row a1 and the Part 3 date table if a slot has run.

## Phase 2 - Lint and checks

- [x] 2.1 Run Acceptance Criteria 1 to 10 of the plan (the PR-body half of 8 at ship) and fix any hit.
- [x] 2.2 Run `python3 scripts/lint-infra-no-human-steps.py` on the plan and on `decision-challenges.md` (both exit 0).
- [x] 2.3 Confirm `git diff --quiet origin/main...HEAD -- apps .github scripts plugins` exits 0.

## Phase 3 - Ship

- [ ] 3.1 Open the PR ready with body `Ref #9927` (no `Closes`, `Fixes` or `Resolves`) and auto-merge once checks pass.
- [ ] 3.2 After the merge, resolve the archived path with `git ls-tree -r --name-only <merge-sha> | grep inngest-host-replace-window`.
- [ ] 3.3 Append one comment (not a body edit) to #9927 that links the document at its merge-commit path, states that the 2026-11-09 orphan-sweeps re-look hold is superseded (#10972 closed 2026-10-29, monitor destroyed by PR #11535, probe retired), and states that nothing was dispatched, applied, revoked or closed and nothing was drafted for the A6 record.
- [ ] 3.4 After any review panel that simulated an inherited `GIT_DIR`, check `git log main -1`, `HEAD` and `git config --local --list` for leaked `user.*` or `commit.gpgsign`.

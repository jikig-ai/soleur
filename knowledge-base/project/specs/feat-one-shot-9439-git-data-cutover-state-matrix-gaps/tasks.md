# Tasks: feat-one-shot-9439-git-data-cutover-state-matrix-gaps (#9439)

Plan: `knowledge-base/project/plans/2026-10-09-fix-git-data-cutover-residual-state-matrix-gaps-plan.md`

Constraints in force: no production write, host replace, key rotation, ruleset change or workflow
dispatch; no agent `--admin` merge on a PR that edits `.github/workflows`; targeted suites only; PR
body uses `Refs` (never `Closes`) for #9439, #8211, #9066, #9377, #8609; do not touch PR #9811, PR
#9466, `git-data-gc.sh` or any hash-bound host payload.

## 1. Setup

- 1.1 Confirm the edit regions are clear of PR #9811's hunks (`gh pr diff 9811`, read only).
- 1.2 Run once as a baseline: `bash apps/web-platform/infra/git-data-cutover-access.test.sh`; record `MUTANT_FLOOR` and `FLOOR` as measured.
- 1.3 Run `bash apps/web-platform/infra/ci-deploy.test.sh` once (timer-start pin) and note the result.

## 2. Phase 1 — unwind marker (item 6)

- 2.1 RED: add FZ11 (flip, markers `freeze_held` + `flag_write_attempted`, expects flag-off write, redeploy, one unfreeze) and FZ12 (rollback, only `flag_write_attempted`, expects "nothing to unwind", zero unfreeze) inside `case_fz`.
- 2.2 RED: add a WF pin that the `flag_write` step body touches `flag_write_attempted` after the xtrace guard and before the precheck call; add the mutant that moves it after.
- 2.3 GREEN: add the `touch` to the workflow `flag_write` step; change the finalizer flip condition to `flag_written || flag_write_attempted`; leave rollback conditions on `flag_written`.

## 3. Phase 2 — gc timer restart (item 8)

- 3.1 RED: MZ-U5 (ours sentinel, `SHIM_GC_START_RC=1`) and MZ-U6 (absent sentinel, same): exit 5, `unfreeze-gc-timer gc_timer_restart_failed`, sentinel removal still happened in U5.
- 3.2 GREEN: `mode_unfreeze` timer branch -> `_store_refuse` with the rc captured explicitly.
- 3.3 Add the warn-only mutant (restores the old branch) and require MZ-U5 RED.
- 3.4 Update the finalizer's two "unfreeze FAILED" error lines (cleared sentinel / stopped timer wording).

## 4. Phase 3 — probe pre-flight (item 5)

- 4.1 RED: MZ-P10 (probe, `SHIM_VERIFY=r21`, marker absent) -> exit 5 `store_unverified reason=marker_absent`, no `id=` session in the timeline; MZ-P11 (probe, `SHIM_VERIFY=r23`, `SHIM_FREEZE=foreign`) -> `cutover_frozen`. Check MZ-P1..P9 timelines gain exactly the one read.
- 4.2 GREEN: `verified-only` argument on `refuse_if_store_unverified_or_not_empty`; `mode_probe` sets `STORE_SOURCE="$LUKS_MAPPER"` and calls it before the provision session.
- 4.3 Notify-body PROBE_FAILED string: name the verdict words; add/adjust the NB text row; subject word unchanged.

## 5. Phase 4 — docs and records

- 5.1 Workflow header comment and "Nothing to rollback" echo.
- 5.2 Runbook: notify-channel table (`PROBE_FAILED`, `FREEZE_HELD` rows), known-gaps sentences, verdict-map row for `gc_timer_restart_failed`, plain statement of the flip-unwind cost, bad-token RECOVERY_FAILED note.
- 5.3 Restate `MUTANT_FLOOR` and `FLOOR` from a measured run (commit the implementation first, then run mutants).
- 5.4 Run the targeted suites: the cutover-access suite, `tests/scripts/test-git-data-root-token-census.sh`, the shell-trace credential-refusal lint, `ci-deploy.test.sh`, and actionlint on the workflow; run the RB rows.
- 5.5 Simulate the rollback (scratch detached worktree: `git revert --no-commit`, rerun the cutover-access suite).

## 6. Ship

- 6.1 PR body first line: merging alone does not mutate production. `Refs` only.
- 6.2 Post the deferral comment on #9439; file the arm-B issue; do not close #9439.
- 6.3 Merge through the queue only; if a merge_group run fails on an unrelated flake, one re-enqueue then report; never sync or push a PR armed in the queue.

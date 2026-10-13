# Tasks: ship Phase 7 merge-queue-aware BEHIND handling

Plan: knowledge-base/project/plans/2026-10-07-fix-ship-phase-7-merge-queue-aware-behind-sync-plan.md
Hard boundary: PR #9697 belongs to another session. Read-only `gh` calls only; never push to, sync, enqueue or merge it.

## 1. Failing tests first

- 1.1 Add the `QGH` mock to `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (rules arm with `merge_queue` mid-array, `autoMergeRequest` arm, `pr checks` arm that runs the handed `--jq`).
- 1.2 Add scenarios Q1, Q2, Q3, Q4 (loop false/error), Q6 (loop green/none/error), Q6b (`ONCE` on expiry, `MOCK_NO_MERGE_ON_PUSH=1`), Q6c (consecutive idle count), Q7 (`MOCK_MSS=DIRTY`), Q8, Q9 (`MOCK_MERGED_AT=8`), Q10 (`MOCK_CHECKS=required_fail`), Q11 (`git()` override, sync disabled) through `run_scenario_both`; Q1 asserts `queue_wait\]` exactly once via `ONCE`; Q1 and Q6 also under `SCENARIO_SET_E=1`; `QGH` defaults `MOCK_GQL_SEQ=not_queued`.
- 1.3 Run the suite detached (`setsid nohup`, rc file written last): Q1, Q6, Q6b, Q6c, Q8, Q9 RED; Q2-Q5, Q7, Q10, Q11 GREEN.

## 2. The fence (ship canonical + merge-pr mirror, one commit)

- 2.1 `QUEUE_RULE` fetch before `while true`, gated on `sync_ok` and a non-empty `SYNC_SNAP`.
- 2.2 `[ship.phase7.queued]` report in the every-5th-tick block, gated on `QUEUE_RULE`.
- 2.3 `real_behind` marker before the DIRTY block.
- 2.4 Wait arm (armed read, pending count, idle grace with the `--queue-state` check at the crossing, expiry latch) and turn the sync `if` into the `elif`.
- 2.5 Mirror the same in `plugins/soleur/skills/merge-pr/SKILL.md` section 5.2; add the anchored parity tokens to the suite.
- 2.6 Full suite green, 0 fail.

## 3. Mutation battery (Guard 1)

- 3.1 Apply each of the 11 matrix rows (neutralise the arm with `if false &&`, never delete it) and both harness rows, observe RED, revert; record in the PR body.
- 3.2 `python3 scripts/lint-guard-contract.py` on the plan.

## 4. Prose, ADR, learning

- 4.1 ship/SKILL.md Queue mode paragraph and the unmergeable-states sentence; merge-pr section 5.2 intro and tag paragraph.
- 4.2 Reword `ship/references/settle-then-admin-merge.md` line 7.
- 4.3 Amend ADR-270 Decision 5 and record the measurement under Canary measurements (status stays adopting).
- 4.4 Append `## Resolution under the merge queue (2026-10-07)` to the 2026-06-02 learning (additions only).

## 5. Verify and ship

- 5.1 `git diff --stat origin/main -- plugins/soleur/scripts/sync-pr-behind.sh .claude/hooks/pre-merge-rebase.sh infra/github/ruleset-ci-required.tf` is empty.
- 5.2 `bash plugins/soleur/test/c4-count-parity.test.sh`; check the fixture against `scripts/suite-durations.tsv` / `scripts-shard-runtime-coverage.test.sh`.
- 5.3 `soleur:ship`: PR body `Ref #8683`, `Ref #9454`, `Ref #9670` (no Closes), Changelog, `semver:patch`.
- 5.4 After merge: comment on #8683; record the first real queue-mode PR outcome (including last-green-to-enqueue latency) on #9454.

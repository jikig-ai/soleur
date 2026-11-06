# Tasks: feat-local-test-gate-speed (#12013)

Plan: `knowledge-base/project/plans/2026-11-03-chore-local-test-gate-enable-pool-and-live-red-plan.md`

## Phase 0 — Baseline
- 0.1 Record `bash scripts/test-all.sh --print-selection` `AFFECTED_SUMMARY` fields (observation only).
- 0.2 Serial always-on run with timing log on a docs-only diff; keep `suite-timings.tsv` as the P1 floor.

## Phase 1 — Enable the pool
- 1.1 Write failing tests first: `plugins/soleur/test/affected-tests-pool-default.test.sh` (stub-runner fixture; cases a-f; mutation rows). Register in `scripts/test-all.sh`.
- 1.2 `plugins/soleur/scripts/affected-tests.sh`: runner arm, `--affected`, `CI` unset → `SOLEUR_TEST_JOBS="${SOLEUR_TEST_JOBS:-4}"` in the runner call's env only.
- 1.3 Find suites that re-invoke `test-all.sh`; scrub the width where they scrub `TEST_GROUP`; add the nested-runner test.
- 1.4 Extend `scripts/test-all-parallel-benchmark.test.sh` with the pool-beats-serial stub assertion.
- 1.5 Live measurement pair + soak (max 2 runs, background) incl. `git-data-replication`; assert `[parallel] mode engaged`; separate queue wait; add lane tokens only if a divergence is found; check `grok-pre-push-gate.sh` / one-shot concurrency.

## Phase 2 — Red visible at reap
- 2.1 Failing tests first in `scripts/test-all-parallel-scheduler.test.sh` (live lines with ms, provisional marker, one `[FAIL]`, consumers unchanged; mutation rows).
- 2.2 Add `_pj_fmt_done` helper; use at all three `[run] … done` sites in `scripts/test-all.sh`.

## Phase 3 — Measured weights
- 3.1 Measure `apps/web-platform/test/destroy-ask-mutation` and `scripts/image-cve-verdict`; add rows via `regenerate-shard-manifest.py` (growth-ack flow); exemption row only if over cap.
- 3.2 Pin that `lint-legal-registers` / `check-pa-22` stay registered (`grep -c` = 2).

## Phase 4 — Record
- 4.1 ADR-242 addendum (deviation from dispatch-level enablement, caller table, provisional-line wording, point 6 not taken).
- 4.2 `plugins/soleur/skills/ship/SKILL.md`: one sentence (pool engaged, poll loop greps the log, exit code authoritative); run `fullsuite-merge-gate.test.ts`.
- 4.3 Update `local-gate-parallel-mode.md` runbook.
- 4.4 Comment measurements on #12013; link the follow-up.
- 4.5 File the deferred follow-up issue (edge re-pricing).

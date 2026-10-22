# Tasks: apply delivery gap follower

Plan: `knowledge-base/project/plans/2026-10-23-feat-apply-delivery-gap-follower-plan.md`
Branch: `feat-one-shot-apply-delivery-gap-follower` | Draft PR: #10879 | Refs: #9454, #10033, #8167 (Ref only)

## Phase 0 - RED

- 0.1 Create `plugins/soleur/test/fixtures/apply-delivery-gap/base/` (empty world) and the ten named scenario directories plus `delivery-requires-apply-job`, `replay-37964350917`, `replay-37964762496`, `replay-38144232116`, `replay-incident-delivered` (overrides only).
- 0.2 Write `plugins/soleur/test/apply-delivery-gap-follower.test.sh`: instrument self-test, `run_case` harness, `mkrun`/`mkjobs`/`mkcompare` builders, scenarios S1-S13, R1-R4, H1/H3/H4/H5, wiring leg W, mutation battery M1-M13 + Y1-Y2 (declared count asserted).
- 0.3 Run the suite with no script present; record the red count in the commit message.

## Phase 1 - script to GREEN

- 1.1 `scripts/apply-delivery-gap.sh`: input validation, `assert_fixture_dir`, `api_get`/`fail_loud` chokepoint, fixture-mode reader (read sequence `.r<N>`, `fail.<call>` injectors, `now` file, page-size/max-page overrides in fixture mode only).
- 1.2 Runs read with paging, truncation stop, shape validation; trigger-run visibility (3 attempts).
- 1.3 Candidate filter with the per-workflow kill-switch marker table (bash `=~`, message in a variable).
- 1.4 Delivery predicate: same workflow, success, created >= S, ancestry (compare 404 = not a descendant), `apply` job leg (memoised jobs); unconditional deferral with stale caps; classification by jobs count.
- 1.5 Issue reconcile: label create before both arms, one create or one edit (`--add-label`, never remove), close rules (F3, F13, F14), body with the "Do this" block and the last-reconciled footer, close comment contents.
- 1.6 Trace notices and summary line; `--self-test` (three pure checks, under 5 s).
- 1.7 Classification gate: `bash scripts/test-all.sh --affected --print-affected-set | grep apply-delivery-gap` and `bash scripts/lint-orphan-test-suites.sh`; apply the fallback order from the plan if UNCLASSIFIED.

## Phase 2 - workflow

- 2.1 `.github/workflows/apply-delivery-gap-follower.yml` (exact permissions, own concurrency group, one event value via env, SHA-pinned checkout, no forbidden words even in comments).
- 2.2 Wiring leg green; run `actionlint`, `shellcheck`, the workflow linters.

## Phase 3 - mutation battery

- 3.1 Battery green on the default invocation (every mutant lands and reddens); record wall time (ceiling 90 s).

## Phase 4 - docs

- 4.1 Runbook section in `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` (decision table, verification, p0 note, flip-evidence recipe, stale-gap note).
- 4.2 ADR-270 addendum (decision, flip bar and counting, the F1 refinement, residuals).
- 4.3 Re-check `decision-challenges.md` with `technical-ruling-gate.sh --branch`.

## Phase 5 - verify and hand off

- 5.1 Run the full Phase 5 command list from the plan; `git diff --name-only origin/main...HEAD` must not list CODEOWNERS, `test-affected-paths.sh`, `suite-shard-legs.tsv`, an apply workflow, an AGENTS file or the acks file.
- 5.2 PR body: `Ref #9454`, `Ref #10033`, `Ref #8167`; no closing keyword; merge only through the merge queue.

# Tasks: apply delivery gap follower

Plan: `knowledge-base/project/plans/2026-10-23-feat-apply-delivery-gap-follower-plan.md`
Branch: `feat-one-shot-apply-delivery-gap-follower` | Draft PR: #10879 | Refs: #9454, #10033, #8167 (Ref only)

## Phase 0 - RED

- [x] 0.1 Create `plugins/soleur/test/fixtures/apply-delivery-gap/shim/gh` (models `gh api`, `gh issue list/create/edit/close`, `gh label create`; real 404 shape; refuses unmodeled argv with exit 64; logs reads and writes).
- [x] 0.2 Create `base/` (empty world) and the named scenario directories (overrides only): `cancelled-zero-jobs`, `cancelled-then-later-success-descendant`, `cancelled-with-jobs`, `cancelled-killswitch`, `success-only`, `non-push-or-non-main`, `inflight-descendant`, `api-failure`, `dedup`, `sibling-success-does-not-count`, `delivery-requires-apply-job`, `replay-37964350917`, `replay-37964762496`, `replay-38144232116`, `replay-incident-delivered`.
- [x] 0.3 Write `plugins/soleur/test/apply-delivery-gap-follower.test.sh`: instrument self-test, `run_case` harness with EXIT/INT/TERM cleanup, `mkrun`/`mkjobs`/`mkcompare` builders, scenarios S1-S17 (incl. S2b, S3c), R1-R4, H1/H3/H4/H5, wiring leg W, mutation battery M1-M20 + Y1-Y2 with the Phase 3 hygiene rules.
- [x] 0.4 Run the suite with no script present; record the red count in the commit message.

## Phase 1 - script to GREEN

- [x] 1.1 `scripts/apply-delivery-gap.sh`: `--self-test` first (three pure checks, prints `apply_delivery_gap_self_test=ok`), argv/env validation, `assert_fixture_dir`, fixture mode (PATH-prepended shim, `now` file, test-only page-size/max-page overrides inert in live mode).
- [x] 1.2 `api_get`/`fail_loud` chokepoint: transient retry (5xx, 429, 403 rate-limit, network, rc 124), HTTP-status classification from stderr (never echoed), 150-read budget.
- [x] 1.3 Runs read with paging (sort, dedupe, whole-page cutoff, truncation stop), relevant-run validation; trigger-run visibility (3 attempts).
- [x] 1.4 Candidate filter with the per-workflow marker table (bash `=~`, message in a variable); delivery predicate (same workflow, success, created >= S, ancestry with 404 = not a descendant, `apply` job leg, memoised jobs); unconditional deferral with per-workflow stale caps; classification by jobs count; later-run column.
- [x] 1.5 Issue reconcile: bot-author + exact-title identity, extras closed, owned labels created without overwriting, one create or one edit (`--add-label`, p1 only at create, never remove), close only with delivered >= 1 and nothing in flight, aged-out marker comment otherwise, body (Do-this block, 40-row cap, footer), write retry.
- [x] 1.6 Degraded path (best-effort upsert for read-class failures, closed by the next complete reconcile); trace notices and summary line.
- [x] 1.7 Classification gate: `bash scripts/test-all.sh --affected --print-affected-set | grep apply-delivery-gap` and `bash scripts/lint-orphan-test-suites.sh`; apply the plan's fallback order if UNCLASSIFIED (do not edit `scripts/lib/test-affected-paths.sh` while #10744 / #7390 are open).

## Phase 2 - workflow

- [x] 2.1 `.github/workflows/apply-delivery-gap-follower.yml` (exact permissions, own concurrency group, `TRIGGER_RUN_ID` as the one event value, SHA-pinned sparse checkout, no forbidden words even in comments).
- [x] 2.2 Wiring leg green; run `actionlint`, `shellcheck`, the workflow linters.

## Phase 3 - mutation battery

- [x] 3.1 Battery green on the default invocation: pristine control, rc discrimination (only an assertion-failure rc counts as caught), anchor-once-in-function, copies via env path, `timeout -k`, sub-case pins; record wall time (ceiling 90 s).

## Phase 4 - docs

- [x] 4.1 Runbook section in `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` (decision table, verification, closing is not an acknowledgement, degraded issue reasons, flip-evidence recipe, non-main dispatch warning).
- [x] 4.2 ADR-270 addendum (context, decision, flip bar and evidence unit, refinements to the ruling, residuals).
- [x] 4.3 Re-check `decision-challenges.md` with `technical-ruling-gate.sh --branch`.

## Phase 5 - verify and hand off

- [x] 5.1 Run the full Phase 5 command list from the plan, the Check-10-shaped `--self-test` run and the uncommitted live read-only rehearsal; `git diff --name-only origin/main...HEAD` must not list CODEOWNERS, `test-affected-paths.sh`, `suite-shard-legs.tsv`, `suite-durations.tsv`, an apply workflow, an AGENTS file or the acks file.
- [x] 5.2 Merge-time check: any cancelled push inside the 7-day window will page on the first reconcile. (checked 2026-10-23: no cancelled push inside the 7-day window of either workflow; the live-snapshot first reconcile yields candidates=0)
- [ ] 5.3 PR body: `Ref #9454`, `Ref #10033`, `Ref #8167`; no closing keyword; merge only through the merge queue.

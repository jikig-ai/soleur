# Tasks - measure the local affected gate and re-price its slow edge-selected suites

Plan: `knowledge-base/project/plans/2026-11-04-chore-affected-gate-measure-and-reprice-plan.md`
Issues: #12013, #12025. Draft PR: #12103. Follow-up filed: #12106.

## Phase 0 - Preconditions

- [ ] 0.1 Record `BASE_SHA` (`git rev-parse origin/main`), `uptime`, sibling `test-all.sh` runner count; kill this session's stale runs
- [ ] 0.2 `bash scripts/test-all.sh --print-selection` shows `fallback=none` on the current diff

## Phase 1 - `suite-rate` subcommand (tests first)

- [ ] 1.1 Write failing `plugins/soleur/test/ci-pr-affected-suite-rate.test.sh`: rows R1-R4, four mutations, one permitted-variation must-PASS fixture, real five-column selector stub, `gh` stub that fails if called
- [ ] 1.2 Implement `cmd_suite_rate` in `scripts/ci-pr-affected-replay.py` on `glob_units` / `glob_selector_rows` / `glob_existing_hit` / `glob_spot_check`; update docstring; leave `collect`, `select()`, `cmd_glob_rate` untouched
- [ ] 1.3 `python3 scripts/regenerate-shard-manifest.py --incremental --write`; verify `--print-affected-set` reports the new label `derived` (else move to `scripts/`, never into the split replay test); run `scripts/lint-orphan-test-suites.sh` and the existing replay test arms
- [ ] 1.4 Re-check `--print-selection` still `fallback=none`

## Phase 2 - Selection rates

- [ ] 2.1 Run `suite-rate --commits 100 --base <BASE_SHA> --out <scratch>` in the background (Monitor); record elapsed and derive-cache state
- [ ] 2.2 Copy `suite-rate.tsv` and `commits.tsv` to `knowledge-base/project/specs/feat-one-shot-12013-12025-affected-gate-reprice/measurements/`

## Phase 3 - Gate measurement (#12013)

- [ ] 3.1 Pick >= 3 diffs by the rule (30 most recent attributable commits, per-class median, web-platform upper quartile, lowest-SHA tie-break)
- [ ] 3.2 Throwaway worktree at `BASE_SHA`; apply each pick uncommitted; check `AFFECTED_SUMMARY selected` equals modelled `selected_n`
- [ ] 3.3 Start `nproc/2` CPU burners (trap-killed); run `affected-tests.sh` with timestamped stderr; record banner, summary, queue wait, cold derive, timing log path; warm rerun and serial pair (40 min box) on the median pick only
- [ ] 3.4 Induced red on a first-scheduled small suite; assert another suite starts before and ends after the provisional line, one `[FAIL]` at drain, non-zero exit; revert
- [ ] 3.5 Verify timing-row count (third column not `skip=`) equals selected count; copy logs to `measurements/gate-run-<n>.tsv`
- [ ] 3.6 Apply the 600 s rule to the median cold gate time; file the derive-cache tracker if derive >= 25 percent
- [ ] 3.7 Remove the worktree, kill burners and leftover runs

## Phase 4 - Weights and ledger (#12025)

- [ ] 4.1 Three standalone runs each for `scripts/image-cve-verdict` and `apps/web-platform/test/destroy-ask-mutation` (record "unmeasured: reason" if the latter cannot run)
- [ ] 4.2 Wall for the other six: committed CI weight tagged `ci-committed` if the bar is met, else one standalone run each
- [ ] 4.3 Apply the rule (rate x standalone wall >= 5 s per PR and a nameable verdict-input set); whole-tree suites priced-and-kept
- [ ] 4.4 Write the pricing ledger (eight full labels; `demoted` not available once; only `image-cve-verdict-consumers` is always-on)

## Phase 5 - Conditional lib edit (only if the bar is missed AND summed candidate savings >= the gap)

- [ ] 5.1 Evaluate candidate globs with `glob-rate --candidates`; read each SUT first
- [ ] 5.2 One edit of `scripts/lib/test-affected-paths.sh`; never touch the four legal-lint always-on entries; split to a second PR if the diff would exceed 800 lines
- [ ] 5.3 Never-lose-a-selection before/after diff over each suite's whole subject population; pair-audit ratchets, affected tests, kb-consumers baseline, corpus-weight budget green
- [ ] 5.4 PR test plan states the full-battery-by-construction gate and its substitute

## Phase 6 - Record

- [ ] 6.1 ADR-242 amendment (rule, measurement table, ledger, correction)
- [ ] 6.2 markdownlint on new markdown; `technical-ruling-gate.sh --branch`
- [ ] 6.3 File the conditional derive-cache tracker; comment the next lever on #12013 if unmet
- [ ] 6.4 PR body per the Closing Rules; post table and ledger on #12013 and #12025

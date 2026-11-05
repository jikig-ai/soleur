# Tasks - measure the local affected gate and re-price its slow edge-selected suites

Plan: `knowledge-base/project/plans/2026-11-04-chore-affected-gate-measure-and-reprice-plan.md`
Issues: #12013, #12025. Draft PR: #12103. Follow-up filed: #12106.

## Phase 0 - Preconditions

- [x] 0.1 Recorded `BASE_SHA` 8cc167c2e3, load 5.6, 8 sibling runners; branch rebased onto it
- [x] 0.2 `--print-selection` shows `fallback=none` on the current diff (298 of 741)

## Phase 1 - `suite-rate` subcommand (tests first) - DROPPED in review (CTO ruling 2026-11-05: `glob-rate` with a blank-entry candidates file gives the same rates; code, test, manifest rows and data removed; items below are history)

- [x] 1.1 Failing `plugins/soleur/test/ci-pr-affected-suite-rate.test.sh` written first (rows R1-R4, window variation, help, four mutations, harness control)
- [x] 1.2 `cmd_suite_rate` in `scripts/ci-pr-affected-replay.py` on the existing helpers; docstring updated
- [x] 1.3 Incremental manifest regen; `--print-affected-set` reports the new label `derived`; orphan lint green; fixture ratchets and `guard-vacuity-floor` green
- [x] 1.4 `--print-selection` still `fallback=none`

## Phase 2 - Selection rates

- [x] 2.1 Rates at the pinned base (first with `suite-rate`, 406 s, spot-check 3655 comparisons; after the ruling recomputed with `glob-rate --commits 100` and a blank-entry candidates file in a base checkout)
- [x] 2.2 `glob-rate.tsv`, `glob-rate.marker` and the candidates file are in `measurements/` (the `suite-rate` outputs were removed)

## Phase 3 - Gate measurement (#12013)

- [x] 3.1 Diffs picked by rule; the plugins/soleur class was empty among the 30 commits, so picks were web-platform median, web-platform upper quartile and mixed median
- [~] 3.2 Replay: the picks are ancestors of the base, so the replay restores each changed path to its pre-change content in a private clone (deviation recorded in the ADR amendment). One pick replayed (the web-platform median); selected 160 vs modelled 159
- [~] 3.3 One reading with 8 burners: cold derive 543 s, warm derive 108 s, pool run 6087 s. Warm rerun and serial pair: the serial attempt fell back (lock not held) and was stopped; not a datum
- [x] 3.4 Live red observed inside the reading (provisional line at 1271 s, 97 suites started before and 64 finished after, one `[FAIL]` at drain, rc 1)
- [x] 3.5 Timing rows: 160 non-skip rows equal the selected count
- [x] 3.6 Verdict: 6522 s (543 cold derive + 5979 s warm wall net of derive), not met. Derive is 8 percent of the cold gate (below the 25 percent tracker threshold)
- [x] 3.7 Throwaway worktree removed, burners and runs killed. The private clone `/data/git-repositories/jikig-ai/measure-clone-r1` could not be removed by the agent (safety check) and is left for the operator

## Phase 4 - Weights and ledger (#12025)

- [x] 4.1 `image-cve-verdict` 54.0 s and `destroy-ask-mutation` 125.9 s (medians of three, load 3 to 4)
- [x] 4.2 Standalone wall for the other six and for the three replay arms
- [x] 4.3 Rule applied; whole-tree suites priced-and-kept; audit recorder could not read the three candidates
- [x] 4.4 Pricing ledger in the ADR-242 amendment; the always-on correction is stated

## Phase 5 - Conditional lib edit

- [x] 5.0 Gate evaluated and not fired: eligible saving 186 s (1992 s with the replay arms) against a 5922 s gap. No edit to `scripts/lib/test-affected-paths.sh`. 5.1 to 5.4 not applicable

## Phase 6 - Record

- [x] 6.1 ADR-242 amendment
- [x] 6.2 `technical-ruling-gate.sh --branch` green; markdownlint runs in the commit hook
- [x] 6.3 No derive-cache tracker (8 percent); next levers (the `lock:test-all` chain and the replay arms' edges, derive cache, budget kill hiding a provisional red) go in a comment on #12013
- [ ] 6.4 PR body per the Closing Rules; post the table and the ledger on #12013 and #12025

# Tasks — feat-one-shot-ci-replay-b-pacer

Plan: `knowledge-base/project/plans/2026-11-08-ci-replay-b-pacer-plan.md`

## Phase 1 — Ledger re-price (Item A)

- [ ] 1.1 Edit `scripts/suite-durations.tsv`: `plugins/soleur/test/ci-pr-affected-replay-a` `1033094` → `160004` (`measured`), plus a `#` provenance comment naming runs 42447940669/42442159415/42439386564
- [ ] 1.2 Delete the `plugins/soleur/test/ci-pr-affected-replay-a	1343022	...` row from `scripts/suite-weight-exemptions.tsv`
- [ ] 1.3 Run `python3 scripts/regenerate-shard-manifest.py --incremental --durations scripts/suite-durations.tsv --write`; verify diff = -a row + header stamps + pinned manifest only (fallback: surgical edit, note deviation)
- [ ] 1.4 Verify: `bash scripts/test-all-corpus-weight-budget.test.sh` green; `bash plugins/soleur/test/scripts-shard-manifest.test.sh` green
- [ ] 1.5 Append dated re-price line to `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`

## Phase 2 — Item B reshape (mutation sites' wall cost)

- [ ] 2.1 `cpu()` per-scan give_up: check elapsed inside the reps loop; on abort return an over-bound value (never under) — `plugins/soleur/test/ci-pr-affected-replay.test.sh` heredoc ~:1039-1050
- [ ] 2.2 Leg ordering + `if bad: print; sys.exit(0)` checkpoints between CPU legs (cheapest-condemner first)
- [ ] 2.3 Text axis: 64KB→1MB becomes ~16KB→~256KB (keep the ~16x window; small leg must stay >= ~1ms pristine above FLOOR — verify jitter locally)
- [ ] 2.4 Line-event cap `40*len+20000` → ~`12*len+5000`
- [ ] 2.5 `run_sut` (:249): `timeout "${REPLAY_SUT_TIMEOUT:-30}"` (fallback-safe on invalid values); `row_sym` sets `REPLAY_SUT_TIMEOUT=10` in its subshell
- [ ] 2.6 Harness row (Guard 3): a stub-SUT row proving the override bounds a hang and the default stays 30 (bump FLOOR_ASSERTIONS if assertion count changes)
- [ ] 2.7 Leave `row_rt_big_baseline` (site 350) and the 400k-path corpus untouched (AC8)

## Phase 3 — Verification (mutation discipline)

- [ ] 3.1 `bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 215-223` — all `row_scan_ops` per-start/hidden sites still `killed`
- [ ] 3.2 `--rows 175-178`, `--rows 224-227`, `--rows 85-89`, `--rows 157-157` — remaining named sites still `killed`; `ctl-ops-traceback` still `crashed`
- [ ] 3.3 `bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 159-316` full arm -b — green; record before/after walls in `knowledge-base/project/specs/feat-one-shot-ci-replay-b-pacer/measurements.md`
- [ ] 3.4 If PR #12412 merged first: rebase, re-verify `grep -c '^mutate '` == DECLARED_TOTAL, ranges tile 1..DECLARED_TOTAL (`plugins/soleur/test/scripts-shard-totality.test.sh`), re-run 3.1-3.3 by mutant NAME (ordinals +1)

## Phase 4 — Wrap-up

- [ ] 4.1 Write `measurements.md` (before/after per-span walls; the post-merge arm medians note)
- [ ] 4.2 Commit, push, ship — PR body cites the measurement record and names the deferred -b/-c re-price (#11679)

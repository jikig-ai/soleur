# Work notes — feat-one-shot-12017-soak-read-window

Implementation-phase log for #12017 (Epic #11556 Lever A), plan
`knowledge-base/project/plans/2026-11-10-ci-soak-read-window-bound-plan.md`.

## Wall-time ledger (this host, contended — five foreign test-all.sh runs per the plan)

| checkpoint | wall | assertions | mutants |
|---|---|---|---|
| baseline (pristine) | 6m19.4s | 176 | 67/67 |
| Phase 1 (suite bounds only) | 3m31.5s | 176 | 67/67 |
| Phase 2 (+ probe batching) | 2m16.3s | 176 | 67/67 |
| Phase 3 (+ bounded mg pages) | 3m05.4s | 179 | 68/68 |

Phase 3's uptick vs Phase 2 is fixture-build cost: every fixture now pads its merge_group voucher
list to a full 100-entry first page (~90 filler entries per unique signature, built once thanks to
memoization) plus a second `&page=` request per probe run — the price of keeping vouchers spanning
a page boundary under the new enumeration model. Net vs baseline: −51%.

## Deviation records

- **r_max_cap seconds.** Task 1.3 says "60→40 full runs (property preserved)". Literal
  `10 60 510 2000`→`10 40 510 2000` is arithmetically impossible: (10·510 + 40·2000)/50 = 1702 s =
  28.37 min < the 1744.8 s (29.08 min) limit, so the row itself would go red expecting FAIL.
  Full-run seconds rose 2000→2200 in the same edit: 50-run mean 31.03 min (FAIL "over 29.08"),
  mutant newest-30 mean 27.28 min (pass) — property and mutant kill both preserved.
- **Fixture repagination.** The old mg-1/mg-2 split left vouchers on page 2 that the new model can
  never reach (a short page 1 ends enumeration). All voucher entries now paginate 100-per-page with
  the first page padded full, so a tail page is always fetched — same coverage class the split gave
  --paginate.
- **created_epoch placement.** `fromdateiso8601` runs in the runs-slice `--jq` (guarded by
  `fail_api "ci.yml push runs"`), not the loop feeder — a process-substitution jq failure would be
  invisible. New `badcreated` flag + `r_badcreated` pin the edge (rc 3 "ci.yml push runs").

## Structural AC census (post-Phase-3)

- loop-body `jq -r` sites: 1 (the merged TSV call); per-run `date`/voucher sites: 0.
- `CONTROL_ROWS` occurrences: 6 (definition + 3 control sites + comment mentions); zero `ALL_ROWS`
  inside `core_rows_quiet`.
- `--paginate` in the probe: 0. MG_MAX_PAGES=10 declared at :74.
- ADR-276 S2 contract vars byte-unchanged: MIN_ELIDED=10, MIN_DAYS=7, DEADLINE_DAYS=30,
  MAX_RUNS=100, IDLE_RUNS=10, MEAN_LIMIT_HUNDREDTHS_MIN=2908.
- MUTANTS: 68 of 68 caught (floor 67); zero "did NOT land"; always-PASS 10 of 12 red (floor 10,
  r_pass + r_needcomplete red-immune as commented).

## Phase 4 measurement note

Local final 3m05.4s (−51% vs 6m19.4s baseline). CI-equivalent ≈ 124 s (254.6 × 185.4/379.4),
at the ~120 s success-metric target. The committed price re-measure waits on this branch's own
CI run's `suite-timings-scripts-*` artifacts (uploaded `always()` per shard leg).

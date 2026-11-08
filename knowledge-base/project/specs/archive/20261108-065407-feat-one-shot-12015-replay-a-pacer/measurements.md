# Measurements — ci-pr-affected-replay arm timings (issue #12015)

Verdict: the `-a` pace-setter reported in `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md` (1280.4s median) is **retired**. Neither of the issue's remedies (4th `--rows` leg, fixture-corpus bound) is warranted.

## Mechanism

PR #12296 (`feat-one-shot-retire-10865-window-probe`, merged 2026-11-07T13:45Z) retired the 129 `row_ow_*` observation-window mutation sites — ordinals 1-129 of the then-602-site `DECLARED_TOTAL`. The committed site-cost measurement (`knowledge-base/project/specs/archive/20261107-204952-feat-one-shot-12013-site-cost-measurement/measurements/summary.txt`) attributes 993.4s of arm `-a`'s 1042.6s of gated site time to exactly those sites. The report's five sampled `merge_group` runs (41693754894, 41685524714, 41678029255, 41677528300, 41668436219) all ran **pre-retirement**.

## Post-retirement CI evidence (green `merge_group` runs, 2026-11-08, artifact `suite-timings-scripts-*`)

| arm | run 42447940669 | run 42442159415 | run 42439386564 | median |
|---|---|---|---|---|
| `-a` | 160004 ms | 160670 ms | 156007 ms | **160004 ms (~160s)** |
| `-b` | 196624 ms | 229025 ms | 225993 ms | 225993 ms (~226s) |
| `-c` | 183223 ms | 143796 ms | 165824 ms | 165824 ms (~166s) |

Arm `-a` is now the **fastest** arm; `-b` is the mild pace-setter at ~226s — well under the 600000ms corpus-weight cap.

## Local evidence (tree f0c3bb8656, 476-site DECLARED_TOTAL)

- Slices: `--rows 1-1` = 76s wall (unconditional head ~74s dominates a single site); 2-20/35-50/120-158/159-200/400-476 ≈ 0.4-1s/site.
- Guarded three-arm reading via the archived `site_cost_run.sh` (rep r1, verdict CLEAN, no foreign runs): walls a=173.0s b=261.9s c=210.2s; gated site seconds a=98.8 b=188.6 c=136.5; unconditional ≈ 74s per arm. Heaviest sites: `row_scan_ops` 47.3s (site 219, b), `row_rt_big_baseline` 31.2s (site 350, c), `row_sym` 30.2s (site 225, b).
- Raw reading: `/var/tmp/m12015/r1/` (not committed); rebuilt table `/var/tmp/m12015/table.tsv`.

## Ruling consequences

- 4th leg: buys ~40s of parallelism while adding a 4th ~74s unconditional head — net loss, and no arm needs relief.
- Corpus bound: `-a`'s entire gated corpus work is 98.8s; nothing material to bound.
- `suite-durations.tsv` `-a` row (1033094ms) is now over-priced post-retirement but stays internally consistent with its `suite-weight-exemptions.tsv` cap; the re-price belongs to sibling #12016 (stale-prices slice).

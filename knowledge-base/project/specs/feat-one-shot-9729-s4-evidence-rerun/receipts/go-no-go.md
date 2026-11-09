# Go/no-go re-ruling — 2026-11-09 (4th re-ruling, #9729)

Window: 300 first-parent commits of origin/main at BASE af764001eebe535b44af468c9f3904f2809f8220 (pinned 10:32Z; collect legs re-launched ~13:55Z enumerated a base shifted 3 commits — corrected to the pin by collecting the 3 missing tail commits and dropping the 3 out-of-window units; dedup on sha kept first occurrences, idx renumbered by window position).
Ejection window: 2026-10-30T09:03:16Z..2026-11-09T12:43:53Z — 446 merge_group runs, 104 refused (failure 81, cancelled 23); corroboration: merge_group_on_landed=293/300, missing=0, refused=0, read_failures=0; queue oracle shortfall=40 synthetic units, expected_units=144.

## Criteria

- (a) escape bound: attributable=0/444, unverified_as_escape=2/444 (point 0.45%, passes ≤2%), worst_case=68/444 → cp95 18.41% ≥ 12% → **fail**. Not-evaluable=66 (failed-job-without-fail-line 22, queue-oracle-shortfall ~36 synthetic, unsettled-jobs ~5, +2 unverified would-skip-suite-failed).
- (b) index completeness: pinned audit rc=0, `unaudited=0 gap_suites=0 stale=0 accepted=1639 refs=4541 files_read=1269` → **pass**.
- (c) saving: reading-1 net 69.05 ≥ 22.11 bar (M=110.55/run); reading-2 population-weighted ~92% of bar → **within-10%**.
- (d) reader audit: kb-consumers 31/31, edge:consumed sel=0 on README-only diff → **pass**.

Improvement vs R3: unclassified-* buckets eliminated (0 vs 29+20), corroboration exercised with zero drops, unsettled legs now witness-cleared (flake-cleared 32). Remaining bound driver = queue-oracle shortfall synthetics + failed-job-without-fail-line — coverage gaps in the measurement, not escapes.

SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-11-09

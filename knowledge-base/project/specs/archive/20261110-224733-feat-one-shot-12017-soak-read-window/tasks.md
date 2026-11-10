# Tasks — feat-one-shot-12017-soak-read-window

Derived from `knowledge-base/project/plans/2026-11-10-ci-soak-read-window-bound-plan.md` (#12017,
Epic #11556 Lever A).

## Phase 1 — Suite-side bounds (probe untouched)

- [x] 1.1 In `scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`, add `build_fx` memoization:
      `declare -A FX_SEEN`, key `"$fx|$*"`; on a hit `rm -f "$fx/requests.log" "$fx/refused.log"`
      and return. Comment names the invariant (no post-build fixture mutation may exist).
- [x] 1.2 Add `CONTROL_ROWS` (12 rows: `r_pass r_unmatched1 r_unmatched3 r_over r_nomarker r_zero
      r_jobsfail r_noperm_act r_adr_proposed r_unregistered r_deact r_needcomplete`) and switch the
      three `ALL_ROWS` harness controls (identity copy, no-lib copy, always-PASS probe) to it;
      update the always-PASS floor to ≥10 of 12 with a comment naming the two red-immune rows.
- [x] 1.3 `r_max_cap` fixture 60→40 full runs (property preserved vs the MAX_RUNS=30 mutant).
      NOTE: 40 full runs at 2000 s put the 50-run mean at 28.37 min — UNDER the 29.08 limit — so
      full-run seconds rose 2000→2200 in the same edit (50-run mean 31.03 min over, mutant's
      newest-30 mean 27.28 min under; property preserved).
- [x] 1.4 Verify: `bash scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh` exits 0 with the
      probe unmodified; record `time` delta vs the 12m30s local baseline (254.6s CI median).
      Measured: 6m19.4s → 3m31.5s; 176 assertions, 67/67 mutants. Commit 116fde7aff.

## Phase 2 — Probe loop batching

- [x] 2.1 In `scripts/followthroughs/ci-push-dedupe-soak-9512.sh`, merge the four per-run jq
      evaluations into one `jq -r '[(<P1>),(<P2>),(<P3>),(<P4>)] | @tsv'` with each program copied
      verbatim inside parens (all jq-internal mutant anchors stay byte-identical); bash
      `IFS=$'\t' read -r is_elided pd_failed proof_holds secs`.
- [x] 2.2 Emit `created_epoch` in the runs slice (`(.created_at | fromdateiso8601)` 4th TSV
      field); delete the per-run `date` call.
- [x] 2.3 Move voucher checking post-loop: collect elided `{id, sha}` during the loop, one jq
      pass diffs against `mg_json`, emitting `run=<id> sha=<prefix>` for `wrong`/`wrong_list`.
- [x] 2.4 Re-anchor `m-unmatched-ok` and `m-no-voucher` to the new voucher code (killable-by-
      construction replacements per learning 2026-11-08).
- [x] 2.5 Verify: suite green, `MUTANTS: 67 of 67 caught` (N ≥ 67), zero "did NOT land".
      Measured: 3m31.5s → 2m16.3s; 176 assertions. Commit b54687c88d.

## Phase 3 — Bounded merge_group enumeration

- [x] 3.1 Replace `api --paginate` on the merge_group listing with `for page in 1..MG_MAX_PAGES`
      using `&page=$p` (MG_MAX_PAGES=10); accumulate until a short page; a full last page at the
      cap → exit 3 `CANNOT ESTABLISH` naming the cap.
- [x] 3.2 Update the fake `gh`: serve `mg-N.json` per `&page=N`, `{"workflow_runs":[]}` beyond;
      refuse a merge_group read lacking `page=`; add `mgpages=K` fixture flag. Voucher fixtures
      re-paginated: entries pad to a FULL first page so the tail page is always fetched and
      vouchers span the boundary (a short mg-1 would have ended enumeration before mg-2).
- [x] 3.3 Add `r_mgcap` (mgpages=11 → rc 3) and `m-mg-cap-silent` mutant (dropping the exhaustion
      check turns `r_mgcap` red); update the requests-log assertion for the new argv shape.
      Also added `r_badcreated` (unparseable created_at → rc 3 "ci.yml push runs") pinning the
      epoch-in-slice edge, and the `badcreated` fixture flag.
- [x] 3.4 Verify: suite green; `git grep` confirms no remaining `--paginate` in the probe.
      Measured: 3m05.4s; 179 assertions, `MUTANTS: 68 of 68 caught`. Commit dc4ea86f07.

## Phase 4 — Measure + re-price

- [x] 4.1 `time bash scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`; target ≤ ~120s
      CI-class. Final local: 3m05.4s on a contended host (baseline 6m19.4s, −51%); CI-equivalent
      ≈ 124s (254.6 × 185.4/379.4), at the ~120s target.
- [x] 4.2 Re-price `scripts/suite-durations.tsv` row via
      `python3 scripts/regenerate-shard-manifest.py` (or targeted edit per PR #12419 convention);
      commit message names the green `merge_group` run IDs measured. — targeted edit at
      `scripts/suite-durations.tsv:427`: 87919 → 185400 measured (local wall on a contended host;
      this PR's test-scripts legs are oracle-selection-skipped so no CI artifact carries the new
      code; commit ae1e1ce196 names the merge_group runs used as the CI-scale basis:
      42891735582 / 42887535182 / 42864026488).
- [x] 4.3 Confirm `MAX_RUNS`, `IDLE_RUNS`, `MIN_ELIDED`, `MIN_DAYS`, `DEADLINE_DAYS`, and the
      mean limit are byte-unchanged (ADR-276 S2 contract). Verified: lines 69–77 unchanged.

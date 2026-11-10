# Tasks — feat-one-shot-12017-soak-read-window

Derived from `knowledge-base/project/plans/2026-11-10-ci-soak-read-window-bound-plan.md` (#12017,
Epic #11556 Lever A).

## Phase 1 — Suite-side bounds (probe untouched)

- [ ] 1.1 In `scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`, add `build_fx` memoization:
      `declare -A FX_SEEN`, key `"$fx|$*"`; on a hit `rm -f "$fx/requests.log" "$fx/refused.log"`
      and return. Comment names the invariant (no post-build fixture mutation may exist).
- [ ] 1.2 Add `CONTROL_ROWS` (12 rows: `r_pass r_unmatched1 r_unmatched3 r_over r_nomarker r_zero
      r_jobsfail r_noperm_act r_adr_proposed r_unregistered r_deact r_needcomplete`) and switch the
      three `ALL_ROWS` harness controls (identity copy, no-lib copy, always-PASS probe) to it;
      update the always-PASS floor to ≥10 of 12 with a comment naming the two red-immune rows.
- [ ] 1.3 `r_max_cap` fixture 60→40 full runs (property preserved vs the MAX_RUNS=30 mutant).
- [ ] 1.4 Verify: `bash scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh` exits 0 with the
      probe unmodified; record `time` delta vs the 12m30s local baseline (254.6s CI median).

## Phase 2 — Probe loop batching

- [ ] 2.1 In `scripts/followthroughs/ci-push-dedupe-soak-9512.sh`, merge the four per-run jq
      evaluations into one `jq -r '[(<P1>),(<P2>),(<P3>),(<P4>)] | @tsv'` with each program copied
      verbatim inside parens (all jq-internal mutant anchors stay byte-identical); bash
      `IFS=$'\t' read -r is_elided pd_failed proof_holds secs`.
- [ ] 2.2 Emit `created_epoch` in the runs slice (`(.created_at | fromdateiso8601)` 4th TSV
      field); delete the per-run `date` call.
- [ ] 2.3 Move voucher checking post-loop: collect elided `{id, sha}` during the loop, one jq
      pass diffs against `mg_json`, emitting `run=<id> sha=<prefix>` for `wrong`/`wrong_list`.
- [ ] 2.4 Re-anchor `m-unmatched-ok` and `m-no-voucher` to the new voucher code (killable-by-
      construction replacements per learning 2026-11-08).
- [ ] 2.5 Verify: suite green, `MUTANTS: N of N caught` (N ≥ 67), zero "did NOT land".

## Phase 3 — Bounded merge_group enumeration

- [ ] 3.1 Replace `api --paginate` on the merge_group listing with `for page in 1..MG_MAX_PAGES`
      using `&page=$p` (MG_MAX_PAGES=10); accumulate until a short page; a full last page at the
      cap → exit 3 `CANNOT ESTABLISH` naming the cap.
- [ ] 3.2 Update the fake `gh`: serve `mg-N.json` per `&page=N`, `{"workflow_runs":[]}` beyond;
      refuse a merge_group read lacking `page=`; add `mgpages=K` fixture flag.
- [ ] 3.3 Add `r_mgcap` (mgpages=11 → rc 3) and `m-mg-cap-silent` mutant (dropping the exhaustion
      check turns `r_mgcap` red); update the requests-log assertion for the new argv shape.
- [ ] 3.4 Verify: suite green; `git grep` confirms no remaining `--paginate` in the probe.

## Phase 4 — Measure + re-price

- [ ] 4.1 `time bash scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`; target ≤ ~120s
      CI-class.
- [ ] 4.2 Re-price `scripts/suite-durations.tsv` row via
      `python3 scripts/regenerate-shard-manifest.py` (or targeted edit per PR #12419 convention);
      commit message names the green `merge_group` run IDs measured.
- [ ] 4.3 Confirm `MAX_RUNS`, `IDLE_RUNS`, `MIN_ELIDED`, `MIN_DAYS`, `DEADLINE_DAYS`, and the
      mean limit are byte-unchanged (ADR-276 S2 contract).

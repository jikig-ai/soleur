# Tasks: measure replay-arm site costs for the local gate (Ref #12013)

Plan: knowledge-base/project/plans/2026-11-07-chore-measure-replay-site-costs-for-local-gate-plan.md
Measurements dir (M): knowledge-base/project/specs/feat-one-shot-12013-site-cost-measurement/measurements

## Phase 1: Preserve volatile inputs
- [x] 1.1 Copy /var/tmp/m12231/{control2,t1}/{run.log,timing.tsv} to the session scratchpad; commit M/launch_order.{t1,control2}.tsv
- [x] 1.2 Identify the 3 sites added by 8da7b8359f and their ordinals (skip if under 1% of arm c)

## Phase 2: Hook, runner, table builder
- [x] 2.1 Write M/rows-range-site-cost-hook.patch (stamps at parse-args end, in_range, rows_gate_floor entry)
- [x] 2.2 Write M/site_cost_run.sh <rep> (guard, clone, apply patch, three concurrent arms, guard.txt)
- [x] 2.3 Write M/site_cost_table.py (raw_cost, cost, noise_s, row, others_live, unconditional_s, --selftest)
- [x] 2.4 Run --selftest, fixture-relative-assert.test.sh and grep-q-pipe-guard.test.sh

## Phase 3: Site-cost runs (serial reps, about 25 min each)
- [x] 3.0 Smoke: one hooked arm with --rows 1-1 -> 604 stamp lines, rc 0, same "N passed" line as unhooked
- 3.1 site_cost_run.sh r1 then r2 (Monitor on the .rc files, load/foreign guard)
- 3.2 r3 only if an arm wall differs more than 15% between r1 and r2; replace DISTURBED reps
- 3.3 Copy stamps to M/raw/

## Phase 4: Table, validation, paper checks
- 4.1 Build M/site_costs.tsv
- 4.2 Validation (scale fit on b and c; a within 15%; flagged-site 20% rule)
- 4.3 site_cost_whatif.py: baseline reproduction on t1, split search with/without pristine charge, 27-combination paired robustness, GATE line
- 4.4 Price #12263 levers on paper; name the run-ending suite and its registration position; reap latency paragraph
- 4.5 Write M/summary.txt

## Phase 5: Conditional - only if GATE: PROCEED
- 5.1 Re-split argv in scripts/test-all.sh, scripts/ci-oracle-lane-suites.txt, argv-drift mutant in scripts/ci-oracle-lane.test.sh
- 5.2 scripts-shard-totality, ci-oracle-lane, corpus-weight-budget gates; manifest no-diff check
- 5.3 Cold readings c1 then t2 (+c2 per G1 keep rule) with adapted measure.sh/derive.sh; abort on disturbance or no pool engagement

## Phase 6: Records
- 6.1 Re-run ratchets, compare git diff with the AC2 allow-list
- 6.2 Comment on #12263
- 6.3 Prepare the #12231 closing comment (close after merge)
- 6.4 ADR-242 amendment paragraph (F1 disposition)
- 6.5 Comment on #12013; PR body with Ref #12013, Ref #12231, Ref #12263 (no Closes)

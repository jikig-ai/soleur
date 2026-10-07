# Tasks: reduce hosted-runner demand (#9721)

Plan: `knowledge-base/project/plans/2026-10-07-ci-reduce-hosted-runner-demand-plan.md`

## Phase 1: Plan artifacts (this PR)

- 1.1 Plan, ADR-276 (`proposed`) and the lever-5 memo written and linted
  - 1.1.1 `bash scripts/check-adr-ordinals.sh` passes
  - 1.1.2 `python3 scripts/lint-guard-contract.py` passes on the plan
- 1.2 Plan review applied (Stage 1 moved out of this PR)
- 1.3 Follow-up issues filed (#9727, #9728, #9729, #9730; #9512 commented)
- 1.4 Commit and push

## Phase 2: Stage 1 (own PR, #9727)

- 2.1 Failing census suite and synthesized fixture first, then the script
- 2.2 Register the suite and run `bash scripts/lint-orphan-test-suites.sh`
- 2.3 Optional smoke path gate with its own Guard Contract and a fan-out ledger bump

## Phase 3: Stage 2 (#9512)

- 3.1 Keep one real keyed job in the elided push run (an all-skipped run concludes `skipped`, measured); reuse `scripts/main-push-duplicate-skip.sh` with a `test` job-conclusion and non-draft guard
- 3.2 Keyed tolerance arm and its Guard Contract; dark launch behind a variable

## Phase 4: Stage 3 (#9728)

- 4.1 Resolve the entry gates on a throwaway PR (rollup, token identity, fork vars, arm-after-ready window, admin-merge path)
- 4.2 Draft light checks (Option R preferred), `battery-owed.sh` and `admin-merge-ready.sh` rows, ship Phase 6 wait-for-ready-run, Guard 1 mutation suite
- 4.3 Canary, then 7 days on; removal trigger at 30 days

## Phase 5: Stage 4 and 5 (#9729, #9730)

- 5.1 Re-decide S4 after S2 and S3 censuses; replay evidence
- 5.2 Decision issue for CodeQL cost and runner supply

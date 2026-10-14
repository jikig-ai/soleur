# Tasks: reduce hosted-runner demand (#9721)

Plan: `knowledge-base/project/plans/2026-10-07-ci-reduce-hosted-runner-demand-plan.md`

## Phase 1: Plan artifacts (this PR)

- [x] 1.1 Plan, ADR-276 (`proposed`) and the lever-5 memo written and linted
  - [x] 1.1.1 `bash scripts/check-adr-ordinals.sh` passes
  - [x] 1.1.2 `python3 scripts/lint-guard-contract.py` passes on the plan
- [x] 1.2 Plan review applied (Stage 1 moved out of this PR)
- [x] 1.3 Follow-up issues filed (#9727, #9728, #9729, #9730; #9512 commented)
- [ ] 1.4 Commit and push

## Phase 2: Stage 1 (own PR, #9727)

- [ ] 2.1 Failing census suite and synthesized fixture first, then the script
- [ ] 2.2 Register the suite and run `bash scripts/lint-orphan-test-suites.sh`
- [ ] 2.3 Optional smoke path gate with its own Guard Contract and a fan-out ledger bump

## Phase 3: Stage 2 (#9512)

- [ ] 3.1 Keep one real keyed job in the elided push run (an all-skipped run concludes `skipped`, measured); reuse `scripts/main-push-duplicate-skip.sh` with a `test` job-conclusion and non-draft guard
- [ ] 3.2 Compare the attestation job with keying the deploy `workflow_run` arm on the `merge_group` run (an ADR-217 amendment is required in either design); keyed tolerance arm and its Guard Contract; dark launch behind a variable

## Phase 4: Stage 3 (#9728)

- [ ] 4.1 Resolve the six entry gates on a throwaway PR (rollup, token identity, fork vars, arm-after-ready window, admin-merge path, and the cheaper alternative with its pass criterion: pre-policy and post-policy mean draft pushes per PR measured separately, post-policy at least 2.75; the gate may fail and then S3 closes); ADR-270 `accepted` and the stage's ADR-276 amendment first
- [ ] 4.2 Draft light checks (Option R is the decision; Option T rejected), `battery-owed.sh` and `admin-merge-ready.sh` rows, ship Phase 6 wait-for-ready-run, Guard 1 mutation suite
- [ ] 4.3 Canary, then 7 days on; removal trigger at 30 days

## Phase 5: Stage 4 and 5 (#9729, #9730)

- [ ] 5.1 Re-decide S4 once S2 and S3 each have a census, or are closed by their entry gate or stop rule; replay evidence; the `admin-merge-ready.sh` full-battery marker (run-level: `[full]` run-name discriminator; the on-demand `workflow_dispatch` producer exists), an admin-side control and trusted base-ref selection are entry gates
- [ ] 5.2 Decision issue for CodeQL code scanning, Code Quality and runner supply, once S2 and S3 each have a census or are closed by their entry gate or stop rule

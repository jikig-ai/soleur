# Tasks — feat-one-shot-13122-machinery-drain-verification (#13122)

Plan: `knowledge-base/project/plans/2026-11-28-chore-machinery-drain-verification-plan.md`

## Phase 1 — probe and fixture harness

- [x] 1.1 Write `scripts/followthroughs/machinery-drain-actor-gate-13122.test.sh` first with synthesized fixtures and a strict `gh` stub; cover every mutation-matrix row in the plan.
- [x] 1.2 Confirm representative rows fail before implementation where practical, then implement `scripts/followthroughs/machinery-drain-actor-gate-13122.sh` to green.
- [x] 1.3 Implement deterministic workflow-run selection: first qualifying completed post-cutoff `scheduled-machinery-drain.yml` run on main whose triggering actor is `soleur-ai[bot]`; skip only cancelled/skipped non-measurements and fail closed on incomplete pagination.
- [x] 1.4 Implement exact-step evidence reads through the jobs API and per-step logs API; never use run conclusion or parent step conclusion as actor-gate evidence.
- [x] 1.5 Implement emitted-runtime-line scans for the actor refusal and `updated standing issue #9508`; echoed workflow/shell source must not count.
- [x] 1.6 Implement #9508 comment correlation and `closed=N` classification with exit codes 0/1/2/3 exactly as specified in the plan.

## Phase 2 — registration and static gates

- [x] 2.1 Register the fixture suite in `scripts/test-all.sh`.
- [x] 2.2 Regenerate `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` with `python3 scripts/regenerate-shard-manifest.py --incremental --write`.
- [x] 2.3 Run the fixture suite standalone plus `scripts/lint-followthrough-varq-ban.sh` and applicable followthrough exec-bit/predicate parity suites.
- [ ] 2.4 Run targeted affected tests required by `soleur:work`/`soleur:qa`; record the exact commands and results.

## Phase 3 — branch sweeper dry run

- [x] 3.1 Prepare the exact post-merge tracker directive at column 0 with `secrets=GH_TOKEN` and `earliest=2026-11-30T18:00:00Z`.
- [ ] 3.2 Run the read-only branch sweeper dry run prescribed by the follow-through convention and inspect the run log for this probe's parse/exit line.
- [ ] 3.3 Confirm there is no missing-secret error and no machinery-drain production trigger is fired.

## Phase 4 — post-merge enrollment

- [ ] 4.1 After merge, create the new tracker issue with label `follow-through` and the exact unfenced column-0 directive.
- [ ] 4.2 Verify the tracker issue body and labels with `gh issue view`.
- [ ] 4.3 Close #13122 with a comment naming the tracker and dry-run evidence; leave the new tracker open for the probe to close on PASS.

# Tasks — fix #8760 (carried-over jobs) and #9085 (follower lock placement)

Plan (v3, deepened): `knowledge-base/project/plans/2026-09-27-fix-pin-redeploy-gate-ignores-carried-over-jobs-plan.md`

## Phase 1 — Setup

- [ ] 1.1 Capture `tests/scripts/fixtures/gh-run-view-36325677861-attempt2-jobs-startedAt.json` with the plan's exact command (`GH_REPO=jikig-ai/soleur`), and record the command and date in the suite's provenance comment.
- [ ] 1.2 Look in `git-data-pin-redeploy.yml` run history for evidence that a job skipped by `if:` does not cancel a pending job. Record what you find, or that there is none, for the PR body (AC12).

## Phase 2 — Tests first (RED)

- [ ] 2.1 gh stub: add source arms for `--json jobs,startedAt` with and without `--attempt N`, both covered by `view.rc`. Delete the `--attempt N --json jobs` arm.
- [ ] 2.2 Harness: `_gexec` writes `$S/harness.violation` on any UNEXPECTED line and leaves its return code alone. The G/GH/GM loops check for the marker. `_scenario` unsets `ATT`. Add the HX row.
- [ ] 2.3 `_gjob`/`_gdoc`: take timestamps from the fixture, with a `carried` profile. Update G23's expected argvs.
- [ ] 2.4 Add rows GC1 (and GC1b) through GC9, each with its GH entry. Add GM mutations 1-7 (Guard 1).
- [ ] 2.5 Parity tests (`plugins/soleur/test/terraform-target-parity.test.ts`): rewrite the follower-structure tests for the two jobs. Add Guard 2's five RED cases. PT3 checks each job; PT5's lookup reads `jobs.redeploy`.
- [ ] 2.6 Confirm GC1 fails against the current gate with only the argv patched (H1 evidence).

## Phase 3 — Implementation (GREEN)

- [ ] 3.1 Gate: switch the source argv; add CARRIED as a single jq expression whose failure means `no` (not via `_q`); add row 2c; add the `carried` flag and a notice arm that is one `echo` line with `verdict=carried_over` and `REDEPLOY_CMD`; update the header.
- [ ] 3.2 Workflow: split into a `gate` job (no lock, `actions: read`, outputs mapped, pin_published email, failure email) and a `redeploy` job (`needs: gate`, `if: needs.gate.outputs.proceed == 'true'`, the job-level group, `actions: write`, 80 min, pointer, `track.sh`, failure email). Update the header comments.
- [ ] 3.3 ADR-237: add the clause. Runbook: add the `verdict=carried_over` sentence on a line that names `source-run-gate`, and rewrite both `.jobs[0].steps[]` lookups to read `jobs.redeploy`.

## Phase 4 — Verification

- [ ] 4.1 Re-measure `FLOOR` from a green run; comment it with the date and #8760.
- [ ] 4.2 Local light checks: `bash -n`, `shellcheck`, the dispatch-web-redeploy suite. Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test` and rely on CI for the rest.
- [ ] 4.3 AC1-AC13 green in CI on the exact head SHA (including the parity suite and `c4-count-parity.test.sh`). The PR body carries `Closes #8760`, `Closes #9085`, H1, the fixture re-capture diff and the AC12 evidence. The PR touches `.github/`, so it gets auto-merge only.

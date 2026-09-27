# Tasks — fix #8760: pin-redeploy gate skips carried-over git-data jobs only with deploy evidence

Plan: `knowledge-base/project/plans/2026-09-27-fix-pin-redeploy-gate-ignores-carried-over-jobs-plan.md`

## Phase 1 — Setup (fixtures from the live API)

- [ ] 1.1 Capture `tests/scripts/fixtures/gh-run-view-36325677861-attempt2-jobs-startedAt.json` with the plan's exact command (`GH_REPO=jikig-ai/soleur`).
- [ ] 1.2 Capture `tests/scripts/fixtures/gh-web-platform-release-evidence.json` with the per-id loop in the plan.
- [ ] 1.3 Record both commands, the date and the run ids in the suite's fixture-provenance comment.

## Phase 2 — Tests first (RED)

- [ ] 2.1 gh stub: source arms `--json jobs,startedAt` (with and without `--attempt N`); delete the `--attempt N --json jobs` arm; per-id `view.<id>.rc`; new `run list --workflow web-platform-release.yml --limit 50 --json databaseId,status,event,createdAt` arm (`relruns.json` / `relruns.rc`).
- [ ] 2.2 `_gexec`: assert zero `UNEXPECTED` lines and, unless `EVIDENCE=1`, zero release-list calls (`grep -cxF` compared to 0).
- [ ] 2.3 `_gjob` / `_rep` / `_birth` / `_gdoc`: timestamps from the captured fixture; carried profile sets the apply step's `completedAt` to the captured job's `completedAt`.
- [ ] 2.4 Update G23's expected argv.
- [ ] 2.5 Add rows GC1 (a/b/c) through GC13 (a-d) and H3; add the non-proceed GC rows to the GH list.
- [ ] 2.6 Confirm GC1 fails against the current gate (H1 evidence for the PR body).

## Phase 3 — Gate (GREEN)

- [ ] 3.1 Source read `--json jobs,startedAt`; run-level epoch read through its own checked assignment.
- [ ] 3.2 CARRIED: one jq expression printing `yes`/`no`; any jq failure means `no`; only for attempt >= 2.
- [ ] 3.3 DEPLOYED_AFTER: `T_apply` from the apply step's `completedAt`; list, then filter (`EVENT_ARM`, not `queued`, `createdAt >= T_apply`); view each candidate; exactly one `deploy` concluded `success`; failures mean false.
- [ ] 3.4 Row 2c in `grade()`; `carried` flag and notice arm in the combination loop. The notice is one `echo` line carrying `deploy_after_apply=${EV}`, `verdict=carried_over` and `REDEPLOY_CMD`. Add `deploy_after_apply=none` to `rotated` when CARRIED holds without evidence.
- [ ] 3.5 Header: predicates block, row 2c, replace the `SOURCE_RUN_ATTEMPT` paragraph, `Env:` line.

## Phase 4 — Guard battery and docs

- [ ] 4.1 Add GM mutations 1-13 from the Guard Contract; each must red its named row.
- [ ] 4.2 Re-measure `FLOOR` from a green run and comment it with the date and #8760.
- [ ] 4.3 Add one sentence to the workflow comment (`THE GATE` paragraph), one clause to ADR-237 and the runbook line (on a line naming `source-run-gate`).
- [ ] 4.4 Check locally, lightly: `bash -n`, `shellcheck`, the dispatch-web-redeploy suite, then rely on CI (commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`).

## Phase 5 — Verification

- [ ] 5.1 AC1-AC12 green in CI on the exact head SHA (PT5 via `terraform-target-parity.test.ts`, `c4-count-parity.test.sh`).
- [ ] 5.2 PR body: `Closes #8760`, H1/H2 evidence, and the diff of re-captured fixtures against the committed ones.

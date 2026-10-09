# Tasks: canary_sandbox_failed self-diagnosis (Ref #9871, Ref #9860)

Plan: knowledge-base/project/plans/2026-10-09-fix-canary-sandbox-failure-self-diagnosis-plan.md

## Phase 1: Tests first (ci-deploy.test.sh)

- 1.1 Docker mock: diag arm keyed on the `soleur-canary-diag` token, placed BEFORE the Guard-2 recorder and the `bwrap`-substring arms; writes MOCK_CANARY_DIAG_LOG and MOCK_CANARY_SEQ_LOG; env knobs MOCK_CANARY_DIAG_OUT / _RC / _SLEEP.
- 1.2 Docker mock: `stop` and `rm` append to MOCK_CANARY_SEQ_LOG.
- 1.3 Logger mock: MOCK_LOGGER_FAIL=1 exits 1 after capture.
- 1.4 Row D1: rc!=0 emits exactly one diag exec, >= 8 DIAG lines, last-field anchor, order DEPLOY_ROLLBACK < DIAG < stop/rm.
- 1.5 Row D2: rc==0 (pass and pass-with-chatter) emits zero diag exec and zero DIAG lines.
- 1.6 Rows D3: diag rc=1, diag hang (CANARY_DIAG_TIMEOUT=1), 4 MB output, logger failing: exit code, state file reason, teardown and DEPLOY_ROLLBACK line unchanged vs baseline.
- 1.7 Row D4: credential-shaped fixtures (synthesized, incl. one straddling the 8192-byte read cut) are redacted in logger capture and stdout.
- 1.8 Row D5: source census of CANARY_DIAG_SCRIPT and both functions, with a positive control.
- 1.9 Row D6: faithful-path emission once per deploy; none on ok and canary_infra_error.
- 1.10 Row D7/D8: Guard 1/2 unmodified and green; instrument control for the DIAG-line helper.
- 1.11 Raise CI_DEPLOY_ASSERT_FLOOR by the measured number of added rows (dated comment).

## Phase 2: Implementation (ci-deploy.sh)

- 2.1 Add CANARY_DIAG_SCRIPT, _canary_diag_emit, emit_canary_sandbox_diag after _cred_err_tail.
- 2.2 Call `emit_canary_sandbox_diag legacy || true` in the canary_sandbox_failed arm after the DEPLOY_ROLLBACK logger line and before docker stop.
- 2.3 Call `emit_canary_sandbox_diag faithful || true` in run_canary_replay on sandbox_broken (CANARY_DIAG_EMITTED once-guard).
- 2.4 Add the DIAG-bundle subsection (section names, H1-H5 decision table, query) to knowledge-base/engineering/operations/runbooks/canary-probe-set.md under the bwrap self-report heading.
- 2.5 Bump BASELINE_DECLARED_PROBES 51 -> 52 in plugins/soleur/test/preflight-discoverability-test.test.ts with the PLACEMENT/TRUTH/NO SUBSTITUTE comment; run that suite (not skippable via LEFTHOOK_EXCLUDE=bun-test).
- 2.6 Run ci-deploy.test.sh, shellcheck, lint-shell-capture-exit; confirm probe statement and rollback line are byte-identical in the diff.

## Phase 3: Delivery verification (no SSH)

- 3.1 After merge, `bash scripts/check-deploy-script-parity.sh --status-only`; if apply-deploy-pipeline-fix was cancelled (#8167), re-dispatch only with the operator's explicit go.
- 3.2 After the next canary failure, read SOLEUR_CANARY_SANDBOX_DIAG via scripts/betterstack-query.sh and decide H1-H5 per the plan table.

## Ship notes

- PR body: `Ref #9871`, `Ref #9860`, never `Closes`.
- Comment on #8167 with the 2026-10-09 recurrence evidence (plan Secondary Findings 1).
- File follow-ups if confirmed: push CI red on d7dfd05aac gated v0.334.1; tag/image provenance mismatch.

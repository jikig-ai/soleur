# Tasks — fix: main-health-monitor red on scripts shards (TEST_GROUP env leak)

Plan: `knowledge-base/project/plans/2026-11-03-fix-main-health-monitor-test-group-env-leak-plan.md`
Issue: #11939 | Draft PR: #11952 | Deferral: #11953

## Phase 1 — Failing test first

- 1.1 Add Part C ("environment hygiene") to `scripts/test-all-group-affected.test.sh`, reusing the `run_sb` fixture sandbox (run serially: `env -u SOLEUR_TEST_JOBS`): probe suite(s) registered in the spliced region, each printing `PROBE <name> TEST_GROUP=<set|absent>` plus a `bash -c` grandchild reading (a free extra reading, not a mutation row).
- 1.2 Add the built-in positive control (row 1: delete the demotion line from the sandbox runner copy via a `re.M` `^export -n TEST_GROUP$` match asserting exactly one hit; probe must read `set`) and the must-PASS rows (positional channel; `TEST_GROUP=scripts-heavy`; these guard over-rejection only).
- 1.3 Add the ledger floors (>= 2 probes, >= 1 control, each sentinel exactly once).
- 1.4 Run against the unfixed runner with `TEST_GROUP=scripts` exported; record the RED output.

## Phase 2 — The fix

- 2.1 `scripts/test-all.sh`: add `export -n TEST_GROUP` directly after `unset SCRIPTS_SHARD SOLEUR_SHARD_MANIFEST SOLEUR_SHARD_MANIFEST_HEAVY`; extend the comment (consume at the point of coupling; placement after group resolution/alias/parse) WITHOUT writing the literal `export -n TEST_GROUP` in the comment (the sandbox splice asserts exactly one line match).
- 2.2 `scripts/test-all.sh`: correct the SCOPE NOTE near `_shard_selects` that says the monitor runs `TEST_GROUP=all`.
- 2.3 Re-run Part C: GREEN.
- 2.4 Drive mutation rows 2, 3, 4 once each by hand against a scratch copy of the sandbox runner (reorder into the registration window; silent probes; `export TEST_GROUP` injected between probe A and probe B) and record RED per row in the PR body (not committed); row 1 is the committed control.

## Phase 3 — Verification

- 3.1 Run the three originally failing suites as runner children under the monitor shape: `TEST_GROUP=scripts SCRIPTS_SHARD=<k>/8 bash scripts/test-all.sh` for the shards owning `scripts/lint-orphan-test-suites-mutations-a`, `-b` and `scripts/test-all-group-affected`.
- 3.2 `bash plugins/soleur/test/main-health-monitor-workflow.test.sh` and `bash scripts/followthroughs/jobs1-stopgap-7432.test.sh` pass unchanged.
- 3.3 `bash scripts/lint-orphan-test-suites.sh` exit 0; `python3 scripts/lint-guard-contract.py` on the plan exit 0.
- 3.4 `bash scripts/test-all.sh --affected` (measured gate; runner is the changed file).
- 3.5 Push; dispatch `gh workflow run main-health-monitor.yml --ref feat-one-shot-11939-main-health-scripts-shards -f dry_run=true`; arm a watch; require every leg green.

## Phase 4 — Ship

- 4.1 PR body: `Closes #11939` only if 3.5 is fully green, else `Ref #11939`; include the RED evidence from 1.4/2.4.
- 4.2 Post-merge: confirm the next scheduled monitor run is green.
- 4.3 Capture the learning (`soleur:compound`): "run each suite under the channel its caller ships" (env-vs-positional), extending the 2026-08-14 and 2026-10-31 entries.

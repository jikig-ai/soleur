# Tasks: Item I, the JOBS=1 stopgap on the main health monitor

Plan: `knowledge-base/project/plans/2026-10-16-chore-grep-q-series-item-i-jobs1-stopgap-plan.md`
Issue: #7432 (Ref, not Closes). Tracker: #9217 (Ref). Draft PR: #10459.

## Phase 0: re-measure

- 0.1 Pull the monitor history and the infra-validation legs with the `gh` queries in `evidence.md` (the `measure/` scripts were cut at review)
- 0.2 Confirm the pull is well-formed (every run has its annotation and its legs) before reading any count
- 0.3 Compare M1 to M4 with the plan figures; a suite RED at `-P 4` that was clean at `-P 1` in a paired sha goes back to the CTO agent before any edit

## Phase 1: guard first, then the pin-removed edit, then the dry-run gate

- 1.1 Lift check (12) into `check_jobs_pin(text)` in `plugins/soleur/test/main-health-monitor-workflow.test.sh`; write Guard 1 rows 1, 2, 3, 4a, 4b, 5 and P1 as in-Python assertion pairs first (each asserts the mutation landed), watch (12b) go RED against the current workflow and save that output for `evidence.md`; raise `MIN_ASSERTIONS` by the rows added
- 1.2 Edit `.github/workflows/main-health-monitor.yml`: remove the infra-step `JOBS: 1` and its pointer comment, keep the tests-step pin, rewrite the comment block (no literal `JOBS: 1` in comments), add one TIMEOUT BUDGET line
- 1.3 Run `bash plugins/soleur/test/main-health-monitor-workflow.test.sh`; commit guard and workflow together
- 1.4 Verify `git log -1 --format='%an <%ae>'` reads Jean Deruelle; push the branch (diff must touch no `apps/web-platform/infra/` path and not `apply-web-platform-infra.yml`)
- 1.5 Dispatch twice: `gh workflow run main-health-monitor.yml --ref feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap -f dry_run=true`; list the runs with `gh run list --workflow main-health-monitor.yml --branch <branch> --event workflow_dispatch --json databaseId,createdAt,headSha`
- 1.6 Wait with the Monitor tool (never a background polling loop), then read each run's `main-health-outcomes` annotation and job log (`gh api --allow-escape-sequences`)
- 1.7 Gate: the tests-step log prints the `not_in_diff` skip line and no nested runner; both runs show `-P 4`, `infra=success` (or only the known tag-drift RED), `infra_elapsed_s` at most 2400, no timeout annotation, no `[KILLED]`, no `UNACCOUNTED`; elapsed 2400 to 3000 s is ambiguous, so dispatch a third time; a non-deterministic RED or elapsed above 3000 s goes to 5b

## Phase 2: stale-statement corrections (comment-only)

- 2.1 `.github/workflows/infra-validation.yml` comment: monitor infra step now runs at the default width
- 2.2 ADR-252 sentence "main-health-monitor keeps JOBS:1 ..." corrected
- 2.3 `.claude/hooks/grep-q-pipe-guard.test.sh` STILL OPEN header: Item I outcome with its #9217 reference
- 2.4 The `run-registered-suites.sh` "pinned on both steps" clause is fixed by the separate bounds PR #10486, not here (an edit under `apps/web-platform/infra/` would arm the nested runner)

## Phase 3: follow-through probe

- 3.1 Read `scripts/sweep-followthroughs.sh` exit map (0 close, 1 reopen/comment, 2 NOT YET, 3 CANNOT ESTABLISH, 5 ACTION REQUIRED) and how `SOLEUR_FT_EARLIEST` reaches the probe
- 3.2 Write `scripts/followthroughs/jobs1-stopgap-7432.test.sh` first (Guard 2 rows 1 to 8, P1, X; strict stub `gh` that exits 64 on unmodeled argv; copy `assert_fixture_dir` from the 9728 suite)
- 3.3 Rewrite `scripts/followthroughs/jobs1-stopgap-7432.sh`: xtrace refusal prologue (exit 78), soak window from `SOLEUR_FT_EARLIEST`, 12 oldest non-cancelled `main` runs, allowlist for the tag-drift RED, `RETIREMENT:` header line
- 3.4 Delete line 30 of `scripts/lint-shell-trace-credential-refusal.baseline.txt`; run `python3 scripts/lint-shell-trace-credential-refusal.py`
- 3.5 Register the suite with one `run_suite` line in `scripts/test-all.sh`; run `bash scripts/lint-orphan-test-suites.sh` and the PJ_TRIPLES recompute before and after
- 3.6 Add `checks: read` to `.github/workflows/scheduled-followthrough-sweeper.yml` with a comment citing #8450
- 3.7 BEFORE merge (ship gating, CTO Q3/Q4): set the #7432 directive `earliest=2026-10-19T00:00:00Z` or later (re-edit if the merge slips past it), post the revert trigger on #7432, update its body item 1, raise it to priority/p2, and remove the follow-through directive from #7376's body; after merge read the first sweep comment: NOT YET (exit 2), not CANNOT ESTABLISH (exit 3)
- 3.8 Review round (2026-10-18): bounds PR #10486 must merge BEFORE this PR is marked ready (the soak starts on its bounds); probe rewritten (flag, per-run width proof, strikes, judged list); guard quoted-key, wrong-block and runner-parity rows; monitor pinned to `ubuntu-24.04`; #7376 probe deleted; `measure/` deleted

## Phase 4: evidence, ship

- 4.1 Write `evidence.md` (figures, dispatch rows, commands) under the spec dir
- 4.2 `python3 scripts/lint-guard-contract.py` on the plan; markdownlint on plan, tasks and evidence
- 4.3 PR body with `Ref #7432` / `Ref #9217`, figures, CTO lines, revert trigger, the left-as-is clause; `soleur:ship`
- 4.4 `soleur:postmerge`; comment the Item I merge record on #9217 (do not emit DONE)

## Phase 5b: not-fixed branch (only if 1.7 fails or 0.3 flips)

- 5b.1 Revert the Phase 1 commit; no workflow, probe or comment edits land
- 5b.2 Fresh CTO consult on the new data; record `Ruled by CTO agent` in `decision-challenges.md`
- 5b.3 Comment Item I as not fixed on #9217 with the failing run id, suite, rc and elapsed

# Tasks: Item I, the JOBS=1 stopgap on the main health monitor

Plan: `knowledge-base/project/plans/2026-10-16-chore-grep-q-series-item-i-jobs1-stopgap-plan.md`
Issue: #7432 (Ref, not Closes). Tracker: #9217 (Ref). Draft PR: #10459.

## Phase 0: re-measure

- 0.1 Run `ITEM_I_DIR=/var/tmp/item-i-work bash knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap/measure/run-all.sh`
- 0.2 Confirm the output contains `CONTROLS OK` before reading any count
- 0.3 Compare M1 to M4 with the plan figures; a suite RED at `-P 4` that was clean at `-P 1` in a paired sha goes back to the CTO agent before any edit

## Phase 1: guard first, then the pin-removed edit, then the dry-run gate

- 1.1 Lift check (12) into `check_jobs_pin(text)` in `plugins/soleur/test/main-health-monitor-workflow.test.sh`; write Guard 1 rows 1 to 5 and P1 as in-Python assertion pairs first and watch (12b) go RED against the current workflow
- 1.2 Edit `.github/workflows/main-health-monitor.yml`: remove the infra-step `JOBS: 1` and its pointer comment, keep the tests-step pin, rewrite the comment block (no literal `JOBS: 1` in comments), add one TIMEOUT BUDGET line
- 1.3 Run `bash plugins/soleur/test/main-health-monitor-workflow.test.sh`; commit guard and workflow together
- 1.4 Verify `git log -1 --format='%an <%ae>'` reads Jean Deruelle; push the branch (diff must touch no `apps/web-platform/infra/` path)
- 1.5 Dispatch twice: `gh workflow run main-health-monitor.yml --ref feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap -f dry_run=true`; list the runs with `gh run list --workflow main-health-monitor.yml --branch <branch> --event workflow_dispatch --json databaseId,createdAt,headSha`
- 1.6 Wait with the Monitor tool (never a background polling loop), then read each run with `measure/extract-monitor-facts.sh` and the `main-health-outcomes` annotation
- 1.7 Gate: both runs show `-P 4`, `infra=success` (or only the known tag-drift RED), `infra_elapsed_s` at most 2400, no timeout annotation, no `[KILLED]`, no `UNACCOUNTED`; elapsed 2400 to 3000 s is ambiguous, so dispatch a third time; a non-deterministic RED or elapsed above 3000 s goes to 5b

## Phase 2: stale-statement corrections (comment-only)

- 2.1 `.github/workflows/infra-validation.yml` comment: monitor infra step now runs at the default width
- 2.2 ADR-252 sentence "main-health-monitor keeps JOBS:1 ..." corrected
- 2.3 `.claude/hooks/grep-q-pipe-guard.test.sh` STILL OPEN header: Item I outcome with its #9217 reference
- 2.4 Leave the `run-registered-suites.sh` clause; record it in the PR body

## Phase 3: follow-through probe

- 3.1 Read `scripts/sweep-followthroughs.sh` exit map (0 close, 1 reopen/comment, 2 NOT YET, 3 CANNOT ESTABLISH, 5 ACTION REQUIRED)
- 3.2 Write `scripts/followthroughs/jobs1-stopgap-7432.test.sh` first (Guard 2 rows 1 to 6 and P1, stub `gh`)
- 3.3 Rewrite `scripts/followthroughs/jobs1-stopgap-7432.sh` to the soak criterion (12 oldest non-cancelled main runs after the workflow's last commit); add a `RETIREMENT:` header line
- 3.4 Register the suite with one `run_suite` line in `scripts/test-all.sh`; run `bash scripts/lint-orphan-test-suites.sh`
- 3.5 Update the #7432 body directive (`earliest=` merge plus 3 days) at ship time; keep the issue open

## Phase 4: evidence, ship

- 4.1 Write `evidence.md` (figures, dispatch rows, commands) under the spec dir
- 4.2 `python3 scripts/lint-guard-contract.py` on the plan; markdownlint on plan, tasks and evidence
- 4.3 PR body with `Ref #7432` / `Ref #9217`, figures, CTO lines, revert trigger, the left-as-is clause; `soleur:ship`
- 4.4 `soleur:postmerge`; comment the Item I merge record on #9217 (do not emit DONE)

## Phase 5b: not-fixed branch (only if 1.7 fails or 0.3 flips)

- 5b.1 Revert the Phase 1 commit; no workflow, probe or comment edits land
- 5b.2 Fresh CTO consult on the new data; record `Ruled by CTO agent` in `decision-challenges.md`
- 5b.3 Comment Item I as not fixed on #9217 with the failing run id, suite, rc and elapsed

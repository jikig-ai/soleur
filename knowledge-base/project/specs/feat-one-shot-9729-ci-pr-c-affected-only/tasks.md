# Tasks: S4 PR C, affected-only pull_request runs (Ref #9729)

Plan: `knowledge-base/project/plans/2026-10-15-feat-ci-pr-c-affected-only-plan.md`. Every stage 2 task is GO only: do not start Phase 3 or 4 before `receipts/go-no-go.md` exists, is committed and says GO. Never write to the repo while a `test-all.sh` run is in flight. `Ref #9729` only in every PR text.

## Phase 0: Preflight

- 0.1 Run `bash scripts/test-all.sh --capacity`; under contention rely on CI and run the minimal local set one suite at a time with exit codes captured.
- 0.2 Confirm no competing PR, `CI_PR_AFFECTED` absent, organization variables 0.
- 0.3 Preview the scope with `bash scripts/test-all.sh --print-selection` (state `selected N of M`); never `TEST_GROUP=affected` as the lead gate.
- 0.4 Probe the vehicle: push a throwaway branch with a trivial workflow to test the `workflow` scope; if refused, stop stage 1 at "evidence incomplete: no vehicle" and ask the user.
- 0.5 Run `pipeline-tally.sh` only as `cd <worktree> && ...` in one command.

## Phase 1: Evidence (stage 1, no workflow edit)

- 1.0 Cheap kill: 30-commit stratified local sample, mean skipped suite-min vs the 19.96 job-min bar; reconcile the 99.8 and 164.4 denominators; a deterministic fail writes NO-GO and skips 1.2 chunks, 1.3 replay and 1.5.
- 1.1 Write `scripts/ci-pr-affected-preactivation.sh` and its test first (Guard 4 rows, RED then GREEN); run it and record the output.
  - 1.1.1 Six readers: variable, org_variables, lock, artifacts, verdict, prereq5; `ac9c` informational.
  - 1.1.2 Mutants as one apply/revert/expect table.
- 1.2 Write `scripts/ci-pr-affected-replay.sh` and its test (R2 semantics, resumable chunks, `aggregate`, worst-case Clopper-Pearson bound, index-completeness audit with the PR 9404 fixture, candidate list for the reader audit).
- 1.3 Vehicle: throwaway branch `canary-sel-9729` from the feature head with one push-triggered workflow; cold, warm, restored passes as separate steps; replay chunks as matrix jobs; poll with Monitor; read times from the jobs API; record `nproc`, kernel, image version.
- 1.4 Re-measure the dark cost with the stated window and units; record the oldest run still listed.
- 1.5 Reader audit: state the grep command and count; classify each file.
- 1.6 Fixture hardening for #10373 (`maintenance.auto false`, `gc.auto 0`) in `scripts/ci-pr-selection.test.sh` and `scripts/test-all-pr-battery-gate.test.sh`; commit unconditionally; `Ref #10373`.

## Phase 2: Go/no-go record

- 2.1 Write `receipts/go-no-go.md` (criterion rows with status, `computed=`, `ruled=`); verdict function pinned by a test over every status combination.
- 2.2 Spawn `soleur:engineering:cto` on the measured numbers; record `Ruled by CTO agent, <date>` in `decision-challenges.md`; write the machine line; commit and push; delete the canary branch.
- 2.3 NO-GO: write the ADR NO-GO amendment, file the retire-the-stage issue (due merge plus 7 days), ship stage 1. Evidence incomplete: file the follow-through issue (due merge plus 7 days).

## Phase 3: Readers, probe, census (GO only)

- 3.1 `pr-affected-active` step in `ci.yml` plus pin updates and the widened reader census (Guard 2 rows first).
- 3.2 `ci-head-verdict.sh full-verified` and the `admin-merge-ready.sh` call on `CHECK_SHA` (Guard 1 rows first, including the carryover, skipped-`pr-selection` and stacked-PR rows).
- 3.3 Consumer sweep with the closed regex set and census test; ship rerun carve-out and the aggregator remedy-line pin; ADR-270, ADR-262, ADR-183 pointers.
- 3.4 `ci-full-battery-audit.sh` and the `full-battery-audit` job in `post-merge-monitor.yml` (Guard 3 rows first); dry-run dispatch receipt (run id, label, test issue, email).
- 3.5 Census by-mode split and escape count (issue count).
- 3.6 `--admin` and the queue: cite a SHA from history or omit the sentence.

## Phase 4: Lock removal (last commit of the work phase, GO only)

- 4.1 `row_lock_coupling` (unlocked sandbox copy) and `row_empty_skippable`, RED first.
- 4.2 Run the gate script; PR body records `variable=absent` only.
- 4.3 Remove the lock and the dead read; keep `locked=false` on the notice; invert the lock rows and mutants; add the unlocked `darkequiv` rows.
- 4.4 Re-derive the floors of the edited suites from a full green run.
- 4.5 Finalize the ADR amendment (prerequisite 1, named responder, prerequisite-5 producer, latency, runbook, supersessions).

## Phase 5: Verify and ship

- 5.1 Scripted mutant tables per suite; drop mutants that kill nothing.
- 5.2 Minimal local set, then CI's full battery as the authority; extend the declared inputs of `scripts/ci-pr-selection.test.sh`.
- 5.3 Read this PR's own ready run (`pr-selection` skipped, legs and `test` green).
- 5.4 11-seat review plus `soleur:engineering:review:user-impact-reviewer`; ship archives this plan and spec (Phase 6.45); UNTRUSTED-CI rules apply to a stage 2 PR (no agent `--admin`; BEHIND livelock means ask the user; never sync a BEHIND PR with auto-merge armed).

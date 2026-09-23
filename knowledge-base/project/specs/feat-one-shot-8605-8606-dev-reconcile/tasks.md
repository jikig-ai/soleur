# Tasks: dev-ledger closed-PR ownership, dev reconcile, run-migrations cwd fix (#8605, #8606)

Plan: `knowledge-base/project/plans/2026-09-23-fix-dev-ledger-closed-unmerged-reconcile-and-migration-gate-cwd-plan.md`
(the Guard Contract is the source of truth for mutation rows).

## Phase 1: #8606 run-migrations pathspecs

- [ ] 1.1 RED: parameterize `runScript()` by cwd in `apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts`;
  run all cases from the repo root and `apps/web-platform`; add the collision case for both.
- [ ] 1.2 Record the subdirectory RED run for the PR body.
- [ ] 1.3 GREEN: anchor both `git ls-tree` pathspecs in `run-migrations.sh` with `:(top,literal)`; rewrite the header comment.
- [ ] 1.4 Apply G1-M1..M4 once each and record the RED case.
- [ ] 1.5 Past-tense the #8606 sentence in the `dev-ledger-parity.sh` header.

## Phase 2: classifier (`closed` verdict)

- [ ] 2.1 Test harness: fake `gh` in `BIN`; `GITHUB_REPOSITORY` in `run_classify` and `run_probe`; update the two exact-summary cases.
- [ ] 2.2 RED: Guard 2 rows G2-M1..M11 and harness rows H1-H2.
- [ ] 2.3 `owner_candidates`, `branch_pr_state` (commit-bound, file memo, `jq -e`, `fromdateiso8601`, no `--paginate`).
- [ ] 2.4 `classify_row` fresh walk with `closed` fallback; five-field `closed` line; summary field appended.
- [ ] 2.5 `DLP_AS_LIBRARY` library mode; usage text; repoint the two `check` messages at the workflow.
- [ ] 2.6 `action.yml`: `github-token` input; `closed` arm with the 24 h split; blocking list, fail condition, Sentry class; stale text.
- [ ] 2.7 `tenant-integration.yml` and `scheduled-dev-migration-drift.yml`: `pull-requests: read`, pass the token; run `tests/scripts/test-dev-suite-mutex-wiring.sh`.

## Phase 3: writer `dev-ledger-reconcile.sh`

- [ ] 3.1 RED: Guard 3 rows G3-M1..M16 and harness rows H1-H2, including the fake mutex sharing the psql log.
- [ ] 3.2 Parse, env check, PR facts, `refs/pull/N/head` fetch with sha check.
- [ ] 3.3 First-parent tree walk for (F, B) pairs and down pairing; early `nothing to do` exit.
- [ ] 3.4 Mutex acquire (own state dir, 600 s), in-mutex reopen check, ledger read with `applied_at`.
- [ ] 3.5 Eligibility; raw-media blob fetch with hash check; BEGIN/COMMIT normalization; refusals (transactional, non-transactional, CASCADE with a later foreign row).
- [ ] 3.6 Dry run output; execute units (CAS `DO` block + down body, one `psql --single-transaction -f` per row, descending); summary; EXIT trap composing cleanup and release.

## Phase 4: workflow `dev-ledger-reconcile.yml`

- [ ] 4.1 RED: Guard 4 static cases G4-M1..M5 and the 0-steps harness row.
- [ ] 4.2 Triggers, permissions, job `if:`, checkout of main, Doppler CLI, reconcile step with env-only inputs and step outputs.
- [ ] 4.3 Audit comment via the REST issues-comments API; `action-required` issue with de-duplication.
- [ ] 4.4 Workflow lints (AC8).

## Phase 5: ADR, learning, archive

- [ ] 5.1 Append the ADR-061 amendment (AC10).
- [ ] 5.2 Replace the #8605 pointer in the 2026-05-21 learning.
- [ ] 5.3 Tick AC11 in the #8521 plan, commit, then run `archive-kb.sh` for both slugs; repoint the test header's plan pointer (AC11).

## Phase 6: verification

- [ ] 6.1 Raise `EXPECTED_CASES` to the exact count; update the `guard-vacuity-floor.test.sh` comment number.
- [ ] 6.2 Repo ratchets (AC9) and `c4-count-parity` (AC13).
- [ ] 6.3 Pre-merge live read (AC12): `gh workflow run scheduled-dev-migration-drift.yml --ref feat-one-shot-8605-8606-dev-reconcile`.

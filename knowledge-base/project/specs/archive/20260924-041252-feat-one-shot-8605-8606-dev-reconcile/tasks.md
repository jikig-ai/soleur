# Tasks: dev-ledger closed-PR ownership, dev reconcile, run-migrations cwd fix (#8605, #8606)

Plan: `knowledge-base/project/plans/2026-09-23-fix-dev-ledger-closed-unmerged-reconcile-and-migration-gate-cwd-plan.md`
(deepened 2026-09-23; the Guard Contract is the source of truth for mutation rows).

## Phase 1: #8606 run-migrations pathspecs

- [x] 1.1 RED: parameterize `runScript()` by cwd in `apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts`;
  run all cases from the repo root and `apps/web-platform`; add the collision case for both.
- [x] 1.2 Record the subdirectory RED run for the PR body.
- [x] 1.3 GREEN: anchor both `git ls-tree` pathspecs in `run-migrations.sh` with `:(top,literal)`; rewrite the header comment.
- [x] 1.4 Apply G1-M1..M3 once each and record the RED case.
- [x] 1.5 Past-tense the #8606 sentence in the `dev-ledger-parity.sh` header.

## Phase 2: shared harness and classifier (`closed-grace` / `closed`)

- [x] 2.1 Harness: fake psql `-f` capture + writer-mode contract + instrument self-tests; routed, sequenced fake `gh` (branch-keyed
  `pulls?head=`, sequenced `pulls/N`, raw `git/blobs`, 403/5xx/non-JSON modes); shared ordered call log with a fake mutex;
  suite-wide `GH_CONFIG_DIR`, `GH_TOKEN=invalid`, `GH_HOST=fixture.invalid`, `GITHUB_REPOSITORY`; update the two exact-summary cases.
- [x] 2.2 RED: Guard 2 rows G2-M1..M16 (each arm its own case) and harness rows H1-H2 (exit-127 `gh`, never a removed fake).
- [x] 2.3 `owner_candidates`; `branch_pr_state` (commit-bound, reduction rules, file memo, `-i` status split, one retry on 5xx/429, `fromdateiso8601`).
- [x] 2.4 `classify_row` fresh walk with `closed-grace`/`closed` (`CLOSED_GRACE_H=24`), closed before stale; summary fields appended.
- [x] 2.5 Library mode: `declare -gA`, `DLP_AS_LIBRARY` with direct-run error, Library API comment block, `independent_holder` extraction.
- [x] 2.6 Messages: no-`content_sha` message names the workflow; A1 message keeps restore-and-new-file first and adds the discard alternative.
- [x] 2.7 `action.yml`: `github-token` input; `closed-grace` (warning) and `closed` (blocking, Sentry class) arms; stale text; orphan lookup hint.
- [x] 2.8 `tenant-integration.yml` and `scheduled-dev-migration-drift.yml`: `pull-requests: read`, pass the token; run `tests/scripts/test-dev-suite-mutex-wiring.sh`.

## Phase 3: writer `dev-ledger-reconcile.sh`

- [x] 3.1 RED: Guard 3 rows G3-M1..M23 (each arm its own case, each zero-write row with a positive control) and harness rows H1-H3;
  writer copy (`DLR_WRITER`) beside a guard copy (`DLR_GUARD`) in a separate writer clone; `DLP_OWNERS_CACHE` unset.
- [x] 3.2 Top-level source of the guard from the writer's own dir; composed EXIT trap; `mktemp` temp files; `--help` first.
- [x] 3.3 Parse, env check, PR facts (fork / null `head.repo`), `refs/pull/N/head` fetch with sha check.
- [x] 3.4 First-parent tree walk for (F, B) pairs and down pairing; early `nothing to do` exit.
- [x] 3.5 Open-PR author check; mutex acquire (own state dir, 600 s, banner check); in-mutex reopen re-read; ledger read with microsecond `applied_at`.
- [x] 3.6 Eligibility; raw-media blob fetch with hash check.
- [x] 3.7 Refusals: backslash byte; wrapper normalization; `python3` stripped view; transaction-control, non-transactional and later-row-sensitive sets;
  open-PR ledger-only; the 95-file pinned refusal-set case.
- [x] 3.8 Dry-run output (`would-discard`, `later-row`); single execute unit (timeouts, CAS `DO` blocks, down bodies, `applied_at` DESC then filename DESC),
  `env -u GH_TOKEN psql … --single-transaction -f`; timeout → rc 2; output hygiene (`::stop-commands::`, validated lines only).

## Phase 4: workflow `dev-ledger-reconcile.yml`

- [x] 4.1 RED: Guard 4 static cases G4-M1..M7, the argv case, and the 0-steps harness row.
- [x] 4.2 SECURITY ENVELOPE header; triggers and input descriptions; permissions; job `if:`; checkout with no `ref:`; Doppler CLI; Doppler dev assertion step.
- [x] 4.3 Reconcile step with env-only inputs, argv building, validated step outputs.
- [x] 4.4 Audit comment via the REST issues-comments API; action-required issue on any close-path failure or residue, de-duplicated, failing the job if it cannot be filed.
- [x] 4.5 Workflow lints (AC8).

## Phase 5: ADR, learning, archive

- [x] 5.1 Append the ADR-061 amendment with every required element (AC10).
- [x] 5.2 Replace the #8605 pointer in the 2026-05-21 learning.
- [x] 5.3 Tick AC11 in the #8521 plan, commit, then run `archive-kb.sh` for both slugs; repoint the test header's plan pointer (AC11).

## Phase 6: verification

- [x] 6.1 Raise `EXPECTED_CASES` to the exact count; update the `guard-vacuity-floor.test.sh` comment number.
- [x] 6.2 Repo ratchets (AC9) and `c4-count-parity` (AC13).
- [x] 6.3 Pre-merge live read (AC12): `gh workflow run scheduled-dev-migration-drift.yml --ref feat-one-shot-8605-8606-dev-reconcile`.

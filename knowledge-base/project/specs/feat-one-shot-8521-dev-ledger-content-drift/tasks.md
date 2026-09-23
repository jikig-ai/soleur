# Tasks: fix PR-CI unmerged-migration ledger parity (#8520, #8521)

Plan: `knowledge-base/project/plans/2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md`

## Phase 0: RED first

- [ ] 0.1 Create `apps/web-platform/scripts/dev-ledger-parity.test.sh`.
  - [ ] 0.1.1 Fixture scaffold: a bare `origin` with `main` history (one migration renamed on main), a set of feature branches, a work clone, and a fake `psql` on `PATH` (scripted rows / empty / non-zero). Scrub `GIT_DIR` and `GIT_INDEX_FILE`.
  - [ ] 0.1.2 Guard 1 matrix: rows 1–11, must-PASS rows (a)–(g), harness rows H1–H4.
  - [ ] 0.1.3 Guard 2 matrix: rows 1–9, the must-PASS rows, harness rows H1–H3.
  - [ ] 0.1.4 Wiring asserts on `tenant-integration.yml`: Guard 1 rows 12–14 and the AC4 anchor token. Key them on step names and order.
  - [ ] 0.1.5 Wiring asserts on `action.yml`: the `Repair:` line, the renamed-after-apply line, the `missing_pairs` split, and the fail-on-only call.
  - [ ] 0.1.6 SQL-literal assert (AC7): compare the fake-psql argv capture byte-for-byte.
  - [ ] 0.1.7 Put `EXPECTED_CASES` directly above its `if`.
- [ ] 0.2 Run the suite with no script present. Every row must fail, and the suite must not report "0 passed, 0 failed".

## Phase 1: Ownership primitive

- [ ] 1.1 Write `branch_owners` in `dev-ledger-parity.sh`. It must be lazy, fetch once by refspec into `refs/ledger-owners/*` with `--depth=1 --filter=blob:none` (verify the filter; fall back if needed), use `for-each-ref`, exclude the base branch and `gh-readonly-queue/*`, and run `ls-tree` per head.
- [ ] 1.2 Match owners in tier order: exact name, then blob, then slug. Exclude `*.down.sql`.
- [ ] 1.3 Measure the wall time against the real `origin`. Record it for the PR body (AC8).

## Phase 2: `check` subcommand

- [ ] 2.1 CLI: `need_value` parser, `--repo` required with `_assert_repo_root`, `--help` that shows the `ledger-parity:` summary format, and the exit triad.
- [ ] 2.2 Population `U`: `git -C "$REPO"` with a `:(top)` pathspec everywhere, `hash-object`, `M` and `T` sets.
- [ ] 2.3 Ledger read: `${DATABASE_URL_POOLER:-${DATABASE_URL:-}}`, where empty means exit 2. Fixed SELECT only. Zero rows means exit 2. Sanitize names and SHAs.
- [ ] 2.4 Arms A1 and A2, where an exact-name owner means `::notice::`. Remediation texts. Exit-2 messages end in "not caused by this PR; re-run".
- [ ] 2.5 Summary line, plus the `U = ∅` notice. Sanitize branch names in annotations.

## Phase 3: Workflow wiring (`.github/workflows/tenant-integration.yml`)

- [ ] 3.1 `detect-changes`: a new step after `filter` that emits `ledger_guard` (`base` / `introduction` / `deleted`), computed over full history, and the new job output.
- [ ] 3.2 `detect-changes`: append the `apps/web-platform/scripts/dev-ledger-parity` anchor.
- [ ] 3.3 Heavy job: the `Resolve dev-ledger-parity guard (base-ref copy)` step, after `Lint migration FK preconditions` and before `Acquire dev-suite mutex`. `LEDGER_GUARD` comes in via `env:`.
- [ ] 3.4 Heavy job: the `Assert unmerged migrations match the dev ledger` step, between `Detect dev-vs-main migration drift` and `Preflight schema-vs-ledger consistency check`, run under `doppler run`.
- [ ] 3.5 Comment block on the new steps (property, fail-not-reapply, ADR-061, #8521).

## Phase 4: `classify-missing` + drift-probe action

- [ ] 4.1 `classify-missing`: stdin pairs, main-history exclusion (blobless `--unshallow` of main), ownership, one output line per input line.
- [ ] 4.2 `action.yml` step `probe`: collect `missing_pairs` separately from the display, call the classifier under fail-on only, emit in-flight warnings and orphan errors, fail closed on classifier failure or a line-count mismatch, and base the exit on orphans plus content drift.

## Phase 5: Repair paths and records

- [ ] 5.1 Add the `Repair:` line to the `action.yml` content-drift block, and the renamed-after-apply line to the missing block.
- [ ] 5.2 Add a `## Content drift (same filename, different blob)` section to learning `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` (the A/B/C procedure).
- [ ] 5.3 Amend ADR-061 via `soleur:architecture`: `## Amendment 2026-09-23` with points 1 and 2.

## Phase 6: Verification

- [ ] 6.1 `bash apps/web-platform/scripts/dev-ledger-parity.test.sh` is green (AC1, AC2, AC3, AC4, AC5, AC7).
- [ ] 6.2 `shellcheck` passes. `lint-orphan-test-suites.sh`, `lint-workflow-step-env-refs.test.sh`, `lint-workflow-errexit-capture.test.sh` and `lint-migration-immutability.test.sh` are green (AC9).
- [ ] 6.3 The PR's own heavy job prints `ledger-parity: clean` with `ledger-rows` > 0 (AC10).
- [ ] 6.4 The PR body carries `Closes #8520`, `Closes #8521`, the run evidence, the AC8 timing, and #8606 (AC12).

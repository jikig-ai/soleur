# Tasks: fix PR-CI unmerged-migration ledger parity (#8520, #8521)

Plan: `knowledge-base/project/plans/2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md`
(deepened 2026-09-23; the Guard Contract is the source of truth for rows).

## Phase 0: RED first

- [ ] 0.1 Create `apps/web-platform/scripts/dev-ledger-parity.test.sh`.
  - [ ] 0.1.1 Fixtures. Build a bare `origin` over a `file://` URL with `uploadpack.allowFilter=true`,
    plus a variant without it. Give `main` history in which one migration is renamed on main. Add
    feature branches, including the PR head pushed to origin, and a work clone. Put a fake `psql` on
    PATH (NUL-delimited argv log, scripted rows, empty result, non-zero exit). Scrub `GIT_DIR` and
    `GIT_INDEX_FILE`.
  - [ ] 0.1.2 Harness. The guard runs as a copy (`DLP_GUARD`), with a control run of the unmutated
    guard. Only rc=1 counts as caught. Place `EXPECTED_CASES` directly above its `if`.
  - [ ] 0.1.3 Guard 1 matrix. Rows 1–15 plus 3b, 4b, 5b and 9b. Must-PASS rows (a)–(j). Harness rows
    H1–H5.
  - [ ] 0.1.4 Guard 2 matrix. Rows 1–12 plus 3b and 3c, the must-PASS rows, and harness rows H1–H3.
    Rows 4, 5, 7, 9 and 12 run the extracted `probe` block with stubbed psql, doppler and
    `GITHUB_OUTPUT`.
  - [ ] 0.1.5 Wiring asserts. Anchor exact step names (`^      - name: <exact>$`, count 1), check the
    order, and assert the anchor token and the `action.yml` lines (AC3, AC4, AC5).
  - [ ] 0.1.6 Assert that the checkout's `.git/config` and `.git/shallow` are unchanged after both
    subcommands run (AC7).
- [ ] 0.2 Run the suite with the script absent. Every row fails, and the suite does not report
  "0 passed, 0 failed".

## Phase 1: Ownership primitive (`owners_repo`)

- [ ] 1.1 Create a throwaway bare repo with `mktemp -d` and a trap that removes it. Fetch
  `+refs/heads/*:refs/owners/*` once, with full history, `--filter=blob:none`, the checkout's origin
  URL and extraheader, and `timeout 120`. A filter warning is not a failure. On fetch failure, exit 2
  with class `transient`.
- [ ] 1.2 Owner set. Exclude the base branch, `gh-readonly-queue/*`, heads that are ancestors of base,
  and heads with no commit in over 30 days (those give the `stale` verdict).
- [ ] 1.3 Build each head's map from its files that are absent from the base tree, skipping
  `*.down.sql`. Match in tier order: exact name, then blob, then slug. Apply the main-history
  exclusion.
- [ ] 1.4 Sanitize under `LC_ALL=C`. Branch names must match `^[A-Za-z0-9._/-]+$`, filenames must pass
  the whitelist, and SHAs must match `^[0-9a-f]{40}$`.
- [ ] 1.5 Measure one build against the real `origin` for AC8.

## Phase 2: `check` subcommand

- [ ] 2.1 CLI. Use the `need_value` parser, make `--repo` required and validate it, accept an
  optional `--head-branch`, and make `--help` show both summary formats. Exit 2 messages are classed
  `transient` or `config`.
- [ ] 2.2 Build `U`, `M` and `T` with `git -C "$REPO"` and `:(top,literal)` pathspecs everywhere.
- [ ] 2.3 Ledger. Read it every run. Use `${DATABASE_URL_POOLER:-${DATABASE_URL:-}}` and a single
  `psql -c` with the `readonly LEDGER_SQL` query. Zero rows means exit 2.
- [ ] 2.4 Arms. A1, with its own message for an empty SHA. Candidates `C`: skip a candidate that
  another fresh branch holds by exact name, with a notice. Then A2 (blob or slug), then A4 (a blob in
  the PR-branch history). Remediation texts, including the `gh api` fallback and the
  no-credentials escalation.
- [ ] 2.5 Summary line and the notice for `U = ∅`.

## Phase 3: Workflow wiring (`.github/workflows/tenant-integration.yml`)

- [ ] 3.1 In `detect-changes`, add the `Resolve dev-ledger-parity guard state` step. It uses full
  history, emits `ledger_guard` (`base`, `introduction`, `deleted`, or `n/a` on merge_group), and
  never exits non-zero. Add the job output.
- [ ] 3.2 In `detect-changes`, add the `apps/web-platform/scripts/dev-ledger-parity` anchor.
- [ ] 3.3 In the heavy job, add `Resolve dev-ledger-parity guard (base-ref copy)` after the FK lint
  and before the mutex. It is a `case` with `base`, `introduction`, `deleted`→exit 1 and `*`→exit 1.
- [ ] 3.4 In the heavy job, add `Assert unmerged migrations match the dev ledger` between
  `Detect dev-vs-main migration drift` and `Preflight schema-vs-ledger consistency check`. Pass
  `HEAD_BRANCH` via `env:` and run it under `doppler run`.
- [ ] 3.5 Add a comment block to the new steps.

## Phase 4: `classify-missing` + drift-probe action

- [ ] 4.1 `classify-missing`. Re-validate stdin, emit ordered verdicts (`in-flight`, `stale`,
  `orphan`), and write a `ledger-classify:` summary to stderr.
- [ ] 4.2 In `action.yml` step `probe`:
  - make the suspicious-row line count-only;
  - add `missing_pairs`;
  - call the classifier only when fail-on is set;
  - check each output line against its input;
  - map verdicts to warnings or errors;
  - on failure, print `UNCLASSIFIED` first and list the rows under `Unclassified:`;
  - decide the exit from orphan, stale, unclassified and content-drift rows.

## Phase 5: Repair paths and records

- [ ] 5.1 Add the `Repair:` line to the `action.yml` content-drift block, and the
  `no live branch owns these rows` line to the missing block.
- [ ] 5.2 Add `## Content drift (same filename, different blob)` (the A/B/C procedure) to the learning
  `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`.
- [ ] 5.3 Amend ADR-061 via `soleur:architecture`: `## Amendment 2026-09-23` with points 1 and 2, and
  the "superseded in part" note.

## Phase 6: Verification

- [ ] 6.1 `bash apps/web-platform/scripts/dev-ledger-parity.test.sh` is green (AC1–AC5, AC7).
- [ ] 6.2 shellcheck and the sibling lint suites are green (AC9).
- [ ] 6.3 The PR's own heavy job prints `ledger-parity: clean` with `ledger-rows` > 0 (AC10).
- [ ] 6.4 Run `gh workflow run scheduled-dev-migration-drift.yml --ref feat-one-shot-8521-dev-ledger-content-drift`.
  The output shows `ledger-classify:`, or no drift, and never `UNCLASSIFIED`. Record the timing
  (AC10b).
- [ ] 6.5 The PR body has `Closes #8520` and `Closes #8521`, the run evidence, the AC8 and AC10b
  timings, and #8606 (AC12).

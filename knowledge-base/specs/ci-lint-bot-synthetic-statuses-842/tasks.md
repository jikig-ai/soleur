# Tasks: ci lint check for bot workflows missing synthetic statuses

## Phase 1: Setup

- [ ] 1.1 Create `scripts/lint-bot-synthetic-statuses.sh` with executable permissions
  - Scan `.github/workflows/scheduled-*.yml` for `gh pr create`
  - Verify matching files also contain `context=cla-check` and `context=test`
  - Exit non-zero with clear error listing non-compliant files
  - Exit 0 with summary when all files pass

## Phase 2: CI Integration

- [ ] 2.1 Add `lint-bot-statuses` job to `.github/workflows/ci.yml`
  - `runs-on: ubuntu-latest`
  - Checkout with pinned `actions/checkout` SHA
  - Run `bash scripts/lint-bot-synthetic-statuses.sh`

## Phase 3: Testing

- [ ] 3.1 Create `test/lint-bot-synthetic-statuses.test.sh`
  - Test: file with `gh pr create` + both contexts passes (exit 0)
  - Test: file with `gh pr create` missing `context=test` fails (exit 1)
  - Test: file with `gh pr create` missing `context=cla-check` fails (exit 1)
  - Test: file with `gh pr create` missing both contexts fails (exit 1)
  - Test: file without `gh pr create` is skipped (exit 0)
  - Test: empty workflow directory (no scheduled-*.yml) exits 0
- [ ] 3.2 Add test suite to `scripts/test-all.sh` runner
  - Add `run_suite` entry for `test/lint-bot-synthetic-statuses.test.sh`
- [ ] 3.3 Run full test suite to verify no regressions

## Phase 4: Validation

- [ ] 4.1 Run lint script against current repo to confirm all 9 bot workflows pass
- [ ] 4.2 Run `soleur:compound` before commit
- [ ] 4.3 Commit, push, create PR with `Closes #842`

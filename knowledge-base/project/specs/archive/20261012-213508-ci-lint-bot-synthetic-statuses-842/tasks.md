# Tasks: ci lint check for bot workflows missing synthetic statuses

## Phase 1: Setup

- [ ] 1.1 Create `scripts/lint-bot-synthetic-statuses.sh` with executable permissions (`chmod +x`)
  - Accept `WORKFLOW_DIR` env var override (default: `.github/workflows`)
  - Define `REQUIRED_CONTEXTS=("cla-check" "test")` array
  - Scan `$WORKFLOW_DIR/scheduled-*.yml` for `gh pr create`
  - For matching files, verify `context=cla-check` and `context=test` also present
  - Track `checked` and `failures` counters
  - Print `ok: $file` for passing files (CI debuggability)
  - Exit 1 with clear error listing non-compliant files
  - Exit 0 with `"All N scheduled bot workflow(s) have required synthetic statuses."`

## Phase 2: CI Integration

- [ ] 2.1 Add `lint-bot-statuses` job to `.github/workflows/ci.yml`
  - `runs-on: ubuntu-latest`
  - Checkout with pinned `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`
  - Run `bash scripts/lint-bot-synthetic-statuses.sh`
  - Parallel to existing `test` job (no dependency)

## Phase 3: Testing

- [ ] 3.1 Create `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh` (auto-discovered by `test-all.sh` loop)
  - Source `test-helpers.sh` for `assert_eq`, `print_results`
  - Resolve `LINT_SCRIPT` path: `$SCRIPT_DIR/../../..` (3 levels up to repo root)
  - Use `WORKFLOW_DIR` env var to point lint script at temp directories
  - Test 1: file with `gh pr create` + both contexts passes (exit 0)
  - Test 2: file with `gh pr create` missing `context=test` fails (exit 1)
  - Test 3: file with `gh pr create` missing `context=cla-check` fails (exit 1)
  - Test 4: file with `gh pr create` missing both contexts fails (exit 1)
  - Test 5: file without `gh pr create` is skipped (exit 0)
  - Test 6: empty workflow directory (no scheduled-*.yml) exits 0
- [ ] 3.2 Run full test suite (`bash scripts/test-all.sh`) to verify no regressions
  - Note: `test-all.sh` does NOT need updating -- it auto-discovers `plugins/soleur/test/*.test.sh`

## Phase 4: Validation

- [ ] 4.1 Run `bash scripts/lint-bot-synthetic-statuses.sh` against current repo to confirm all 9 bot workflows pass
- [ ] 4.2 Run `soleur:compound` before commit
- [ ] 4.3 Commit, push, create PR with `Closes #842`

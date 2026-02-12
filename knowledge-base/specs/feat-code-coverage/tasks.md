# Tasks: Add Code Coverage

**Issue:** #66
**Plan:** `knowledge-base/plans/2026-02-12-feat-add-code-coverage-plan.md`

## Phase 1: Setup

- [x] 1.1 Create `apps/telegram-bridge/bunfig.toml` with coverage thresholds (80% line, 80% function)
- [x] 1.2 Verify `bun test --coverage` passes locally from `apps/telegram-bridge/`

## Phase 2: CI Integration

- [x] 2.1 Add coverage enforcement step to `ci.yml` (kept existing `bun test` step, added separate coverage step)
- [x] 2.2 Add `--coverage` flag and `working-directory` for telegram-bridge step
- [x] 2.3 Existing tests step unchanged -- runs all tests without coverage

## Phase 3: Validation

- [x] 3.1 Run full test suite from repo root to confirm nothing breaks
- [x] 3.2 Coverage verified locally: 88.54% functions, 96.79% lines (above 80% threshold)

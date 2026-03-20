# Spec: Add Code Coverage

**Issue:** #66
**Branch:** feat-code-coverage
**Date:** 2026-02-12

## Problem Statement

The project has 527 tests across two domains but no code coverage measurement, thresholds, or CI enforcement. Developers can merge PRs that regress test coverage without any signal.

## Goals

- G1: Measure code coverage for telegram-bridge using Bun's native `--coverage`
- G2: Enforce minimum thresholds (80% lines, 80% functions) in CI
- G3: Block PRs that drop below thresholds

## Non-Goals

- NG1: Coverage for plugin component tests (markdown validators -- metrics not meaningful)
- NG2: External reporting services (Codecov, Coveralls)
- NG3: PR comments with coverage diffs
- NG4: Per-file coverage thresholds

## Functional Requirements

- FR1: CI pipeline collects coverage when running telegram-bridge tests
- FR2: CI fails if line coverage drops below 80%
- FR3: CI fails if function coverage drops below 80%
- FR4: Plugin component tests continue to run without coverage collection

## Technical Requirements

- TR1: Use Bun's built-in `--coverage` (V8 instrumentation) -- zero new dependencies
- TR2: Thresholds configured in `apps/telegram-bridge/bunfig.toml`
- TR3: CI workflow updated to run domain-specific test steps

## Files to Change

| File | Action | Purpose |
|------|--------|---------|
| `apps/telegram-bridge/bunfig.toml` | Create | Coverage threshold configuration |
| `.github/workflows/ci.yml` | Modify | Split test steps, add `--coverage` for telegram-bridge |
| `lefthook.yml` | Modify (optional) | Add coverage to local pre-commit |

## Acceptance Criteria

- [ ] `bun test --coverage` in `apps/telegram-bridge/` enforces 80% line and 80% function thresholds
- [ ] CI fails on PRs that drop below thresholds
- [ ] Plugin component tests are unaffected (no coverage collection)
- [ ] No new dependencies added

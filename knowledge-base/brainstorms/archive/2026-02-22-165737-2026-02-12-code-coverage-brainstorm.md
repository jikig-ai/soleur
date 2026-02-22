# Code Coverage Brainstorm

**Date:** 2026-02-12
**Issue:** #66
**Branch:** feat-code-coverage

## What We're Building

Add code coverage enforcement to the CI pipeline using Bun's native `--coverage` support. When a PR drops coverage below 80% lines or 80% functions in telegram-bridge, CI fails and blocks the merge.

## Why This Approach

- **Bun native tooling** -- The project constitution mandates preferring Bun builtins. Bun's `--coverage` uses V8 instrumentation with zero additional dependencies.
- **Scoped to telegram-bridge** -- The plugin component tests validate markdown structure, not TypeScript source code. Coverage metrics only make sense for telegram-bridge (84 tests, real TypeScript logic).
- **Hard CI gate** -- PRs that regress coverage below thresholds cannot merge. No soft warnings -- the project values strictness.
- **CI gate only, no external reporters** -- Keep it simple. No Codecov or Coveralls. Just pass/fail based on thresholds in `bunfig.toml`.

## Key Decisions

1. **Scope:** Telegram-bridge only. Plugin component tests excluded (their "coverage" is just helpers.ts -- not meaningful).
2. **Tooling:** Bun native `--coverage` via `bunfig.toml` configuration. Zero new dependencies.
3. **Thresholds:** 80% lines, 80% functions globally. Current baseline is 88.5% functions / 96.8% lines, so 80% gives room without allowing major regressions.
4. **Enforcement:** CI fails the PR if below threshold. No override mechanism.
5. **Reporting:** CI pass/fail only. No PR comments or coverage diff reports. Can add Codecov later if needed.

## Implementation Sketch

### Files to Change

1. **`apps/telegram-bridge/bunfig.toml`** (new) -- Coverage thresholds config
2. **`.github/workflows/ci.yml`** (modify) -- Run telegram-bridge tests with `--coverage`
3. **`lefthook.yml`** (optional) -- Add `--coverage` to local pre-commit for telegram-bridge

### Configuration

```toml
# apps/telegram-bridge/bunfig.toml
[test]
coverage = true
coverageThreshold = { line = 80, function = 80 }
```

### CI Change

Split the single `bun test` step into domain-specific steps:
- `bun test plugins/soleur/test/` (no coverage)
- `cd apps/telegram-bridge && bun test --coverage` (with coverage enforcement)

## Open Questions

- Should `lefthook.yml` also enforce coverage on pre-commit, or is CI-only sufficient? Pre-commit adds latency.
- Should we add a coverage badge to the README?

## What We're NOT Building

- External coverage reporting services (Codecov, Coveralls)
- Coverage for plugin component tests (markdown validators)
- Per-file coverage thresholds
- Coverage diff reporting on PRs

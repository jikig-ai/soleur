---
title: "feat: Add Code Coverage"
type: feat
date: 2026-02-12
---

# feat: Add Code Coverage

## Overview

Add code coverage enforcement to CI using Bun's native `--coverage`. Telegram-bridge tests must maintain 80% line and 80% function coverage or PRs are blocked.

## Problem Statement

527 tests exist across two domains but no coverage measurement, thresholds, or CI enforcement. PRs can regress test coverage without any signal.

## Proposed Solution

Use Bun's built-in V8 coverage instrumentation with threshold enforcement via `bunfig.toml`. Split the CI test step into domain-specific steps so coverage only applies to telegram-bridge (where metrics are meaningful).

## Non-Goals

- Coverage for plugin component tests (markdown validators -- only coverable file is `helpers.ts`)
- External reporting services (Codecov, Coveralls)
- PR comments with coverage diffs
- Per-file coverage thresholds
- Coverage in pre-commit hooks (CI is the gate)

## Acceptance Criteria

- [x] `apps/telegram-bridge/bunfig.toml` configures 80% line and 80% function thresholds
- [x] CI runs telegram-bridge tests with `--coverage` and fails if below thresholds
- [x] CI runs plugin component tests separately without coverage
- [x] No new dependencies added
- [x] Current test suite passes with coverage enabled (baseline: 88.5% functions, 96.8% lines)

## Test Scenarios

- Given telegram-bridge tests pass with current coverage, when CI runs `bun test --coverage`, then the step succeeds
- Given a PR drops function coverage below 80%, when CI runs, then the test step fails with non-zero exit
- Given plugin component tests run, when CI executes, then no coverage is collected for that step
- Given `bunfig.toml` sets `coverage = true`, when running `bun test` from `apps/telegram-bridge/`, then coverage report is printed

## MVP

### apps/telegram-bridge/bunfig.toml

```toml
[test]
coverage = true
coverageThreshold = { line = 0.8, function = 0.8 }
```

### .github/workflows/ci.yml

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup Bun
        uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install

      - name: Run plugin component tests
        run: bun test plugins/soleur/test/

      - name: Run telegram-bridge tests with coverage
        run: bun test --coverage
        working-directory: apps/telegram-bridge
```

## References

- Issue: #66
- Brainstorm: `knowledge-base/brainstorms/2026-02-12-code-coverage-brainstorm.md`
- Spec: `knowledge-base/specs/feat-code-coverage/spec.md`
- Bun coverage docs: https://bun.sh/docs/test/code-coverage
- Bun bunfig.toml reference: https://bun.sh/docs/runtime/bunfig
- Current CI: `.github/workflows/ci.yml`
- Current baseline: 88.5% functions, 96.8% lines (`apps/telegram-bridge/`)

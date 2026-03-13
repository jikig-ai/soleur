---
title: No unified test runner from repo root
date: 2026-03-03
category: technical-debt
tags: [testing, bun, ci, developer-experience]
severity: low
---

# No Unified Test Runner from Repo Root

## Problem

The repository has two completely separate test suites with no top-level test script to run them together. The root `package.json` has no `test` script (only `docs:dev` and `docs:build`). Each suite must be run independently:

- `apps/telegram-bridge/` -- `bun test` (3 test files, ~130 tests)
- `plugins/soleur/test/` -- `bun test` (component validation tests)

There is no single command that exercises both suites from the repo root.

## Key Insight

CI already runs both suites separately in `ci.yml` (different `working-directory` values), so correctness is not at risk. The gap is developer experience -- contributors must know to run tests in both locations manually.

## Tags

testing, developer-experience, ci

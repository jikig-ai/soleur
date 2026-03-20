---
title: "Bun Coverage Threshold Configuration"
date: 2026-02-12
category: implementation-patterns
module: apps/telegram-bridge
tags: [bun, testing, coverage, ci, bunfig]
severity: low
---

# Learning: Bun Coverage Threshold Configuration

## Problem

Adding code coverage enforcement to CI for a multi-project Bun monorepo. Needed to configure thresholds and integrate with GitHub Actions.

## Solution

1. **Threshold format is decimal (0.0-1.0), not percentage.** `coverageThreshold = { line = 0.8, function = 0.8 }` for 80%. Using `80` would effectively require 8000% coverage and always pass.

2. **Keep existing `bun test` step, add separate coverage step.** Splitting CI into domain-specific steps (`bun test plugins/soleur/test/` + `bun test --coverage`) breaks when test directories don't exist yet. Simpler: keep `bun test` for all tests, add a second step scoped to the coverage target via `working-directory`.

3. **`bunfig.toml` is directory-scoped.** Place it in the app directory and use `working-directory` in CI. Bun picks up the config automatically when running from that directory.

## Key Insight

For multi-project repos, additive CI steps (keep existing + add new) are safer than splitting. Splitting creates ordering dependencies between PRs and fragile assumptions about which directories exist.

## Tags

category: implementation-patterns
module: apps/telegram-bridge

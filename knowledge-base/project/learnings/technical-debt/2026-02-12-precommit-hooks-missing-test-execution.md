---
title: Pre-commit Hooks Do Not Run Tests
date: 2026-02-12
category: workflow-patterns
tags: [lefthook, pre-commit, testing, bun-test]
module: infrastructure
component: ci
problem_type: best_practice
severity: medium
status: open
---

# Pre-commit Hooks Do Not Run Tests

## Context

`lefthook.yml` runs `cargo fmt`, `cargo clippy`, and `markdownlint` on pre-commit, but does not include `bun test`. The constitution says "Run `bun test` before merging" but there is no automated enforcement. Tests only run when developers remember to invoke them manually.

## Fix

Add a `bun-test` hook to `lefthook.yml` in the pre-commit section targeting TypeScript/JavaScript files.

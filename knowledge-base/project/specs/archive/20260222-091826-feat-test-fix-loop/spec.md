# Spec: Self-Iterating Test-Fix Loop Skill

**Date:** 2026-02-22
**Issue:** #216
**Status:** Draft

## Problem Statement

After code implementation, test failures require manual diagnosis and fix cycles. This is the most common friction point in Claude Code sessions (15 "buggy_code" events across 139 sessions). The current `/soleur:work` loop handles one task at a time with RED/GREEN/REFACTOR, but has no structured retry mechanism when the GREEN phase produces unexpected failures elsewhere.

## Goals

- G1: Automate the test-fail-diagnose-fix-retest cycle
- G2: Detect and stop on circular fixes or regression
- G3: Minimize context window consumption via truncated failure summaries
- G4: Isolate each fix attempt via git stash for safe revert
- G5: Auto-detect the project's test runner

## Non-Goals

- NG1: Replace RED/GREEN/REFACTOR discipline (handled by atdd-developer)
- NG2: Handle non-test quality checks (linting, type-checking) in the loop
- NG3: Per-iteration human approval (fully autonomous by design)
- NG4: Modify test files themselves (only fix implementation code)

## Functional Requirements

- FR1: Skill auto-detects test runner from project files (package.json, Makefile, Cargo.toml, Gemfile, etc.)
- FR2: Skill runs full test suite and parses output into failure summaries (test name + error message)
- FR3: Skill clusters failures by file/module (max 5 groups) for batch diagnosis
- FR4: Skill applies fixes, stashes state, and re-runs tests to validate
- FR5: Skill tracks failure count trajectory across iterations
- FR6: Skill detects circular fixes via test name set comparison
- FR7: Skill terminates on: all pass, max iterations, regression, or circular detection
- FR8: Skill writes a diagnostic report when terminating without success
- FR9: Skill commits fixes only when all tests pass

## Technical Requirements

- TR1: Skill definition at `plugins/soleur/skills/test-fix-loop/SKILL.md`
- TR2: Uses git stash for fix isolation (stash before apply, pop/drop based on result)
- TR3: Max 5 sub-agent clusters for parallel failure diagnosis
- TR4: Default max iterations: 5 (configurable via argument)
- TR5: Failure summaries only -- no full stack traces passed to fix logic

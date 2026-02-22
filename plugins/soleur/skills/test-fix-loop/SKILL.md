---
name: test-fix-loop
description: This skill should be used when autonomously iterating on test failures until all tests pass or a termination condition is met. It runs the test suite, diagnoses failures, applies minimal fixes, and re-runs in a loop with git stash isolation. Triggers on "test fix loop", "fix failing tests", "make tests pass", "iterate until green".
---

# Test-Fix Loop

Autonomous test-fix iteration loop. Run the test suite, diagnose failures, apply fixes to implementation code, and re-run until all tests pass or a termination condition is met. This is a recovery mechanism for unexpected failures -- not a replacement for RED/GREEN/REFACTOR (use `atdd-developer` for TDD discipline).

## When to Use

- After implementation produces unexpected test failures in unrelated modules
- When `/soleur:work` GREEN phase fails and manual diagnosis is tedious
- To batch-fix multiple test failures across a codebase
- NOT for writing new tests (use `atdd-developer`)
- NOT for linting, type-checking, or non-test failures

## Phase 0: Detect and Confirm

### Detect Test Runner

Auto-detect the test command from project files in priority order:

1. `CLAUDE.md` -- explicit test command (highest priority)
2. `package.json` -- `scripts.test` field
3. `Cargo.toml` -- `cargo test`
4. `Makefile` / `Justfile` -- `test` target
5. `Gemfile` / `Rakefile` -- `bundle exec rake test` or `bin/rails test`
6. `pyproject.toml` -- `pytest`
7. `go.mod` -- `go test ./...`

If `$ARGUMENTS` contains a custom test command, use it instead of auto-detection.
If `$ARGUMENTS` contains a number, use it as max iterations (default: 5).
If no runner is detected, ask the user for the test command.

### Require Clean Working Tree

Run `git status --porcelain`. If output is non-empty, STOP and tell the user to commit or stash their changes first. A dirty working tree will cause stash interleaving.

### Pre-flight Confirmation

<decision_gate>
Show the user: detected test command, max iterations, current branch.
Get one confirmation before starting the loop. This is the only approval gate --
no per-iteration approval.
</decision_gate>

## Phase 1: Test-Fix Loop

Run the initial test suite. If all tests pass, exit with "All tests already pass. Nothing to fix."

For each iteration (up to max iterations):

### 1. Parse Failures

Extract failure summaries from test output: test name and error message only (one line each). Discard full stack traces and passing test output to minimize context consumption.

Distinguish build/compilation errors from test failures. If the suite fails to compile, treat the entire build error as a single cluster and fix the compilation issue first.

### 2. Check Termination Conditions

Before attempting fixes, check whether to stop:

| Condition | Detection | Action |
|-----------|-----------|--------|
| All tests pass | Zero failures | Drop stash, stage fixes, report success |
| Max iterations | iteration == limit | Drop stash (keep partial progress), report |
| Regression | Failure count increased vs previous iteration | Pop stash (revert to last good state), report |
| Circular fix | Failure name set matches any prior iteration | Pop stash (revert), report |
| Non-convergence | Failure count unchanged for 2 consecutive iterations | Pop stash (revert), report |
| Build error persists | Same compilation error after fix attempt | Pop stash (revert), report |

If a termination condition triggers, skip to the Diagnostic Report.

### 3. Cluster and Diagnose

Cluster failures by file or module (max 5 groups, sorted by failure count descending). If more than 5 modules fail, take the top 5 and note the skipped modules.

For each cluster, apply the diagnostic-first rule:

- Read the failing test to understand expected behavior
- Read the implementation code referenced by the error
- Identify the root cause before proposing a fix

### 4. Stash and Fix

<critical_sequence>
Stash the current working tree as a rollback checkpoint before applying fixes:

    git stash push -m "test-fix-loop: checkpoint iteration N"

Apply fixes to implementation code only. NEVER modify test files, add skip annotations, delete tests, or weaken assertions.

Re-run the full test suite after applying fixes.

Evaluate the result:
- All pass: `git stash drop`, stage all fixes, report success, STOP
- Failures decreased: `git stash drop` (keep progress), continue to next iteration
- Regression or circular: `git stash pop` (revert this iteration's fixes), STOP
</critical_sequence>

## Diagnostic Report

On termination (success or failure), write a report to stdout:

- **Result**: SUCCESS, REGRESSION, CIRCULAR, MAX_ITERATIONS, or NON_CONVERGENCE
- **Iterations completed**: N out of max
- **Termination reason**: one-line explanation
- **Iteration history**: failure count per iteration with delta
- **Remaining failures**: test name and error message for each (if not success)
- **Fixes applied**: files modified and what changed (last iteration)
- **Recommendation**: what the user should investigate next (if not success)

On success, fixes are staged but NOT committed. The user reviews and commits via `/ship` or manually.

## Key Principles

- Diagnose before fixing -- never guess at the root cause
- Fix implementation code only -- tests define the contract
- Truncate aggressively -- failure summaries only, no full stack traces
- Fail safe -- stash before every fix attempt, revert on regression
- Exit early -- stop as soon as the trajectory indicates non-convergence
- Stage, do not commit -- respect the Workflow Completion Protocol

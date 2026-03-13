# Feature: Pre-Flight Validation Checks

## Problem Statement

"wrong_approach" is the #1 friction type (45 of 139 sessions). Worktree discipline, convention compliance, and scope alignment are currently advisory-only -- nothing validates them before implementation begins. Post-implementation gates in `/ship` catch errors too late.

## Goals

- Catch environment errors (wrong branch, wrong directory) before any code is written
- Surface stashed/uncommitted changes before starting new work
- Detect merge conflict zones before implementation begins
- Add convention verification reminder to the plan reading step

## Non-Goals

- No new agents (checks are deterministic, not LLM reasoning)
- No changes to `/soleur:plan` (avoid redundant validation gates)
- No fast-path bypass (checks run in milliseconds)
- No persistent reporting (results displayed inline only)

## Functional Requirements

### FR1: Environment Assertions

Phase 0.5 in work.md runs `git branch`, `pwd`, `git status`, and `git stash list` to validate the working environment. Default branch = FAIL. No worktree = WARN. Uncommitted/stashed changes = WARN.

### FR2: Scope Assertions

Verify plan file exists. Detect merge conflict zones via `git log` comparison. Missing plan = FAIL. Conflict zones = WARN.

### FR3: Convention Reminder

Phase 1 "Read Plan and Clarify" step includes explicit instruction to verify plan against AGENTS.md conventions.

## Technical Requirements

### TR1: Inline Instructions Only

All checks are inline in work.md. No new files created.

### TR2: Graceful Network Failure

If `git fetch` fails (offline), skip conflict zone check with a WARN.

### TR3: Non-Blocking Warnings

Only FAIL blocks execution. WARN displays and proceeds. All pass continues silently.

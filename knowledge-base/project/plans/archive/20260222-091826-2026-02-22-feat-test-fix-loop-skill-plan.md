---
title: "feat: Add test-fix-loop skill for autonomous test-fix iteration"
type: feat
date: 2026-02-22
issue: "#216"
version_bump: MINOR
---

# feat: Add test-fix-loop skill for autonomous test-fix iteration

## Overview

Add a new skill at `plugins/soleur/skills/test-fix-loop/SKILL.md` that autonomously runs tests, diagnoses failures, applies fixes, and re-runs tests in a loop until all pass or a termination condition is met. This is a recovery mechanism for unexpected test failures after implementation -- not a replacement for RED/GREEN/REFACTOR (that is `atdd-developer`).

Motivated by 15 "buggy_code" friction events across 139 Claude Code sessions.

## Proposed Solution

A single SKILL.md file implementing a phased autonomous loop:

1. **Detect** -- Auto-detect test runner from project files (CLAUDE.md > package.json > Cargo.toml > Makefile > Gemfile, fallback to asking user)
2. **Pre-flight** -- Require clean working tree, show detected runner, confirm with user once
3. **Loop** -- Run tests, parse failures into name+message summaries, cluster by module (max 5), diagnose (diagnostic-first), fix implementation code (never tests), stash before fixing, re-run. Accept optional arguments: custom test command (override) and max iterations (default 5).
4. **Terminate** -- Exit on success, regression, circular detection, non-convergence, or max iterations. Rollback via `git stash pop` on failure; `git stash drop` on success. Stage fixes (do not commit) when all pass.

### Key Design Decisions (from brainstorm)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Placement | Skill (not command) | Agent-discoverable; `/soleur:work` can delegate to it |
| Autonomy | Fully autonomous with pre-flight gate | Consent is the invocation; termination conditions provide safety |
| Context budget | Truncated failure summaries only | ~80% token reduction; no full stack traces to fix logic |
| Fix isolation | Git stash per attempt | Stash before fix as rollback checkpoint |
| Circular detection | Failure count trajectory + test name set | Primary: monotonic decrease check; secondary: set comparison |
| Sub-agent strategy | Batch by module, max 5 clusters | Same pattern as `/soleur:work` Tier B |
| Test runner | Auto-detect from project files | Fallback to asking the user |
| Max iterations | 5 (configurable via argument) | Per-invocation, not per-failure |

### Termination Conditions

| Condition | Detection | Action |
|-----------|-----------|--------|
| All tests pass | Zero failures after re-run | Drop stash, stage fixes, report success |
| Max iterations reached | iteration == max_iterations | Drop stash (keep partial progress), write diagnostic report |
| Regression | Failure count increased vs previous | Pop stash (revert to last good state), write diagnostic report |
| Circular fix | Failure name set matches any prior iteration | Pop stash (revert), write diagnostic report |
| Non-convergence | Failure count unchanged for 2 consecutive iterations | Pop stash (revert), write diagnostic report |
| Build error persists | Same build error after fix attempt | Pop stash (revert), write diagnostic report |

Note: Rollback is to the last good state (previous iteration), not to original state. Each successful iteration's fixes are kept.

## Files to Create

- [x] `plugins/soleur/skills/test-fix-loop/SKILL.md` -- The skill definition (~100-150 lines)

## Files to Update

- [x] `plugins/soleur/docs/_data/skills.js` -- Register under "Workflow" category, update count comment (45 -> 46)
- [x] `plugins/soleur/README.md` -- Add row to Workflow skills table, update skill count
- [x] `plugins/soleur/.claude-plugin/plugin.json` -- MINOR version bump, update skill count in description
- [x] `plugins/soleur/CHANGELOG.md` -- Add entry under new version
- [x] `README.md` (root) -- Update version badge and skill count
- [x] `.github/ISSUE_TEMPLATE/bug_report.yml` -- Update placeholder version

## SKILL.md Structure

Follow the `atdd-developer` pattern (markdown headings, imperative instructions, phase-based). Use `<critical_sequence>` and `<decision_gate>` XML semantic tags for the stash isolation and termination condition logic.

```markdown
---
name: test-fix-loop
description: This skill should be used when autonomously iterating on
  test failures until all tests pass or a termination condition is met.
  It runs the test suite, diagnoses failures, applies minimal fixes, and
  re-runs in a loop with git stash isolation. Triggers on "test fix loop",
  "fix failing tests", "make tests pass", "iterate until green".
---

# Test-Fix Loop

[Purpose statement]

## When to Use

## Phase 0: Detect and Confirm
- Auto-detect test runner from project files
- Require clean working tree (git status --porcelain)
- Pre-flight confirmation (one-time, not per-iteration)
- <decision_gate> for user confirmation

## Phase 1: Test-Fix Loop
- For each iteration: run tests, parse failures into name+message summaries,
  check termination conditions, cluster by module (max 5), diagnose
  (diagnostic-first) and fix implementation code (never tests), stash
  before fixing, re-run
- <critical_sequence> for stash push/pop/drop logic
- Distinguish build errors (single cluster) from test failures

## Termination Conditions
- Table of conditions and actions (same as plan)

## Diagnostic Report
- Write to stdout: result status, iteration history, remaining failures,
  recommendation for next steps

## Key Principles
```

## Acceptance Criteria

- [ ] AC1: Skill auto-detects test runner from at least 4 project file types
- [ ] AC2: Skill requires clean working tree before starting
- [ ] AC3: Skill shows pre-flight confirmation with detected runner and max iterations
- [ ] AC4: Skill parses test output into failure summaries (test name + error message only)
- [ ] AC5: Skill clusters failures by module with max 5 groups
- [ ] AC6: Skill uses git stash for fix isolation with proper cleanup on all termination paths
- [ ] AC7: Skill terminates on: all pass, max iterations, regression, circular detection, non-convergence
- [ ] AC8: Skill writes a diagnostic report when terminating without success
- [ ] AC9: Skill stages (not commits) fixes when all tests pass
- [ ] AC10: Skill never modifies test files
- [ ] AC11: Skill registered in skills.js, README, plugin.json, CHANGELOG
- [ ] AC12: Description uses third person, imperative instructions in body

## Non-Goals

- Replacing RED/GREEN/REFACTOR discipline (handled by `atdd-developer`)
- Handling linting, type-checking, or non-test quality failures
- Per-iteration human approval (fully autonomous by design)
- Modifying test files (only fix implementation code)
- Auto-committing (respects Workflow Completion Protocol; stages only)
- Managing worktree/branch creation (caller's responsibility)
- Monorepo subdirectory scoping (pass custom test command if needed)

## Rollback Plan

Revert the commit. The skill file and all registration changes (skills.js, README, plugin.json, CHANGELOG, bug_report.yml) are additive with no schema or external state changes.

## Affected Parties

- Users of `/soleur:work` (skill may be delegated to from Phase 2 task loop)
- Direct invokers via `/test-fix-loop`

## References

### Internal

- Brainstorm: `knowledge-base/brainstorms/2026-02-22-test-fix-loop-brainstorm.md`
- Spec: `knowledge-base/specs/feat-test-fix-loop/spec.md`
- Similar skill: `plugins/soleur/skills/atdd-developer/SKILL.md`
- Work command loop: `plugins/soleur/commands/soleur/work.md:304-319`

### Learnings Applied

- Skills cannot invoke other skills (`knowledge-base/learnings/implementation-patterns/2026-02-18-skill-cannot-invoke-skill.md`)
- Token budget matters in iterative loops (`knowledge-base/learnings/performance-issues/2026-02-20-agent-description-token-budget-optimization.md`)
- Worktree edit discipline (`knowledge-base/learnings/workflow-patterns/2026-02-11-worktree-edit-discipline.md`)

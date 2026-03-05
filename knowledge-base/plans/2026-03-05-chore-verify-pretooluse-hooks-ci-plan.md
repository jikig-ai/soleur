---
title: "chore: Verify PreToolUse Hooks in claude-code-action"
type: fix
date: 2026-03-05
---

# chore: Verify PreToolUse Hooks in claude-code-action

## Overview

Empirically verify whether PreToolUse hooks (`.claude/settings.json`) fire when skills run inside `claude-code-action` (GitHub Actions). If they don't, add inline fallback branch-safety checks to ship, compound, and work skills. This is a prerequisite for the headless mode scheduled workflows descoped from #393.

## Problem Statement / Motivation

PreToolUse hooks are the primary safety mechanism for the Soleur plugin:

- **guardrails.sh** blocks commits on main, rm -rf on worktrees, --delete-branch with active worktrees, and commits with conflict markers
- **pre-merge-rebase.sh** auto-syncs feature branches with origin/main before `gh pr merge`
- **worktree-write-guard.sh** blocks file writes to the main repo when worktrees exist

Whether these hooks fire in `claude-code-action` is unknown and untested. Four existing workflows already use `claude-code-action` (daily-triage, bug-fixer, competitive-analysis, code-review), but none exercise hook-triggering scenarios (commits, merges, file writes). If hooks silently don't fire in CI, the competitive-analysis workflow (which commits directly to main) and future headless ship/compound workflows operate without safety guards.

The brainstorm for #393 (headless mode) explicitly flagged this as a risk: "PreToolUse hooks MUST be verified to fire under `claude -p` / GitHub Actions."

## Proposed Solution

### Phase 1: Create a Test Workflow

Create `.github/workflows/test-pretooluse-hooks.yml` -- a `workflow_dispatch`-only workflow that invokes `claude-code-action` with a prompt designed to trigger each hook and report results.

**Test matrix:**

| Hook | Trigger | Expected Behavior | Verification |
|------|---------|-------------------|-------------|
| guardrails.sh Guard 1 | `git commit -m "test" --allow-empty` on main | Blocked with "BLOCKED: Committing directly to main" | Check workflow logs for deny message |
| guardrails.sh Guard 2 | `rm -rf .worktrees/test-dir` (after creating dummy dir) | Blocked with "BLOCKED: rm -rf on worktree paths" | Check workflow logs for deny message |
| guardrails.sh Guard 4 | Stage a file with `<<<<<<<` markers, then commit | Blocked with "BLOCKED: Staged content contains conflict markers" | Check workflow logs for deny message |
| pre-merge-rebase.sh | `gh pr merge` on a branch behind main | Auto-syncs and allows merge | Check logs for "merged origin/main" message |
| worktree-write-guard.sh | Write to main repo path with `.worktrees/` dir present | Blocked with "BLOCKED: Writing to main repo checkout" | Check workflow logs for deny message |

### Phase 2: Analyze Results and Document

After running the test workflow:

1. **If hooks fire**: Document confirmation in a learning file, close the issue
2. **If hooks don't fire**: Proceed to Phase 3

### Phase 3: Inline Fallback Guards (Conditional)

If hooks don't fire, add lightweight inline checks to the skills that depend on them:

**ship SKILL.md** -- Add before commit phase:
```bash
# Fallback branch guard (defense-in-depth when PreToolUse hooks unavailable)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "ERROR: Cannot ship from main/master" >&2; exit 1
fi
```

**compound SKILL.md** -- Add before constitution promotion:
```bash
# Fallback branch guard
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "ERROR: Cannot run compound on main/master" >&2; exit 1
fi
```

**work SKILL.md** -- Add before first file write:
```bash
# Fallback branch guard
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "ERROR: Cannot run work on main/master" >&2; exit 1
fi
```

## Technical Considerations

### Hook Loading in claude-code-action

The critical unknown: does `claude-code-action` load `.claude/settings.json` from the checked-out repository? The action checks out the repo, then invokes Claude Code. If Claude Code reads `.claude/settings.json` from the working directory (standard behavior), hooks should load. But if the action operates in a sandboxed mode that ignores project settings, hooks won't fire.

### Hook Dependencies

All three hooks require `jq` on the runner. `ubuntu-latest` includes `jq` by default, but this is an implicit dependency. The test workflow should verify `jq` availability.

### Git State in CI

GitHub Actions checkout creates a detached HEAD state by default. Guard 1 (block commits on main) uses `git rev-parse --abbrev-ref HEAD`, which returns `HEAD` in detached state -- this would bypass the guard. The test must verify behavior in both detached HEAD and checked-out branch states.

### Multiple Hooks on Same Matcher

Two hooks match the `Bash` tool (guardrails.sh and pre-merge-rebase.sh). The test must verify that all matching hooks execute, not just the first.

### SpecFlow Edge Cases (from analysis)

1. **Hook path resolution**: Hooks are referenced as relative paths (`.claude/hooks/guardrails.sh`). In CI, the working directory is the repo root after checkout -- this should resolve correctly, but needs verification.
2. **stdin JSON contract**: Hooks receive `tool_input` and `cwd` on stdin. The `cwd` field behavior in claude-code-action is unknown -- it may be the runner workspace path or undefined.
3. **Exit code semantics**: Hooks that output `permissionDecision: "deny"` with exit 0 block the tool. Non-JSON output or non-zero exits may fail open. The test must verify deny actually blocks tool execution.
4. **Worktree absence in CI**: Guards 2, 3, and the write guard check for worktrees. In CI there are no worktrees -- these guards should pass-through (allow). Test should verify no false denials.

## Acceptance Criteria

- [ ] Test workflow `.github/workflows/test-pretooluse-hooks.yml` created and runs successfully
- [ ] Guard 1 (commit on main) behavior documented for claude-code-action
- [ ] Guard 2 (rm -rf worktrees) behavior documented for claude-code-action
- [ ] Guard 4 (conflict markers) behavior documented for claude-code-action
- [ ] pre-merge-rebase.sh behavior documented for claude-code-action
- [ ] worktree-write-guard.sh behavior documented for claude-code-action
- [ ] If hooks don't fire: inline fallback branch guards added to ship, compound, and work skills
- [ ] If hooks do fire: learning file documenting confirmation created
- [ ] Results documented in knowledge-base/learnings/ regardless of outcome

## Test Scenarios

- Given the test workflow runs on ubuntu-latest, when the agent attempts `git commit` on main branch, then either (a) the hook blocks with "BLOCKED" message or (b) the commit succeeds -- documenting which outcome occurs
- Given the test workflow runs, when the agent creates a `.worktrees/` directory and attempts to write a file to the repo root, then either the write guard blocks or allows -- documenting the outcome
- Given the test workflow runs, when the agent stages a file with conflict markers and attempts to commit, then either Guard 4 blocks or the commit succeeds -- documenting the outcome
- Given hooks don't fire in CI, when inline fallback guards are added to ship/compound/work, then those skills abort when run on main/master regardless of hook availability
- Given hooks do fire in CI, when all guards are verified as operational, then a learning file is created confirming the behavior and the issue is closed

## Non-Goals

- Fixing or improving the existing hooks (separate issues if needed)
- Adding hooks to the scheduled workflows that already exist (daily-triage, bug-fixer, etc.)
- Making all skills headless (that's #393's scope, already shipped)
- Testing `claude -p` (non-Action CLI) hook behavior (different runtime, different issue)

## Success Metrics

- Binary: hooks fire or they don't. The outcome determines the next action.
- If hooks fire: issue closes immediately with learning documentation.
- If hooks don't fire: PR adds fallback guards to 3 skills (ship, compound, work).

## Dependencies & Risks

**Risk: Test workflow costs API credits.** Mitigation: use `claude-sonnet-4-6` (cheaper), limit `--max-turns 15`, and make the test prompt deterministic (explicit commands to run, not open-ended exploration).

**Risk: Test modifies repo state.** Mitigation: all test operations use `--allow-empty` commits or temporary files, test runs on a disposable branch created by the workflow.

**Risk: Hook behavior differs between claude-code-action versions.** Mitigation: pin the same action version used by existing workflows (v1).

**Semver intent:** `semver:patch` if hooks fire (docs only). `semver:patch` if fallback guards needed (defensive improvement, no new capability).

## References & Research

### Internal References

- PreToolUse hooks: `.claude/settings.json:14-44`
- guardrails.sh: `.claude/hooks/guardrails.sh`
- pre-merge-rebase.sh: `.claude/hooks/pre-merge-rebase.sh`
- worktree-write-guard.sh: `.claude/hooks/worktree-write-guard.sh`
- Headless mode plan: `knowledge-base/plans/2026-03-03-feat-headless-mode-repeatable-workflows-plan.md`
- Headless mode brainstorm: `knowledge-base/brainstorms/2026-03-03-headless-mode-brainstorm.md`
- Existing claude-code-action workflows: `.github/workflows/scheduled-bug-fixer.yml`, `.github/workflows/scheduled-daily-triage.yml`, `.github/workflows/scheduled-competitive-analysis.yml`, `.github/workflows/claude-code-review.yml`
- Hook learning (worktree write guard): `knowledge-base/learnings/2026-02-26-worktree-enforcement-pretooluse-hook.md`
- Hook learning (pre-merge rebase): `knowledge-base/learnings/2026-03-03-pre-merge-rebase-hook-implementation.md`
- Hook learning (SessionStart contract): `knowledge-base/learnings/2026-03-04-sessionstart-hook-api-contract.md`

### Related Work

- Parent issue: #393 (headless mode)
- This issue: #419
- Constitution hook preference: `knowledge-base/overview/constitution.md:199` ("Prefer hook-based enforcement over documentation-only rules")

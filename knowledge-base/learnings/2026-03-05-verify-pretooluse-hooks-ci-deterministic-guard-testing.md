---
title: Verifying PreToolUse hooks fire in claude-code-action CI
date: 2026-03-05
category: ci-testing
module: hooks
tags: [pretooluse-hooks, claude-code-action, ci, defense-in-depth, guard-testing]
related_issues: ["#419", "#447"]
related_files:
  - .github/workflows/test-pretooluse-hooks.yml
  - plugins/soleur/skills/ship/SKILL.md
  - plugins/soleur/skills/compound/SKILL.md
  - plugins/soleur/skills/work/SKILL.md
---

# Learning: Deterministic Guard Testing for PreToolUse Hooks in CI

## Problem

PreToolUse hooks (5 guards: no commits on main, no rm -rf on worktrees, no --delete-branch with active worktrees, no conflict markers in staged content, no writes to main repo when worktrees exist) were only validated locally during interactive sessions. There was no mechanism to confirm hooks fire inside `claude-code-action` (GitHub Actions). Silent failure would mean the entire safety net is absent in CI-driven agentic runs -- the riskiest execution context since no human watches the terminal.

Additionally, `ship` and `compound` skills lacked explicit branch-check guards in their instruction text, relying solely on PreToolUse hooks as the only line of defense.

## Solution

1. **Deterministic test workflow** (`.github/workflows/test-pretooluse-hooks.yml`): workflow_dispatch-only, checks out with `ref: main` (avoids detached HEAD bypass), runs `chmod +x` on hooks, uses a fixed prompt with `--max-turns 20` / `claude-sonnet-4-6` for cost control. Tests 5 guards with explicit PASS/FAIL criteria.

2. **Defense-in-depth branch guards**: Added to `ship/SKILL.md` (Phase 0) and `compound/SKILL.md` (all modes, not just headless). `work/SKILL.md` already had the guard.

3. **Follow-up issue #447**: Filed for `brainstorm` and `plan` skill guards.

## Key Insight

PreToolUse hooks are a runtime safety net, not a compile-time guarantee. Their effectiveness depends on the execution environment loading and invoking them. Any time the execution context changes (local CLI to CI, version upgrade), hooks must be re-verified empirically. The correct pattern: build a deterministic, automated test that attempts each guarded operation and asserts the block occurs; run it in every new context. Defense-in-depth (duplicating the guard in skill instructions) reduces blast radius if the hook layer fails silently.

**Secondary insight:** Test teardown must respect the same guards it is testing. Using `rm -rf` to clean up a `.worktrees/` test directory triggers Guard 2, so `rmdir` (empty-directory-only) is the correct cleanup primitive. Test harnesses for safety systems must themselves be safe.

## Session Errors

1. Security reminder hook fired when writing workflow YAML (false positive -- no untrusted inputs). Added security comment to file header to document the safety analysis.

## Prevention

- When adding new PreToolUse hooks, add a corresponding test case to `test-pretooluse-hooks.yml`
- When changing execution contexts (new CI provider, action version bump), re-run the test workflow
- Always add skill-level branch guards alongside hook guards (defense-in-depth)

## Related Learnings

- [worktree-enforcement-pretooluse-hook](2026-02-26-worktree-enforcement-pretooluse-hook.md) -- Write guard implementation
- [guardrails-chained-commit-bypass](2026-02-24-guardrails-chained-commit-bypass.md) -- Guard 1 chain-operator fix
- [guardrails-grep-false-positive](2026-02-24-guardrails-grep-false-positive-worktree-text.md) -- Guard 2 proximity fix
- [canonicalize-merge-and-conflict-marker-guard](2026-03-03-canonicalize-merge-and-conflict-marker-guard.md) -- Guard 4 addition
- [pre-merge-rebase-hook](2026-03-03-pre-merge-rebase-hook-implementation.md) -- Pre-merge auto-sync hook
- [claude-code-action-token-revocation](2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md) -- Token lifecycle in CI
- [github-actions-workflow-security-patterns](2026-02-21-github-actions-workflow-security-patterns.md) -- SHA pinning, input validation

## Tags

category: ci-testing, safety-verification
module: hooks, skills (ship, compound, work)

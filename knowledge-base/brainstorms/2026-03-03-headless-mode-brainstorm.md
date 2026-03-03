# Headless Mode for Repeatable Git/Merge Workflows

**Date:** 2026-03-03
**Issue:** #393
**Branch:** feat-headless-mode
**Status:** Brainstorm complete, ready for planning

## What We're Building

A `--headless` flag convention for Soleur skills that lets them run without interactive prompts. When `$ARGUMENTS` contains `--headless`, skills use sensible defaults instead of calling AskUserQuestion. This makes the ship, compound, and work skills executable in unattended pipelines (GitHub Actions, one-shot, future `claude -p` once plugin loading is fixed).

Additionally: two new GitHub Actions scheduled workflows (ship-merge and compound-review) that exercise the headless capability.

## Why This Approach

### Problem

- 42 merge PR sessions (50%+ of top goals) are highly repeatable
- 865 AskUserQuestion calls, many routine confirmations
- `merge-pr` and `changelog` are already fully headless, proving the pattern works
- Skills violate the existing `$ARGUMENTS` bypass rule (constitution.md line 71)

### Why Bottom-Up Compliance Over New Infrastructure

1. **The convention already exists.** Constitution mandates `$ARGUMENTS` bypass (line 71) but it's unenforced across 23+ AskUserQuestion calls. Enforcing the existing rule is lower risk than creating new orchestration.
2. **`claude -p` can't load plugins reliably.** Four attempts to fix headless plugin auto-load were all reverted. GitHub Actions via `claude-code-action` is the proven headless runtime. Making skills bypass-compatible works with Actions today and `claude -p` if/when that blocker is fixed.
3. **No new orchestration layer needed.** The CTO warned against adding a third orchestration layer alongside `one-shot` and `merge-pr`. Bottom-up compliance means each skill works independently.
4. **merge-pr is the reference implementation.** Zero AskUserQuestion calls, auto-aborts on low-confidence failures. This proves the pattern.

## Key Decisions

### 1. Detection Mechanism: Explicit `--headless` flag

Skills check `$ARGUMENTS` for `--headless`. When present:
- All AskUserQuestion calls are bypassed with sensible defaults
- Compound auto-promotes learnings to constitution.md using LLM judgment
- Ship auto-derives PR title/body from branch name and diff summary
- Work skips interactive approval gates

Follows the `schedule` skill's existing flag pattern (`--name`, `--yes`, `--cron`).

### 2. Compound Auto-Promotion: Full Auto, No Safety Net

In headless mode, compound auto-promotes learnings to constitution.md without human approval. The PR review process is the safety net — promotions land on a feature branch and get reviewed before reaching main. No staging files, no deferred review, no logging.

Rationale: The model already drafts promotion proposals. The human approval gate adds friction in pipelines where the PR itself provides review. If a bad rule gets promoted, it's caught in PR review.

### 3. Priority Skills: ship + compound + work

| Skill | Current Gates | Headless Behavior |
|-------|-------------|-------------------|
| ship | 3 (compound confirm, tests confirm, PR body confirm) | Auto-run compound, auto-run tests, auto-derive PR body |
| compound | 3+ (constitution promotion, route-to-definition, decision menu) | Auto-promote, auto-route, skip decision menu |
| work | 2 (approval gates in interactive mode) | Skip gates (same as existing pipeline mode) |

Already headless: `merge-pr` (0 gates), `changelog` (0 gates), `cleanup-merged` (0 gates).

### 4. New GitHub Actions Workflows

**scheduled-ship-merge.yml:** Auto-ship and merge PRs that pass CI and have been open for N hours. Runs the headless ship pipeline on qualifying PRs.

**scheduled-compound-review.yml:** Weekly compound pass across recent sessions, surfacing learnings that might have been missed during manual sessions.

### 5. Enforcement: Lefthook Pre-Commit Check

Add a check that flags new AskUserQuestion calls in skills that lack a `--headless` bypass path. Prevents regression.

### 6. worktree-manager.sh: Add `--yes` Flag

The `create` and `cleanup` commands use `read -r` prompts that block in non-interactive shells. Add a `--yes` flag that auto-confirms.

## CTO Assessment Summary

- **Architecture:** Option C (enforce existing convention) is lowest risk. No new components needed.
- **Risk:** PreToolUse hooks MUST be verified to fire under `claude -p` / GitHub Actions. If hooks are bypassed in headless mode, guardrails (block commits on main, block rm -rf, block --delete-branch) are silently disabled.
- **Compound:** Hardest skill to make headless due to the HARD RULE. The user chose full auto-promote — simplest implementation, PR review is the gate.
- **Cost control:** Headless pipelines need `--max-turns` to prevent runaway billing.

## Open Questions

1. What value of N hours should trigger scheduled-ship-merge? (24h? 48h?)
2. Should the lefthook check be a warning or a blocking error?
3. How should headless mode handle merge conflicts that compound can't auto-resolve?
4. Should `--headless` imply `--max-turns 30` (or similar) as a cost cap?

## Implementation Sequence

| Phase | Work | Scope |
|-------|------|-------|
| 1 | Add `--yes` flag to worktree-manager.sh interactive functions | Small |
| 2 | Add `--headless` bypass to ship, compound, work skills | Medium |
| 3 | Update constitution.md with `--headless` convention | Small |
| 4 | Create scheduled-ship-merge.yml and scheduled-compound-review.yml | Small |
| 5 | Add lefthook pre-commit check for AskUserQuestion bypass | Small |

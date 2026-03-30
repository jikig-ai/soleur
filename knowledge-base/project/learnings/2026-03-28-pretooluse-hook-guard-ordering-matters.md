# Learning: PreToolUse hook guard ordering determines enforcement coverage

## Problem

Guard 6 (review evidence gate) was initially placed after the detached HEAD and main/master early exits in `pre-merge-rebase.sh`. This meant `gh pr merge` from detached HEAD bypassed the review evidence check entirely — the gate never fired.

The security reviewer caught this during code review: the early exits were written for the auto-sync logic (fetch/merge/push), not for the review gate. The review gate's purpose is orthogonal to HEAD state — `gh pr merge` operates on a PR number, not the local checkout.

## Solution

Reorder the guards so the review evidence gate fires before state-dependent early exits:

1. Main/master exit stays **before** the gate (no local review evidence to check on main — the agent merges PRs *into* main, not from it)
2. Review evidence gate fires **before** detached HEAD exit (commits are still visible in detached HEAD via `git log origin/main..HEAD`)
3. Detached HEAD exit stays **after** the gate (only the auto-sync logic needs a named branch)

## Key Insight

When adding a new guard to an existing hook with multiple early exits, audit every exit that fires before your guard. Each early exit is a bypass path. Ask: "Does my guard's purpose depend on the condition this exit checks?" If not, the guard should fire first. Hook guards are ordered by independence from execution context — the most context-independent guards fire earliest.

This parallels the fail-closed vs fail-open principle from the CI squash fallback learning: every exit path must be evaluated for whether it preserves or undermines the guard's intent.

## Tags

category: hook-design
module: .claude/hooks/pre-merge-rebase.sh
severity: medium

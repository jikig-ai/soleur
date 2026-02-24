# Learning: Guardrails grep false positive on literal .worktrees/ in command text

## Problem

Guard 2 in `.claude/hooks/guardrails.sh` used two separate grep calls to block `rm -rf` on worktree paths:

```bash
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-rf)\s' && echo "$COMMAND" | grep -qE '\.worktrees/'; then
```

When `gh issue comment 289 --body "... .worktrees/ ..."` was run, both greps matched independently -- one found the comment contained no rm but the other grep only checked for `.worktrees/` anywhere in the string. Result: legitimate commands blocked.

## Solution

Combined into a single pattern requiring `.worktrees/` as a direct argument to `rm`:

```bash
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+\S*\.worktrees/'; then
```

Key changes:
- Single pattern enforces proximity -- `.worktrees/` must follow rm flags as an argument
- Handles all flag orderings (-rf, -fr, -rfv, -frv) via `[a-zA-Z]*` after both r and f
- `\S*` before `.worktrees/` allows absolute paths

## Key Insight

When building grep-based security guards, never split a compound check into independent grep calls that are ANDed together. Each grep only sees "does this substring exist anywhere?" -- it cannot enforce that two substrings appear in a meaningful relationship (e.g., as command + argument). Combine into a single pattern that enforces proximity and syntactic context.

## Tags
category: safety-mechanisms
module: .claude/hooks/guardrails.sh

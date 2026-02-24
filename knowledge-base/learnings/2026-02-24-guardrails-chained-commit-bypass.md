# Learning: Guard 1 bypassed by chained git commands

## Problem

Guard 1 in `.claude/hooks/guardrails.sh` used `^\s*git\s+commit` to block commits on main. The `^` anchor only matches `git commit` at the start of the command string. Chained commands like `git add file && git commit -m "msg"` start with `git add`, so the anchor never matches and the commit goes through unblocked.

This allowed two commits directly to main in violation of the branching hard rule.

## Solution

Replace the `^` anchor with an alternation that matches `git commit` at command boundaries:

```bash
# Before (bypassed by chaining)
grep -qE '^\s*git\s+commit'

# After (catches chained commands)
grep -qE '(^|&&|\|\||;)\s*git\s+commit'
```

The pattern now matches `git commit` at start of string OR after `&&`, `||`, or `;` chain operators.

## Key Insight

When guarding against specific commands in a shell string, never anchor to `^` alone. The Bash tool routinely chains commands with `&&` for sequential execution. A `^`-anchored pattern only catches the first command in the chain, leaving subsequent commands unguarded. Match at command boundaries instead: `(^|&&|\|\||;)`.

This is the third guardrail grep pattern bug in this file -- all three had the same root cause of insufficient context matching. Guard patterns should be reviewed holistically whenever one is fixed.

## Tags
category: safety-mechanisms
module: .claude/hooks/guardrails.sh

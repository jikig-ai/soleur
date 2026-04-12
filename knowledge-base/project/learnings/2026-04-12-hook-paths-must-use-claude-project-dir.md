# Learning: Hook paths must use $CLAUDE_PROJECT_DIR for reliable resolution

## Problem

Claude Code hooks defined in `.claude/settings.json` used relative paths like `.claude/hooks/guardrails.sh`. These paths resolve relative to the hook's CWD at execution time, which is not guaranteed to be the project root. In bare repos with worktrees, parallel sessions, and agent isolation worktrees, the CWD can vary, causing `/bin/sh: 1: .claude/hooks/guardrails.sh: not found` errors.

## Solution

Prefix all hook commands with `"$CLAUDE_PROJECT_DIR"/` instead of using bare relative paths. Claude Code sets `CLAUDE_PROJECT_DIR` as an environment variable in hook execution environments, pointing to the absolute project root path. This resolves correctly regardless of the shell's CWD.

Before: `".claude/hooks/guardrails.sh"`
After: `"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guardrails.sh"`

## Key Insight

Hook commands run via `/bin/sh -c` and the CWD is not guaranteed to be the project root. Always use `$CLAUDE_PROJECT_DIR` for absolute path resolution in hook commands. The `CLAUDE_PROJECT_DIR` env var is available in hook execution contexts but NOT in the Bash tool environment.

## Session Errors

1. **Hook "not found" errors in parallel session** — `.claude/hooks/guardrails.sh: not found` and `.claude/hooks/pre-merge-rebase.sh: not found` in a worktree session. Recovery: Changed all hook paths to use `$CLAUDE_PROJECT_DIR`. Prevention: This fix itself prevents recurrence.

## Tags

category: integration-issues
module: claude-code-hooks

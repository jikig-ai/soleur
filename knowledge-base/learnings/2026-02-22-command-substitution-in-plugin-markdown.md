# Learning: $() command substitution in plugin markdown triggers Claude Code permission prompts

## Problem

Claude Code's security mechanism prompts users with "Command contains $() command substitution" when the Bash tool receives commands containing `$()`. Plugin markdown files (commands, skills, agents, and reference docs) contain bash code blocks with `$()` that agents try to execute, triggering this permission prompt repeatedly and breaking autonomous workflows.

This issue recurred four times:
- v2.23.15: one-shot command
- v2.23.18: 4 commands, 9 skills, AGENTS.md
- v2.26.1: merge-pr skill, community-manager agent, 2 reference files
- v3.0.6: help command -- no literal `$()` but used `find | wc` and `cat` via Bash, which also trigger permission prompts

Each fix caught the files known at the time but missed others because the search scope was too narrow.

## Solution

Replace `$()` in bash code blocks with one of these patterns:

| Original pattern | Replacement |
|-----------------|-------------|
| `VAR=$(command)` | Separate bash block with just `command`, then prose: "Store the result as VAR" |
| `$(cat <<'EOF' ... EOF)` | Inline string with `--body "..."` (no subshell) |
| `$(command \| jq ...)` | Separate bash block, then prose: "Parse the output to extract..." |
| Complex `$(eval ...)` | Change code fence from `bash` to `text` and use comments |

Key principle: bash code blocks in plugin markdown are instructions for Claude, not scripts. They don't need to be valid standalone bash -- they need to be individual commands that Claude executes one at a time via the Bash tool.

**Better alternative (v3.0.6 insight):** When a bash block only reads files or lists directories, replace it entirely with prose instructions for Claude's native tools (Read, Glob, Grep). This eliminates Bash permission prompts completely and is more reliable than splitting commands. Example: `find ... | wc -l` becomes "Use the Glob tool with pattern X and count the results."

## Key Insight

The root cause of recurrence is **incomplete search scope**. Each prior fix searched only the files that triggered the immediate complaint (commands, then skills) but missed:
- Agent definition files (`agents/**/*.md`)
- Reference documents (`skills/*/references/*.md`)
- Any new files added after the previous fix

The correct fix is to search the ENTIRE `plugins/soleur/` directory for `$()` in all `.md` files, not just the category that triggered the report. The grep command:

```text
grep -rn '\$(' plugins/soleur/ --include='*.md'
```

Then filter out non-bash contexts (prose mentions in changelogs, etc.) and fix all bash code blocks.

## Prevention

When fixing a pattern across files, always search the widest reasonable scope. For plugin markdown issues, that means all `.md` files under `plugins/soleur/`, including subdirectories for agents, skills (with references/), and commands.

**Root-cause fix:** When the same `$()` pattern recurs across multiple files, extract it into a bash script (see `2026-02-24-extract-command-substitution-into-scripts.md`). The `archive-kb` skill demonstrates this pattern.

## Session Errors

1. Attempted to Edit worktree files without reading them first (tool requires a Read before Edit)
2. First edit to merge-pr SKILL.md was incomplete -- left `$(cat <<'EOF')` in the PR creation block, requiring a second edit pass

## Tags
category: integration-issues
module: plugins/soleur
symptoms: "Command contains $() command substitution" permission prompt

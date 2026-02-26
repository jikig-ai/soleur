# Learning: Allow rule for session-start command substitution

## Problem

The AGENTS.md session-start rule requires running `bash $(git rev-parse --show-toplevel)/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged` at the beginning of every session. Claude Code's security model prompts for confirmation whenever a Bash command contains `$()` command substitution, causing a blocking permission dialog on every session start.

Unlike skill-embedded `$()` (which can be extracted into scripts per the `extract-command-substitution-into-scripts` learning), this command inherently needs `$(git rev-parse --show-toplevel)` to resolve the repo root — it can't be simplified further.

## Solution

Add a glob-style allow rule to `.claude/settings.json` (project-level):

```json
"Bash(bash $(git rev-parse --show-toplevel)/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh *)"
```

The trailing `*` matches any subcommand (`cleanup-merged`, `feature`, `draft-pr`, etc.), so a single rule covers all worktree-manager invocations.

## Key Insight

There are two categories of `$()` in Claude Code workflows:

1. **Skill-embedded `$()`** — extract into scripts (per existing learning)
2. **Structural `$()`** that resolve environment context (repo root, branch name) — allow-list them in project settings

Session-start commands fall into category 2. They run before any skill context exists, and the `$(git rev-parse --show-toplevel)` pattern is the standard cross-platform way to resolve repo root regardless of CWD.

## Tags
category: integration-issues
module: .claude/settings.json
symptoms: "Command contains $() command substitution" prompt on every session start

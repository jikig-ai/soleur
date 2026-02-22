# Learning: Shell expansion syntax triggers manual approval in Claude Code

## Problem

Soleur plugin `.md` files (commands, skills, agents) contained bash code blocks with `${VARIABLE}`, `$VARIABLE`, and `$()` shell expansion syntax. When Claude Code reads these instructions and executes the suggested bash commands, its security layer flags the shell expansion and triggers a "Shell expansion syntax in paths requires manual approval" prompt -- breaking autonomous workflow execution.

**Scope:** 18+ files across commands, skills, and agents contained shell expansion patterns in executable bash code blocks.

**Symptoms:**
- Every `${CLAUDE_PLUGIN_ROOT}`, `${WORKTREE_PATH}`, `${BRANCH}`, `${slug}`, `$token`, `$VARIABLE` in a bash code block triggered manual approval
- Autonomous one-shot workflows stalled waiting for human approval at each flagged command
- The ship skill had already fixed this in v2.31.5, but the pattern was not applied project-wide

## Solution

Applied three fix strategies depending on context:

1. **Relative paths** -- Replace `${CLAUDE_PLUGIN_ROOT}/skills/foo/scripts/bar.sh` with `./plugins/soleur/skills/foo/scripts/bar.sh` (relative from repo root). Best for paths that always resolve to the same plugin directory.

2. **Angle-bracket prose placeholders** -- Replace `${BRANCH}` with `<branch-name>` and add a prose instruction: "Replace `<branch-name>` with the actual branch name from the previous step." Best for dynamic values.

3. **Two-step instructions** -- Split "run command with `${result}`" into "Step 1: run command to get value. Step 2: use that value literally in the next command." Best for values that come from command output.

**Files fixed:** git-worktree SKILL.md, brainstorm.md, one-shot.md, merge-pr SKILL.md, deploy SKILL.md, compound-docs SKILL.md, community-manager.md, community SKILL.md, functional-discovery.md, agent-finder.md, heal-skill SKILL.md, deploy-docs SKILL.md, file-todos SKILL.md, discord-content SKILL.md, changelog SKILL.md, release-announce SKILL.md, hetzner-setup.md

**Constitution rule added:** Never use shell variable expansion in bash code blocks within skill, command, or agent .md files.

## Key Insight

When doing codebase-wide pattern fixes, the initial grep must be exhaustive. Three categories of patterns were missed in the first pass and caught later:

1. **Case sensitivity** -- Initial search for `${UPPERCASE}` missed `${lowercase}` variables like `${slug}`, `${page}`, `${dep}`
2. **Bare variables** -- `$VARIABLE` (no braces) was missed when only searching for `${VARIABLE}`
3. **Conditional syntax** -- `${VAR:-}` (with default) in bash conditionals was a distinct pattern missed by the initial regex

The fix: run multiple grep patterns (`\$\{`, `\$[A-Z]`, `\$[a-z]`) and verify against a comprehensive exclusion list (hooks.json, TypeScript/JS code examples, CHANGELOG history).

## Session Errors

1. **Plan missed 4+ files** -- Initial plan listed 12 files but missed community/SKILL.md, discord-content/SKILL.md, changelog/SKILL.md, release-announce/SKILL.md, hetzner-setup.md. Found during verification grep.
2. **First implementation pass missed variable patterns** -- Only searched `${UPPERCASE_VAR}`, missing `${lowercase_var}`, `$BARE_VAR`, and `${VAR:-}` patterns. Caught by code review agents.
3. **Inconsistent placeholder notation** -- community/SKILL.md used `{APP_ID}` (curly braces) instead of `<app-id>` (angle brackets). Caught by code review and standardized.

## Tags
category: integration-issues
module: plugin-instructions

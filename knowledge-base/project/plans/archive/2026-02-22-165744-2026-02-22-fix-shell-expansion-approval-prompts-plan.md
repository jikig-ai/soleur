---
title: "fix: Eliminate shell expansion syntax that triggers manual approval prompts"
type: fix
date: 2026-02-22
version_bump: PATCH
---

# fix: Eliminate shell expansion syntax that triggers manual approval prompts

## Overview

Soleur plugin .md files (commands, skills, agents) contain bash code blocks with `${VARIABLE}` shell expansion syntax. When Claude Code reads these instructions and executes the suggested bash commands, it triggers a "Shell expansion syntax in paths requires manual approval" security prompt, breaking autonomous workflow execution.

The ship skill already has the fix pattern (v2.31.5): replace variable interpolation with prose instructions telling Claude to substitute actual values. This plan extends that pattern across all remaining files.

## Problem Statement

Claude Code's security layer flags bash commands containing `${}`, `$()`, `$VARIABLE`, and glob patterns (`**/*.md`) in paths. Every flagged command requires manual user approval, defeating the purpose of autonomous agent execution.

**Already fixed:** ship SKILL.md (v2.31.5), some `$()` removal (v2.31.3)
**Still broken:** 12+ files with `${CLAUDE_PLUGIN_ROOT}`, `${WORKTREE_PATH}`, `${BRANCH}`, `${slug}`, `${SCRIPT_DIR}`, `${SKILL_DIR}`, `${DEPLOY_HOST}`, `${QUERY}`, `${STACK}`, and other shell variables in bash code blocks.

## Proposed Solution

Apply the ship skill's established pattern: replace shell variable syntax in bash code blocks with prose instructions that tell Claude to substitute actual values literally. Two strategies depending on context:

1. **Relative paths** -- Replace `${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh` with `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (relative from repo root)
2. **Prose placeholders** -- Replace `${BRANCH}` with `<branch-name>` and add prose: "Replace `<branch-name>` with the actual branch name from the previous step"
3. **Two-step instructions** -- Split "run command with `${result}`" into "Step 1: run command to get value. Step 2: use that value literally in the next command"

## Acceptance Criteria

- [x] No bash code blocks in any .md file under `plugins/soleur/` contain `${VARIABLE}` or `$VARIABLE` shell expansion that Claude Code would execute
- [x] Code examples inside TypeScript/JavaScript template literals (backtick strings) are NOT modified -- these are source code, not bash commands
- [x] `hooks.json` `${CLAUDE_PLUGIN_ROOT}` references are NOT modified -- these are resolved by the plugin loader, not by Claude Code's bash executor
- [x] All bash commands remain functionally equivalent after the change
- [x] A global rule is added to a shared location (AGENTS.md or constitution) documenting this convention

## Test Scenarios

- Given a skill with `${CLAUDE_PLUGIN_ROOT}` in bash blocks, when the fix is applied, then the path uses `./plugins/soleur/` relative syntax
- Given a command with `${WORKTREE_PATH}` in bash blocks, when the fix is applied, then prose instructs Claude to substitute the actual worktree path
- Given an agent with `${QUERY}` in curl commands, when the fix is applied, then prose says "Replace `<search-query>` with the URL-encoded search term"
- Given a TypeScript template literal like `` `Stored ${key}` ``, when reviewing files, then it is left unchanged

## Files to Modify

### High Priority (frequently executed commands/skills)

| File | Variable(s) | Strategy |
|------|------------|----------|
| `skills/git-worktree/SKILL.md` | `${CLAUDE_PLUGIN_ROOT}` (20+ instances) | Relative path: `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` |
| `commands/soleur/brainstorm.md` | `${WORKTREE_PATH}` (4 instances) | Prose placeholder: `<worktree-path>` |
| `commands/soleur/one-shot.md` | `${CLAUDE_PLUGIN_ROOT}` (1 instance) | Relative path |
| `skills/merge-pr/SKILL.md` | `${BRANCH}`, `${STARTING_SHA}`, `${REPO_ROOT}` (8 instances) | Prose placeholder |
| `skills/deploy/SKILL.md` | `${CLAUDE_PLUGIN_ROOT}`, `${DEPLOY_HOST}`, `${DEPLOY_IMAGE}`, `${DEPLOY_DOCKERFILE}` (4 instances) | Mixed: relative path + prose |
| `skills/compound-docs/SKILL.md` | `${CATEGORY}`, `${FILENAME}`, `${slug}`, `${timestamp}` (15+ instances) | Prose placeholder |

### Medium Priority (agents, less frequently executed)

| File | Variable(s) | Strategy |
|------|------------|----------|
| `agents/marketing/community-manager.md` | `${SCRIPT_DIR}` (6 instances) | Prose: "Replace with the agent's script directory path" |
| `agents/engineering/discovery/functional-discovery.md` | `${QUERY}`, `${owner}`, `${repo}`, `${name}` (5 instances) | Prose placeholder |
| `agents/engineering/discovery/agent-finder.md` | `${STACK}`, `${owner}`, `${repo}`, `${name}` (5 instances) | Prose placeholder |

### Low Priority (rarely executed)

| File | Variable(s) | Strategy |
|------|------------|----------|
| `skills/heal-skill/SKILL.md` | `$SKILL_DIR` (3 instances) | Prose placeholder |
| `skills/deploy-docs/SKILL.md` | `${page}` (1 instance) | Prose placeholder |
| `skills/file-todos/SKILL.md` | `${dep}` (1 instance) | Prose placeholder |

### Exclusions (DO NOT modify)

- `hooks/hooks.json` -- `${CLAUDE_PLUGIN_ROOT}` is resolved by the plugin loader
- `skills/docs-site/SKILL.md` -- JavaScript template literals, not bash
- `skills/agent-native-architecture/references/*.md` -- TypeScript code examples, not bash instructions
- `agents/engineering/review/agent-native-reviewer.md` -- TypeScript examples
- `CHANGELOG.md` -- Historical references

## Global Convention

Add to `constitution.md` under `### Never`:

> Never use shell variable expansion (`${VAR}`, `$VAR`, `$()`) in bash code blocks within skill, command, or agent .md files -- use prose placeholders (`<variable-name>`) with substitution instructions instead; the ship skill's "No command substitution" pattern is the reference implementation

## Non-goals

- Modifying hooks.json (plugin loader resolves these)
- Modifying TypeScript/JavaScript code examples
- Changing the deploy skill's actual shell scripts (only the SKILL.md instructions)

## References

- Ship skill fix: CHANGELOG.md v2.31.5 entry
- Constitution line 69: "When fixing a pattern across plugin files..."
- Constitution line 117: "When skills use `!` code fences with permission-sensitive Bash commands..."

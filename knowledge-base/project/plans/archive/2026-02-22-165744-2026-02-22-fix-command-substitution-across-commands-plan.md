---
title: "fix: Remove $() command substitution from all commands and skills"
type: fix
date: 2026-02-22
---

# fix: Remove $() command substitution from all commands and skills

## Overview

Claude Code's security mechanism prompts users with "Command contains $() command substitution" when the Bash tool receives commands containing `$()`. Our command and skill markdown files contain bash code blocks with `$()` that the agent tries to execute, triggering this permission prompt repeatedly.

v2.23.14 fixed the one-shot command but missed the 4 commands and 8+ skills that still contain `$()` in their bash code blocks.

## Problem Statement

When running `/soleur:brainstorm`, `/soleur:plan`, `/soleur:work`, `/soleur:compound`, or any skill that references them (like `/ship`), users get repeated "Command contains $() command substitution" permission prompts. This breaks the autonomous workflow.

## Proposed Solution

Replace all `$()` command substitution in bash code blocks across commands and skills with either:

1. **Plain-language instructions** for the agent (preferred)
2. **Multi-step sequential commands** without `$()` (when specific commands are needed)
3. **Pre-resolved values** where possible

### Pattern Catalog

| Current Pattern | Replacement |
|---|---|
| `current_branch=$(git branch --show-current)` | Separate `git branch --show-current` call, store result in context |
| `cd $(git rev-parse --show-toplevel)` | "Navigate to the repository root directory" or use known path |
| `existing_issue=$(echo "..." \| grep ...)` | Plain-language: "Parse the feature description for #N pattern" |
| `$(date +%Y-%m-%d)` | "Use today's date in YYYY-MM-DD format" |
| `$(git merge-base HEAD origin/main)` | Separate command, store result |
| `$(cat <plan_path>)` | "Read the plan file content and pass as argument" |

## Acceptance Criteria

- [ ] No `$()` in any bash code block in `commands/soleur/*.md`
- [ ] No `$()` in any bash code block in `skills/*/SKILL.md`
- [ ] All commands still function correctly (agent understands what to do)
- [ ] Version bump (PATCH)

## Files to Modify

### Commands (4 files)
1. `plugins/soleur/commands/soleur/brainstorm.md` - 3 occurrences (lines 276, 283, 319)
2. `plugins/soleur/commands/soleur/plan.md` - 3 occurrences (lines 42, 642, 730)
3. `plugins/soleur/commands/soleur/work.md` - 5 occurrences (lines 36, 49, 87, 88, 92)
4. `plugins/soleur/commands/soleur/compound.md` - 1 occurrence (line 121)

### Skills (8+ files)
5. `plugins/soleur/skills/git-worktree/SKILL.md` - 2 occurrences (lines 244, 267)
6. `plugins/soleur/skills/compound-docs/SKILL.md` - 2 occurrences (lines 329, 439)
7. `plugins/soleur/skills/ship/SKILL.md` - ~20 occurrences (heaviest)
8. `plugins/soleur/skills/release-announce/SKILL.md` - 1 occurrence
9. `plugins/soleur/skills/release-docs/SKILL.md` - 5 occurrences
10. `plugins/soleur/skills/deploy/SKILL.md` - 4 occurrences
11. `plugins/soleur/skills/deploy-docs/SKILL.md` - 4 occurrences
12. `plugins/soleur/skills/rclone/SKILL.md` - 1 occurrence
13. `plugins/soleur/skills/file-todos/SKILL.md` - 1 occurrence

## Test Scenarios

- Given a fresh `/soleur:brainstorm` invocation, when the agent executes Phase 3.6, then no command substitution prompt appears
- Given `/soleur:plan` invocation, when the agent loads knowledge base context, then no command substitution prompt appears
- Given `/soleur:work` invocation, when Phase 0 runs cleanup-merged, then no command substitution prompt appears

## MVP

Fix all 13 files by replacing `$()` patterns with plain-language instructions or multi-step commands.

---
title: "feat: eliminate all utility commands, namespace remaining under soleur:"
type: feat
date: 2026-02-12
---

# Eliminate Utility Commands

[Updated 2026-02-12 after plan review]

## Overview

Remove all 9 top-level utility commands. Convert 6 to skills, delete 1 (redundant), move 2 into `commands/soleur/` with renames. Result: 8 commands (all `soleur:`-namespaced), 35 skills, zero top-level utility commands.

## Migration Table

Same migration pattern as PR #60. For each: rewrite frontmatter to third-person description with triggers, drop `argument-hint`/`allowed-tools`, keep body intact, delete command file.

| # | Command Source | Destination | Action | Notes |
|---|---------------|-------------|--------|-------|
| 1 | `commands/agent-native-audit.md` | `skills/agent-native-audit/SKILL.md` | Convert to skill | |
| 2 | `commands/deploy-docs.md` | `skills/deploy-docs/SKILL.md` | Convert to skill | |
| 3 | `commands/feature-video.md` | `skills/feature-video/SKILL.md` | Convert to skill | |
| 4 | `commands/generate_command.md` | _(none)_ | Delete | Redundant with `skill-creator` skill |
| 5 | `commands/heal-skill.md` | `skills/heal-skill/SKILL.md` | Convert to skill | Drop `allowed-tools` from frontmatter |
| 6 | `commands/report-bug.md` | `skills/report-bug/SKILL.md` | Convert to skill | |
| 7 | `commands/triage.md` | `skills/triage/SKILL.md` | Convert to skill | |
| 8 | `commands/help.md` | `commands/soleur/help.md` | Move + rename to `soleur:help` | Full body rewrite (see below) |
| 9 | `commands/lfg.md` | `commands/soleur/one-shot.md` | Move + rename to `soleur:one-shot` | Fix stale refs (see below) |

## Stale References in lfg/one-shot

The `lfg.md` body references commands that were renamed in PR #60 or will become skills in this PR:

```
/soleur:deepen-plan          -> /deepen-plan          (skill since PR #60)
/soleur:resolve_todo_parallel -> /resolve-todo-parallel (skill since PR #60, also underscore->kebab)
/soleur:test-browser         -> /test-browser          (skill since PR #60)
/soleur:feature-video        -> /feature-video         (skill after this PR)
```

Also references `/ralph-wiggum:ralph-loop` -- external plugin dependency. Keep as-is but note it in the command description.

## help Body Rewrite

The current `help.md` body is stale from before PR #60 -- it lists commands that were already converted to skills. The body needs a full rewrite, not just count updates:
- Command list: only the 8 `soleur:` commands
- Skill list: all 35 skills (read dynamically from manifest, per existing `help.md` approach)
- Agent list: keep current structure
- Remove all references to deleted utility commands

## AGENTS.md Update

Update directory structure comment in `plugins/soleur/AGENTS.md` -- remove `*.md # Utility commands` line since no top-level command files will exist.

## Acceptance Criteria

- [x] 6 new skill directories created under `plugins/soleur/skills/`
- [x] Each SKILL.md has valid frontmatter (name, third-person description with triggers)
- [x] 7 command files deleted (6 converted to skills + 1 redundant)
- [x] 2 command files moved to `commands/soleur/` (help, one-shot)
- [x] `one-shot` body: stale skill references fixed
- [x] `help` body: full rewrite reflecting final state
- [x] `AGENTS.md` directory structure comment updated
- [x] Plugin versioning triad updated (MINOR bump)
- [x] README tables and counts accurate (commands=8, skills=35)
- [x] `commands/` directory contains only `soleur/` subdirectory

## Test Scenarios

- Given the plugin, when running `ls plugins/soleur/commands/*.md 2>/dev/null | wc -l`, then count is 0
- Given the plugin, when running `ls plugins/soleur/commands/soleur/*.md | wc -l`, then count is 8
- Given the plugin, when running `ls -d plugins/soleur/skills/*/ | wc -l`, then count is 35
- Given SKILL.md files, when checking frontmatter, then all use third-person descriptions

## Breaking Changes

Only 3 user-facing name changes:
- `/help` -> `/soleur:help`
- `/lfg` -> `/soleur:one-shot`
- `/generate_command` -> removed (use `/skill-creator` instead)

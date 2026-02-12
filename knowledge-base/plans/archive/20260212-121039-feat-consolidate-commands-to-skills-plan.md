---
title: "feat: consolidate 10 command-only items into skills"
type: feat
date: 2026-02-12
---

# Consolidate Commands to Skills

[Updated 2026-02-12 after plan review]

## Overview

Convert 10 command-only items into skills for agent discoverability. Delete 1 pure-wrapper command. Update plugin versioning triad.

## Problem Statement

10 utility commands exist only as commands, invisible to agents. Converting them to skills makes them discoverable during autonomous workflows (e.g., agents can invoke `test-browser` during QA, `resolve-pr-parallel` during reviews).

## Proposed Solution

For each command: create a skill directory, write a SKILL.md with compliant frontmatter, move the command content, delete the command file. Then update versioning.

## Known Breaking Change

Converting underscore-named commands to kebab-case skills changes the slash command name. Users typing `/resolve_pr_parallel` will need to use `/resolve-pr-parallel`. This is acceptable -- kebab-case is the project convention and the old names were inconsistent.

## Acceptance Criteria

- [x] 10 new skill directories created under `plugins/soleur/skills/`
- [x] Each SKILL.md has valid frontmatter (name, third-person description with triggers)
- [x] 11 command files deleted (10 converted + 1 pure wrapper)
- [x] Plugin versioning triad updated (MINOR bump)
- [x] README tables and component counts accurate (commands=15, skills=29)
- [x] Root README version badge updated
- [x] `bug_report.yml` placeholder updated

## Test Scenarios

- Given the plugin is loaded, when running `ls plugins/soleur/skills/ | wc -l`, then count is 29
- Given the plugin is loaded, when running `ls plugins/soleur/commands/ | wc -l`, then count includes only 15 files (9 top-level + 6 in soleur/)
- Given the SKILL.md files, when running `grep -E '^description:' plugins/soleur/skills/*/SKILL.md | grep -v 'This skill'`, then no results (all use third person)
- Given the SKILL.md files, when checking `name` field vs directory name, then all match

## Technical Considerations

### SKILL.md Format

Each skill follows this pattern:

```yaml
---
name: kebab-case-name
description: "This skill should be used when [context]. It [does what]. Triggers on [keywords]."
---
```

- Name must match directory name (imperative/noun form, not gerund)
- Description must use third person ("This skill should be used when...")
- Include trigger keywords for agent discovery
- Use imperative/infinitive form for instructions

### Naming Convention

Existing skills use imperative/noun form (`ship`, `rclone`, `git-worktree`). New skills follow this convention. Normalize underscore names to kebab-case (e.g., `plan_review` becomes `plan-review`).

### Argument Handling

Commands use `argument-hint` in frontmatter and `$ARGUMENTS` in the body. Skills receive arguments via the Skill tool's `args` parameter, which is injected as `$ARGUMENTS` in the same way. No body changes needed -- just drop `argument-hint` from frontmatter.

### Version Bump Intent

**MINOR** bump -- adding 10 new skills is a feature change.

### Excluded Commands

**Orchestration commands stay as commands** (they compose multiple skills into multi-phase workflows):
- `soleur:brainstorm`, `soleur:plan`, `soleur:work`, `soleur:review`, `soleur:compound`, `soleur:sync`
- `triage` -- spawns sequential finding presentation with status transitions, composes `file-todos` skill
- `agent-native-audit` -- spawns 8 parallel principle-review agents with score compilation

**User-only commands stay as commands** (require human intent/judgment):
- `deploy-docs`, `generate_command`, `heal-skill`, `feature-video`, `report-bug`, `help`, `lfg`

## Implementation Phases

### Phase 1: Create 10 Skill Directories and SKILL.md Files

For each of these, create `plugins/soleur/skills/<name>/SKILL.md`:

| # | Command Source | Skill Directory |
|---|---------------|----------------|
| 1 | `commands/changelog.md` | `skills/changelog/` |
| 2 | `commands/deepen-plan.md` | `skills/deepen-plan/` |
| 3 | `commands/plan_review.md` | `skills/plan-review/` |
| 4 | `commands/release-docs.md` | `skills/release-docs/` |
| 5 | `commands/reproduce-bug.md` | `skills/reproduce-bug/` |
| 6 | `commands/resolve_parallel.md` | `skills/resolve-parallel/` |
| 7 | `commands/resolve_pr_parallel.md` | `skills/resolve-pr-parallel/` |
| 8 | `commands/resolve_todo_parallel.md` | `skills/resolve-todo-parallel/` |
| 9 | `commands/test-browser.md` | `skills/test-browser/` |
| 10 | `commands/xcode-test.md` | `skills/xcode-test/` |

**Migration per command:**
1. Create `plugins/soleur/skills/<name>/` directory
2. Read command file content
3. Rewrite frontmatter: normalize `name` to kebab-case, rewrite `description` to third person with trigger keywords, drop `argument-hint`
4. Keep the body content intact -- it is already prompt-format instructions
5. Write as `SKILL.md`

### Phase 2: Delete Command Files

Delete these 11 files from `plugins/soleur/commands/`:

1. `changelog.md`
2. `create-agent-skill.md` -- pure wrapper; the `create-agent-skills` skill (directory: `skills/create-agent-skills/`, name field: `creating-agent-skills`) already provides this. Only the command wrapper is deleted; the existing skill is not modified.
3. `deepen-plan.md`
4. `plan_review.md`
5. `release-docs.md`
6. `reproduce-bug.md`
7. `resolve_parallel.md`
8. `resolve_pr_parallel.md`
9. `resolve_todo_parallel.md`
10. `test-browser.md`
11. `xcode-test.md`

### Phase 3: Update Plugin Versioning Triad

All paths relative to repo root:

1. **`plugins/soleur/.claude-plugin/plugin.json`** -- MINOR version bump, update description counts (commands: 15, skills: 29)
2. **`plugins/soleur/CHANGELOG.md`** -- add entry documenting the consolidation
3. **`plugins/soleur/README.md`** -- update component count tables (commands: 15, skills: 29), update skills and commands tables
4. **Root `README.md`** -- update version badge
5. **`.github/ISSUE_TEMPLATE/bug_report.yml`** -- update placeholder version

Validate with existing commands from `plugins/soleur/AGENTS.md`:
```bash
grep -E '`(references|assets|scripts)/[^`]+`' plugins/soleur/skills/*/SKILL.md  # should return nothing
grep -E '^description:' plugins/soleur/skills/*/SKILL.md | grep -v 'This skill'  # should return nothing
```

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-12-consolidate-commands-to-skills-brainstorm.md`
- Spec: `knowledge-base/specs/feat-consolidate-commands-to-skills/spec.md`
- Issue: #58
- Inspiration: [Amp - Slashing Custom Commands](https://ampcode.com/news/slashing-custom-commands)
- Learning: `knowledge-base/learnings/plugin-versioning-requirements.md`

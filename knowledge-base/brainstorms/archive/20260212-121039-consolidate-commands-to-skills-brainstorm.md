# Brainstorm: Consolidate Commands to Skills

**Date:** 2026-02-12
**Status:** Approved
**Inspired by:** [Amp - Slashing Custom Commands](https://ampcode.com/news/slashing-custom-commands)

## What We're Building

Consolidate 10 command-only items into skills so agents can discover and invoke them autonomously during workflows. Delete 1 pure-wrapper command that duplicates an existing skill. Keep 7 user-only commands as-is.

This follows the pattern Amp adopted -- eliminating the command/skill duality where it creates redundancy -- but adapted to Soleur's architecture where orchestration commands (brainstorm, plan, work, review, etc.) legitimately compose multiple skills and should remain as commands.

## Why This Approach

**Problem:** 17 commands exist with no skill equivalent. 10 of these could be useful to agents during workflows (e.g., `resolve_pr_parallel` during code review, `test-browser` during QA). As command-only items, agents can't discover or invoke them.

**Amp's insight applies partially:** Soleur's orchestration commands (8 total) legitimately serve as workflow pipelines that compose multiple skills -- these are NOT redundant. But the 10 utility commands that do one thing well are perfect candidates for skills.

## Key Decisions

### Convert to Skills (10 commands)
These become skill directories with SKILL.md files. The command files are deleted.

| Command | New Skill Name | Rationale |
|---------|---------------|-----------|
| `release-docs` | `release-docs` | CI/agents can trigger after component changes |
| `reproduce-bug` | `reproduce-bug` | Triage agents can spawn investigations |
| `xcode-test` | `xcode-test` | Review agents can run for iOS PRs |
| `plan_review` | `plan-review` | Planning workflows can auto-trigger |
| `resolve_todo_parallel` | `resolve-todo-parallel` | Workflow agents can clean up before PRs |
| `changelog` | `changelog` | Can be auto-triggered after merges |
| `deepen-plan` | `deepen-plan` | Planning workflows can auto-invoke |
| `resolve_pr_parallel` | `resolve-pr-parallel` | Review workflows can address feedback |
| `test-browser` | `test-browser` | Review agents can run for web PRs |
| `resolve_parallel` | `resolve-parallel` | Workflow agents can use for TODO cleanup |

### Delete Pure Wrapper (1 command)
- `create-agent-skill` command -- the `create-agent-skills` skill already handles this

### Keep as Commands (7)
These require user intent/judgment and stay as-is:
- `deploy-docs` -- production deployment decision
- `generate_command` -- meta-command requiring design decisions
- `heal-skill` -- requires human judgment about correctness
- `feature-video` -- requires human curation
- `report-bug` -- user-facing support tool
- `help` -- documentation lookup
- `lfg` -- deliberate "let's go" trigger

### Keep as Orchestration Commands (8)
These compose multiple skills and are NOT redundant:
- `soleur:brainstorm`, `soleur:plan`, `soleur:work`, `soleur:review`
- `soleur:compound`, `soleur:sync`, `triage`, `agent-native-audit`

## Migration Pattern

For each command being converted:
1. Create `plugins/soleur/skills/<name>/SKILL.md`
2. Add YAML frontmatter (name, description in third person with trigger keywords)
3. Move command content into the skill, adapting format
4. Delete the command file from `plugins/soleur/commands/`
5. Update component counts in plugin.json, README, CHANGELOG

## Open Questions

- None -- approach is clear and approved.

## Impact

- **Commands:** 26 -> 15 (-11: 10 converted + 1 deleted)
- **Skills:** 19 -> 29 (+10 new)
- **Net effect:** Same functionality, better agent discoverability

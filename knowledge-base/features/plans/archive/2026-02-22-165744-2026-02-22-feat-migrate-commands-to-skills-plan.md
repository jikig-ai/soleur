---
title: "feat: Migrate Workflow Commands to Skills"
type: feat
date: 2026-02-22
---

# feat: Migrate Workflow Commands to Skills

## Overview

Migrate 6 internal pipeline commands (`brainstorm`, `plan`, `work`, `review`, `compound`, `one-shot`) from `commands/soleur/` to `skills/` so the `/` autocomplete menu shows only the 3 user-facing commands: `go`, `sync`, `help`. Rename 2 existing skills with name conflicts. MAJOR version bump.

## Problem Statement

Users see 9 commands in autocomplete when they only need 1 (`/go`). The 6 pipeline stages are internal orchestration that `/go` routes to automatically. Additionally, these workflow stages are invisible to agents (commands are not agent-discoverable), limiting autonomous pipeline execution.

## Proposed Solution

Big-bang migration of all 6 commands to skills in a single PR, with MAJOR version bump signaling the breaking change.

### Component Count Changes

| Component | Before | After | Delta |
|-----------|--------|-------|-------|
| Commands | 9 | 3 | -6 |
| Skills | 46 | 52 | +6 |
| Agents | 60 | 60 | 0 |

### Skill Renames

| Old Name | New Name | Purpose |
|----------|----------|---------|
| `brainstorming` | `brainstorm-techniques` | Question techniques & YAGNI reference |
| `compound-docs` | `compound-capture` | Documentation template & YAML schema |

### Command -> Skill Migrations

| Command File | New Skill Dir | Skill `name:` |
|-------------|--------------|---------------|
| `commands/soleur/brainstorm.md` | `skills/brainstorm/` | `brainstorm` |
| `commands/soleur/plan.md` | `skills/plan/` | `plan` |
| `commands/soleur/work.md` | `skills/work/` | `work` |
| `commands/soleur/review.md` | `skills/review/` | `review` |
| `commands/soleur/compound.md` | `skills/compound/` | `compound` |
| `commands/soleur/one-shot.md` | `skills/one-shot/` | `one-shot` |

## Technical Considerations

### Invocation Syntax Compatibility

`skill: soleur:<name>` resolves identically for both commands and skills because:
- Commands: `name: soleur:<name>` in frontmatter -> Skill tool matches `soleur:<name>`
- Skills: `name: <name>` in frontmatter + plugin namespace `soleur` -> Skill tool matches `soleur:<name>`

This means `go.md` lines 53-55 (`skill: soleur:brainstorm`) need zero changes for invocation. However, `go.md` prose (description, table text) says "command" where it should say "skill" post-migration.

### Invocation Prefix Convention

All Skill tool invocations use `skill: soleur:<name>` (with plugin namespace prefix), regardless of whether the skill was originally a command or an existing skill. This is consistent: `go.md` already uses this pattern, and it resolves correctly for all skills under the `soleur` plugin namespace.

### Constitution Conflict: Skills Invoking Skills

Constitution line 81: "Never design skills that invoke other skills programmatically."

After migration, `one-shot` (a skill) chains `plan` -> `work` -> `review` -> `compound` (all skills). This violates the letter of the principle.

**Resolution:** Update the constitution to distinguish pipeline orchestration (sequencing steps via Skill tool) from tight programmatic coupling (importing/calling as library functions). The `go` command already invokes skills via `skill:` syntax -- the pattern is established. Add a clarifying note to the constitution.

### Cross-Reference Update Pattern

| Before | After |
|--------|-------|
| `/soleur:plan` (slash syntax) | `skill: soleur:plan` |
| `skill: soleur:brainstorm` | No change (already correct) |
| `` `brainstorming` skill `` | `` `brainstorm-techniques` skill `` |
| `` `compound-docs` skill `` | `` `compound-capture` skill `` |

### Frontmatter Migration Pattern

```yaml
# BEFORE (command)
---
name: soleur:brainstorm
description: Explore requirements and approaches before planning
argument-hint: "[feature description or issue reference]"
---

# AFTER (skill)
---
name: brainstorm
description: "This skill should be used when exploring requirements and approaches through collaborative dialogue before planning implementation."
---
```

Changes per file:
1. `name:` -- Remove `soleur:` prefix
2. `description:` -- Rewrite to third person ("This skill should be used when...")
3. `argument-hint:` -- Remove entirely (skills don't use this field)
4. Body content: Update any internal `/soleur:<name>` references to `skill: soleur:<name>` syntax

**Test invariants enforced by `components.test.ts`:**
- All commands MUST have `argument-hint` field (applies to remaining 3 commands)
- All skill descriptions MUST start with "This skill" (applies to all 52 skills including the 6 new ones)
- Migrated SKILL.md files MUST satisfy both constraints

### Skill Category Assignments for `docs/_data/skills.js`

| New/Renamed Skill | Category |
|-------------------|----------|
| `brainstorm-techniques` | Review & Planning |
| `compound-capture` | Content & Release |
| `brainstorm` | Review & Planning |
| `plan` | Review & Planning |
| `work` | Workflow |
| `review` | Review & Planning |
| `compound` | Content & Release |
| `one-shot` | Workflow |

Note: `brainstorming` was categorized under "Content & Release" -- the rename to `brainstorm-techniques` is an opportunity to recategorize to "Review & Planning" where it fits alongside `plan-review` and `deepen-plan`.

## Acceptance Criteria

- [ ] Autocomplete shows only 3 commands: `go`, `sync`, `help`
- [ ] All 6 migrated skills are discoverable via `find plugins/soleur/skills -mindepth 1 -maxdepth 1 -type d`
- [ ] `skill: soleur:brainstorm` invocation still works (test via `/go`)
- [ ] `/soleur:go` routes correctly to all three intents
- [ ] `one-shot` pipeline executes: plan -> work -> review -> compound
- [ ] `bun test` passes
- [ ] No orphaned references to old command paths (outside CHANGELOG.md)
- [ ] CHANGELOG documents migration path for users

## Test Scenarios

- Given a user types `/`, when they see autocomplete, then only `go`, `sync`, `help` appear (no `brainstorm`, `plan`, etc.)
- Given a user runs `/soleur:go "fix auth bug"`, when they select "Build", then `one-shot` skill is invoked and chains through plan -> work -> review -> compound
- Given a user runs `/soleur:go "let's brainstorm"`, when they select "Explore", then `brainstorm` skill is invoked
- Given the `ship` skill runs, when it invokes compound, then the `compound` skill is found and executed
- Given `bun test` is run, when skill discovery scans `skills/`, then 52 skills are found
- Given `bun test` is run, when command discovery scans `commands/soleur/`, then 3 commands are found

## Rollback Plan

Since this is a single-PR big-bang migration, rollback is one revert: `git revert <merge-sha>`. All changes are in a single merge commit.

## Implementation Phases

### Phase 1: Rename Conflicting Skills (2 skills)

Rename directories and update all references.

**1.1 Rename `brainstorming` -> `brainstorm-techniques`**
- `git mv skills/brainstorming/ skills/brainstorm-techniques/`
- Update `SKILL.md` frontmatter: `name: brainstorm-techniques`
- Update references in:
  - `commands/soleur/brainstorm.md:13,194` -- "Load the `brainstorming` skill" -> "Load the `brainstorm-techniques` skill"
  - `commands/soleur/plan.md:177` -- brainstorming reference
  - `docs/_data/skills.js:10` -- `brainstorming` -> `"brainstorm-techniques"`, move to "Review & Planning" category
  - `README.md` skill table row

**1.2 Rename `compound-docs` -> `compound-capture`**
- `git mv skills/compound-docs/ skills/compound-capture/`
- Update `SKILL.md` frontmatter: `name: compound-capture`
- Update `skills/compound-capture/references/yaml-schema.md:3` -- internal path `plugins/soleur/skills/compound-docs/` -> `plugins/soleur/skills/compound-capture/`
- Update references in:
  - `commands/soleur/compound.md:169,202` -- `compound-docs` -> `compound-capture`
  - `commands/soleur/sync.md:266,320,417` -- YAML schema references
  - `agents/engineering/research/learnings-researcher.md:135` -- schema reference
  - `agents/engineering/research/best-practices-researcher.md:28` -- routing reference
  - `docs/_data/skills.js:12` -- `"compound-docs"` -> `"compound-capture"`
  - `README.md` skill table row

### Phase 2: Migrate Commands to Skills (6 commands)

For each command, create the skill directory, adapt the content, and delete the command.

**Per-command checklist:**
1. Create `skills/<name>/SKILL.md`
2. Copy body content from command
3. Adapt frontmatter (remove `soleur:` prefix, rewrite description to third person, remove `argument-hint`)
4. Update internal `/soleur:<name>` references to `skill: soleur:<name>` syntax within the file
5. Delete `commands/soleur/<name>.md`

**2.1 Migrate `brainstorm`**
- Body references to update: `/soleur:one-shot` (line 54), `/soleur:plan` (lines 315, 331, 353)
- Internal reference to `brainstorming` skill already updated in Phase 1

**2.2 Migrate `plan`**
- Body references to update: `/soleur:work` (lines 644, 676-686, 693, 721), `/deepen-plan` (already a skill)
- Re-running section references `/soleur:plan` (self-reference, update to skill name)

**2.3 Migrate `work`**
- Body references to update: `/soleur:review` (line 470), `/soleur:compound` (lines 430, 477)
- `skill: ship` reference (already correct)

**2.4 Migrate `review`**
- Minimal internal references to other commands

**2.5 Migrate `compound`**
- Body references to update: `compound-docs` -> `compound-capture` (already done in Phase 1)
- `/soleur:plan` reference (line 353)

**2.6 Migrate `one-shot`**
- Rewrite pipeline to use Skill tool syntax:
  ```
  1. skill: soleur:plan (with args)
  2. skill: soleur:deepen-plan
  3. skill: soleur:work
  4. skill: soleur:review
  5. skill: soleur:resolve-todo-parallel
  6. skill: soleur:compound
  7. skill: soleur:test-browser
  8. skill: soleur:feature-video
  ```

### Phase 3: Update Remaining Commands (3 files)

**3.1 Update `commands/soleur/go.md`**
- Description (line 3): "routes to the right workflow command" -> "routes to the right workflow skill"
- Lines 25, 33-35: Update `/soleur:work`, `/soleur:brainstorm`, `/soleur:one-shot`, `/soleur:review` prose references
- Lines 53-55: Already use `skill:` syntax -- no change needed for invocations

**3.2 Update `commands/soleur/help.md`**
- Lines 53-59: Remove "WORKFLOW COMMANDS (advanced)" section entirely. Replace with note that workflow stages are now skills invoked via `/soleur:go`.

**3.3 Verify `commands/soleur/sync.md`**
- `compound-docs` references already handled in Phase 1.2

### Phase 4: Update External Skills (8 skills)

Skills that reference the migrated commands:

| Skill | References (with line counts) | Update |
|-------|------|--------|
| `ship/SKILL.md` | `/soleur:compound` (lines 76, 82, 228, 230) | -> `skill: soleur:compound` |
| `deepen-plan/SKILL.md` | `/soleur:plan` (lines 12, 480), `/soleur:work` (lines 467, 474), `/soleur:compound` (lines 147, 153, 356) -- 7 refs total | -> `skill: soleur:*` |
| `git-worktree/SKILL.md` | `/soleur:review` (lines 41, 50), `/soleur:work` (lines 207, 220) | -> `skill: soleur:*` |
| `brainstorm-techniques/SKILL.md` | `/soleur:plan` (line 154) | -> `skill: soleur:plan` |
| `test-fix-loop/SKILL.md` | `/soleur:work` (line 13) | -> `skill: soleur:work` |
| `merge-pr/SKILL.md` | `/soleur:compound` | -> `skill: soleur:compound` |
| `xcode-test/SKILL.md` | `/soleur:review` | -> `skill: soleur:review` |
| `file-todos/SKILL.md` | `/soleur:review` | -> `skill: soleur:review` |

### Phase 5: Update Agents (2 agents)

- `agents/engineering/research/learnings-researcher.md:135` -- Update `compound-docs` reference to `compound-capture`
- `agents/engineering/research/learnings-researcher.md:239` -- Update `/soleur:plan` reference
- `agents/engineering/research/best-practices-researcher.md:28` -- Update `compound-docs` reference to `compound-capture`

### Phase 6: Update Documentation and Infrastructure

**6.1 Root `AGENTS.md`**
- Line 58 (Workflow Completion Protocol): `/soleur:compound` -> `skill: soleur:compound`
- Line 67: `/soleur:compound` -> skill reference
- Lines 74-78: Command naming section -- update to reflect that workflow stages are now skills, only `go`, `sync`, `help` remain as commands
- Lines 101-105: Feature lifecycle -- update from `/soleur:<name>` to skill references

**6.2 Constitution (`knowledge-base/overview/constitution.md`)**
- Line 48: "Core workflow commands use `soleur:` prefix..." -> Update to reflect only `go`, `sync`, `help` are commands; workflow stages are skills
- Line 58: `/soleur:compound` -> `skill: soleur:compound`
- Line 81: Add clarifying note -- pipeline orchestration via Skill tool (e.g., `one-shot` sequencing `plan` -> `work`) is the approved pattern; the principle targets tight programmatic imports, not Skill tool invocations
- Line 90: "Use skills for agent-discoverable capabilities; use commands only for..." -> Update to reflect the new pattern where workflow orchestration uses skills
- Line 110: "When simplifying a multi-command system, prefer adding a router/facade..." -> Update to note Phase 2 (migration) completed after Phase 1 (router) proved the concept

**6.3 Plugin `AGENTS.md` (`plugins/soleur/AGENTS.md`)**
- Lines 74-80: **Substantial rewrite** of "Command Naming Convention" section. The `soleur:` prefix rationale changes -- skills inherit the prefix from the plugin namespace, not from frontmatter `name: soleur:plan`. Update all examples to show only the 3 remaining commands, and explain the skill naming convention.
- Update any other references to migrated commands

**6.4 Plugin `README.md`**
- Workflow diagram: Update from command syntax to skill syntax
- Command table: Remove 6 rows
- Skill table: Add 6 rows, update 2 renamed rows
- Update all component counts

**6.5 Root `README.md`**
- Version badge: Update to MAJOR version
- Component counts: "9 commands" -> "3 commands", "46 skills" -> "52 skills"
- Workflow table and pipeline diagram: Update from `/soleur:<name>` command syntax to skill references

**6.6 `knowledge-base/overview/README.md`**
- Mermaid diagram (lines 18-22): Update command references
- Text pipeline (line 60): Update workflow description
- Workflow table (lines 65-69): Update command names
- One-shot reference (line 77): Update
- Narrative references (line 96): Update
- Example (line 156): Update

**6.7 `knowledge-base/overview/components/commands.md`**
- Command count (line 62): "Commands (8)" -> "Commands (3)"
- Workflow sequence diagram (lines 79-98): Rewrite to show commands routing to skills
- Command catalog (lines 62-75): Remove migrated commands, keep go/sync/help
- Examples (lines 107-123): Update

**6.8 `knowledge-base/overview/components/agents.md`**
- Line 48: "Workflow command (e.g., `/soleur:review`)" -> "Workflow skill (e.g., `soleur:review`)"

**6.9 `docs/_data/skills.js`**
- Remove: `brainstorming`, `compound-docs`
- Add with categories per table above: `brainstorm-techniques`, `compound-capture`, `brainstorm`, `plan`, `work`, `review`, `compound`, `one-shot`

**6.10 `docs/pages/getting-started.md`**
- Lines 35-60: Update HTML from command names to skill references
- Rewrite workflow section to show `/soleur:go` as primary entry and skills as pipeline stages

**6.11 `.claude-plugin/plugin.json`**
- Version: MAJOR bump
- Description: "9 commands" -> "3 commands", "46 skills" -> "52 skills"

**6.12 `CHANGELOG.md`**

```markdown
## [MAJOR] - 2026-02-22

### Changed

- Migrate 6 workflow commands (brainstorm, plan, work, review, compound, one-shot) to skills -- pipeline stages are now agent-discoverable via Skill tool
- Rename `brainstorming` skill to `brainstorm-techniques`
- Rename `compound-docs` skill to `compound-capture`

### Removed

- Remove 6 workflow commands from autocomplete (brainstorm, plan, work, review, compound, one-shot) -- use `/soleur:go` instead

### Migration Guide

If you previously invoked `/soleur:brainstorm`, `/soleur:plan`, `/soleur:work`, `/soleur:review`, `/soleur:compound`, or `/soleur:one-shot` directly, use `/soleur:go` instead. All workflow stages are now skills invoked automatically through the router. The `skill: soleur:<name>` invocation syntax continues to work unchanged.
```

**6.13 `.github/ISSUE_TEMPLATE/bug_report.yml`**
- Update version placeholder to MAJOR version

### Phase 7: Test and Verify

1. Run `bun test` -- verify all tests pass (skill descriptions start with "This skill", remaining commands have `argument-hint`)
2. Verify skill count: `find plugins/soleur/skills -mindepth 1 -maxdepth 1 -type d | wc -l` = 52
3. Verify command count: `find plugins/soleur/commands/soleur -name "*.md" -type f | wc -l` = 3
4. Grep for orphaned `/soleur:` references in plugins/soleur/ (should match only CHANGELOG.md historical entries)
5. Grep for orphaned `brainstorming` / `compound-docs` references in plugins/soleur/ (should match only CHANGELOG.md)
6. Grep for orphaned references in knowledge-base/ and root docs (AGENTS.md, README.md)

## Non-Goals

- NOT modifying the plugin loader
- NOT changing agent structure
- NOT updating CHANGELOG.md historical entries
- NOT migrating `go`, `sync`, or `help`

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Cross-reference breakage (170+ total refs) | Systematic grep verification in Phase 7 |
| Skill-to-skill invocation (constitution) | Constitution update in Phase 6.2 |
| Users with muscle memory for `/soleur:plan` | MAJOR bump + migration guide in CHANGELOG |
| CHANGELOG conflicts on merge | Merge main before version bump per protocol |

## References

- Issue: #273
- Brainstorm: `knowledge-base/brainstorms/2026-02-22-migrate-commands-to-skills-brainstorm.md`
- Prior exploration: `knowledge-base/learnings/2026-02-22-simplify-workflow-command-routing.md`
- Router PR: #267

# Brainstorm: Migrate Workflow Commands to Skills

**Date:** 2026-02-22
**Issue:** #273
**Status:** Complete

## What We're Building

Migrating 6 internal pipeline commands (`brainstorm`, `plan`, `work`, `review`, `compound`, `one-shot`) from `commands/soleur/` to `skills/`, so the `/` autocomplete menu shows only the 3 user-facing commands: `go`, `sync`, `help`. This also makes the workflow stages agent-discoverable (skills are visible to agents, commands are not).

Two existing skills with name conflicts will be renamed to free up the clean names:
- `brainstorming` -> `brainstorm-techniques`
- `compound-docs` -> `compound-capture`

## Why This Approach

**Three motivations converge:**
1. **User friction** -- 9 commands in autocomplete when users only need `/go`
2. **Agent discoverability** -- Skills are agent-visible; commands aren't. Making workflows skills means agents can invoke them autonomously.
3. **Cleanliness** -- The router (`/go`) proved the concept; this is the natural follow-through.

**Prior exploration (2026-02-22 learnings)** flagged this as high-cost due to ~80-100 cross-references. New analysis shows the cost is lower than estimated:
- `skill: soleur:<name>` invocations resolve identically for both commands and skills (plugin namespace handles it)
- Only `/soleur:<name>` slash-syntax references need updating (~30-40, not 80-100)
- Historical references in CHANGELOG.md don't need updating

**Constitution tension resolved:** The constitution says "prefer adding a router/facade over migrating existing components." Phase 1 (the `/go` router, #267) already landed. This is Phase 2 -- completing the simplification that the router enabled. The router stays; the underlying commands become skills.

## Key Decisions

1. **Big-bang migration** -- All 6 commands in one PR. Avoids intermediate inconsistency where some are commands and some are skills.

2. **MAJOR version bump** (2.36.1 -> 3.0.0) -- Removing 6 commands from autocomplete is a breaking change for users with muscle memory for `/soleur:brainstorm` etc.

3. **Claim clean names** -- Rename existing conflicting skills first, then use the clean names for migrated commands:
   - `brainstorming` -> `brainstorm-techniques` (reference/knowledge resource)
   - `compound-docs` -> `compound-capture` (documentation template engine)
   - Migrated commands get: `brainstorm`, `plan`, `work`, `review`, `compound`, `one-shot`

4. **Explicit Skill tool syntax for cross-references** -- Update all `/soleur:<name>` slash references to explicit Skill tool invocations (`skill: soleur:<name>`). No ambiguity about invocation method.

5. **`skill: soleur:<name>` references are safe** -- These resolve identically pre- and post-migration. No changes needed for these.

## Migration Mechanics

### Frontmatter Changes (per migrated command)

| Field | Command (before) | Skill (after) |
|-------|-----------------|---------------|
| `name:` | `soleur:<name>` | `<name>` |
| `description:` | Active voice | Third person ("This skill should be used when...") |
| `argument-hint:` | Required | Removed (not used in skills) |

### Reference Update Pattern

| Before | After |
|--------|-------|
| `/soleur:plan $ARGUMENTS` | Use the **Skill tool**: `skill: soleur:plan` with args |
| `/soleur:compound` | Use the **Skill tool**: `skill: soleur:compound` |
| `skill: soleur:brainstorm` | No change (already correct) |

### Files Requiring Cross-Reference Updates

**Migrated commands (internal references):**
- `one-shot` chains: plan -> work -> review -> compound
- `brainstorm` hands off to: one-shot, plan
- `plan` hands off to: work
- `work` references: review, compound

**External skills referencing these commands:**
- `ship/SKILL.md` -> compound
- `deepen-plan/SKILL.md` -> plan, work, compound
- `git-worktree/SKILL.md` -> review, work
- `brainstorming/SKILL.md` (becoming brainstorm-techniques) -> plan
- `test-fix-loop/SKILL.md` -> work
- `merge-pr/SKILL.md` -> compound
- `xcode-test/SKILL.md` -> review
- `file-todos/SKILL.md` -> review

**Agents:**
- `agents/engineering/research/learnings-researcher.md` -> plan

**Documentation (update prose, not functional):**
- `AGENTS.md` command naming section
- `README.md` command/skill counts
- `docs/pages/getting-started.md`

### Registration Checklist (per new skill)

1. `skills/<name>/SKILL.md`
2. `docs/_data/skills.js` (category map)
3. `README.md` (skill table)
4. `plugin.json` (version + counts)
5. `CHANGELOG.md`
6. Root `README.md` (version badge + counts)

### Test Updates

- `components.test.ts`: Command count drops from 9 to 3, skill count increases from 46 to 52 (rename 2 + add 6)
- Verify migrated skills pass third-person description test
- Verify migrated skills don't have `argument-hint` field

## Open Questions

1. **Downstream user impact** -- Are there external users who invoke `/soleur:plan` directly rather than through `/go`? The MAJOR bump signals breaking change but we should document the migration path in CHANGELOG.
2. **`$ARGUMENTS` vs `#$ARGUMENTS`** -- Both patterns exist in skills. Verify both work identically post-migration (research confirms they do, but validate empirically).

## Scope Exclusions

- NOT moving `go`, `sync`, or `help` -- these stay as commands
- NOT changing agent structure
- NOT modifying the plugin loader itself
- NOT updating CHANGELOG.md historical references (they're historical)

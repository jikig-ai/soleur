# Tasks: Add Branch Guards to Brainstorm and Plan Skills

## Phase 1: Setup

- 1.1 Read `plugins/soleur/skills/brainstorm/SKILL.md` to confirm current state (no guard exists)
- 1.2 Read `plugins/soleur/skills/plan/SKILL.md` to confirm current state (no guard exists)
- 1.3 Read `plugins/soleur/skills/compound/SKILL.md` line 28 as the reference guard pattern

## Phase 2: Core Implementation

- 2.1 Edit `plugins/soleur/skills/brainstorm/SKILL.md`: insert branch safety check paragraph after the "Load project conventions" bash block (after line 35), before the "Plugin loader constraint" paragraph
- 2.2 Edit `plugins/soleur/skills/plan/SKILL.md`: insert branch safety check paragraph after the "Load project conventions" bash block (after line 31), before "Check for knowledge-base directory and load context"

## Phase 3: Verification

- 3.1 Grep all SKILL.md files for "defense-in-depth" to confirm brainstorm and plan now appear alongside compound, ship, and work
- 3.2 Verify guard phrasing matches exactly: "defense-in-depth alongside PreToolUse hooks"
- 3.3 Verify guard placement is before any file-writing phases in both skills
- 3.4 Run compound, commit, push, create/update PR

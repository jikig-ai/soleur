---
feature: compound-error-analysis
issue: "#168"
branch: feat-compound-error-analysis
---

# Tasks: Compound Session Error Analysis

## Phase 1: Core Implementation

- [x] 1.1 Extend Step 2 (Gather Context) in `plugins/soleur/skills/compound-docs/SKILL.md`
  - Add "Session errors" sub-section to the "Extract from conversation history" block
  - Use imperative form for all instruction bullets
  - Include: extraction criteria, skip conditions, output format

- [x] 1.2 Add "Session Errors" section to `plugins/soleur/skills/compound-docs/assets/resolution-template.md`
  - Insert after "What Didn't Work", before "Solution"
  - Use bold-heading + bullet format (matching "What Didn't Work" style)
  - Include conditional note: omit section when no errors found

- [x] 1.3 Add "Session errors" bullet to "What It Captures" in `plugins/soleur/commands/soleur/compound.md`

## Phase 2: Finalize

- [x] 2.1 Version bump (PATCH) -- update plugin.json, CHANGELOG.md, README.md
- [x] 2.2 Run code review on changes
- [x] 2.3 Run /soleur:compound (no significant learnings -- straightforward markdown edits)
- [ ] 2.4 Commit, push, create PR referencing #168

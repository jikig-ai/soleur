# Tasks: Sync Definitions

**Issue:** #110
**Plan:** `knowledge-base/plans/2026-02-17-feat-sync-definitions-plan.md`

## Phase A: Prerequisite

- [x] **A.1** Update compound-docs Step 8.4 to write `synced_to` to learning frontmatter after accepted routing
  - File: `plugins/soleur/skills/compound-docs/SKILL.md`
  - After "If accepted, write the edit to the file" add frontmatter update logic
  - Handle: existing frontmatter with `synced_to`, existing frontmatter without `synced_to`, no frontmatter

## Phase B: Definition Sync (sync.md Phase 4)

- [x] **B.1** Add Phase 4 to sync.md after Phase 3
  - File: `plugins/soleur/commands/soleur/sync.md`
  - Step 4.1: Gate check (area is `all` or default, both directories exist)
  - Step 4.2: Load learnings (titles, tags, `synced_to`) and definitions (names, types)
  - Step 4.3: Match learnings to definitions (single-pass LLM, skip already-synced, check for existing bullets)
  - Step 4.4: Review UX (Accept/Skip/Edit/Done reviewing, write bullets on accept, update `synced_to` frontmatter)
  - Step 4.5: Summary

- [x] **B.2** Update sync.md area filter to skip Phase 4 on scoped areas
  - When area is `conventions`, `architecture`, `testing`, `debt`, or `overview`: skip Phase 4
  - When area is `all` or unspecified: run Phase 4

## Phase C: Versioning

- [x] **C.1** Version bump (PATCH)
  - Update `plugin.json`, `CHANGELOG.md`, `README.md`

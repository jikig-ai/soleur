---
name: Release Announce Tasks
description: Implementation tasks for the release-announce skill
date: 2026-02-12
issue: "#59"
---

# Release Announce Tasks

## Phase 1: Create Skill

- [x] 1.1 Create `plugins/soleur/skills/release-announce/SKILL.md`
  - YAML frontmatter: name, description (third-person)
  - Step 1: Read version + changelog, generate summary
  - Step 2: Post to Discord (curl + DISCORD_WEBHOOK_URL, truncate to 1900 chars)
  - Step 3: Create GitHub Release (gh release create, idempotency check)
  - Include Discord message template with exact format
  - Graceful degradation: warn and continue on missing env var or failures

## Phase 2: Ship Integration

- [x] 2.1 Modify `plugins/soleur/skills/ship/SKILL.md` Phase 8
  - After merge step, before cleanup
  - Check if plugin.json was modified in branch
  - If modified: invoke /release-announce

## Phase 3: Version Bump and Documentation

- [x] 3.1 Bump version 2.1.0 -> 2.2.0 in `plugins/soleur/.claude-plugin/plugin.json`
- [x] 3.2 Add `## [2.2.0]` entry to `plugins/soleur/CHANGELOG.md`
- [x] 3.3 Update `plugins/soleur/README.md` skill count (34 -> 35) and skill table
- [x] 3.4 Update plugin.json description with new skill count
- [x] 3.5 Update root `README.md` version badge to 2.2.0
- [x] 3.6 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder to 2.2.0

## Phase 4: Validation

- [x] 4.1 Run `bun test` to verify plugin component tests pass
- [x] 4.2 Verify skill is discoverable (check test output for release-announce)

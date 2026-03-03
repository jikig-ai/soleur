# Tasks: Serialize Version Bumps to Merge-Time Only

## Phase 1: Core GitHub Action + PR Template

- [ ] 1.1 Create `.github/workflows/version-bump-and-release.yml`
  - [ ] 1.1.1 Trigger on push to main, concurrency group, permissions
  - [ ] 1.1.2 Plugin file change detection (`git diff --name-only HEAD~1 -- plugins/soleur/`)
  - [ ] 1.1.3 PR lookup from squash-merge commit message `(#NNN)`
  - [ ] 1.1.4 Semver label reading with PATCH default
  - [ ] 1.1.5 Version computation (read current, increment)
  - [ ] 1.1.6 Idempotency check (tag existence)
  - [ ] 1.1.7 CHANGELOG extraction from PR body (sanitized, temp file)
  - [ ] 1.1.8 Component count auto-computation (`find` commands)
  - [ ] 1.1.9 Atomic 6-file update (plugin.json, CHANGELOG.md, README.md, marketplace.json, root README, bug_report.yml)
  - [ ] 1.1.10 Git commit and push
  - [ ] 1.1.11 GitHub Release creation
  - [ ] 1.1.12 Discord notification (with secret check, truncation)
- [ ] 1.2 Create `.github/PULL_REQUEST_TEMPLATE.md` with `## Changelog` section
- [ ] 1.3 Validate component count `find` commands match current counts (61 agents, 3 commands, 55 skills)

## Phase 2: Ship Skill Restructuring

- [ ] 2.1 Remove Phase 3.5 (merge main before version bump)
- [ ] 2.2 Remove Phase 5 (version bump sealing operation)
- [ ] 2.3 Update Phase 6 checklist (remove version items)
- [ ] 2.4 Add to Phase 7: bump type analysis + `semver:*` label setting
- [ ] 2.5 Add to Phase 7: `## Changelog` section generation in PR body
- [ ] 2.6 Update Phase 8 (remove auto-release.yml reference)
- [ ] 2.7 Update frontmatter description

## Phase 3: Related Skill Updates

- [ ] 3.1 `merge-pr/SKILL.md`: remove Phase 4 (version bump), update conflict table, update description
- [ ] 3.2 `one-shot/SKILL.md`: update ship phase description (line 98)
- [ ] 3.3 `compound-capture/SKILL.md`: remove "version-bump" reference (line 308)
- [ ] 3.4 `release-announce/SKILL.md`: add manual fallback note

## Phase 4: Convention Documentation Updates

- [ ] 4.1 `AGENTS.md` (root): rewrite version gate (line 24)
- [ ] 4.2 `plugins/soleur/AGENTS.md`: rewrite versioning section + pre-commit checklist
- [ ] 4.3 `constitution.md`: update ~6 version bump references (lines 50, 63, 64, 66, 77, 104)

## Phase 5: Workflow Cleanup

- [ ] 5.1 Delete `.github/workflows/auto-release.yml`
- [ ] 5.2 Add `workflow_run` trigger to `deploy-docs.yml`

## Phase 6: Pre-Existing Fixes

- [ ] 6.1 Fix root README badge drift (3.8.1 → current version)
- [ ] 6.2 Validate all 6 version files are in sync

## Phase 7: Migration and Testing

- [ ] 7.1 Document worktree migration instructions in PR description
- [ ] 7.2 Verify the Action works on first real merge

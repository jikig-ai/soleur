# Tasks: Serialize Version Bumps to Merge-Time Only

## Phase 1: Core GitHub Action + PR Template

- [x] 1.1 Create `.github/workflows/version-bump-and-release.yml`
  - [x] 1.1.1 Trigger on push to main + workflow_dispatch (escape hatch), concurrency group, permissions
  - [x] 1.1.2 Plugin file change detection (`git diff --name-only HEAD~1 -- plugins/soleur/`)
  - [x] 1.1.3 PR lookup from squash-merge commit message `(#NNN)`
  - [x] 1.1.4 Semver label reading with PATCH default
  - [x] 1.1.5 Version computation (read current, increment)
  - [x] 1.1.6 Idempotency check (tag existence)
  - [x] 1.1.7 CHANGELOG extraction from PR body (sanitized, temp file)
  - [x] 1.1.8 Component count auto-computation (`find` commands)
  - [x] 1.1.9 Atomic 6-file update (plugin.json, CHANGELOG.md, README.md, marketplace.json, root README, bug_report.yml)
  - [x] 1.1.10 Version consistency verification (all 6 files match before commit)
  - [x] 1.1.11 Git commit with explicit file paths (no `git add -A`) and push
  - [x] 1.1.12 GitHub Release creation
  - [x] 1.1.13 Discord notification (with secret check, truncation)
- [x] 1.2 Create `.github/PULL_REQUEST_TEMPLATE.md` with `## Changelog` section
- [x] 1.3 Validate component count `find` commands match current counts (61 agents, 3 commands, 55 skills)

## Phase 2: Ship Skill Restructuring

- [x] 2.1 Remove Phase 3.5 (merge main before version bump)
- [x] 2.2 Remove Phase 5 (version bump sealing operation)
- [x] 2.3 Remove version conflict routing from Phase 7.5 (dead code — version files never in branches)
- [x] 2.4 Update Phase 6 checklist (remove version items)
- [x] 2.5 Add to Phase 7: bump type analysis + `semver:*` label setting
- [x] 2.6 Add to Phase 7: `## Changelog` section generation in PR body
- [x] 2.7 Update Phase 8 (remove auto-release.yml reference)
- [x] 2.8 Update frontmatter description

## Phase 3: Related Skill Updates

- [x] 3.1 `merge-pr/SKILL.md`: remove Phase 4 (version bump), update conflict table, update description
- [x] 3.2 `one-shot/SKILL.md`: update ship phase description (line 98)
- [x] 3.3 `compound-capture/SKILL.md`: remove "version-bump" reference (line 308)
- [x] 3.4 `release-announce/SKILL.md`: add manual fallback note

## Phase 4: Convention Documentation Updates

- [x] 4.1 `AGENTS.md` (root): rewrite version gate (line 24)
- [x] 4.2 `plugins/soleur/AGENTS.md`: rewrite versioning section + pre-commit checklist
- [x] 4.3 `constitution.md`: update ~6 version bump references (lines 50, 63, 64, 66, 77, 104)

## Phase 5: Workflow Cleanup

- [x] 5.1 Delete `.github/workflows/auto-release.yml`
- [x] 5.2 Add `workflow_run` trigger to `deploy-docs.yml` (with `conclusion == 'success'` check)

## Phase 6: Pre-Existing Fixes

- [x] 6.1 Fix root README badge drift (3.8.1 → 3.8.2)
- [x] 6.2 Validate all 6 version files are in sync

## Phase 7: Migration and Testing

- [ ] 7.1 Document worktree migration instructions in PR description
- [ ] 7.2 Verify the Action works on first real merge

# Tasks: Pre-Flight Validation Checks

## Phase 1: Core Implementation

- [ ] 1.1 Add Phase 0.5 section to `plugins/soleur/commands/soleur/work.md` between Phase 0 and Phase 1
  - [ ] 1.1.1 Environment checks: git branch, pwd, git status, git stash list
  - [ ] 1.1.2 Scope checks: plan file existence, merge conflict zone detection
  - [ ] 1.1.3 Result handling: FAIL blocks, WARN displays, all-pass continues silently
- [ ] 1.2 Add convention verification reminder to Phase 1 "Read Plan and Clarify" step

## Phase 2: Testing

- [ ] 2.1 Verify work.md Phase 0.5 instructions are complete and unambiguous
- [ ] 2.2 Run `bun test` to ensure no regressions

## Phase 3: Documentation and Versioning

- [ ] 3.1 Update `plugins/soleur/CHANGELOG.md` with new version entry
- [ ] 3.2 Bump version in `plugins/soleur/.claude-plugin/plugin.json` (PATCH)
- [ ] 3.3 Update `plugins/soleur/README.md` if needed (no new agents, likely no change)
- [ ] 3.4 Update root `README.md` version badge
- [ ] 3.5 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder

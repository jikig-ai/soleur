# Tasks: Add review agents to /soleur:review

**Issue:** #38
**Branch:** feat-add-review-agents
**Plan:** `knowledge-base/plans/2026-02-10-feat-add-review-agents-to-soleur-review-plan.md`

## Phase 1: Core Implementation

- [x] 1.1 Add `code-quality-analyst` as item #10 in `<parallel_tasks>` block (`plugins/soleur/commands/soleur/review.md:79`)
- [x] 1.2 Add `test-design-reviewer` conditional section in `<conditional_agents>` block (`plugins/soleur/commands/soleur/review.md:107-122`)

## Phase 2: Version Bump

- [x] 2.1 Bump MINOR version to 1.15.0 in `plugins/soleur/.claude-plugin/plugin.json`
- [x] 2.2 Add CHANGELOG entry in `plugins/soleur/CHANGELOG.md`
- [x] 2.3 Verify agent counts in `plugins/soleur/README.md` (no change needed -- agents already listed)
- [x] 2.4 Update version badge in root `README.md`
- [x] 2.5 Update placeholder in `.github/ISSUE_TEMPLATE/bug_report.yml`

## Phase 3: Ship

- [ ] 3.1 Commit all changes
- [ ] 3.2 Run `/ship` to push and create PR

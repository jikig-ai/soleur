# Tasks: Brainstorm Brand Routing

**Plan:** `knowledge-base/plans/2026-02-13-feat-brainstorm-brand-routing-plan.md`
**Issue:** #76

## Phase 1: Core Implementation

- [ ] 1.1 Add "Phase 0.5: Specialized Domain Routing" section to `plugins/soleur/commands/soleur/brainstorm.md` after line 55 (after one-shot paragraph, before Phase 1)
  - Brand/marketing keyword list
  - AskUserQuestion for brand workshop confirmation
  - Worktree + issue creation on acceptance (reuse Phase 3/3.6 logic)
  - Task brand-architect handoff
  - Brand workshop output summary template
  - HTML comment for future domain extension pattern

## Phase 2: Version Bump

- [ ] 2.1 Bump version in `plugins/soleur/.claude-plugin/plugin.json` from 2.3.1 to 2.4.0
- [ ] 2.2 Add changelog entry in `plugins/soleur/CHANGELOG.md`
- [ ] 2.3 Verify `plugins/soleur/README.md` description and counts
- [ ] 2.4 Update root `README.md` version badge
- [ ] 2.5 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder

## Phase 3: Ship

- [ ] 3.1 Run code review on unstaged changes
- [ ] 3.2 Run `/soleur:compound` to capture learnings
- [ ] 3.3 Stage all artifacts (brainstorm, spec, plan, tasks, code)
- [ ] 3.4 Commit
- [ ] 3.5 Push and create PR referencing #76

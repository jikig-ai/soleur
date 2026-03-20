# Tasks: Ops Directory with Ops Advisor Agent

**Plan**: `knowledge-base/plans/2026-02-14-feat-ops-directory-advisory-agents-plan.md`
**Branch**: `feat-ops-directory`
**Issue**: #81

## Phase 1: Data Files

- [x] 1.1 Create `knowledge-base/ops/` directory
- [x] 1.2 Create `knowledge-base/ops/expenses.md` with frontmatter, Recurring + One-Time table headers, and example rows
- [x] 1.3 Create `knowledge-base/ops/domains.md` with frontmatter, table headers, and example row

## Phase 2: Agent

- [x] 2.1 Create `plugins/soleur/agents/operations/` directory
- [x] 2.2 Create `plugins/soleur/agents/operations/ops-advisor.md` with frontmatter (name, description with 2 example blocks, model: inherit) and sharp-edges prompt

## Phase 3: Version Bump

- [x] 3.1 Update `plugins/soleur/.claude-plugin/plugin.json` -- version 2.7.0 -> 2.8.0, agent count 24 -> 25
- [x] 3.2 Update `plugins/soleur/CHANGELOG.md` -- add `## [2.8.0]` entry
- [x] 3.3 Update `plugins/soleur/README.md` -- agent count and Operations section in agent table

## Phase 4: Validation

- [x] 4.1 Run markdownlint on all new files
- [x] 4.2 Phase 0 loader test -- verify ops-advisor is discovered as `soleur:operations:ops-advisor`
- [ ] 4.3 Run code review on unstaged changes
- [ ] 4.4 Run `/soleur:compound` to capture learnings

## Phase 5: Ship

- [ ] 5.1 Stage all artifacts (data files, agent, plans, specs, learnings)
- [ ] 5.2 Commit
- [ ] 5.3 Push and create PR referencing #81

# Tasks: ops-research Agent

**Plan:** `knowledge-base/plans/2026-02-16-feat-add-ops-research-agent-plan.md`
**Branch:** `feat-ops-research`

## Phase 1: Core Implementation

- [ ] 1.1 Create `plugins/soleur/agents/operations/ops-research.md` with YAML frontmatter (name, description with 2 examples, model: inherit) and agent body
- [ ] 1.2 Update `plugins/soleur/agents/operations/ops-advisor.md` -- replace Advisory Limitations with Research Delegation section

## Phase 2: Version Bump and Documentation

- [ ] 2.1 Bump `plugins/soleur/.claude-plugin/plugin.json` version (MINOR), update agent count
- [ ] 2.2 Update `plugins/soleur/CHANGELOG.md` with new version entry
- [ ] 2.3 Update `plugins/soleur/README.md` -- agent count, Operations table
- [ ] 2.4 Update root `README.md` version badge
- [ ] 2.5 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder

## Phase 3: Validation

- [ ] 3.1 Verify agent frontmatter fields (name, description, model)
- [ ] 3.2 Verify ops-advisor.md no longer contains contradictory "Cannot check live" limitations
- [ ] 3.3 Run code review on all changes
- [ ] 3.4 Run `/soleur:compound` to capture learnings

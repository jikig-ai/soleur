# Support Domain Tasks

**Issue:** #266
**Plan:** `knowledge-base/plans/2026-02-22-feat-add-support-domain-plan.md`

## Phase 1: Agent Files

- [ ] 1.1 Create `plugins/soleur/agents/support/` directory
- [ ] 1.2 Write `plugins/soleur/agents/support/cco.md` (domain leader, CLO template, 3-phase contract)
- [ ] 1.3 Write `plugins/soleur/agents/support/ticket-triage.md` (specialist, triage skill disambiguation)
- [ ] 1.4 `git mv plugins/soleur/agents/marketing/community-manager.md plugins/soleur/agents/support/community-manager.md`

## Phase 2: Cross-References

- [ ] 2.1 Update `agents/marketing/cmo.md` -- remove community-manager from delegation table AND description parenthetical, add Sharp Edges note
- [ ] 2.2 Update `skills/triage/SKILL.md` -- add disambiguation against ticket-triage agent
- [ ] 2.3 Add Support row to Domain Config table in `commands/soleur/brainstorm.md` Phase 0.5

## Phase 3: Docs Infrastructure

- [ ] 3.1 Update `docs/_data/agents.js` (DOMAIN_LABELS, DOMAIN_CSS_VARS, domainOrder)
- [ ] 3.2 Update `docs/css/style.css` (add `--cat-support: #9B59B6`)
- [ ] 3.3 Update `docs/_data/skills.js` (add `"community": "Workflow"` to SKILL_CATEGORIES, update comment count)

## Phase 4: Documentation and Version

- [ ] 4.1 Update `plugins/soleur/AGENTS.md` (directory tree, domain leader table)
- [ ] 4.2 Update root `AGENTS.md` (domain list in opening description)
- [ ] 4.3 Update `plugins/soleur/README.md` (agent counts 54->56, add Support section)
- [ ] 4.4 Update `plugins/soleur/.claude-plugin/plugin.json` (description: add "support", agent count 54->56)
- [ ] 4.5 Grep for hardcoded domain lists and update all matches
- [ ] 4.6 Version bump (MINOR) across plugin.json, CHANGELOG.md, README.md + root README badge + bug_report.yml

## Phase 5: Verification

- [ ] 5.1 Token budget check (under 2,500 words)
- [ ] 5.2 Build docs and verify Support renders on agents page
- [ ] 5.3 Agent compliance check (no example blocks in descriptions)

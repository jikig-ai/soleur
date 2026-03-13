# Tasks: UX Design Lead Agent + Pencil MCP Integration

**Issue:** #87
**Plan:** [2026-02-14-feat-ux-design-lead-plan.md](../../plans/2026-02-14-feat-ux-design-lead-plan.md)

## Phase 1: Agent + Housekeeping

- [ ] 1.1 Create `plugins/soleur/agents/design/ux-design-lead.md` (~50-60 lines)
  - [ ] 1.1.1 YAML frontmatter with 2 example blocks
  - [ ] 1.1.2 3-step workflow: Design Brief, Design, Deliver
  - [ ] 1.1.3 Graceful degradation when Pencil MCP unavailable
- [ ] 1.2 Add `.playwright-mcp/` to `.gitignore`
- [ ] 1.3 Stage `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`
- [ ] 1.4 Add ux-design-lead as handoff option in brainstorm Phase 4

## Phase 2: Version Bump + Documentation

- [ ] 2.1 Bump `plugins/soleur/.claude-plugin/plugin.json` to 2.8.0, update description (25 agents)
- [ ] 2.2 Add `## [2.8.0]` to `plugins/soleur/CHANGELOG.md`
- [ ] 2.3 Update `plugins/soleur/README.md` (count 25, Design section, Pencil dependency note)
- [ ] 2.4 Update `plugins/soleur/docs/pages/agents.html` with Design category
- [ ] 2.5 Verify root README badge, bug report template, HTML docs version strings

## Phase 3: Ship

- [ ] 3.1 Verify plugin loader discovers `agents/design/ux-design-lead.md`
- [ ] 3.2 Run code review on unstaged changes
- [ ] 3.3 Run `/soleur:compound`
- [ ] 3.4 Stage all artifacts, commit, push, create PR

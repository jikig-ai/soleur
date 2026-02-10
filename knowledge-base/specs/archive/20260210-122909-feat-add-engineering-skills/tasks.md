# Tasks: Add Engineering Skills

**Plan:** `knowledge-base/plans/2026-02-09-feat-add-engineering-skills-plan.md`
**Branch:** feat-add-engineering-skills

[Updated 2026-02-09 after plan review]

## Phase 1: Create 4 Agents

- [ ] 1.1 Create `plugins/soleur/agents/review/code-quality-analyst.md`
  - Merge code-smell-detector + refactoring-expert into one agent
  - Keep: 5-phase framework, severity model, smell-to-refactoring mappings, report structure
  - Drop: smell encyclopedia, 66 techniques catalog, bash commands
  - ~80 lines target (50-90 prompt body)
- [ ] 1.2 Create `plugins/soleur/agents/review/test-design-reviewer.md`
  - Reformat frontmatter from source
  - Keep: Farley Score formula, weighted rubric, grade bands, table output
  - ~70 lines target
- [ ] 1.3 Create `plugins/soleur/agents/review/legacy-code-expert.md`
  - Reformat frontmatter from source
  - Keep: Feathers' 24 techniques, seam taxonomy, 4-step approach
  - ~70 lines target
- [ ] 1.4 Create `plugins/soleur/agents/review/ddd-architect.md`
  - Reformat frontmatter, drop 1,447-line knowledge base
  - Keep: strategic-first mandate, context mapping, 5-step process, Mermaid output
  - ~70 lines target

## Phase 2: Create 2 Skills + Update Brainstorming

- [ ] 2.1 Create `plugins/soleur/skills/atdd-developer/SKILL.md`
  - Reformat to skill frontmatter (third-person description, triggers)
  - Keep: RED/GREEN/REFACTOR phases, permission gates, Task() delegation to clean-coder
  - ~70 lines target
- [ ] 2.2 Create `plugins/soleur/skills/user-story-writer/SKILL.md`
  - Reformat to skill frontmatter
  - Keep: INVEST criteria, Elephant Carpaccio, story template, prioritization
  - ~90 lines target
- [ ] 2.3 Update `plugins/soleur/skills/brainstorming/SKILL.md`
  - Add routing option for pure problem analysis mode (~5 lines)
  - When user requests problem analysis, stay in Phase 1, output problem-analysis.md

## Phase 3: Version Bump & Docs

- [ ] 3.1 Update `.claude-plugin/plugin.json` version to 1.9.0
- [ ] 3.2 Update `CHANGELOG.md` with [1.9.0] entry
- [ ] 3.3 Update `README.md` agent/skill counts and tables

## Phase 4: Validate

- [ ] 4.1 Run `bun test` and verify pass
- [ ] 4.2 Verify no naming conflicts with existing agents
- [ ] 4.3 Invoke code-quality-analyst and test-design-reviewer against a sample file
- [ ] 4.4 Spot-check YAML frontmatter format matches existing agents

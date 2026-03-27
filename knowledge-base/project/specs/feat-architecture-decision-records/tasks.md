# Tasks: Architecture as Code

## Phase 1: Skill + Knowledge Base Convention

- [x] 1.1 Create `knowledge-base/engineering/architecture/decisions/.gitkeep`
- [x] 1.2 Create `knowledge-base/engineering/architecture/diagrams/.gitkeep`
- [x] 1.3 Create `plugins/soleur/skills/architecture/SKILL.md` with sub-commands: `create`, `list`, `supersede`, `diagram`
- [x] 1.4 Create `plugins/soleur/skills/architecture/references/adr-template.md`
- [x] 1.5 Update `knowledge-base/project/constitution.md` — add architecture documentation convention under `## Architecture > ### Always`
- [x] 1.6 Update `knowledge-base/project/components/knowledge-base.md` — add `engineering/architecture/` to directory tree
- [x] 1.7 Extend CTO agent body (`plugins/soleur/agents/engineering/cto.md`) — add instruction to recommend `/soleur:architecture create` when architectural decisions detected
- [x] 1.8 Extend architecture-strategist body (`plugins/soleur/agents/engineering/review/architecture-strategist.md`) — add ADR coverage check as advisory finding
- [x] 1.9 Verify agent description word count unchanged: `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` (must stay at or below 2,500)

## Phase 2: Registration + Validation

- [x] 2.1 Add architecture skill entry to `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES`
- [x] 2.2 Update skill count and add category row in `plugins/soleur/README.md`
- [x] 2.3 Update skill count in root `README.md`
- [x] 2.4 Run `bun test plugins/soleur/test/components.test.ts` — all tests pass
- [ ] 2.5 Manual test: `/soleur:architecture create "Test decision"` — ADR-001 created correctly
- [ ] 2.6 Manual test: `/soleur:architecture list` — shows ADR-001
- [ ] 2.7 Manual test: `/soleur:architecture supersede 1 "Better decision"` — ADR-001 superseded, ADR-002 created
- [ ] 2.8 Manual test: `/soleur:architecture diagram system-context` — Mermaid diagram generated

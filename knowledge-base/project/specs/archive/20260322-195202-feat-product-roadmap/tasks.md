---
feature: product-roadmap
issue: 675
status: in-progress
created: 2026-03-22
---

# Tasks: Product Roadmap Skill

## Phase 1: Core Implementation

- [x] 1.1 Create `plugins/soleur/skills/product-roadmap/SKILL.md` with 7-phase workshop structure
- [x] 1.2 Implement Phase 0 (Setup & Discover): branch check, KB artifact reading, context summary
- [x] 1.3 Implement Phase 1 (Fill Gaps): targeted AskUserQuestion per missing artifact
- [x] 1.4 Implement Phase 2 (Research): optional agent spawning for competitive-intelligence/business-validator
- [x] 1.5 Implement Phase 3 (Workshop): 4-topic dialogue (themes, phases, priorities, criteria)
- [x] 1.6 Implement Phase 4 (Generate): roadmap.md template with frontmatter
- [x] 1.7 Implement Phase 5 (Operationalize): milestone creation and issue assignment via gh api
- [x] 1.8 Implement Phase 6 (Handoff): output summary, pipeline-safe language
- [x] 1.9 Add headless mode support (--headless flag bypass)

## Phase 2: Registration

- [x] 2.1 Add `"product-roadmap": "Review & Planning"` to `docs/_data/skills.js` SKILL_CATEGORIES
- [x] 2.2 Update skills.js count comment (58 → 59)
- [x] 2.3 Add row to `plugins/soleur/README.md` Review & Planning table
- [x] 2.4 Update root `README.md` skill count (58 → 59)
- [x] 2.5 Update `knowledge-base/marketing/brand-guide.md` skill count (58 → 59, 2 occurrences)

## Phase 3: Validation

- [x] 3.1 Run `bun test plugins/soleur/test/components.test.ts` — all 935 tests pass
- [ ] 3.2 Verify no remaining "58 skills" in active registration files
- [ ] 3.3 Commit and push

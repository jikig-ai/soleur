---
feature: product-roadmap
issue: 675
status: draft
created: 2026-03-22
---

# feat: Product Roadmap Skill (#675)

## Summary

Add a `/soleur:product-roadmap` skill — a CPO-grade interactive workshop for defining and operationalizing product roadmaps. Synthesizes knowledge-base context, fills gaps through targeted questions, and creates GitHub milestones.

Reframed from original issue scope (shell script for milestone status tables) based on domain leader assessments and user research.

## Implementation

### Files Created

| File | Purpose |
|------|---------|
| `plugins/soleur/skills/product-roadmap/SKILL.md` | The skill — single monolithic file |

### Files Modified

| File | Change |
|------|--------|
| `plugins/soleur/docs/_data/skills.js` | Add `"product-roadmap": "Review & Planning"` entry; update count 58 → 59 |
| `plugins/soleur/README.md` | Add row to Review & Planning table |
| `README.md` (root) | Update skill count 58 → 59 |
| `knowledge-base/marketing/brand-guide.md` | Update skill count 58 → 59 (2 occurrences) |

### SKILL.md Phases

1. **Phase 0: Setup & Discover** — Branch check, read 8 KB artifacts, present context summary
2. **Phase 1: Fill Gaps** — One AskUserQuestion per missing artifact
3. **Phase 2: Research (Optional)** — Spawn competitive-intelligence or business-validator if needed
4. **Phase 3: Workshop** — 4-topic dialogue: themes, phases, priorities, success criteria
5. **Phase 4: Generate** — Write `knowledge-base/product/roadmap.md`
6. **Phase 5: Operationalize** — Create GitHub milestones, assign issues
7. **Phase 6: Handoff** — Output summary, suggest next steps

### Key Design Decisions

- Single SKILL.md (no scripts, references, or sub-skills)
- AskUserQuestion relay (no interactive agent spawning)
- Headless mode via `--headless` flag
- Update mode: detects and preserves existing roadmap.md
- Milestones via REST API (idempotent)

## Acceptance Criteria

- [ ] SKILL.md follows brainstorm skill pattern (phases, arguments, AskUserQuestion)
- [ ] Description passes token budget test (`bun test plugins/soleur/test/components.test.ts`)
- [ ] Registered in skills.js under "Review & Planning"
- [ ] Skill counts updated in 4 locations (README, root README, brand-guide x2)
- [ ] Supports both interactive and headless modes
- [ ] Creates GitHub milestones idempotently
- [ ] Assigns issues to milestones via REST API

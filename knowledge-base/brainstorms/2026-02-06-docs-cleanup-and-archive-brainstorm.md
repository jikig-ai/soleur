# Brainstorm: Docs Cleanup and Knowledge-Base Migration

**Date:** 2026-02-06
**Status:** Ready for Planning

## What We're Building

A migration that consolidates documentation from scattered `/docs/` subdirectories into the new `/knowledge-base/` structure, cleans up the unused `/openspec/` directory, and documents learnings from the recently completed spec-driven workflow implementation (GitHub issues #3 and #4).

## Why This Approach

The spec-driven workflow foundation (completed Feb 6, 2026) established `knowledge-base/` as the canonical location for specs, learnings, and constitution. However, legacy content remains in `/docs/` and the unused `/openspec/` directory adds confusion. Consolidating everything into the knowledge-base structure:

1. **Single source of truth** - All project knowledge in one place
2. **Consistent conventions** - Uses the spec-driven workflow patterns we just built
3. **Reduces confusion** - No more wondering "is this in docs or knowledge-base?"
4. **Captures learnings** - Documents what we learned implementing issues #3 and #4

## Key Decisions

### 1. Plans Migration Strategy
- **Decision:** Convert current plans to spec format, archive old plans
- **Why:** The 2 current Feb 6 plans (foundation + command integration) represent completed features - they should become feature specs. The 5 archived Feb 5 plans are historical reference only.

### 2. External Specs Location
- **Decision:** `knowledge-base/specs/external/` for platform documentation
- **Why:** These describe target formats (Claude Code, Codex, OpenCode) - they're reference material, not feature specs, but still belong in the specs hierarchy.

### 3. OpenSpec Integration
- **Decision:** Extract rules into constitution.md, delete directory
- **Why:** The config.yaml has useful rules (proposal requirements, spec format, task sizing) that belong in the constitution. The empty specs/ and changes/ directories indicate we're not using the OpenSpec system.

### 4. Brainstorms Location
- **Decision:** New `knowledge-base/brainstorms/` directory
- **Why:** Brainstorms inform specs and should live alongside them in the knowledge-base, not separately in docs/.

### 5. Solutions Migration
- **Decision:** Move to `knowledge-base/learnings/`
- **Why:** Solutions are learnings - the plugin-versioning-requirements.md fits the learnings pattern.

## Migration Map

```
FROM                                          TO
────────────────────────────────────────────────────────────────────
docs/plans/2026-02-06-*-plan.md          →   knowledge-base/specs/feat-*/spec.md
docs/plans/archive/*.md                   →   knowledge-base/specs/archive/
docs/specs/*.md                           →   knowledge-base/specs/external/
docs/solutions/*.md                       →   knowledge-base/learnings/
docs/brainstorms/*.md                     →   knowledge-base/brainstorms/
openspec/config.yaml (rules)              →   knowledge-base/constitution.md (merged)
openspec/                                 →   (deleted)
docs/plans/, docs/specs/, etc.            →   (deleted after migration)
```

## New Directory Structure

```
knowledge-base/
├── constitution.md              (existing + openspec rules merged)
├── brainstorms/
│   └── 2026-02-05-unified-spec-workflow-brainstorm.md
├── learnings/
│   ├── plugin-versioning-requirements.md
│   └── 2026-02-06-spec-workflow-implementation.md  (NEW)
└── specs/
    ├── feat-spec-workflow-foundation/
    │   └── spec.md              (converted from plan)
    ├── feat-command-integration/
    │   └── spec.md              (converted from plan)
    ├── archive/
    │   └── (5 archived Feb 5 plans)
    └── external/
        ├── claude-code.md
        ├── codex.md
        └── opencode.md

docs/
├── pages/                       (keep - documentation site)
├── css/                         (keep - documentation site)
└── js/                          (keep - documentation site)
```

## OpenSpec Rules to Integrate

From `openspec/config.yaml`, these rules should be added to constitution.md:

**Proposal Rules:**
- Include rollback plan
- Identify affected teams
- Always include a "Non-goals" section

**Spec Rules:**
- Use Given/When/Then format for scenarios

**Design Rules:**
- Include sequence diagrams for complex flows

**Task Rules:**
- Break tasks into chunks of max 2 hours

## New Learning Document

Document learnings from implementing issues #3 and #4:

**File:** `knowledge-base/learnings/2026-02-06-spec-workflow-implementation.md`

**Key learnings to capture:**
1. Simplification approach: 8 domains → 3 domains worked well
2. Human-in-the-loop for v1 was the right call
3. Fall-back patterns ensure backward compatibility
4. Convention over configuration (branch names → spec directories)
5. Skill-based architecture promotes reuse

## Open Questions

None - all decisions made through brainstorming dialogue.

## Next Steps

1. Run `/soleur:plan` to create implementation tasks
2. Execute migration
3. Update any references in CLAUDE.md or other docs
4. Verify documentation site still works after cleanup

---
title: "feat: Add capability gap detection to domain leader agents"
type: feat
date: 2026-02-22
issue: "#234"
version_bump: PATCH
---

# feat: Add capability gap detection to domain leader agents

## Overview

Add a "Capability Gaps" subsection to each domain leader's Assess phase, telling them to identify missing agents/skills in their domain during brainstorm participation. The brainstorm command includes these gaps in the brainstorm document. The plan command's Phase 1.5b (functional-discovery) references this section to guide registry searches.

This is advisory only -- no installation during brainstorm. Prompt-only changes to 7 existing markdown files. No new files, agents, skills, or infrastructure. PATCH version bump because this modifies existing agent behavior without adding new discoverable components.

**Brainstorm:** [2026-02-22-domain-gap-detection-brainstorm.md](../brainstorms/2026-02-22-domain-gap-detection-brainstorm.md)
**Spec:** [spec.md](../specs/feat-domain-gap-detection/spec.md)

## Design Decisions

1. **Agent files only, not brainstorm Task prompts.** Gap detection instructions go in each domain leader's agent file (Assess phase). The agent file IS the prompt -- when the brainstorm command spawns `Task cto:`, the CTO's full instructions (including Capability Gaps) are loaded. No need to duplicate in Task prompts.

2. **Gaps feed into functional-discovery (Phase 1.5b) only, not agent-finder (Phase 1.5).** Agent-finder is stack-based (searches by "flutter", "rust"). Domain leader gaps are functional descriptions ("need a social media scheduling agent"). Functional-discovery already searches by feature description and is the correct target.

3. **Leaders omit the Capability Gaps section when they find no gaps.** Simpler than always including an empty section. The brainstorm document only gets a Capability Gaps section when at least one leader reported gaps.

### Heading-Level Contract

Per constitution line 119, define the heading contract for downstream parsing:

| Heading | Level | Location | Required |
|---------|-------|----------|----------|
| `#### Capability Gaps` | h4 | Domain leader assessment output | No (omit if no gaps) |
| `## Capability Gaps` | h2 | Brainstorm document | No (omit if no leader reported gaps) |

## Acceptance Criteria

- [ ] Each of the 5 domain leaders includes a `#### Capability Gaps` subsection in their Assess phase instructions
- [ ] Brainstorm command Phase 3.5 includes a `## Capability Gaps` section in the brainstorm document when domain leaders reported gaps
- [ ] Plan command Phase 1.5b passes brainstorm gap context to functional-discovery (not agent-finder)
- [ ] No Capability Gaps section appears when no domain leaders participate or no gaps are found
- [ ] Cumulative agent description word count stays under 2500 words

## Test Scenarios

- Given a brainstorm with CTO participating, when the CTO identifies a missing Flutter review agent, then the CTO's assessment includes a Capability Gaps section and the brainstorm document contains a consolidated Capability Gaps section
- Given a brainstorm with CMO and CTO participating, when both identify the same gap, then the brainstorm document deduplicates and lists it once
- Given a brainstorm with CMO and CTO participating, when CMO identifies a social media gap and CTO identifies a Flutter gap, then both appear in the brainstorm document's Capability Gaps section
- Given a brainstorm with COO participating, when no capability gaps exist, then the COO's assessment omits the Capability Gaps section and the brainstorm document has no Capability Gaps section
- Given a brainstorm without domain leaders, when the document is written, then no Capability Gaps section appears
- Given CTO participating, when CTO identifies a missing legal compliance agent, then the gap is attributed to the Legal domain (cross-domain attribution)
- Given a plan reading a brainstorm with Capability Gaps, when Phase 1.5b runs, then functional-discovery receives the gap descriptions as additional search context
- Given a plan reading a pre-feature brainstorm (no gaps section), when Phase 1.5b runs, then functional-discovery runs with default behavior

## MVP

### 1. Domain leader agent files (5 files, identical block)

Add a `#### Capability Gaps` subsection under the existing Assess section in each leader. Use one generic instruction, identical across all 5 agents -- the LLM already knows what gaps look like in its own domain:

```markdown
#### Capability Gaps

After completing the assessment, check whether any agents or skills are missing from the current domain that would be needed to execute the proposed work. If gaps exist, list each with what is missing, which domain it belongs to, and why it is needed. If no gaps exist, omit this section entirely.
```

**Insertion points:**

| File | Insert after |
|------|-------------|
| `plugins/soleur/agents/engineering/cto.md` | Line 18 (last Assess bullet) |
| `plugins/soleur/agents/marketing/cmo.md` | Line 20 (last Assess bullet) |
| `plugins/soleur/agents/operations/coo.md` | Line 18 (last Assess bullet) |
| `plugins/soleur/agents/product/cpo.md` | Line 21 (last Assess bullet) |
| `plugins/soleur/agents/legal/clo.md` | Line 18 (last Assess bullet) |

### 2. Brainstorm command template update (`plugins/soleur/commands/soleur/brainstorm.md`)

Update Phase 3.5 "Capture the Design" (line 377) to include the optional Capability Gaps section. Add after the existing key sections line:

```markdown
If domain leaders participated and reported capability gaps, include a "## Capability Gaps" section after "Open Questions" listing each gap with what is missing, which domain it belongs to, and why it is needed.
```

No separate consolidation step needed -- the LLM writing the brainstorm document naturally consolidates and deduplicates gap content from leader assessments already in context.

### 3. Plan command gap reference (`plugins/soleur/commands/soleur/plan.md`)

Update Phase 1.5b "Functional Overlap Check" Step 2 (line 170) to include brainstorm gap context. Add before the existing Task prompt:

```markdown
If the brainstorm document (loaded in Phase 0.5) contains a "## Capability Gaps" section, include the gap descriptions as additional search context in the functional-discovery Task prompt.
```

### 4. Spec fix

Update `knowledge-base/specs/feat-domain-gap-detection/spec.md` FR4 to reference only functional-discovery:

> FR4: `/plan` Phase 1.5b MUST read the brainstorm document's Capability Gaps section (if present) and use it to inform `functional-discovery` searches

(Remove "agent-finder" reference -- it is stack-based, not functional.)

## References

- Brainstorm command: `plugins/soleur/commands/soleur/brainstorm.md`
- Plan command: `plugins/soleur/commands/soleur/plan.md`
- Domain leaders: `plugins/soleur/agents/{engineering/cto,marketing/cmo,operations/coo,product/cpo,legal/clo}.md`
- Functional-discovery: `plugins/soleur/agents/engineering/discovery/functional-discovery.md`
- Constitution heading contract: `knowledge-base/overview/constitution.md` line 119
- Token budget learning: `knowledge-base/learnings/performance-issues/2026-02-20-agent-description-token-budget-optimization.md`

---
title: "fix: add gh issue state verification to domain leader task prompts"
type: fix
date: 2026-04-10
---

# fix: add gh issue state verification to domain leader task prompts

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 3 (Root Cause, Proposed Solution, Acceptance Criteria)
**Research sources:** codebase pattern analysis, institutional learnings, brainstorm/plan skill source review

### Key Improvements

1. Identified the deeper root cause: spawning instructions use anonymous Tasks instead of named agent Tasks, so agent files never load
2. Added alternative approach analysis (named agent spawning vs Task Prompt patching)
3. Expanded scope to include brainstorm SKILL.md and plan SKILL.md spawning instruction fixes

### New Considerations Discovered

- Learning from 2026-02-22 ("domain-leader-extension-simplification-pattern") previously assumed `Task cto:` loaded full agent instructions -- but brainstorm/plan skills never use that syntax
- Passive domain routing in AGENTS.md has the same gap -- uses Task Prompt text, not named agent spawning
- The `{desc}` substitution in Task Prompts may not contain issue references if the feature description was paraphrased during brainstorm

## Overview

Issue #1930 reports that domain leaders cite closed issues as open blockers during brainstorm assessments. The issue attributes this to missing `gh issue view` instructions in agent files. However, investigation reveals the instruction already exists in all 8 domain leader agent files (added in commit a558001a). The actual gap is in the **Task Prompts** used to spawn domain leaders AND in the spawning instructions that use anonymous Tasks instead of named agents.

## Problem Statement

When domain leaders are spawned via Task during brainstorm Phase 0.5, plan Phase 2.5 Domain Review Gate, or passive domain routing, they receive only the Task Prompt from `brainstorm-domain-config.md` -- not their full agent file instructions. The Task Prompts contain no instruction to verify GitHub issue state before making assertions.

### Root Cause Analysis

**Layer 1 -- Missing verification in Task Prompts:** Three code paths spawn domain leaders using Task Prompts that lack `gh issue view` verification:

1. **Brainstorm Phase 0.5** (`plugins/soleur/skills/brainstorm/SKILL.md` line 74): "spawn a Task using the Task Prompt from the table"
2. **Plan Phase 2.5** (`plugins/soleur/skills/plan/SKILL.md` line 204): "spawn the domain leader as a blocking Task using the Task Prompt from brainstorm-domain-config.md"
3. **Passive domain routing** (`AGENTS.md` line 74): "spawn the relevant domain leader as a background agent using the Task Prompt to delegate"

All three use the Task Prompt column from `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`. None of these Task Prompts include the `gh issue view` verification instruction.

**Layer 2 -- Anonymous Task spawning loses agent context:** The codebase pattern for spawning named agents is `Task agent-name(prompt)` (e.g., `Task spec-flow-analyzer(...)`, `Task kieran-rails-reviewer(...)`). This syntax loads the agent's full `.md` definition. However, the brainstorm and plan skills say "spawn a Task using the Task Prompt" without specifying the agent name from the Leader column. This means the domain leader's full instruction set (Assess phase, Sharp Edges, Capability Gaps) is never loaded -- the subagent only gets the raw Task Prompt text.

### Research Insight: Contradicted Assumption

Learning `2026-02-22-domain-leader-extension-simplification-pattern.md` states: "When brainstorm spawns `Task cto:`, the CTO's full instructions (including the new section) load automatically." However, the actual brainstorm SKILL.md never uses the `Task cto:` syntax -- it says "spawn a Task using the Task Prompt from the table." This means the 2026-02-22 learning's assumption about agent loading was incorrect, which explains why the Capability Gaps section added in that same change may also not load during brainstorm assessments.

### Evidence

During brainstorm #1062 (2026-04-10), the CTO cited three closed issues (#1060, #1044, #1076) as open blockers -- despite `cto.md` line 17 containing the verification instruction. The CTO was spawned via Task with only the Task Prompt: "Assess the technical implications of this feature: {desc}. Identify architecture risks, complexity concerns, and technical questions the user should consider during brainstorming. Output a brief structured assessment."

### Existing State (already fixed -- agent files)

All 8 domain leader agent files already contain the instruction (commit a558001a):

| Agent | File | Line | Status |
|-------|------|------|--------|
| CPO | `plugins/soleur/agents/product/cpo.md` | 19 | Present |
| CTO | `plugins/soleur/agents/engineering/cto.md` | 17 | Present |
| CFO | `plugins/soleur/agents/finance/cfo.md` | 16 | Present |
| CRO | `plugins/soleur/agents/sales/cro.md` | 16 | Present |
| CCO | `plugins/soleur/agents/support/cco.md` | 16 | Present (slight wording variation: "a specific") |
| COO | `plugins/soleur/agents/operations/coo.md` | 18 | Present |
| CLO | `plugins/soleur/agents/legal/clo.md` | 18 | Present |
| CMO | `plugins/soleur/agents/marketing/cmo.md` | 19 | Present |

### Actual Gap (not yet fixed -- task prompts)

All 8 Task Prompts in `brainstorm-domain-config.md` lack the verification instruction:

| Domain | Current Task Prompt (truncated) | Has gh verify? |
|--------|-------------------------------|----------------|
| Marketing | "Assess the marketing implications..." | No |
| Engineering | "Assess the technical implications..." | No |
| Operations | "Assess the operational implications..." | No |
| Product | "Assess the product implications..." | No |
| Legal | "Assess the legal implications..." | No |
| Sales | "Assess the sales implications..." | No |
| Finance | "Assess the financial implications..." | No |
| Support | "Assess the support implications..." | No |

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| A. Add `gh issue view` to Task Prompts only | Minimal change (1 file), directly addresses #1930 | Fixes only this symptom; other agent instructions (Assess phase, Sharp Edges, Capability Gaps) still missing from Task context | **Partial -- include as belt-and-suspenders** |
| B. Change spawning to use named agents (`Task cto(...)`) | Loads ALL agent instructions automatically, DRY, future-proof | Larger change (3 files: brainstorm SKILL.md, plan SKILL.md, AGENTS.md), changes spawning semantics | **Rejected for this PR -- separate issue** |
| C. Both A and B | Maximum coverage | Redundant -- if B works, A is unnecessary | Over-engineered |

**Decision:** Approach A for this PR. The named-agent spawning change (Approach B) is architecturally better but changes the spawning semantics for all domain leader interactions. It should be tracked as a separate issue for proper testing. Adding `gh issue view` to Task Prompts directly fixes #1930 with minimal risk.

## Proposed Solution

Add the `gh issue view` verification instruction to each Task Prompt in `brainstorm-domain-config.md`. This is a single-file change affecting one Markdown table.

### Implementation

Edit `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` to append the verification instruction to each Task Prompt cell:

**Before (example -- Engineering):**

```text
"Assess the technical implications of this feature: {desc}. Identify architecture
risks, complexity concerns, and technical questions the user should consider during
brainstorming. Output a brief structured assessment."
```

**After:**

```text
"Assess the technical implications of this feature: {desc}. If {desc} references
a GitHub issue (#N), verify its state via `gh issue view <N> --json state` before
asserting whether work is pending or complete. Identify architecture risks,
complexity concerns, and technical questions the user should consider during
brainstorming. Output a brief structured assessment."
```

Apply the same pattern to all 8 Task Prompts, inserting the verification sentence immediately after the `{desc}` substitution and before the domain-specific assessment instructions.

### Implementation Edge Cases

- **`{desc}` may not contain raw issue numbers.** The feature description substituted into `{desc}` may have been paraphrased during brainstorm Phase 0 (e.g., "the authentication feature from the last sprint" instead of "#1060"). The verification instruction uses "If {desc} references a GitHub issue" which relies on the model detecting issue references in the substituted text. This is acceptable -- the AGENTS.md hard rule ("Before asserting GitHub issue status, verify via `gh issue view`") provides the fallback for cases where the Task Prompt instruction is not triggered.

- **Markdown table cell formatting.** The Task Prompt cells in `brainstorm-domain-config.md` are single-line pipe-delimited Markdown table cells. Adding a sentence increases cell width. Run `npx markdownlint-cli2 --fix` after editing to ensure table alignment is valid.

### Minor Consistency Fix

Normalize CCO agent file wording from "a specific GitHub issue" to "a GitHub issue" to match all other agents:

- File: `plugins/soleur/agents/support/cco.md` line 16
- Before: `If the task references a specific GitHub issue`
- After: `If the task references a GitHub issue`

## Acceptance Criteria

- [ ] All 8 Task Prompts in `brainstorm-domain-config.md` include `gh issue view` verification instruction
- [ ] Verification instruction follows the exact pattern from commit a558001a
- [ ] CCO agent file wording normalized to match other agents
- [ ] No other files modified
- [ ] `npx markdownlint-cli2 --fix` passes on all changed `.md` files

## Test Scenarios

- Given a brainstorm referencing a closed GitHub issue, when the CTO is spawned via Task, then the CTO Task Prompt includes the `gh issue view` instruction
- Given the brainstorm-domain-config.md file, when all 8 Task Prompts are inspected, then each contains "verify its state via `gh issue view <N> --json state`"
- Given the CCO agent file, when line 16 is inspected, then it reads "a GitHub issue" (not "a specific GitHub issue")
- Given the plan SKILL.md Phase 2.5, when it spawns domain leaders, then the Task Prompt from the table already contains the verification instruction (no plan SKILL.md changes needed -- it reads from the same config file)
- Given a grep for `gh issue view` across `brainstorm-domain-config.md`, then exactly 8 matches are returned (one per domain row)

## Context

### Files to modify

1. `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` -- add verification to all 8 Task Prompts
2. `plugins/soleur/agents/support/cco.md` -- normalize wording (optional consistency fix)

### Files NOT modified (and why)

- `plugins/soleur/skills/brainstorm/SKILL.md` -- spawning instruction unchanged (Approach B deferred)
- `plugins/soleur/skills/plan/SKILL.md` -- reads from same config file, no changes needed
- `AGENTS.md` -- passive domain routing reads from same config file, no changes needed
- All 8 domain leader agent `.md` files (except CCO) -- already have the instruction

### Related issues

- #1058: Original fix that added `gh issue view` to agent files (commit a558001a)
- #1062: Brainstorm where CTO cited closed issues as open (exposed this gap)
- #1930: This issue

### Deferred work

- Named agent spawning for domain leaders (Approach B): architecturally better fix that loads full agent definitions during brainstorm/plan domain assessments. Tracked separately to avoid scope creep.

## References

- Commit a558001a: Original domain leader verification fix
- Learning: `knowledge-base/project/learnings/workflow-issues/domain-leader-false-status-assertions-20260323.md`
- Learning: `knowledge-base/project/learnings/2026-02-22-domain-leader-extension-simplification-pattern.md` (contains contradicted assumption about agent loading)
- Learning: `knowledge-base/project/learnings/2026-02-21-domain-leader-pattern-and-llm-detection.md` (LLM semantic assessment pattern)
- AGENTS.md hard rule: "Before asserting GitHub issue status, verify via `gh issue view <N> --json state`"

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change affecting agent spawning prompts only.

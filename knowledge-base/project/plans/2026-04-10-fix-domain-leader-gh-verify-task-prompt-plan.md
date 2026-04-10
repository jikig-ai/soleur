---
title: "fix: add gh issue state verification to domain leader task prompts"
type: fix
date: 2026-04-10
---

# fix: add gh issue state verification to domain leader task prompts

## Overview

Issue #1930 reports that domain leaders cite closed issues as open blockers during brainstorm assessments. The issue attributes this to missing `gh issue view` instructions in agent files. However, investigation reveals the instruction already exists in all 8 domain leader agent files (added in commit a558001a). The actual gap is in the **Task Prompts** used to spawn domain leaders.

## Problem Statement

When domain leaders are spawned via Task during brainstorm Phase 0.5, plan Phase 2.5 Domain Review Gate, or passive domain routing, they receive only the Task Prompt from `brainstorm-domain-config.md` -- not their full agent file instructions. The Task Prompts contain no instruction to verify GitHub issue state before making assertions.

### Root Cause Analysis

Three code paths spawn domain leaders using Task Prompts that lack `gh issue view` verification:

1. **Brainstorm Phase 0.5** (`plugins/soleur/skills/brainstorm/SKILL.md` line 74): "spawn a Task using the Task Prompt from the table"
2. **Plan Phase 2.5** (`plugins/soleur/skills/plan/SKILL.md` line 204): "spawn the domain leader as a blocking Task using the Task Prompt from brainstorm-domain-config.md"
3. **Passive domain routing** (`AGENTS.md` line 74): "spawn the relevant domain leader as a background agent using the Task Prompt to delegate"

All three use the Task Prompt column from `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`. None of these Task Prompts include the `gh issue view` verification instruction.

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

## Proposed Solution

Add the `gh issue view` verification instruction to each Task Prompt in `brainstorm-domain-config.md`. This is a single-file change affecting one Markdown table.

### Implementation

Edit `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` to append the verification instruction to each Task Prompt cell:

**Before (example -- Engineering):**

```
"Assess the technical implications of this feature: {desc}. Identify architecture risks, complexity concerns, and technical questions the user should consider during brainstorming. Output a brief structured assessment."
```

**After:**

```
"Assess the technical implications of this feature: {desc}. If {desc} references a GitHub issue (#N), verify its state via `gh issue view <N> --json state` before asserting whether work is pending or complete. Identify architecture risks, complexity concerns, and technical questions the user should consider during brainstorming. Output a brief structured assessment."
```

Apply the same pattern to all 8 Task Prompts, inserting the verification sentence immediately after the `{desc}` substitution and before the domain-specific assessment instructions.

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

## Test Scenarios

- Given a brainstorm referencing a closed GitHub issue, when the CTO is spawned via Task, then the CTO Task Prompt includes the `gh issue view` instruction
- Given the brainstorm-domain-config.md file, when all 8 Task Prompts are inspected, then each contains "verify its state via `gh issue view <N> --json state`"
- Given the CCO agent file, when line 16 is inspected, then it reads "a GitHub issue" (not "a specific GitHub issue")

## Context

### Files to modify

1. `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` -- add verification to all 8 Task Prompts
2. `plugins/soleur/agents/support/cco.md` -- normalize wording (optional consistency fix)

### Related issues

- #1058: Original fix that added `gh issue view` to agent files (commit a558001a)
- #1062: Brainstorm where CTO cited closed issues as open (exposed this gap)
- #1930: This issue

## References

- Commit a558001a: Original domain leader verification fix
- Learning: `knowledge-base/project/learnings/workflow-issues/domain-leader-false-status-assertions-20260323.md`
- AGENTS.md hard rule: "Before asserting GitHub issue status, verify via `gh issue view <N> --json state`"

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change affecting agent spawning prompts only.

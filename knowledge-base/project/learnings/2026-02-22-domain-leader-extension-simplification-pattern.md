---
title: Domain Leader Extension Simplification Pattern
date: 2026-02-22
category: agent-design
tags: [implementation-patterns, agents, commands]
---

# Learning: Domain Leader Extension Simplification Pattern

## Problem

When extending domain leader agents with new behavior (adding a Capability Gaps section to all 5 leaders), the initial plan specified 5 domain-specific instruction variants with custom examples per leader, 5 duplicate Task prompt updates, an explicit consolidation step, and a 4-column table format -- totaling 13 tasks. This was over-engineered for what amounts to adding one generic paragraph to 5 files.

## Solution

Plan review by 3 specialized reviewers (DHH, Kieran, Code Simplicity) consistently converged on the same simplifications:

1. **One generic instruction, not 5 domain-specific variants.** The LLM already knows what gaps look like in its own domain. A CTO does not need to be told to consider "review agents for unfamiliar stacks" -- it already knows. The generic version: "check whether any agents or skills are missing from the current domain" works identically across all 5 leaders.

2. **Agent file only, not Task prompt duplication.** ~~The agent file IS the prompt. When brainstorm spawns `Task cto:`, the CTO's full instructions (including the new section) load automatically.~~ **CORRECTION (2026-04-10):** This assumption was incorrect. The brainstorm SKILL.md uses anonymous Tasks ("spawn a Task using the Task Prompt from the table"), not named agent Tasks (`Task cto:`). Agent file instructions do NOT load during brainstorm/plan spawning. See #1930 and learning `2026-04-10-anonymous-task-spawning-loses-agent-context.md`. Task Prompt patching IS needed as belt-and-suspenders until Approach B (#1937) switches to named agent spawning.

3. **No explicit consolidation step.** The brainstorm command writes the document by synthesizing all leader outputs already in context. It naturally consolidates and deduplicates without being told to "1. Collect 2. Deduplicate 3. Include."

4. **Bullet list, not table format.** A 4-column table (Gap, Domain, Identified By, Rationale) for content an LLM reads once and passes as context adds no value over a simple bullet list.

Result: 13 tasks reduced to 7. 5 domain-specific blocks reduced to 1 generic block. The entire implementation was 27 lines of insertions across 7 files.

## Key Insight

When extending LLM-executed agents with parallel behavior (same capability added to N sibling agents), use one generic instruction rather than N domain-customized variants. The LLM's role-specific knowledge fills in the domain details automatically. Customization is only needed when the behavior genuinely differs across domains -- not when only the examples differ.

Secondary insight: SpecFlow analysis caught a misreference (plan said "agent-finder" for functional gap descriptions, but agent-finder is stack-based -- functional-discovery was the correct target). This validates running SpecFlow even for prompt-only changes.

## Tags

category: implementation-patterns
module: agents, commands

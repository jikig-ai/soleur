---
title: Anonymous Task Spawning Loses Agent Context
date: 2026-04-10
category: workflow-issues
tags: [agents, brainstorm, spawning, task-prompts]
---

# Learning: Anonymous Task Spawning Loses Agent Context

## Problem

During brainstorm #1062, the CTO cited three closed GitHub issues (#1060, #1044, #1076) as open blockers. All three had been closed 3-13 days prior. The CTO agent file (`cto.md` line 17) already contained the `gh issue view` verification instruction (added in commit a558001a), yet the instruction was never executed.

Investigation revealed two root cause layers:

1. **Task Prompts lack verification.** The brainstorm, plan, and passive domain routing code paths spawn domain leaders using Task Prompts from `brainstorm-domain-config.md`. These prompts contained no `gh issue view` instruction.

2. **Anonymous Task spawning loses agent file context.** The brainstorm SKILL.md says "spawn a Task using the Task Prompt from the table" — this creates an anonymous Task that only receives the raw prompt text. Named agent Tasks (`Task cto(prompt)`) would load the agent's full `.md` definition, but that syntax was never used.

A prior learning (2026-02-22, "domain-leader-extension-simplification-pattern") incorrectly assumed "When brainstorm spawns `Task cto:`, the CTO's full instructions load automatically." The brainstorm SKILL.md never used that syntax — the assumption was never validated against the actual spawning code.

## Solution

Approach A (this PR): Added `gh issue view` verification to all 8 Task Prompts in `brainstorm-domain-config.md`. This directly fixes the symptom by ensuring the verification instruction reaches the spawned subagent regardless of spawning method.

Approach B (deferred to #1937): Switch to named agent Tasks (`Task cto(...)`) so full agent definitions load automatically. Architecturally better but changes spawning semantics.

## Key Insight

When fixing agent behavior, verify WHERE the agent's instructions actually come from at runtime — not where they exist on disk. Agent files contain instructions, but if the spawning path uses anonymous Tasks, those instructions never load. The fix must target the actual prompt text the subagent receives, not the agent definition file.

Corollary: assumptions about how agents are spawned must be validated against the spawning code (SKILL.md), not inferred from how they "should" work.

## Session Errors

1. **Step 0a script path error** — `bash ./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` failed because the script lives at `./plugins/soleur/scripts/setup-ralph-loop.sh`. **Prevention:** The one-shot SKILL.md should reference the correct path, or the script should be discoverable via a standard location convention.

## Tags

category: workflow-issues
module: agents, brainstorm, skills

---
category: architecture-decisions
module: plugins/soleur/commands
tags: [workflow-patterns, command-routing, intent-classification, plugin-loader, refactoring]
symptoms: [over-engineered initial design, command-to-skill migration risk analysis, reduced intent scope after plan review]
date: 2026-02-22
---

# Learning: Simplify Workflow - Command Routing Architecture

## Problem

The Soleur plugin has 6 fragmented workflow commands (`brainstorm`, `plan`, `work`, `review`, `ship`, `compound`) that accomplish similar goals but require users to memorize when to use each one. The initial design proposal aimed to unify them under a `/soleur:go` command with intent classification and resume detection, moving 6 commands to skills for a flat `/soleur` namespace.

## Solution

Plan review by 3 specialized reviewers (Architecture, Implementation, Plugin Mechanics) identified critical risks with the command-to-skill migration strategy:

1. **Plugin loader doesn't support bare namespace:** The plugin loader discovers skills at `skills/<name>/SKILL.md` only. Skills cannot be in subdirectories. Moving commands to skills would force a 7-agent system with flat names like `/soleur:brainstorm-skill`, defeating the goal.

2. **Cross-references require refactoring:** Commands directly reference other commands (e.g., `ship` calls `review`, `compound` calls `brainstorm`). Moving to skills breaks this one-shot pipeline. Over 53+ cross-references exist across the codebase.

3. **Resume detection was over-engineered:** The initial plan included a 4-step resume detection algorithm to identify incomplete workflows. Plan review revealed this adds complexity without proportional user value. Users explicitly ask for specific actions; implicit state machine reasoning is not necessary.

4. **Intent scope reduced from 7 to 3:** Initial scope proposed 7 intents (brainstorm, plan, work, review, ship, compound, meta). Review consensus reduced to 3:
   - **start** → brainstorm
   - **continue** → compound
   - **finalize** → ship

5. **Single-phase implementation, not 4 phases:** Rather than Phase 0 (Resume Detection), Phase 1 (Intent Classification), Phase 2 (State Validation), Phase 3 (Dispatch), the final design is one 57-line `go.md` command that routes to existing commands based on simple intent keywords.

## Final Design

**2 files changed:**

- `commands/soleur/go.md` (57 lines): Router command that classifies user input into one of 3 intents and dispatches to existing commands
- `commands/soleur/help.md` (updated): Added `/soleur:go` to command listing

**No skills created. No command migration.** The `/soleur:go` command wraps existing commands; it does not replace them.

## Key Insight

**Over-engineering risk increases with architectural decisions.** When a design proposes changing the organizational structure of the codebase (commands → skills, single namespace → multi-level namespace), the cost of being wrong is high. Plan review by multiple specialized perspectives catches these risks early and surfaces simpler alternatives that achieve the same user value with less refactoring.

**The plugin loader constraints are non-negotiable guardrails.** Designs that assume loader flexibility (bare `/soleur` namespace, nested skills) fail at implementation. Always validate design assumptions against the actual loader behavior before committing to architectural changes.

**Resume detection is not solving a real problem.** Users explicitly describe their intent ("I need to review this PR", "I'm ready to ship"). Inferring intent from implicit workflow state adds complexity without reducing friction. Simplicity wins.

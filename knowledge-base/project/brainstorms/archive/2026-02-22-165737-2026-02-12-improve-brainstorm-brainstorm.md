---
date: 2026-02-12
topic: improve-brainstorm
---

# Improve the Brainstorm Command

## What We're Building

Enhancing `/soleur:brainstorm` with parallel research agents and an OpenSpec-inspired conversational philosophy. Currently the brainstorm command is the least parallelized Soleur command (1 agent vs. 10+ in review, 40+ in deepen-plan). We're adding a multi-agent research layer and shifting the brainstorming skill's tone from structured/prescriptive to curious/adaptive.

## Why This Approach

We evaluated three approaches:

- **A: Parallel agents + philosophy update** -- Good impact but misses gap detection.
- **B: Command-only parallel agents** -- Quick win but misses the conversational quality lift.
- **C: Full research + spec-flow analysis (chosen)** -- Maximum impact. Parallel research agents gather context before dialogue, OpenSpec-inspired philosophy improves question quality, and spec-flow-analyzer catches gaps before the brainstorm doc is finalized.

Approach C was chosen because it addresses both the *depth* problem (not enough research context) and the *quality* problem (prescriptive question style) while adding gap detection.

We moved `framework-docs-researcher` to the plan phase only to avoid overlap -- `/soleur:plan` already runs it conditionally.

## Key Decisions

- **3 parallel research agents in Phase 1**: `repo-research-analyst`, `learnings-researcher`, `best-practices-researcher` -- all run before asking user any questions, so the brainstorm starts with informed context.
- **framework-docs-researcher stays in plan phase only**: Avoids duplication since plan already runs it. Best-practices-researcher covers enough external context for brainstorming.
- **spec-flow-analyzer after approach selection**: Runs after Phase 2 (user picks an approach) to validate completeness and surface gaps before writing the brainstorm doc.
- **OpenSpec conversational philosophy adopted**: "Curious, not prescriptive" stance, ASCII diagrams for visual thinking, adaptive thread-following, "explore not prescribe" guardrail. Applied to the brainstorming SKILL.md.
- **DDD architect excluded**: Domain modeling analysis belongs in the planning phase, not brainstorming.
- **Agents run before dialogue, not after**: Gathering context first means the brainstorm asks sharper, more informed questions from the start.

## Files to Modify

1. `plugins/soleur/commands/soleur/brainstorm.md` -- Add parallel agent invocation in Phase 1, add spec-flow-analyzer in Phase 2.5 (new), update phase structure.
2. `plugins/soleur/skills/brainstorming/SKILL.md` -- Adopt OpenSpec-inspired conversational philosophy: curious tone, ASCII diagrams, adaptive threading, explore-not-prescribe guardrail.

## Resolved Questions

- **Research results presentation**: Show a brief 3-5 line context summary to the user before starting dialogue. Transparency helps the user steer the conversation.
- **Spec-flow-analyzer**: Always run, even for simple features. Consistency matters and the overhead is minimal.

## Next Steps

> `/soleur:plan` for implementation details

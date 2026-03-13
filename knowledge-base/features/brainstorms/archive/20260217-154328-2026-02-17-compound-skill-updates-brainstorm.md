# Brainstorm: Compound Should Update Skills and Agents with Learnings

**Date:** 2026-02-17
**Issue:** #104
**Status:** Complete

## What We're Building

Extending `/soleur:compound` to feed captured learnings back into the skill and agent definitions that caused the mistakes. Currently, compound captures learnings and optionally promotes rules to the constitution, but the actual skill/agent instructions never improve. This creates two problems: (1) skills/agents repeat the same mistakes because learnings don't reach their instructions, and (2) the constitution accumulates domain-specific rules that belong in individual definitions.

## Why This Approach

**Approach A: Compound Enhancement with Sync Integration** was selected over two alternatives:

- **Over Agent-Powered Analysis (B):** Spawning a dedicated agent to read all definitions is slow and token-heavy. Most cases are obvious -- the skill that just ran is the one that needs the fix. Session context is sufficient for real-time routing.
- **Over Tagging-Based Deferred Routing (C):** Adding a `target_skill` frontmatter tag defers the fix and adds friction. The learning should flow back immediately during the compound session, not wait for a separate processing step.

The chosen approach works at two layers:
1. **Compound (real-time):** Auto-detect from session context which skill/agent was active, propose a one-line bullet edit, confirm with user.
2. **Sync (periodic):** Broad scan across all definitions to apply accumulated learnings that cross skill boundaries.

## Key Decisions

1. **Auto-detect + confirm routing:** Compound analyzes the learning against session context (which skills/commands/agents were invoked in the conversation). It proposes a targeted edit and the user accepts, skips, or edits. No fully automatic changes.

2. **Surgical one-line edits:** Append a bullet to the relevant existing section in SKILL.md or agent.md rather than creating a dedicated "Learned Behaviors" section or reference file. Keeps instructions cohesive -- the gotcha lives next to the related instructions.

3. **Constitution cross-check integrated into compound:** After routing a learning to a skill/agent, compound checks if the constitution has a related rule that's now redundant and proposes removal. This provides ongoing self-cleaning rather than periodic audits.

4. **Session context for compound, broad scan for sync:** Compound only considers skills/agents active in the current session (fast, reliable). The `/soleur:sync` command handles cross-pollination with a broader scan across all definitions (thorough, periodic).

5. **Sharp edges only principle applies:** The Accept/Skip/Edit gate ensures only genuinely useful gotchas make it into definitions. General knowledge already in training data should be skipped.

## Open Questions

- How to reliably detect which skill/agent was active from conversation history (look for skill invocation markers, command names, agent task launches?)
- Should there be a maximum number of learned bullets per skill section before suggesting a refactor/consolidation?
- How does sync determine that a learning has already been applied to a definition (to avoid duplicate proposals)?

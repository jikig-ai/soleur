# Passive Domain Leader Routing for Mid-Conversation Signals

**Date:** 2026-03-12
**Issue:** #544
**Status:** Decided
**Branch:** feat-passive-domain-routing

## What We're Building

A behavioral rule in AGENTS.md that enables always-on, passive domain leader routing. When the user mentions domain-relevant information mid-conversation (expenses, legal obligations, marketing signals, etc.), the agent auto-routes to the relevant domain leader as a background task without interrupting the primary workflow.

This also includes removing the existing `AskUserQuestion` confirmation gate from brainstorm Phase 0.5, making domain leader routing auto-fire consistently across all contexts.

## Why This Approach

The project already has:
- 8 domain leaders with standardized 3-phase contracts (Assess, Recommend/Delegate, Sharp Edges)
- A domain config table (`brainstorm-domain-config.md`) mapping domains to assessment questions and task prompts
- Proven LLM semantic assessment that outperforms keyword matching (documented in learnings from v1→v2 evolution)
- AGENTS.md loaded every turn, making behavioral rules always-on

Adding a lean behavioral rule (3-4 lines) to AGENTS.md is the minimal change that achieves always-on passive routing. It leverages the existing domain config infrastructure rather than building new detection mechanisms.

**Why not hooks?** The project already moved from keyword matching to LLM semantic assessment for domain routing. A hook-based approach would regress to keyword detection. The LLM is better at understanding intent than substring matching.

**Why not skill-embedded?** The routing should fire on every user message, not just during active workflows. AGENTS.md is the only file guaranteed to be loaded every turn.

## Key Decisions

1. **Location: AGENTS.md** — A short behavioral rule (3-4 lines) always loaded. Points to the existing domain config table for domain→leader mapping. Complex routing logic stays in the reference file, not AGENTS.md.

2. **Detection: LLM semantic assessment** — No keyword matching. The LLM reads the user's message and assesses domain relevance using the existing assessment questions from `brainstorm-domain-config.md`. Consistent with the proven v2 approach.

3. **Confirmation: Auto-route, no gate** — Domain leaders are spawned automatically when a signal is detected. No `AskUserQuestion` confirmation step. Applies to both the new passive routing AND the existing brainstorm Phase 0.5 routing (removing the confirmation gate there for consistency).

4. **Execution: Background agent, inline summary** — Domain leaders spawn as background Task agents. The primary workflow continues uninterrupted. When the background agent completes, its result is woven as a brief inline summary into the next response.

5. **Scope: Every user message** — Always-on, not limited to active workflows. If the user mentions an expense in casual conversation, route it.

6. **Config: Reuse existing domain config table** — No new configuration files. The existing `brainstorm-domain-config.md` provides the domain→leader mapping and task prompts.

## Open Questions

- **False positive rate:** Without a confirmation gate, how often will the LLM misidentify signals? May need a calibration period.
- **Multiple domains in one message:** If a user's message triggers multiple domains, should all fire in parallel or should there be a priority ordering?
- **Background agent visibility:** How should the user be notified that a background domain leader is running? A brief inline note ("Routing to COO...") or silent until results arrive?

## Scope of Changes

1. **AGENTS.md** — Add 3-4 line passive routing rule under a new section
2. **brainstorm SKILL.md** — Remove `AskUserQuestion` confirmation gate from Phase 0.5 domain leader assessment
3. **brainstorm-domain-config.md** — No changes needed (reused as-is)

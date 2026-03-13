---
title: Passive Domain Routing -- Always-On Pattern
date: 2026-03-12
category: implementation-patterns
tags: [agents, domain-routing, passive-routing, AGENTS.md, behavioral-rules]
---

# Learning: Passive Domain Routing -- Always-On Pattern

## Problem

Domain leader routing only fired during brainstorm Phase 0.5 — a one-time upfront gate at task initiation. When users mentioned domain-relevant information mid-conversation (expenses, legal obligations, marketing signals), no routing occurred because the conversation was past the brainstorm phase.

## Solution

Extended domain routing from brainstorm-only to always-on via three changes:

1. **AGENTS.md behavioral rule** (2 bullets): Instructs the agent to assess every user message for domain relevance using the existing domain config table, and spawn the relevant domain leader as a background agent (`run_in_background: true`). Includes qualifying language to prevent false positives on trivial messages.

2. **Brainstorm Phase 0.5 auto-fire**: Removed the AskUserQuestion confirmation gate. Domain leaders now auto-fire for relevant domains without asking permission. Workshops (brand-architect, business-validator) remain explicitly user-invoked.

3. **Domain config header update**: Changed from "use AskUserQuestion tool" to "spawn the domain leader as a Task agent using the Task Prompt column."

### What We Dropped (YAGNI)

Plan review caught several proposed mechanisms that weren't needed:
- **Per-message cap** (2 leaders max): The global 5-agent cap in the constitution is sufficient.
- **Deduplication clause**: The LLM can see what it already spawned in conversational context.
- **Return contract format**: Existing "Output a brief structured assessment" instruction is sufficient.
- **Hook-based keyword detection**: Would regress to pattern matching the project already abandoned.

## Key Insight

When a behavioral rule lives in AGENTS.md (loaded every turn), it becomes always-on without any infrastructure. The existing domain config table + LLM semantic assessment + `run_in_background: true` was all the machinery needed. The simplest approach — a 2-bullet behavioral rule pointing to an existing config file — covered the feature without new files, new hooks, or new mechanisms.

The confirmation gate removal was safe because: (1) the user reviews the brainstorm output anyway (redundant validation), and (2) after months of use, the user confirmed the gate added friction without catching errors.

## Tags

category: implementation-patterns
module: agents, AGENTS.md, brainstorm
symptoms: domain signals missed mid-conversation, routing only at task initiation

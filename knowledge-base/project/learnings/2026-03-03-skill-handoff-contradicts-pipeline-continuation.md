---
title: 'Skill Handoff "Return Control" Contradicts Pipeline Continuation'
date: 2026-03-03
category: plugin-architecture
tags: [logic-errors, plugins/soleur/skills/work, plugins/soleur/skills/one-shot]
---

# Learning: Skill Handoff "Return Control" Contradicts Pipeline Continuation

## Problem

When one-shot invokes `/soleur:work` via the Skill tool, the work skill's Phase 4 handoff said "Return control immediately" for one-shot mode. But after a skill expansion, there is no separate "orchestrator" — it's the same model in the same turn. The model interpreted "return immediately" as "end the turn", causing the one-shot pipeline to stall after implementation instead of continuing to steps 4-10 (review, compound, ship).

Meanwhile, the one-shot SKILL.md explicitly said "After work completes, continue to step 4 — do not end your turn." These two instructions contradicted each other, and the work skill's instruction won because it was the most recently expanded context.

## Solution

Changed work skill Phase 4 handoff from:

> Return control immediately. Do not invoke ship, review, or compound — the orchestrator handles the remaining steps. Output "Implementation complete." then proceed to the next step in the orchestrator's sequence.

To:

> Do not invoke ship, review, or compound — the orchestrator handles the remaining steps. Output "Implementation complete." and then **continue executing the next instruction in the current conversation** (do NOT end your turn — the one-shot pipeline has more steps after this skill).

The key fix: removed "Return control immediately" (which the model interprets as "stop") and replaced with an explicit instruction to continue with whatever other instructions are active in the conversation.

## Key Insight

When a skill is invoked mid-pipeline, its expanded prompt becomes the model's primary instruction set. If that skill says "return/stop/done", the model will end its turn — even if the calling pipeline explicitly says "continue." **Skills that participate in pipelines must never use stop-like language in their handoff.** Instead, they should say "do not invoke X/Y/Z yourself" (scope boundary) without implying "end your turn" (execution boundary).

## Session Errors

1. Worktree manager path failure — relative path from worktree CWD failed; fixed with absolute path
2. One-shot pipeline stall — work skill's "Return control immediately" ended the turn prematurely

## Tags

category: logic-errors
module: plugins/soleur/skills/work, plugins/soleur/skills/one-shot

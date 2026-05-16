---
name: brainstorm-audit-vs-guidance-direction-reframe
description: When a brainstorm issue cites an external pattern (e.g., karpathy-check, principles-as-rules), separate the audit direction (apply rules as a pre-merge checker) from the guidance direction (tell the LLM to follow them). They are orthogonal — one may be already covered and the other may have a partial gap that does NOT justify a new component. Always grep the existing review/* agent inventory before sizing.
type: best-practice
tags: [brainstorm, scoping, yagni, prior-art, agents-md-tier-gate, review-agents]
category: best-practices
module: brainstorm
---

# Audit Direction vs. Guidance Direction in Pattern-Import Brainstorms

## Problem

Issue #2727 imported the `alirezarezvani/claude-skills/commands/karpathy-check.md` pattern: a pre-merge review against Karpathy's 4 principles (Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution). The framing tempted three component-additive options: new skill, new agent, or new slash-command wrapper.

The 2026-05-03 prior-art learning had already addressed the **guidance direction** ("should the LLM be told to follow these rules?"). That direction was answered "no AGENTS.md addition needed" because the Claude Code system prompt already enforces Simplicity First and Surgical Changes, and AGENTS.md `cm-challenge-reasoning-instead-of` covers the Think direction.

But that prior-art covers only one orientation. A brainstorm that uncritically reads it could either:

1. Conclude "already covered, close as won't-fix" and miss the audit-direction gap.
2. Conclude "the audit direction is fully orthogonal, build the full alirezarezvani port" and miss that `code-simplicity-reviewer` already covers ~half of the audit checklist.

Both extremes lose. The correct read is in the middle.

## Solution

Before sizing an import:

1. **Separate the two directions.** "Should the model FOLLOW the rules?" (guidance) vs. "Should reviewers CHECK code against the rules?" (audit). They map to different surfaces (system prompt / AGENTS.md vs. review agents / review skill).
2. **For each direction, audit existing coverage.** For audit-direction, grep `plugins/soleur/agents/engineering/review/` for keywords from the imported principles. For Soleur's `code-simplicity-reviewer`, the principle coverage is:
   - Principle #2 (Simplicity): "Apply YAGNI Rigorously", "Challenge Abstractions" — **covered**.
   - Principle #3 (Surgical): "Remove commented-out code", "Eliminate defensive programming" — **covered**.
   - Principle #1 (Hidden assumptions): **partially covered** by "Challenge Abstractions"; not an explicit output section.
   - Principle #4 (Goal verification): **not covered**.
3. **Size to the residual gap.** If 2 of 4 principles already have audit coverage in an existing agent, the right move is to extend that agent with two output sections — not to ship a new skill / agent / scripts.
4. **Anchor the audit-direction decision in the same learning that documented the guidance-direction decision.** One learning, one source of truth, both reframes covered.

## Why

- **Prior-art reuse.** The 2026-05-03 learning correctly addressed half the question. Extending it (rather than spawning a parallel learning) preserves the single source of truth for the karpathy-pattern decision space.
- **Component-count discipline.** Soleur's `plugins/soleur/AGENTS.md` Skill Compliance Checklist warns about cumulative description word count and discoverability budget. A new skill / slash-command for a content addition to an existing agent is a discoverability tax with no behavior gain.
- **YAGNI at the tier-gate boundary.** `cq-agents-md-tier-gate` routes already-enforced guidance to a pointer; the parallel principle for agents is: route already-mostly-covered audit checks to the existing agent body, not to a new agent file.

## How to Apply

When a brainstorm description names an external pattern + cites `alirezarezvani/`, `forrestchang/`, or any other community Claude Code skill repo:

1. Run a pre-research grep against `plugins/soleur/agents/engineering/review/` for the imported principle keywords (complexity, simplicity, noise, assumptions, goals, verification).
2. Read the matched agent bodies. Score the principle coverage row-by-row.
3. Reframe the brainstorm question explicitly: "audit direction" vs. "guidance direction", and present one to the user.
4. If audit-direction coverage is partial in an existing agent, the default option is **extend the agent**. Promote new skill / slash-command / scripts only when extension would either bloat the agent past comprehension or require deterministic non-LLM checks the agent can't host.
5. When closing, extend the existing prior-art learning rather than creating a parallel one.

## Related

- Source brainstorm: `knowledge-base/project/brainstorms/2026-05-15-karpathy-check-brainstorm.md`
- Source spec: `knowledge-base/project/specs/feat-karpathy-check-2727/spec.md`
- Companion prior-art (guidance direction): `knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md`
- Target agent: `plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md`
- Orchestrator: `plugins/soleur/skills/review/SKILL.md`
- Issue: #2727 (parent #2718)
- AGENTS.md anchors: `cq-agents-md-tier-gate`, `cm-challenge-reasoning-instead-of`, plugin-level skill compliance checklist

## When This Becomes Load-Bearing

- A future brainstorm references `alirezarezvani`, `forrestchang`, or another portable-skill-library import. Read this file first; do the audit/guidance split before sizing.
- An existing review agent's coverage map drifts (e.g., `code-simplicity-reviewer` is restructured). Re-score the principle coverage rows; this learning's recommendation may pivot.

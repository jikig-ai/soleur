# Token Optimization: Context-Aware Agent Gating

**Date:** 2026-04-13
**Status:** Decided
**Participants:** Founder, CTO, CPO, CFO, CMO

## What We're Building

A context-aware gating system for Soleur's agent spawning pipelines. Instead of spawning all available agents in every pipeline invocation, agents are conditionally spawned based on actual context: file types changed, PR size, change scope, and domain relevance. The goal is to reduce Claude Code token consumption and avoid hitting usage limits, without any quality degradation.

## Why This Approach

Soleur is hitting Claude Code usage limits faster than expected due to cumulative agent sprawl across all workflows. With 60+ agents all using `model: inherit` (Opus), a single session can cascade into dozens of expensive subagent calls.

The user's quality bar is non-negotiable across all pipelines (review, domain assessments, implementation). This rules out model downgrades (e.g., `model: sonnet` overrides). Savings must come from **not spawning agents that aren't relevant**, rather than making agents cheaper.

Context-aware gating was chosen over:
- **Tiered profiles** (light/standard/deep presets) — simpler but less surgical
- **Incremental spawning** (start small, escalate) — more efficient but slower and more complex
- **Advisor strategy** (Messages API `advisor_20260301` tool) — cannot work at the plugin level (see below)

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | No model downgrades | Quality is non-negotiable across all pipelines. Savings come from smarter spawning. |
| 2 | Context-aware gating over tiered profiles | More surgical — full quality when relevant, zero waste when not. |
| 3 | Advisor strategy deferred to web platform | The `advisor_20260301` tool is a Messages API construct; Claude Code plugins don't control the API `tools` array. Filed as #2030. |
| 4 | Gating signals: file types, PR size, change scope, domain keywords | Concrete, deterministic signals that can be evaluated before spawning. |
| 5 | All domain leaders recommend deferring advisor | CTO, CPO, CFO, CMO assessed 2026-04-13 — unanimous on deferral. |

## Open Questions

1. **Which pipelines to gate first?** Review (8-13 agents) is the obvious highest-value target. Brainstorm domain assessment (up to 8 leaders) is second.
2. **How to define gating rules?** File-path patterns (e.g., skip security-sentinel for docs-only PRs) vs semantic analysis of the diff.
3. **What's the fallback?** If gating incorrectly skips a relevant agent, how does the user override?
4. **How to measure impact?** No token usage instrumentation exists today. Need baseline before/after data.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** The advisor tool operates at a layer Soleur cannot reach — it's a Messages API construct, and the plugin doesn't control the `tools` array. Three options evaluated: wait for Claude Code native support (recommended), crude model tiering, custom escalation protocol. For plugin-side token reduction, reducing agent fan-out and adding conditional spawning is the right lever. The existing `model: inherit` policy was a deliberate architectural decision that should not be reversed without justification.

### Product (CPO)

**Summary:** The advisor pattern is exclusively a web platform concern — zero relevance to the plugin. BYOK trust conflict identified: silently routing user-funded Opus keys through cheaper models breaks the trust contract. With zero users and undecided pricing, advisor optimization is premature. Recommendation: defer until Phase 4 validation produces real usage cost data. For the plugin, focus on reducing unnecessary agent spawning.

### Finance (CFO)

**Summary:** No cost baseline exists for any Soleur workflow. Under BYOK, the advisor saves users money (not Soleur). Critical infrastructure for viable unit economics if pricing moves to managed billing. High-impact targets for optimization: review pipelines (8-13 parallel Opus agents), resolve-parallel (unbounded agents), brainstorm domain assessment (up to 8 leaders). P0 action: instrument token usage per agent session.

### Marketing (CMO)

**Summary:** This is infrastructure, not a marketing moment. Model routing is table stakes (Notion, GitHub Copilot, Microsoft already ship it). No blog post, changelog, or social content warranted. The value surfaces indirectly in pricing strategy — cost reduction may unblock the $49/month tier viability. Ship quietly when ready.

## Capability Gaps

None identified. Context-aware gating can be implemented using existing skill infrastructure (file-path matching, `git diff` analysis, conditional agent spawning in skill SKILL.md files).

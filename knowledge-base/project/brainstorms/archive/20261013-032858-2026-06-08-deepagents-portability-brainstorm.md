---
title: "deepagents (LangChain) Portability Brainstorm"
date: 2026-06-08
issue: 5034
lane: single-domain
brand_survival_threshold: not-applicable
status: complete
---

# deepagents Portability Brainstorm

## What We're Exploring

Whether `langchain-ai/deepagents` could replace the Claude Code harness for Soleur — the fourth platform portability scan after Codex CLI (#509), Gemini CLI (#1738), and OpenHands (#1770). Deliverable mirrors the OpenHands experiment: inventory, primitive-mapping, GREEN/YELLOW/RED classification, critical unknowns, go/no-go recommendation, and a 4th column on `platform-portability-comparison.md`.

## Premise Correction (caught during research)

The brief framed deepagents as "a LangChain library, a different architectural category from the interactive harnesses." **Research invalidated that premise.** As of v0.6.8 (2026-06-03), deepagents ships `deepagents-code` / `dcode` — an interactive terminal harness self-described as *"similar to Claude Code or Cursor,"* and the repo tagline is *"the batteries-included agent harness."* deepagents is now a genuine OpenHands-class peer (SDK + harness), explicitly inspired by Claude Code. The scan proceeded on that corrected framing.

## Key Findings

| Dimension | Result |
|---|---|
| Components scanned | 152 (67 agents, 82 skills, 3 commands) |
| GREEN / YELLOW / RED | 19.7% (30) / 80.3% (122) / 0% |
| Zero-RED? | Yes — second target after OpenHands; every primitive has an equivalent |
| GREEN% rank | **Lowest of all four platforms** |

**The defining fact:** deepagents subagents are Python `SubAgent` TypedDicts; there is **no markdown-agent loader**. All 67 markdown agents flip from GREEN (markdown→markdown on OpenHands) to YELLOW (markdown→Python rewrite). Prose ports verbatim into `system_prompt`, so it's mechanical, but it's 67 rewrites + 5 bash-hook rewrites. Conversely, **skills port better than on any prior target** — `SkillsMiddleware` reads the identical `SKILL.md` + frontmatter + 3-level progressive disclosure. The OpenHands pattern inverts: agents expensive, skills cheap, no plugin distribution.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Verdict (mechanical port) | **NO-GO** | 67 Python agent rewrites + 5 hook rewrites + no plugin distribution → 6-10 wk for a worse outcome than OpenHands' 1-2 wk |
| Verdict (strategic rebuild) | **CONDITIONAL-GO** | deepagents is the strongest target for model-agnosticism + durable server-side runtime |
| Recommended play | **Hybrid, not replacement** | Port skills (GREEN) as a server-side skill-execution runtime; keep agent orchestration on Claude Code |
| Harness redundancy goal | **Use OpenHands, not deepagents** | OpenHands keeps agents markdown + has a plugin system at a fraction of the cost |
| Deliverable depth | Full inventory + recommendation + critical-unknowns + 4th comparison column | Operator chose full scope |

## Why This Approach

deepagents is **expensive to port but the most strategically valuable destination**. Its differentiators — true model-agnosticism (any LangChain chat model), durable checkpointer persistence (Postgres/Redis), MIT + 24k★ LangChain backing, and a now-real harness — are exactly what a *server-side, model-agnostic agent runtime* needs. That ties to existing Soleur work (`2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md`, ADR-030 Inngest durable trigger layer) surfaced during research. So the value is not "same Soleur on a different CLI" (OpenHands wins that) but "Soleur unbound from Claude, durably persisted server-side."

## Open Questions (→ critical-unknowns.md)

1. **dcode harness maturity** — can the v0.1.0 CLI run Soleur's long multi-step pipelines? (HIGH)
2. **Subagent nesting depth** — multi-level in practice, or one level? (MEDIUM)
3. **Structured-prompt absence** — real impact on brainstorm/plan/ship gates (HITL respond only). (MEDIUM)
4. **Skill arg injection** — does dcode `/skill args` substitute into SKILL.md body? (MEDIUM)
5. **Shell-hook → middleware parity** — deny-with-feedback via `wrap_tool_call`? (MEDIUM)
6. **Plugin/distribution packaging** — how to ship 152 components as one installable unit? (MEDIUM)

## Domain Assessments

**Assessed:** Engineering (CTO lens)

### Engineering

**Summary:** Internal-infra/research assessment, synthesized directly with cited deepagents research rather than spawning the leader fan-out (no user-facing surface, no credential/data/billing axis → `USER_BRAND_CRITICAL=false`, lane=single-domain). Engineering verdict: deepagents is architecturally sound and zero-RED, but the markdown→Python agent rewrite and missing plugin-distribution layer make it a poor mechanical port and a strong strategic-rebuild candidate. Recommend hybrid (skills port + server-side runtime), gate on model-agnosticism / durable-runtime triggers, and resolve U1/U3/U6 via PoC before any scope beyond skills-only.

## Effort Summary

| Scope | Effort |
|---|---|
| Skills-only port (29 GREEN + ~20 light-YELLOW) | 1-2 wk |
| GREEN skills + 43 prose agents (bulk-scripted) | 2-3 wk |
| Full harness parity | 6-10 wk (not recommended) |
| Server-side runtime (greenfield) | Separate initiative |

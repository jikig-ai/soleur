# Functional Overlap Detection for Agent-Finder

**Date:** 2026-02-19
**Issue:** #155
**Status:** Decided

## What We're Building

A functional overlap detection system that surfaces community skills/agents with similar capabilities to what's being planned, preventing redundant development. Two integration points:

1. **Light check during brainstorm** (Phase 1.1) -- informational awareness alongside repo-research-analyst results. "FYI, these community tools exist in this space."
2. **Detailed check during plan** (Phase 1.5b) -- actionable install/skip flow, same UX as current stack-gap discovery.

This complements (not replaces) the existing stack-gap detection in agent-finder.

## Why This Approach

**Problem:** During growth-strategist development (#152), multiple community SEO/content-strategy tools existed across tessl.io, GitHub, and MCP Market but weren't surfaced. The current agent-finder only detects missing technology stacks (Flutter, Rust), not missing functional domains (SEO, code review, content strategy).

**Frequency:** This is a frequent pain point, not a one-off. As the community registry ecosystem grows, the overlap problem will compound.

**Chosen approach: Dedicated discovery agent + shared registry script (Approach 3)**

Rationale: Clean separation of concerns. The agent-finder stays focused on stack gaps. A new `functional-discovery` agent handles keyword-based overlap detection. Both share registry query infrastructure via an extracted script.

Alternative considered and rejected:
- **Extending agent-finder with a mode parameter** -- simpler, but risks overloading a single agent prompt. The "split when it hurts" principle was weighed, but the different trigger mechanisms (file signatures vs. keyword extraction) and different presentation needs (informational vs. actionable) justified separation from the start.

## Key Decisions

1. **Two integration points:** Brainstorm (light/informational) + Plan (detailed/actionable)
2. **Hybrid keyword extraction:** LLM generates 2-3 focused search queries from the feature description, rather than passing raw text or doing NLP extraction
3. **Dedicated agent:** New `functional-discovery` agent in `agents/engineering/discovery/`, separate from agent-finder
4. **Shared registry infrastructure:** Extract registry query/trust/install logic into a reusable script both agents call
5. **Install/Skip per item:** Same UX as current agent-finder -- no inspect or reference options, keeping it simple and consistent
6. **Graceful degradation:** Registry failures are non-blocking, same as current behavior

## Open Questions

- Exact script interface for shared registry queries (inputs/outputs)
- Whether brainstorm integration modifies repo-research-analyst or adds a parallel agent spawn
- Deduplication strategy when the same tool is found during brainstorm AND plan phases

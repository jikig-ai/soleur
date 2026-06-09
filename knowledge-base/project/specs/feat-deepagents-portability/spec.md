---
title: "deepagents Portability Scan"
date: 2026-06-08
issue: 5034
lane: single-domain
brand_survival_threshold: not-applicable
status: complete
---

# Spec: deepagents Portability Scan

## Problem Statement

Soleur has assessed three alternative agent platforms (Codex CLI, Gemini CLI, OpenHands) for harness portability. `langchain-ai/deepagents` is a fourth candidate. Originally assumed to be "a LangChain library, a different category," it has since become a real agent harness (`dcode`), warranting the same portability scan to inform any future multi-harness or model-agnostic strategy.

## Goals

- G1: Classify all 152 Soleur components (agents/skills/commands) GREEN/YELLOW/RED for deepagents.
- G2: Map the 10+ Claude Code primitives to deepagents equivalents with a delta vs OpenHands.
- G3: Produce a go/no-go recommendation with investment triggers and effort estimate.
- G4: Document docs-only critical unknowns gated for PoC.
- G5: Add deepagents as a 4th column to `platform-portability-comparison.md`.

## Non-Goals

- Building any deepagents port (this is an assessment only).
- A PoC implementation (deferred; gated by the recommendation's triggers).
- Re-scanning Codex/Gemini/OpenHands.

## Functional Requirements

- FR1: Inventory with summary stats, four-way comparison, primitive mapping, and full component classification. → `inventory.md`
- FR2: Recommendation with decision, evidence table, goal-conditioned verdict, triggers, effort. → `recommendation.md`
- FR3: Critical-unknowns list with impact ratings and PoC gates. → `critical-unknowns.md`
- FR4: Comparison table updated with deepagents column + strengths/weaknesses/triggers. → `platform-portability-comparison.md`
- FR5: Brainstorm document capturing the premise correction and key decisions. → `2026-06-08-deepagents-portability-brainstorm.md`

## Technical Requirements

- TR1: Classification derived from a grep-based primitive scan of the live repo (not extrapolation from the April snapshot).
- TR2: All deepagents capability claims cited to deepagents/LangGraph docs or source (v0.6.8, accessed 2026-06-08); unverified items flagged docs-only.

## Outcome

**NO-GO as a mechanical port; CONDITIONAL-GO as a strategic server-side rebuild.** 19.7% GREEN / 0% RED. The agent hierarchy must be rewritten markdown→Python and there is no plugin-distribution layer, making it 3-5× the cost of the OpenHands port for a worse distribution story. Strategic value (model-agnostic, durable persistence, real harness) is highest of any target. Recommended play: hybrid (skills port + server-side runtime), not replacement. Harness redundancy → OpenHands; model-agnosticism / durable runtime → deepagents.

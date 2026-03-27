---
adr: ADR-011
title: Three-Tier Enforcement Model
status: active
date: 2026-03-27
---

# ADR-011: Three-Tier Enforcement Model

## Context

Constitution rules requiring semantic judgment (e.g., "detect UI signals in the plan") cannot be enforced by PreToolUse hooks, which are syntactic only.

## Decision

Three enforcement tiers — PreToolUse hooks (syntactic, strongest, mechanical prevention), skill instructions (semantic, medium, LLM-evaluated at specific phases), prose rules (advisory, weakest, requires agent compliance). Annotate constitution rules with `[skill-enforced: <skill> <phase>]` when elevated from prose to skill. Place gates at workflow phases where the LLM already has relevant context.

## Consequences

Semantic rules get real enforcement without requiring new hooks. Clear hierarchy for deciding where to place new rules. Constitution annotations make enforcement level visible. Risk of over-relying on LLM compliance for skill-tier rules.

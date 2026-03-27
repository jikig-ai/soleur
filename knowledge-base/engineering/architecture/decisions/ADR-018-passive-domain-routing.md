---
adr: ADR-018
title: Passive Domain Routing
status: active
date: 2026-03-27
---

# ADR-018: Passive Domain Routing

## Context

User messages during engineering tasks sometimes contain unrelated domain signals (expense mentions, legal commitments, marketing opportunities) that should be captured without blocking the primary task.

## Decision

When user message contains a clear, actionable domain signal unrelated to the current task, spawn the relevant domain leader as a background agent (run_in_background: true). Use brainstorm-domain-config.md to detect relevance. Continue primary task without waiting. Do not route on trivial messages or when the domain signal IS the current task.

## Consequences

Domain signals captured opportunistically without context switching. Background agents can file issues, update documents, or alert the user. Risk of false positive routing on ambiguous messages.

---
adr: ADR-012
title: Tier-0 Lifecycle Parallelism
status: active
date: 2026-03-27
---

# ADR-012: Tier-0 Lifecycle Parallelism

## Context

Sequential RED-GREEN-REFACTOR lifecycle is the bottleneck, not task independence. Code-then-tests is serial because tests depend on implementation.

## Decision

Generate an interface contract (markdown: File Scopes + Public Interfaces) before spawning agents. Spawn two parallel agents — Agent 1 (Code) implements features to satisfy public interfaces, Agent 2 (Tests) writes ATDD RED phase from contract alone without reading source. Coordinator waits for both, commits combined output, runs test-fix-loop until GREEN. Docs written sequentially after GREEN.

## Consequences

ATDD inverts dependency arrow — tests depend on contract, not implementation, enabling lifecycle parallelism. Contract must be minimal (2 sections only) to avoid speculative work. Agents explicitly constrained from running git commands (coordinator commits only).

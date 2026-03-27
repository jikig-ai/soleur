---
adr: ADR-010
title: Brainstorm Default Routing
status: active
date: 2026-03-27
---

# ADR-010: Brainstorm Default Routing

## Context

/soleur:go router was lumping features and bugs together, sending both to one-shot. Features skipped domain leader assessment, leading to missed CMO/CTO concerns.

## Decision

Three intents: explore, generate, build. Everything except bugs routes to brainstorm (which has a Phase 0 escape hatch for trivially clear features). Bug detection via keywords ("fix", "bug", "broken") or issue label check (type/bug). No confirmation step — users invoke commands directly if router misclassifies.

## Consequences

Domain leaders (Phase 0.5) catch blind spots early. Features always get domain assessment before implementation. Bugs get fast-tracked via one-shot. Users can bypass routing by invoking skills directly.

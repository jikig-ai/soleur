---
adr: ADR-015
title: Decoupled Work/Ship for Review Gates
status: active
date: 2026-03-27
---

# ADR-015: Decoupled Work/Ship for Review Gates

## Context

Review running after work/ship had already merged PR left findings unactionable. Need review to run between work and ship.

## Decision

Work's Phase 4 behavior depends on invocation context — via one-shot, hand off control (one-shot orchestrates: work -> review -> resolve -> compound -> ship); direct invocation by user, continue automatically through compound -> ship. Heuristic: hand off if there is a caller, finish if there is not.

## Consequences

Review gates run before merge in orchestrated pipelines. Direct invocations still complete the full lifecycle without requiring explicit orchestration. The heuristic must be reliably detectable from conversation context.

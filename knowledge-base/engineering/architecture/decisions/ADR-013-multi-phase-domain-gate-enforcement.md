---
adr: ADR-013
title: Multi-Phase Domain Gate Enforcement
status: active
date: 2026-03-27
---

# ADR-013: Multi-Phase Domain Gate Enforcement

## Context

Features shipping without CMO, CTO, CLO assessment. Platform complexity requires cross-domain coordination at brainstorm and ship time.

## Decision

Before shipping (/soleur:ship Phase 5.5), three conditional domain leader gates run in parallel — CMO content-opportunity gate (triggers on research/marketing changes), CMO website framing review gate (triggers on brand-guide positioning changes), COO expense-tracking gate (triggers on new service signups). New user-facing capabilities require CPO and CMO assessment at minimum during brainstorm.

## Consequences

Cross-domain concerns caught before merge. Parallel execution keeps gate overhead low. CMO and COO gaps that were discovered in #1173 are now systematically prevented. Risk of gate fatigue if too many domains are always-relevant.

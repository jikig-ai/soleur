---
adr: ADR-005
title: Persistent Session Architecture
status: active
date: 2026-03-27
---

# ADR-005: Persistent Session Architecture

## Context

Agent currently has amnesia — each message spawns fresh agent with no memory. P1 blocker for product viability. Users need continuous conversations across messages.

## Decision

Hybrid approach — SDK resume as primary mechanism for full context fidelity including tool execution history, with message replay from Supabase as fallback when SDK session expires. Three close triggers: inactivity timeout, explicit new chat, work completion. TTL with user control.

## Consequences

Full context continuity for users within session lifetime. Graceful degradation when SDK session expires. Downstream impact on GDPR account deletion, session timeout policy, conversation inbox, and tag-and-route features.

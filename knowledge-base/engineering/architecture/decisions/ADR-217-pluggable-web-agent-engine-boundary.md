---
title: "Pluggable web agent engines bind execution before dispatch"
status: accepted
date: 2026-09-13
issue: none
supersedes: null
---

# ADR-217: Pluggable web agent engines bind execution before dispatch

## Context

Soleur Web currently has Claude-specific streaming and tool behavior, while the
product needs to add Codex and later engines without allowing a client payload
to select a provider. Conversations and routines also need retries to remain on
the engine selected when the execution started.

## Decision

The workspace default is mutable settings state. Each conversation or routine
run gets one immutable `agent_engine_runs` binding before provider dispatch. The
trusted bind RPC resolves the workspace default and enforces tenant membership;
authenticated user calls must use their own `created_by` identity. Reads use RLS
workspace membership, while owner writes use a security-definer RPC with a pinned
`public, pg_temp` search path.

Adapters implement the neutral lifecycle contract: start, continue, cancel,
reconcile, cursor resume, approval response, erasure, and disposal. Dispatch
reloads the persisted binding, verifies adapter identity, persists emitted events
before yielding them, and fails closed on missing bindings, mismatches, or event
ledger errors. Provider SDK types remain inside adapters and transport seams.

The Claude extraction uses a provider-facing SDK message source wrapped by a
translator and neutral transport bridge. The source retains permission,
session, approval, and cancellation behavior; only validated text, progress,
usage, and terminal result payloads cross into the shared event contract.

The reviewed registry controls which engines may appear in settings and which
engine/auth/workflow/capability combinations are qualified for execution. A
settings metadata lookup never grants execution authorization.

Factory and dispatch entry points accept an explicit reviewed registry when a
deployment or deterministic test catalog needs additional engines. When a
dispatch supplies a trusted egress selection, factory creation passes that
selection through registry qualification; a registry without `resolve` fails
closed rather than treating metadata lookup as authorization. The built-in
catalog remains the default, so future providers can be added through reviewed
definitions and additive factories without changing provider control flow.

## Consequences

Adding an engine requires a reviewed definition, adapter transport, lifecycle
tests, credential and qualification evidence, and settings/catalog wiring. A
workspace default change affects new runs only; existing runs retain their
binding. Registry injection keeps future engine wiring additive but does not
bypass enablement, binding identity, event validation, or egress policy. System-
triggered routines still require a dedicated service identity before they can
participate in the same binding path.

---
title: Perplexity SPACE as a Stage-0 sandbox spike candidate
feature: feat-space-sandbox-spike-candidate
epic: 9842
related: [9859, 9867]
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-19-space-sandbox-spike-candidate-brainstorm.md
pr: 10533
---

# Spec: SPACE as a Stage-0 sandbox spike candidate

## Problem Statement

Epic #9842 compares sandbox stacks for the tenant executor. Perplexity's SPACE (Firecracker, self-hosted, suspend/wake, credential injection) appeared after the epic's spikes were scoped and is the only surveyed candidate that targets the session-lifecycle half. It is 18 days old and pre-1.0, so it needs a bounded, evidence-only evaluation with fixed criteria and kill rules rather than open-ended exploration.

## Goals

- G1. Add SPACE as a second contender in S12 (#9867) beside OpenSandbox, run against the same workload and probes.
- G2. Add an optional, conditional Arm E to S0 (#9859) on the same KVM node as Arm C.
- G3. Fix criteria and stop conditions in the ADR before any run.
- G4. Produce an evidence-only verdict; no adoption before SPACE passes 0.9.

## Non-Goals

- No new spike issue.
- No adoption or production use of SPACE in this work.
- No tenant data, no production traffic.
- No change to the Stage-0 gate or to ADR #9854 timing.

## Functional Requirements

- FR1. S12 text lists SPACE credential rules and egress policy as a second contender, run with the same Claude CLI plus SDK workload and S5 probes.
- FR2. S0 text lists Arm E (SPACE on the Arm C KVM node) with a 1-day hard timebox, recording cold start with and without warm pool or base snapshot, RAM per session, and ops surface.
- FR3. Arm E runs only after Arms A-C are complete and only if the S11 (#9866) KVM node is live and EU-resident; otherwise it is dropped without penalty.
- FR4. Criteria 1-10 in the brainstorm are recorded in the ADR before the run.
- FR5. Each result is recorded as observed, with unverified claims labelled.

## Technical Requirements

- TR1. Pin an exact SPACE commit SHA before any run.
- TR2. Use a spike-only Anthropic key, revoked after the run.
- TR3. Run an egress capture to detect telemetry or phone-home.
- TR4. Inspect the interception CA: per-tenant vs shared, key location, rotation.
- TR5. Verify the key is absent from guest env, filesystem, `/proc`, and every suspend snapshot in object storage.
- TR6. Verify SSE streaming and usage/cost data under TLS interception with the CA in the Claude CLI's Node trust store.

## Stop Conditions

- Credential rules cannot keep the key out of the sandbox.
- Streaming breaks under TLS interception.
- Interception CA is shared across tenants or held on the host.
- Postgres plus object-store footprint exceeds the effort of the bespoke supervisor.
- Not KVM-ready on the EU node within the timebox.

## Legal Preconditions (before any production use, not for the spike)

#9851 (Art. 32 TOM), #9852 (Scale-tier copy), #9853 (DPIA re-screen, Schedule 4), plus an Art. 30 register row and policy updates for the decrypting gateway, and a check of Anthropic's current terms on proxying API traffic.

## User-Brand Impact

Threshold: single-user incident. The spike must not touch tenant data. Any adoption proposal re-opens this section.

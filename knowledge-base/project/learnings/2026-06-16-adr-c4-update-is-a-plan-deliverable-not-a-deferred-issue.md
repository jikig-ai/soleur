---
date: 2026-06-16
category: workflow-patterns
tags: [planning, adr, c4, architecture, workflow-gate]
source: ADR-044 workspace-connection brainstorm (#5437)
---

# ADR/C4 updates are a plan deliverable, never a deferred follow-up issue

## What happened

During the ADR-044 workspace-connection brainstorm, the always-enforce-workspace
architectural decision (every user owns a guaranteed personal workspace; connection keys on
workspace) and its C4 connection-owner edge were filed as a **separate deferred issue**
(#5440) alongside billing-relocation and Flagsmith-targeting follow-ups. The operator
rejected this: "C4/ADR should not be a separate deferred issue, it should be very much part
of planning always."

## Why it was wrong

Billing relocation and Flagsmith targeting are genuinely separable future *scope*. An
ADR/C4 update is not scope — it is the **documentation of the decision the current change
embodies**. Deferring it ships a system whose recorded architecture (`knowledge-base/engineering/architecture/`)
lies about its real architecture until someone reopens the issue (usually never). The plan
skill already *reads* the ADR corpus (Phase 0.6) to avoid re-deciding settled questions, but
had no gate requiring it to *produce* an ADR when the plan creates a new decision —
asymmetric: consume-always, produce-never.

## The fix (workflow)

- Added **plan Phase 2.10 — Architecture Decision (ADR/C4) Gate** mirroring the 2.7 GDPR /
  2.8 IaC / 2.9 Observability "Always" gates: when the plan makes/changes an architectural
  decision (ownership/tenancy boundary move, new substrate/trust boundary, reversal/extension
  of an existing ADR), it MUST emit an `## Architecture Decision (ADR/C4)` section naming the
  ADR to create/amend and the C4 view(s) to update **as in-scope plan tasks**. Reject
  condition: detection fires but the ADR/C4 update is deferred to a follow-up issue.
- Backed it with `wg-architecture-decision-is-a-plan-deliverable` (AGENTS.rest.md) so the
  rule reaches one-shot/brainstorm, not just the plan skill.

## The test

Would a competent engineer reading only the existing ADRs + C4 be **misled** about the
system after this plan ships? If yes → the ADR/C4 update is a deliverable of this plan. If no
(bug fix, copy tweak, dep bump) → skip silently.

## Note on the c4-edit flag

C4 diagram edits are Concierge-only (gated behind the `c4-edit` flag, per commit `3c8849655`,
via `/soleur:architecture`). That gating governs *who/how* the edit lands — it does NOT make
the C4 update a separate issue. The update still belongs in the feature's own lifecycle.

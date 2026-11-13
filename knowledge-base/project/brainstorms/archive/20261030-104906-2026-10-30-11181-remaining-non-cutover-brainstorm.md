---
date: 2026-10-30
topic: 11181-remaining-non-cutover-gates
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Remaining Non-Cutover Gates for #11181

## What We're Building

No new user-facing feature or architecture change is warranted. This brainstorm reconciles the still-open non-cutover epic with its shipped child PRs and records the already-decided order for the remaining owner, verification, and cutover gates. Existing plans remain authoritative for implementation details.

The Phase-3 target is concurrent service of one workspace across hosts using per-user worktrees and shared git-data. Until the cutover gates pass, web-2 must remain outside the app load-balancer pool. The user benefit—workspace continuity across hosts—has not yet reached users.

## User-Brand Impact

- **Artifact:** the `/workspaces` multi-host serving path and its LB/readiness gates.
- **Vector:** routing a request to an unready host could leave one user's workspace unavailable or make committed work appear lost.
- **Threshold:** `single-user incident`.

## Why This Approach

The governing ADR and existing token-scope plan already settle the technical choices. Re-planning them would duplicate prior decisions and could blur the operator-reserved widen or the separate cutover authorization. Keep the existing sequence, preserve the holds, and do not infer production readiness from a shape-only check.

## Approaches Considered

### Approach A: Reuse the existing plans (chosen)

Keep F1–F3 in the archived default-token plan and cutover work in #6027. This avoids duplicating settled technical rulings and keeps owner-held acts separate from engineering work. Best when the current scope is already decided and blocked on its stated gates.

### Approach B: Write a new integrated execution plan

Combine the post-widen scope-ledger update, staging continuity probe, runtime-bind verification, and cutover holds into a new plan. This would offer one checklist, but it duplicates the existing plan and risks treating the separate cutover and authorization gates as one execution. Reconsider only if the operator changes scope after the widen.

## Key Decisions

| Decision | Rationale |
|---|---|
| Keep web-2 structurally out of `default_pool_ids` and at serving weight 0 until the cutover gates pass. | ADR-068 and the current LB gate make this a user-data safety invariant, not an optional rollout preference. |
| Preserve the `CF_API_TOKEN` widen as an operator-reserved action. | The merged default-token profile in #11383, corrected by #11456, provides the retained-scope check; it does not grant or prove the Edit permissions. |
| After a successful widen, update the `cf_api_token` scope description and ADR-130 note in the consuming PR. | This is existing follow-on F1; record only permissions that are actually present. |
| Run the throwaway-hostname continuity probe only after the widen; its staging apply dispatch needs fresh, named authorization. | The current standing delegation does not cover that dispatch. No dispatch or production mutation is part of this brainstorm. |
| Keep AC4, the placement-group reboot, and AC11 with cutover planning under #6027. | AC4 awaits the cutover owner; the reboot was re-parked by #11345; the soak starts only after cutover and requires seven qualifying days. |
| Treat the owner proxy listener's runtime bind as unverified until the separate on-host runtime-bind probe passes. | Issue comments report configuration/shape checks, not proof of an active listener. The success log is INFO-level, while the Vector app-container pipeline filters below WARN+, so an empty log query cannot establish absence or presence. |

**Shipped-state reconciliation:** #11182 (LB overlay), #11210 (per-host bind injection), #11348 (AC2 envelope archive), #11383 (default-token probe profile), and #11456 (Notifications route correction) are merged. #11217's placement-group removal was reversed by #11345, so the reboot remains deferred. The Oct. 27 issue comments report the cloud-init/webhook and readiness checks passing; those are historical comment evidence, not a fresh production read. Epic #11181 remains open and its latest issue comment is dated Oct. 28.

## Open Questions

- **Owner hold:** the `CF_API_TOKEN` widen and subsequent retained-scope assertion remain pending. Do not perform them here.
- **Runtime evidence:** the proxy listener's successful bind is not independently visible in Better Stack at INFO level. The cutover flow must use the already-required on-host runtime-bind probe before any weight change.
- **Cutover dependency:** the cutover owner still owes the AC4 `DOPPLER_TOKEN` scope answer. Keep the legal and technical cutover gates in ADR-068 / PA-36; this non-cutover reconciliation adds no new processing purpose, recipient, or legal document change.
- **Calendar-gated AC8:** the Oct. 28 operator note records Nov. 3 as the earliest date, jointly with the cutover session. Re-verify that trigger before acting. This is separate from AC11's seven-day GA soak, which requires cutover and qualifying multi-host leases.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support.

### Product

No new customer-facing promise or positioning gap surfaced. The reliability benefit remains gated on cutover, so do not claim multi-host availability before activation.

### Engineering

ADR-068 already settles the architecture. The remaining engineering delta is the post-widen scope-ledger/ADR-130 update; the on-host runtime-bind probe remains a cutover gate, not a new design choice here.

### Operations

After the operator widen and retained-scope check, update the ledger in the consuming PR; run the staging continuity probe only after the widen, with fresh authorization for its apply dispatch. Keep the reboot and soak with the cutover flow; this brainstorm does not authorize an apply.

### Legal

The widen and staging probe do not add a processing purpose, data category, recipient, or transfer. PA-2's cross-host replication entry remains future-tense while user sessions are not routed across hosts. Existing PA-36 lawful-basis, rights/deletion, and backup-retention gates remain pre-cutover obligations.

## Next Steps

Reuse the archived `cf-token-scope-default-token-profile` plan/tasks for F1–F3 and the existing cutover planning under #6027. No new implementation plan is proposed until the operator-reserved widen is complete and the staging prerequisite is authorized.

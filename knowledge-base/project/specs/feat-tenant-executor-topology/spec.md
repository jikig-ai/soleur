---
title: Per-Tenant Executor Topology + Cluster-Scale Session Placement
status: draft
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-08-tenant-executor-topology-brainstorm.md
issues: [9773, 5863]
branch: feat-tenant-executor-topology
pr: 9832
created: 2026-10-08
---

# Spec: Per-Tenant Executor Topology + Cluster-Scale Session Placement

## Problem Statement

Every hosted agent execution surface resolves execution locally inside one
multi-tenant web-platform container: Concierge sessions run the SDK `query()`
in-process and spawn the `claude` CLI as a child; cron/eval work spawns
`claude --print` children in the same container; `agent-on-spawn-requested`
runs an in-process Messages-API loop. The shared process means a shared heap
(BYOK leases, session state), shared `/proc` (same-uid `/proc/<pid>/environ`
exposes the container's full `prd` env to any session process), and one shared
`/workspaces` mount. Arm F (#5863, PR #9767) removes sibling *filesystem*
presence per session; it does not close the heap/proc-env residual — the
exposure #9773 tracks.

Separately, cluster-scale session *placement* is designed-but-dark: ADR-068's
lease + session-router + session-proxy machinery is fail-closed inert, and
there is no admission/scheduler that consumes host capacity signals.

The operator's question — executor isolation vs cluster scheduling, separately
or unified — resolved to **one unified architecture**: the executor unit IS the
placement atom. This spec covers that design and its staged build.

## Goals

- **G1.** A per-tenant executor unit defined: a tenant-scoped subprocess
  (per-tenant uid + mount namespace, arm-F privilege envelope) spawned via the
  existing `spawnClaudeCodeProcess`/`SpawnedProcess` seam, closing the
  shared-heap + `/proc/<pid>/environ` + filesystem residual classes in one
  boundary.
- **G2.** The executor contract is remote-ready from day one: session identity,
  event channel, and credential handoff survive a network hop (socket-shaped,
  not stdio-bound) — placement later is additive, never a rewrite.
- **G3.** A dedicated executor host (cpx32-class, EU DC, Terraform +
  cloud-init, fresh-boot reachable from `terraform apply`) takes the cron/eval
  fleet off the tenant-serving host — first remote-executor consumer.
- **G4.** Placement = the ADR-068 machinery brought live for executor units
  (lease-keyed), not a second scheduler; tenant sessions migrate after remote
  spawn is proven under fleet load.
- **G5.** Compliance record kept honest through the build: shared-heap residual
  recorded in the Art. 30 register; DPA Schedule 4 executor clause describes
  the boundary as built; DPIA re-screening memo produced.
- **G6.** Tripwires instrumented: `active_sessions` sustained-concurrency alert
  and per-session resource accounting — capacity decisions fire on signal.

## Non-Goals

- **NG1.** Per-tenant containers/microVMs (stronger kernel boundary) — deferred
  with explicit tripwires; subprocess cells are the first form. (Follow-up
  issue tracks the residual.)
- **NG2.** Nomad/k8s/managed runtime — gated on the AX eval's >100-sustained-
  concurrent trigger or a session-hibernation product need.
- **NG3.** Tenant-pinned hosts — rejected as general topology; enterprise
  escape hatch only.
- **NG4.** Session hibernation / in-flight checkpoint-resume — ADR-068 Phase-4b
  concern.
- **NG5.** GHA `claude-code-action` surface — outside the cluster by design.
- **NG6.** Per-tenant LUKS volumes/keys — whole-volume single-key posture
  (ADR-119) retained.
- **NG7.** Public-launch rate limiting / global admission queue (#673 3.3) —
  plan slots exist; separate feature.
- **NG8.** Moving Inngest itself — the control plane stays a dedicated
  singleton host (ADR-100); the executor host is a new sibling.

## Functional Requirements

- **FR1.** Executor supervisor: a host-local component that spawns per-tenant
  (or per-session, per OQ1) executor subprocesses under a per-tenant uid with
  the arm-F mountns wrap — `cap_sys_admin,cap_setuid` file-cap'd bwrap envelope,
  zero `--unshare-*`, own-workspace rw bind only.
- **FR2.** Remote-capable spawn contract: the executor speaks a
  `SpawnedProcess`-compatible transport (stdin/stdout/kill/exit semantics) so
  `realSdkQueryFactory`/`buildAgentQueryOptions` and the `EngineAdapter`
  `transport:"remote"` path are satisfied without rework.
- **FR3.** Credential handoff: executor hosts carry no `prd` Doppler env;
  per-session credentials minted at dispatch through the #9543 broker
  direction (mask/inject at the executor boundary).
- **FR4.** Executor host IaC: `var.executor_hosts`-style `for_each` extending
  the ADR-118 roster pattern; cloud-init only; fresh-boot readiness gate per
  `hr-fresh-host-provisioning-reachable-from-terraform-apply`; per-DC live
  stock probe before birth.
- **FR5.** Cron/eval migration path: `spawnClaudeEval` spawns route through the
  executor contract on the executor host; `CRON_WORKSPACE_ROOT` moves to a
  non-tenant subtree.
- **FR6.** Placement integration: session dispatch consults lease ownership +
  executor availability via the ADR-068 substrate; control ops stay
  lease-sticky (no cross-host control plane invention).
- **FR7.** Observability: per-session resource accounting (cgroup-level)
  + `active_sessions` sustained-concurrency alert at ≥4 + executor
  lifecycle events mirrored to Sentry per `hr-observability-layer-citation`.

## Technical Requirements

- **TR1.** All provisioning Terraform; host config via cloud-init; prod config
  changes via immutable re-provision (`hr-prod-host-config-change-immutable-
  redeploy`); executor host joins the private net question decided in the ADR
  (OQ4).
- **TR2.** ADR required (load-bearing infra/data fork): the executor topology
  ADR, relating to ADR-068 (placement), ADR-075 (isolation), ADR-272
  (credentials), ADR-030 (credential-aggregation ceiling), ADR-100 (Inngest
  singleton), ADR-119 (LUKS), ADR-027/ADR-027-state-supersession.
- **TR3.** gdpr-gate at plan Phase 2.7 and work Phase 2 exit; Art. 30 register
  + DPA Schedule 4 wording changes ride the same PR or a legal-sibling PR.
- **TR4.** uid allocation strategy resolved in the ADR with file-ownership
  analysis for host-side `session-sync`/`replicateToGitData` reads.
- **TR5.** Every failure mode cites its observability layer; executor spawn
  failures classify through `classifySandboxStartupError`-equivalent taxonomy.

## Domain Review (carry-forward)

Triad + COO + platform-strategist assessments recorded in the brainstorm doc's
Domain Assessments; operator overrode leader consensus on Approach A
(separate tracks) in favor of B (unified design, staged delivery).

## Open Questions

See brainstorm `## Open Questions` (executor granularity, uid allocation,
remote transport, private-net membership, action-send shape, credential
handoff, ADR-068 ordering, cgroup accounting, DPIA/Schedule-4 timing,
deploy/drain semantics).

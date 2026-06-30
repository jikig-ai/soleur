---
feature: multi-host-workspaces
date: 2026-06-29
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
issue: 5274
related: [5240, 5273, 5275, 5338, 5546]
branch: feat-multi-host-workspaces
pr: 5710
brainstorm: knowledge-base/project/brainstorms/2026-06-29-multi-host-workspaces-brainstorm.md
---

# Spec: Multi-host `/workspaces` layer for a cluster backend

> **Superseded framing (read the plan first).** This is the brainstorm-era input.
> Its **FR1/FR3 "managed Redis" + "migrate the 7 ADR-027 Maps"** premise and its
> **"Step 1–4" numbering** are **corrected** by the plan's `## Research
> Reconciliation` and **ADR-068 (Option B, rejected)**: only 1 of 7 Maps is
> serializable/cross-host (already Postgres-backed via #5338), the store is
> **self-hosted EU Redis** (not managed), Redis is scoped to the ADR-059 replay
> buffer and lands in **Phase 4a** (not Step 1), and the phases are **0/1/2/3/4a/4b**
> (Phase 3 is the GA line — OQ3 resolved 2026-06-30). Treat the FRs/TRs/Goals below
> as intent; the plan + ADR-068 are authoritative for mechanism and sequencing.

## Problem Statement

The backend is entirely single-host: one Hetzner block volume (RWO single-attach,
`server.tf:937-940`) → one server → one Node process → one set of in-memory state Maps.
`ADR-027` codifies a `replicas = 1` invariant for 7 process-local Maps; `ADR-059` puts the
stream-replay buffer in process memory assuming same-process reconnect. To go live and
scale with real users — for concurrent capacity, HA, GA-readiness, and cost bin-packing —
the `/workspaces` layer must become a cluster. This is the re-evaluation trigger for #5274.

## Goals

- **G1** — A single workspace's users are servable across multiple hosts concurrently (collaboration scales with users), via shared git-data + per-user worktrees, never concurrent writers to one git index.
- **G2** — Failover is invisible on both planned moves and unplanned host crash, with near-zero loss of uncommitted (un-pushed) work.
- **G3** — Preserve the #5240 user contract: no silent fresh-session greeting; committed/pushed work never lost; no wrong-tenant exposure.
- **G4** — Stay within GDPR data-residency: every substrate EU-region-pinned, per-tenant isolated, erasure reaches snapshots/backups.
- **G5** — Reach the end-state via a staged path where each increment is independently shippable forward-progress (Approach A).

## Non-Goals

- Self-hosted CephFS/Rook or Kubernetes (rejected: operational burden disproportionate for a small team).
- Multiple hosts writing the *same* git working tree / live same-file co-editing (Google-Docs-style). Collaboration is git-ref-mediated.
- Cross-region replication or any CDN/edge-cached store (breaches residency).
- Garage object-store migration in the initial increments (deferred until NFS fan-out is measured as a bottleneck — see tracking issue).

## Functional Requirements

- **FR1 (Step 1 — Externalize state)** — Migrate the 7 `ADR-027` Maps + the `ADR-059` replay buffer + the distributed concurrency counter to managed Redis (EU). Per-worktree write-lease lives in Postgres (crash-safe, audit-visible). Behavior identical at `replicas = 1`.
- **FR2 (Step 2 — Split storage)** — Bare git repos (objects/refs) on a shared volume; per-user worktrees on host-local NVMe, disposable and rebuildable from refs.
- **FR3 (Step 3 — Multi-host)** — Add a 2nd Nomad client + a coordinator that routes a session to any host holding/acquiring the workspace lease (keyed by lease, not Cloudflare sticky-to-host). Concurrent multi-host serving of one workspace's users (G1).
- **FR4 (Step 4 — Seamless crash)** — Health-based reschedule + lease-expiry reclaim + continuous worktree checkpointing of uncommitted state to the shared layer, so an unplanned host crash is invisible and loses near-zero un-pushed work (G2).
- **FR5** — The coordinator places a session on a host *before* session start so the bwrap sandbox mount set + `cwd` (frozen per `query()`, #5313 lineage) are never re-derived mid-turn.
- **FR6** — Honest recovery UX retained from #5240: any unavoidable degradation is surfaced, never silent; never requires git literacy from the user.

## Technical Requirements

- **TR1** — Remove every single-host assumption in the blast-radius inventory: `hcloud_volume_attachment` (server.tf:937-940), process-local Maps (agent-session-registry.ts:34,46), in-process grace-abort + buffer (ws-handler.ts:209,228-234), in-process concurrency slots (rate-limiter.ts), per-workspace path composition (workspace-resolver.ts:792-797).
- **TR2** — The cross-host grace-timer abort correctness bug must be eliminated: a disconnect-grace timer must not abort a session that has reconnected on another host (coordinator + durable lease ownership).
- **TR3** — All substrates EU-region-pinned; per-tenant path + credential scoping; encryption-at-rest; no shared cluster-wide mount credential.
- **TR4** — DSAR / Art. 17 erasure must reach worktree checkpoints/snapshots; snapshot TTL ≤ conversation retention.
- **TR5** — Architecture Decision Record authored as a plan deliverable (`wg-architecture-decision-is-a-plan-deliverable`): "Multi-host `/workspaces`: shared git-data + per-user worktrees + externalized state over Ceph/k8s."
- **TR6** — GDPR Art. 30 record-of-processing + sub-processor list updated for each new substrate (managed Redis EU, shared volume/object store) before GA.

## Acceptance Criteria

- **AC1** — With state externalized (FR1), a process restart preserves session/workspace bindings (extends #5338's lazy rehydrate).
- **AC2** — Two users on the same workspace, served by two different hosts, each operate their own worktree without git-index corruption (G1).
- **AC3** — A killed host mid-turn: the user's session resumes on another host with no silent fresh-session greeting and ≤ N seconds of uncommitted-work loss (N from Open Question 2) (G2).
- **AC4** — No cross-tenant workspace is ever readable from another tenant's host (G4).
- **AC5** — A drain/deploy is invisible to an active user (planned-move seamlessness).

## Open Questions (carry to plan)

1. Shared git-data SPOF: replicated object store (Garage) from the start vs GitHub-rehydration + brief re-clone — gated on which step gates GA.
2. Checkpoint cadence/mechanism (shadow-branch vs rsync; value of N).
3. Which staged step gates GA (Step 3 vs Step 4).
4. Managed-Redis EU provider selection + cost (Ops/Finance input at plan time).

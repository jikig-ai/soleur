---
date: 2026-06-29
topic: Multi-host /workspaces layer redesign for cluster backend
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
issues: [5274]
related: [5240, 5273, 5275, 5338, 5546]
branch: feat-multi-host-workspaces
pr: 5710
---

# Brainstorm: Multi-host `/workspaces` layer for a cluster backend

## What We're Building

A redesign of the physical `/workspaces` storage + scheduling layer so the Soleur
backend can run as a **cluster of machines** instead of a single Hetzner instance,
required to go live and scale with real users. This is the explicit re-evaluation
trigger for **#5274** (physical workspace durability / deterministic re-provision),
which was deferred-as-redundant precisely *because* the topology was single-host.

The operator chose the maximum-ambition target on both axes:
- **One workspace's users servable across multiple hosts concurrently** (collaboration scales with users).
- **Failover invisible even on unplanned crash, with near-zero loss of uncommitted (un-pushed) work.**

Chosen delivery: **Approach A — a staged path that reaches that full end-state**, de-risking
the hardest part first, with the operator choosing which step gates GA.

## Why This Approach

The end-state is genuinely distributed, but the *lightest credible substrate* — not
Ceph/k8s — gets there. Approach A (staged) reaches the identical end-state as a big-bang
(Approach B) but ships value at each step and front-loads the riskiest work (state
externalization). Approach C (honest-recovery GA, defer the expensive tail) was rejected
because it reverses the seamless-crash bar the operator explicitly set.

**Architectural reframe agreed during dialogue:** do NOT have multiple hosts write one
git index (corrupts on any FS — a git property, not a storage one). "One workspace spans
hosts" = **shared git *data* (objects/refs) + per-user worktrees placed on any host**,
collaboration mediated by git refs + a shared metadata/state layer. This turns a
research-grade problem (distributed lock on one working tree) into a tractable one.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Staged path (Approach A)**, not big-bang or deferred | Reaches full target; de-risks hardest part first; value per step |
| 2 | **Shared git-DATA + per-user worktrees on local NVMe** | Avoids concurrent-writer-on-one-index corruption; worktrees disposable/rebuildable |
| 3 | **Reject self-hosted CephFS/Rook + k8s** | 2am OSD/cluster-lifecycle tax disproportionate for a small team |
| 4 | **Managed Redis (EU)** for the 7 ADR-027 Maps + ADR-059 buffer + distributed counter | Ephemeral, hot, TTL-friendly; managed avoids HA-failover ops tax |
| 5 | **Per-worktree write-lease in Postgres, NOT Redis** | Crash-safe + audit-visible; a Redis lease silently expires on netsplit → double-write corruption |
| 6 | **Nomad, not k8s**, for placement / health-reschedule / rolling deploys | Single binary; k8s overkill at <5 services / one team |
| 7 | **Coordinator routing keyed by the lease**, not Cloudflare sticky-to-host | Sticky pins to a *dead* host on crash, defeating seamless failover |
| 8 | **Continuous worktree checkpointing** required for goal-2 | Disposable worktrees recover only committed/pushed state; un-pushed edits need checkpoint-to-shared-layer (extends #5275) |
| 9 | **GA gating step is operator's later call** | Each staged step is independently shippable; GA can land at step 3 or 4 |
| 10 | **Architecture Decision Record is a plan deliverable** | Load-bearing infra/data fork (wg-architecture-decision-is-a-plan-deliverable); CTO flagged `/soleur:architecture create` |

### Staged path (each step is forward-progress, no throwaway)
1. **Externalize state** — 7 ADR-027 Maps → managed Redis; per-worktree lease → Postgres. Still `replicas=1`. Riskiest part first; ships value immediately.
2. **Split git-data / worktree** — bare repos (objects/refs) on shared volume; worktrees on local NVMe. Still one host.
3. **2nd Nomad client + coordinator routing** → concurrent multi-host (goal 1).
4. **Health-reschedule + lease-expiry reclaim + continuous worktree checkpoint** → invisible unplanned failover with uncommitted preservation (goal 2).

Hard parts in order: state externalization → lease correctness → crash-failover.

## User-Brand Impact

- **Artifact:** the multi-host `/workspaces` storage + scheduling layer for backend agent sessions.
- **Vector:** a user's repo / worktree / uncommitted in-progress work lands on the wrong host, is lost on host failure or reschedule, or leaks cross-tenant during a migration.
- **Threshold:** single-user incident.

Non-negotiable user contract (CPO): no silent fresh-session greeting (#5240 regression),
no wrong-tenant glimpse (unrecoverable brand damage even with no write), committed/pushed
work never lost. Non-technical users cannot `git reflog` their way out — never surface a
recovery state requiring git literacy, never present a blank workspace as if correct.

## Open Questions

1. **Shared git-data SPOF vs strict no-SPOF.** Single-volume NFS for shared git-data is itself a SPOF, which fights "user never notices a crash." Close it via replicated object store (Garage) from the start, or accept GitHub-as-rehydration + brief re-clone? Decide at plan time per which step gates GA.
2. **Checkpoint cadence/mechanism for uncommitted work** (decision #8): shadow-branch commit vs rsync-to-shared every N seconds; what N bounds "near-zero loss" acceptably?
3. **Which staged step gates GA** (decision #9) — 3 (concurrent multi-host) or 4 (seamless crash)?
4. **Bash bwrap sandbox re-derivation across hosts** (#5313 lineage): mount set + `cwd` are frozen per `query()`; cross-host placement must re-derive — confirm the coordinator places *before* session start so this never happens mid-turn.
5. **GDPR Art. 30 + sub-processor entries** for each new substrate (managed Redis EU, shared volume/object store) — documentable-later but GA-required; EU-region pin + per-tenant isolation are GA-blocking.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO), Engineering/Infra (platform-strategist)

### Engineering (CTO)
**Summary:** Host-affinity + re-clone beats shared NFS for the naive case, but the operator's max bar (one-workspace-spans-hosts + seamless crash) forces externalized state + shared git-data. The cross-host 30s grace-timer abort is a correctness bug (fires on host A, kills a session reconnected on host B) — neutralized by coordinator routing on a durable lease. Single-host anchors: `hcloud_volume_attachment` RWO single-attach (server.tf:937-940), process-local Maps (agent-session-registry.ts), in-process grace/buffer (ws-handler.ts).

### Product (CPO)
**Summary:** Minimum durability promise = committed/pushed work never lost + honest recovery of working state. Wrong-tenant or silent-fresh-session is an unconditional GA-blocker, not a degradation tier. Seamless-crash is normally a post-GA optimization — the operator chose to make it a target, so checkpointing of uncommitted work becomes in-scope.

### Legal (CLO)
**Summary:** Every new substrate (managed Redis, shared volume/object store, snapshots) = a new GDPR Art. 30 record + likely sub-processor entry, EU-region pinned. Cross-region replication or any CDN/edge-cached store **breaches residency** — disallow. Per-tenant path+credential scoping, encryption-at-rest, and erasure reaching snapshots/backups are GA-blocking. Carry-forward from #5273/ADR-059: persisted substrate TTL ≤ conversation retention, same EU region.

### Engineering/Infra (platform-strategist)
**Summary:** Reject Ceph/k8s for a small team. v1 shared layer = bare git repos on a shared volume (objects/refs, single-writer-friendly) + worktrees on local NVMe; migrate git-data to Garage (Rust, S3-compatible, EU, light) only if fan-out bottlenecks. Managed Redis (EU) for hot ephemeral state; per-worktree lease in Postgres (crash-safe). Nomad over k8s. Route on a coordinator keyed by the lease, not CF sticky. Staged path = externalize-first.

## Capability Gaps

None. CTO confirmed execution is covered by existing agents: `platform-strategist` (topology),
`terraform-architect` (replace the single `hcloud_volume_attachment`, provision Nomad clients +
managed Redis), and `data-integrity-guardian` (session_placement / lease migration review).

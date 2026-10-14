---
title: "feat: Multi-host /workspaces layer for a cluster backend (staged Approach A)"
date: 2026-06-29
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5274
related: [5240, 5273, 5275, 5338, 5546, 5547, 5723]
branch: feat-multi-host-workspaces
pr: 5710
brainstorm: knowledge-base/project/brainstorms/2026-06-29-multi-host-workspaces-brainstorm.md
spec: knowledge-base/project/specs/feat-multi-host-workspaces/spec.md
adr: ADR-068
status: epic-plan
---

# ✨ Multi-host `/workspaces` layer for a cluster backend (staged Approach A)

> **Epic plan.** This sequences a multi-month architectural change into four
> forward-progress steps. Each step is large enough to warrant its **own**
> `/soleur:plan` + spec + PR at execution time; this document fixes the
> sequencing, the architecture decision (ADR-068), the IaC shape, and the
> brand/compliance envelope so the per-step plans inherit a settled frame.

## Enhancement Summary

**Deepened on:** 2026-06-29 (after a 3-agent plan-review panel)
**Deepen agents:** data-integrity-guardian, security-sentinel, architecture-strategist, learnings-researcher

### Key improvements
1. **Fencing is writer-side CAS, not a pre-check** (data-integrity): a generation check *before* the ref write is TOCTOU (a GC-paused holder passes the check, gets reclaimed, then writes). The git-data host must hold the per-ref monotonic max and atomically reject `gen < max` at the write. The lease itself mirrors the canonical `acquire_conversation_slot` shape (`029_*.sql:101-210`, `093_*.sql:50-125`): `pg_advisory_xact_lock` + `INSERT … ON CONFLICT DO UPDATE … WHERE heartbeat_at < now()-timeout RETURNING`, `gen+1` in-statement, server-side `now()`.
2. **ADR-027 is SUPERSEDED, ADR-059 RE-OPENED** (learnings): ADR-027 mandates supersession for any multi-replica diff; ADR-059 *explicitly rejected Redis* ("no multi-instance requirement exists") — this plan is the first to create that requirement.
3. **bwrap does not cover remote git-data** (security): the cross-tenant guard scopes sandboxed bash against local NVMe; the bare-repo fetch runs in the Node process. Remote git-data needs per-`workspace_id` credential/mTLS (reuse the `resolve_workspace_installation_id` membership-RPC shape) — never a cluster-wide mount cred.
4. **Replay frames are user content** (security): a shared-password network Redis is a cross-tenant content leak → TLS + per-`workspace_id` key namespacing + `requirepass`/ACL + private-subnet firewall.
5. **Coordinator is a stateless SPOF to replicate** (architecture): holds no live handles (lease in Postgres) → N replicas behind the one tunnel; record statelessness as an ADR-068 property. `abortSession` must return a found-count so the coordinator can distinguish "finished" from "lives remote."
6. **Secrets via `random_password` resource** (security + #5560): dissolves the operator-mint/PR-split; deliver via env, never argv (the Inngest Redis argv-leak bug).
7. **Redis moves to Phase 4a, not 3** (architecture): affinity keeps the buffer host-local-sufficient until a host *dies*.

### New considerations discovered
- Capture-before-cutover (#5542): never re-read the new empty store after a switch; capture old state first.
- Lease-reclaim sweep = Inngest **pure-TS** cron (`cron-workspace-sync-health.ts` shape, ADR-033) — not GH Actions, not the claude-spawn invariants.
- tfstate (R2, no client KMS) stores the Redis password + TLS key in plaintext — treat as secret-bearing.

## Overview

Today the backend is entirely single-host: one Hetzner server → one RWO block
volume (`apps/web-platform/infra/server.tf:937-940`) mounted `/mnt/data` →
container `/workspaces` → one Node process → in-memory state Maps. `ADR-027`
codifies a hard `replicas = 1` invariant; `ADR-059` puts the stream-replay buffer
in process memory assuming same-process reconnect. To go live and scale with real
users — for concurrent capacity, HA, GA-readiness, and cost bin-packing (all four
confirmed by the operator) — the `/workspaces` layer must become a cluster. This
is the explicit re-evaluation trigger for **#5274**.

The operator chose the maximum target on both axes: **one workspace's users
servable across multiple hosts concurrently**, and **failover invisible even on
unplanned crash, with near-zero loss of uncommitted (un-pushed) work**. Delivery
is **Approach A** — a staged path that reaches that full end-state, hardest-part
first, with the operator choosing which step gates GA.

**Architectural reframe (settled at brainstorm):** never have multiple hosts write
one git index (corrupts on any FS — a git property, not a storage one). "One
workspace spans hosts" = shared git **data** (objects/refs) + **per-user
worktrees** on host-local NVMe, collaboration mediated by git refs + a shared
state layer.

## Research Reconciliation — Spec vs. Codebase

The spec/brainstorm inherited "externalize the 7 ADR-027 Maps → Redis" from
ADR-027. Focused code research (2026-06-29) falsifies that as written — it is the
single most important correction this plan makes.

| Spec/brainstorm claim | Codebase reality (file:line) | Plan response |
|---|---|---|
| "Externalize the 7 process-local Maps to Redis" | Only **1 of 7** needs cross-host visibility AND is serializable: `userWorkspaces` (registry:46) — and it is **already** Postgres-backed via #5338 lazy-rehydrate. `activeTurnConversations` (registry:57) is serializable but read **only by the turn-owning host** during the grace window (Kieran) → host-local, no cross-host value. The other 5 hold **live handles** that cannot be serialized: `activeSessions` = AbortController + Promise resolvers (registry:34); `_locks` = Promise-chain mutex (workspace-permission-lock.ts:44); `pendingDisconnects` = `NodeJS.Timeout` (ws-handler.ts:345); `_ccBashGates` = AgentSession w/ resolvers (cc-dispatcher.ts:1178); `activeQueries` = Timers + live SDK `Query` + input queue (soleur-go-runner.ts:1727). The WS `sessions` map (defined `session-registry.ts:6`) holds the live socket — host-local by definition. | **No state externalization in Phase 1.** Live handles stay host-local *by nature* (a turn's AbortController/SDK-Query executes in the owning host's process; only that host can abort it). The cross-host control problem is solved by **affinity + a coordinator** (Phase 3) that routes control ops (abort, gate-resolve, grace) to the owning host — NOT by serializing handles, and NOT by a separate Phase-1 control-plane module. Redis enters in **Phase 4a** (deepen re-map — affinity keeps the buffer host-local-sufficient through Phase 3), scoped to the genuinely-hot shared structure (the ADR-059 replay buffer), once a host *death* can land a reconnect on another host. (Panel: DHH + Kieran + Simplicity.) |
| "Add a distributed concurrency counter" | Concurrency slots are **already** Postgres-backed (`concurrency.ts:77-129`, RPC `acquire/touch/release_conversation_slot`, table `user_concurrency_slots`). | Drop from scope — already multi-host-safe. Only the in-process **rate-limiters** (`start-session-rate-limit.ts:56`, `rate-limiter.ts:44`) are process-local; they are serializable timestamp windows, optionally externalized alongside the buffer in Phase 4a. |
| "Managed Redis (EU)" | Hetzner has **no** managed Redis. A self-hosted Redis already exists but is **loopback-only** (`infra/inngest-redis.conf:13` `bind 127.0.0.1`), serving **only** Inngest; the Node app has no Redis client dep. | Self-host a **dedicated, network-reachable** Redis on a Hetzner CAX node (TLS+auth, EU, no new sub-processor) per the IaC section. Must NOT be conflated with the loopback Inngest Redis (distinct node, port-binding, password var). |
| Stream-replay buffer "move to Redis" (ADR-059 follow-up) | The buffer is **fully serializable** (`stream-replay-buffer.ts:130-317` — strings/numbers/Frame arrays); counters intentionally **outlive** `clear()` so a resumed cursor never rewinds (honest refetch). | Movable to Redis in Phase 4a, but counter-outlives-clear semantics must be preserved exactly. |
| Ingress routing | **Cloudflare Tunnel is the only ingress** (`tunnel -> api` in model.c4); no load balancer. Client connects to `/ws` at `window.location.host` (`ws-client.ts:722`); affinity today is implicit (one host). | Routing (Phase 3) = keep ONE tunnel → a **coordinator that proxies to the lease-holder** over the private net (IaC recommendation (c)). Not CF sticky cookies (pin to a dead host on crash). |

## Implementation Phases

> Each phase below is its own PR (and likely its own `/soleur:plan`). Order de-risks
> by deferring every new substrate (Redis, shared store, Nomad) to the phase that
> actually needs it — plan-review (DHH/Kieran/Simplicity) collapsed the original
> 4-phase shape, killing a premature Phase-1 control-plane and deferring Redis to Phase 4a
> (the deepen pass re-mapped it from the plan-review's initial Phase 3 — affinity covers Phase 3).

### Phase 0 — ADR-068 + C4 (this epic's lifecycle, not deferred)
- [x] Author **ADR-068** "Multi-host `/workspaces` via shared git-data + per-user worktrees + lease-routed coordinator (rejecting Ceph/k8s)" via `/soleur:architecture` — `status: adopting`. Records: affinity-via-lease + coordinator-forwarded control (coordinator is **stateless** — N replicas behind one tunnel); live-handle state stays host-local; writer-side CAS fencing; self-host EU Redis; **GA gates at Phase 3 (OQ3 resolved by operator 2026-06-30)**.
- [x] **Supersede ADR-027** (not amend — ADR-027 self-mandates supersession for any multi-replica diff; mark it `superseded-by: ADR-068`). ADR-068 carries the Bucket-A migration: routing truth → Postgres (#5338, already there); `_locks` → per-workspace lease; live handles stay host-local + coordinator-routed control.
- [x] **Re-open ADR-059** (it explicitly rejected Redis: "no multi-instance requirement exists to justify it"). ADR-068 records that the multi-host move IS that requirement; the replay buffer migrates to Redis in **Phase 4a** (when a reconnect can land on a *different* host after a death — affinity covers Phase 3).
- [x] C4 edits (`model.c4` + `views.c4`) — see `## Architecture Decision (ADR/C4)`. (4 new infra elements + relationships; `likec4 validate` clean; all 4 render in the containers view.)

### Phase 1 — Host-local correctness (NO new infra; still `replicas = 1`)
- [ ] **TR2 host-local grace guard:** before `runDisconnectGraceAbort` (ws-handler.ts:228-240) aborts, confirm this host still owns the conversation (no live reconnect). On a single event loop this is **race-free** as today (cancel at :2893-2899 and fire are serialized) — no poll, no cross-host call. This is the seam Phase 3 will make affinity-correct.
- [ ] **Confirm `userWorkspaces` restart-survival** via the existing #5338 `resolveUserWorkspaceBinding` lazy-DB-rehydrate (registry:288-327, source `user_session_state.current_workspace_id`). The cross-host routing truth is **Postgres**, not a new store — no Redis in Phase 1.
- [ ] **Audit the legacy abort path:** confirm `agent-runner.ts:944` AbortController state rides inside `activeSessions` (registry:34) and is not an unrouted abort surface (ws-handler:2455 references legacy domain-leaders). Add `session-registry.ts` to the edit set.
- [ ] **Make `abortSession` return a found-count** (registry:190-213, currently void) — mirroring `drainAutonomousDisclosureGates` (cc-dispatcher.ts:1340-1361). A void return can't distinguish "turn already finished" from "lives on another host"; the found-count is the load-bearing affordance for the Phase-3 coordinator-forward decision. Harmless at `replicas=1`; required later.

### Phase 2 — Split git-data from worktrees + lease + fencing
- [ ] Bare git repos (objects/refs) on a shared store (new `git-data` host over private net); per-user worktrees on host-local NVMe (`worktree-manager.sh`, agent-runner).
- [ ] Per-worktree write-**lease** in Postgres (migration **114**) — durable + audit-visible. `{workspace_id, worktree_id, host_id, lease_generation, acquired_at, heartbeat_at}`. **Mirror the canonical `acquire_conversation_slot` precedent** (`029_plan_tier_and_concurrency_slots.sql:101-210`, re-issued `093_*.sql:50-125`) — do NOT invent a pattern:
  - Acquire/reclaim = ONE atomic statement under `pg_advisory_xact_lock(hashtextextended(workspace_id||worktree_id))`: `INSERT … ON CONFLICT (workspace_id, worktree_id) DO UPDATE SET host_id=excluded.host_id, lease_generation = <table>.lease_generation + 1, acquired_at=now(), heartbeat_at=now() WHERE <table>.heartbeat_at < now() - interval '120s' RETURNING host_id, lease_generation`. A live lease ⇒ zero rows ⇒ caller lost. `gen+1` happens **in-statement**, never app-side (no SELECT-then-INSERT TOCTOU).
  - Heartbeat via a `touch_worktree_lease` RPC returning row_count (mirror `touch_conversation_slot` 029:174-191) — a host learns its lease was reclaimed when it gets 0 rows.
  - Expiry uses **server-side `now()`** (one clock); hosts NEVER self-judge expiry (clock-skew hazard → fencing, not the timeout, is what makes reclaim safe).
  - **RLS:** `enable row level security` + `revoke all from anon, authenticated, public`; writes through `service_role` SECURITY DEFINER RPCs only (no write policies — mirror 029:88-93); SELECT gated on `is_workspace_member(workspace_id, auth.uid())` (059:71); `references workspaces(id) on delete cascade` (Art.17 erasure). Pin `set search_path = public, pg_temp` (`cq-pg-security-definer-search-path-pin-pg-temp`). `host_id` is infra identity — never an `auth.uid()=host_id` predicate (category error).
- [ ] **Fencing = writer-side CAS, NOT a pre-check (data-integrity — the real gap):** a separate generation check before the ref write is TOCTOU (a GC-paused holder reads gen=N still-current, gets reclaimed to N+1, resumes, writes — check passed, write corrupts). The **git-data host** holds the per-`(workspace,worktree)` monotonic max generation and **atomically rejects any write with `gen < max` (compare-and-write under a per-ref lock)** — the resource server enforces the token (Kleppmann), not the client. A pre-check RPC is insufficient.
- [ ] One-time cutover: drain sessions, rsync `objects/refs` to the shared store. GitHub remains the durable rehydration source (`ensure-workspace-repo.ts` self-heal, #5546).

### Phase 3 — 2nd host + coordinator routing (concurrent multi-host; GA line — OQ3)
- [ ] Add a 2nd `hcloud_server` + `hcloud_placement_group type=spread` (no Nomad yet — DHH: the Postgres lease is the placement authority, the coordinator is the router).
- [ ] **Coordinator** routes a session to the host holding/acquiring the workspace lease (keyed by the Postgres lease; consistent-hash as placement hint) AND **forwards control ops** (abort `registry:200-211`, gate-resolve `cc-dispatcher.ts:1296-1388`, grace) to the owning host — this is the cross-host seam that replaces the deferred Phase-1 control-plane. Edit the single tunnel's `service` target → coordinator (IaC option c).
- [ ] **Affinity (TR2 cross-host fix, Kieran):** a reconnect routes back to the lease-holding host, keeping grace cancel host-local — avoids the TOCTOU poll a cross-host check would introduce. (Affinity keeps the replay buffer host-local-sufficient in Phase 3 — Redis-backing the buffer is deferred to Phase 4a, where a host *death* sends a reconnect to a different host.)
- [ ] **Cross-tenant git-data isolation (security — load-bearing, new TR):** the bwrap `denyRead:["/workspaces"]` guard (`agent-runner-sandbox-config.ts:94`) does NOT cover remote git-data — the bare-repo fetch runs in the Node process (`ensure-workspace-repo.ts`, `git-auth.ts`), outside the sandbox. Network access to git-data MUST enforce **per-`workspace_id` credential/mTLS** (reuse the `resolve_workspace_installation_id` membership-RPC shape — per-workspace token, NULL for non-members), never a cluster-wide mount cred; encryption-at-rest on the git-data volume.
- [ ] **Coordinator authz (security):** **mTLS coordinator↔host** + the **owning host re-verifies** the requester owns the target conversation/lease before honoring any forwarded control op (defense-in-depth, not trust-the-coordinator). Control + Redis ports firewalled to the private subnet, no public IP.
- [ ] **G1 achieved:** two users on one workspace, served by two hosts, each on their own worktree (no shared index).

### Phase 4a — Nomad + health-reschedule + lease-expiry reclaim + Redis buffer (seamless crash recovery of committed state)
- [ ] Introduce **Nomad** (placement, health-reschedule, rolling deploys) — earns its cost here, where host-death detection + reschedule are the requirement.
- [ ] **Lease-expiry reclaim as an Inngest pure-TS cron** `cron-worktree-lease-reclaim.ts` (mirror `cron-workspace-sync-health.ts` reconciler shape per ADR-033 — NOT GH Actions, NOT the claude-spawn invariants I1-I8; no agent spawn) + a Sentry cron monitor: a dead host's leases time out, a surviving host reclaims with `gen+1` (same fenced conditional upsert) + re-provisions (re-clone from shared store / GitHub).
- [ ] **Redis enters here** (deferred from Phase 3): self-hosted EU Redis (dedicated node, **TLS-in-transit**, `requirepass`/ACL, `protected-mode yes`, firewalled to the private subnet, no public IP — inverts every loopback-Inngest assumption). Move the ADR-059 replay buffer (`stream-replay-buffer.ts:130-317`, **preserve counter-outlives-clear**) with **per-`workspace_id` key namespacing** (replay frames carry user content — assistant output/tool results/file content — NOT low-sensitivity routing metadata) + app-layer scope-check on read + TTL ≤ conversation retention. Secrets via a **`random_password` TF resource → `doppler_secret`** (dissolves the operator-mint/PR-split) delivered to the daemon via **env, never argv** (#5560 Inngest argv-leak precedent).
- [ ] **Capture-before-cutover** (#5542): when migrating buffer/state to Redis, capture the OLD in-process state to a persistent medium FIRST; never re-read the new (empty) Redis after the switch and silently lose state.
- [ ] FR5: the coordinator places a session on a host **before** session start, so the bwrap sandbox mount set + `cwd` (frozen per `query()`, #5313 lineage) are never re-derived mid-turn.

### Phase 4b — Continuous worktree checkpoint (the expensive tail — build after evidence)
- [ ] **Continuous worktree checkpoint** of uncommitted state to the durability store (extends #5275) — the ONLY thing that makes "near-zero *uncommitted* loss on crash" (G2) real; disposable worktrees + GitHub-rehydration already recover *committed* state. Cadence/mechanism = OQ2. Panel (Simplicity): most likely built-but-not-needed — build only after a real crash-loss incident or once the operator confirms G2 must hold at GA.

## Files to Create
- `knowledge-base/engineering/architecture/decisions/ADR-068-*.md` (Phase 0)
- `apps/web-platform/supabase/migrations/114_worktree_write_lease.sql` (+ `.down.sql`) (Phase 2; includes `lease_generation` fencing column)
- `apps/web-platform/infra/git-data.tf` (Phase 2)
- `apps/web-platform/server/session-coordinator.ts` — lease-keyed routing + cross-host control forwarding (Phase 3; subsumes the dropped control-plane module)
- `apps/web-platform/server/session-store.ts` — typed Redis adapter, scoped to the replay buffer (Phase 4a)
- `apps/web-platform/infra/network.tf` (Phase 2; `hcloud_network` + subnet for the private git-data path)
- coordinator service def (Phase 3); `nomad.tf` / Nomad jobspec (Phase 4a)
- `apps/web-platform/server/inngest/functions/cron-worktree-lease-reclaim.ts` — pure-TS stale-lease reclaim sweep (mirror `cron-workspace-sync-health.ts`, ADR-033; NOT GH Actions) + Sentry cron monitor (Phase 4a)
- `apps/web-platform/infra/redis-session.tf` + `redis-session-bootstrap.sh` (Phase 4a; TLS + `random_password` + `doppler_secret`)

## Files to Edit
- `apps/web-platform/server/ws-handler.ts` (grace timer :209,:228-240,:345,:2893-2970) — Phase 1
- `apps/web-platform/server/session-registry.ts` (WS `sessions` map :6) — Phase 1 (Kieran: missed in v1)
- `apps/web-platform/server/agent-session-registry.ts` (Maps :34,:46,:57; broadcast abort :200-211) — Phase 1 audit / Phase 3 routing
- `apps/web-platform/server/agent-runner.ts` (legacy AbortController :944) — Phase 1 audit
- `apps/web-platform/server/cc-dispatcher.ts` (`_ccBashGates` :1178,:1296-1388) — Phase 3 control-forward
- `apps/web-platform/server/soleur-go-runner.ts` (`activeQueries` :1727,:2017,:2654) — Phase 3/4a
- `apps/web-platform/server/workspace-permission-lock.ts` (`_locks` :44) — Phase 2/3
- `apps/web-platform/server/stream-replay-buffer.ts` (:130-317) — Phase 4a (Redis-back, keep counter-outlives-clear)
- `apps/web-platform/lib/ws-client.ts` (reconnect/route awareness :722) — Phase 3
- `apps/web-platform/infra/server.tf`, `firewall.tf`, `variables.tf`, `tunnel.tf` — Phase 2/3
- `apps/web-platform/package.json` (Node Redis client dep) — Phase 4a
- `knowledge-base/engineering/architecture/decisions/ADR-027-*.md` (supersede — `superseded-by: ADR-068`, not amend), `model.c4`, `views.c4` — Phase 0

## User-Brand Impact

**If this lands broken, the user experiences:** their conversation resumes on a
different host showing a blank/fresh workspace (the exact #5240 regression), a
half-finished turn silently lost, or — worst — another tenant's repo.

**If this leaks, the user's data/workflow is exposed via:** shared git-data or
session-Redis without per-tenant scoping letting one host read another tenant's
cloned repo, source, or secrets; or a worktree checkpoint/snapshot copied to a
store that survives erasure.

**Brand-survival threshold:** single-user incident.

CPO sign-off carried forward from the 2026-06-29 brainstorm (`USER_BRAND_CRITICAL`
triad). `user-impact-reviewer` runs at each step's PR review.

## Acceptance Criteria

### Per-step (each is its own PR's pre-merge gate)
- **Phase 1 (no infra):** `tsc --noEmit` clean; the grace-abort path is gated on a
  host-local owning-host check (unit test: a reconnect before fire cancels the
  abort — same-event-loop, no poll); an integration test against **dev** Supabase
  (never prod — `hr-dev-prd`) shows a process restart preserves the
  workspace binding via #5338 rehydrate; the legacy `agent-runner.ts:944` abort is
  confirmed routed through `activeSessions` (grep + test).
- **Phase 2:** migration 114 applies + reverses on dev; **two concurrent acquires
  from two hosts → exactly one row / one holder, the loser gets a zero-row return**
  (atomicity test); a write at `gen=N` is **rejected by the git-data host after any
  `gen>N` has been observed, even if the holder still believes it holds N** (fencing
  CAS test — the load-bearing AC, sharper than heartbeat timeout); lease table is
  `revoke`d from anon/authenticated, SELECT gated by `is_workspace_member`,
  cascade-deletes on workspace erasure; bare-data cutover loses no refs (pre/post
  `git rev-list --all` count match, capture-first).
- **Phase 3:** two users on one workspace served by two hosts each operate their
  own worktree with no git-index corruption (G1); **host-A credentials CANNOT read
  tenant-B bare objects on git-data** (network-level negative test, mirror
  `sandbox-isolation.test.ts` AC7-negative); **a control op forged from a non-owning
  identity is rejected at the owning host** (authz re-check, not just routed);
  abort/gate/grace issued on host B for a turn on host A routes to host A; a reconnect
  routes back to the lease-holder (affinity test); a drain/deploy is invisible to an
  active user; `grep` proves `SESSION_REDIS_PASSWORD`/TLS key absent from committed
  `.tf`, config, cloud-init, and bootstrap logs.
- **Phase 4a:** replay buffer survives a cross-host reconnect with counter-no-rewind;
  a Redis key read for workspace-B under workspace-A's scope is denied; buffer TTL ≤
  conversation retention asserted.
- **Phase 4a:** a killed host mid-turn → session resumes on a surviving host with a
  **new `lease_generation`**, no silent fresh-session greeting, committed/pushed work
  intact (G2 for committed state).
- **Phase 4b:** uncommitted work loss on crash is **bounded by the checkpoint
  cadence N** and never *silent* — once OQ2 fixes N, the AC is "≤ N s loss, surfaced
  honestly." (Not a fixed-N AC while N is an open question — Kieran.)

### Cross-cutting (all phases)
- No cross-tenant workspace readable from another tenant's host (G4); per-tenant
  path + credential scoping + encryption-at-rest on every new store.
- DSAR/Art. 17 erasure reaches worktree checkpoints/snapshots; snapshot TTL ≤
  conversation retention.

### Post-merge (operator) — per step
- IaC apply is auto-applied by `apply-web-platform-infra.yml` on `infra/*.tf` merge
  (PR-A provisions Doppler `prd_terraform` vars first — see IaC). `Ref #5274` (not
  `Closes`) until Phase 4 completes the epic.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Operations (carried forward from
the 2026-06-29 brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward + this plan's research)
**Assessment:** Host-affinity + re-clone over shared NFS for the naive case; the
max bar forces externalized state + shared git-data + control-plane. The
cross-host grace-timer abort is a correctness bug (TR2), neutralized by routing
control ops to the owning host. The serializable-vs-live-handle split (Research
Reconciliation) is the load-bearing refinement to ADR-027.

### Product/UX Gate
**Tier:** none
**Decision:** n/a — no UI surface. The change is backend infra/orchestration; the
user-visible contract (continuity, no fresh-session greeting, no wrong-tenant) is
captured in User-Brand Impact + ACs, not new pages/components.
**Pencil available:** N/A (no UI surface)

### Legal (CLO) + GDPR Gate (Phase 2.7)
**Status:** reviewed (carry-forward; full `/soleur:gdpr-gate` deferred to each
step's PR where the concrete regulated-data surface — migration 114, the
session-Redis payload, the checkpoint store — actually materializes).
**Findings:** Each new substrate is a GDPR Art. 30 record-of-processing entry,
EU-region pinned. Self-hosting Redis + git-data on Hetzner EU adds **no new
sub-processor** (the deciding reason to self-host over Upstash/Aiven). Cross-region
replication or any CDN/edge-cached store **breaches residency** — disallow.
Per-tenant isolation (path + credential scoping, encryption-at-rest) and
erasure-reaching-snapshots are GA-blocking. Carry-forward from #5273/ADR-059:
persisted substrate TTL ≤ conversation retention.

### Operations (COO)
**Status:** carry-forward — operational burden of self-hosted Redis + Nomad + a
shared git-data host is a first-class cost; the light path (no Ceph/k8s) was chosen
to bound it. Per-step PRs must add Better Stack monitors (Observability).

## Infrastructure (IaC)

### Terraform changes
Root: `apps/web-platform/infra/`. Providers/pins unchanged (`hcloud ~>1.49`,
`cloudflare ~>4.0`, `random`, `doppler ~>1.21`, `tls ~>4.0`, `required_version
>= 1.6`). No Nomad/Redis TF provider — Nomad agents + the session-Redis daemon
install via cloud-init + idempotent bootstrap (mirroring `inngest-redis-bootstrap.sh`).
> **Note (phase re-map after deepen):** the deepen pass moved Redis to **Phase 4a**
> (affinity covers Phase 3) and confirmed `random_password` dissolves the operator-mint
> split. Steps below are re-keyed to the revised phases.
- **Phase 2:** new `network.tf` (`hcloud_network` + subnet — removes the
  everything-on-loopback assumption; needed first for the private git-data path); new
  `git-data.tf` host exporting bare repos over the private net — the RWO
  `hcloud_volume.workspaces` single-attach **cannot** back multiple clients (the
  single-host assumption being removed). Worktrees → each client's local NVMe via
  cloud-init. Lease table is a Supabase migration (114), not TF.
- **Phase 3:** `hcloud_placement_group` (`type="spread"`) + a 2nd `hcloud_server`;
  convert `hcloud_server.web` to `for_each`/`count` with **`moved` blocks** (else
  reads as destroy+create — verify plan is `0 to destroy`); coordinator service +
  tunnel `service` edit.
- **Phase 4a:** new `redis-session.tf` (dedicated CAX/ARM `hcloud_server`, AOF
  `hcloud_volume`, **TLS** via the `tls` provider, firewall 6379 from the private
  subnet only, no public IP); `nomad.tf`; per-host `betteruptime` monitors.
  reschedule/checkpoint logic = Nomad jobspec + app, not TF.

**Secrets via `random_password` resource (dissolves the operator-mint trap — security
+ #5560):** do NOT declare `session_redis_password` as a no-default TF variable (that
would trip the `apply-web-platform-infra.yml` auto-apply fail-closed and force a
PR-A/PR-B split). Instead generate it **in-band**: `random_password` → `doppler_secret`
(masked, `lifecycle.ignore_changes=[value]`) → delivered to the daemon as the env var
`$SESSION_REDIS_PASSWORD`, which the bootstrap writes into the Redis **conf file's
`requirepass` directive** (the argv-safe path the loopback Inngest Redis already uses —
`inngest-redis.conf`). Do **NOT** pass it as a `redis-server --requirepass "$VAR"` CLI
flag: that re-exposes the secret on `/proc/<pid>/cmdline` / `ps`, the exact #5560
argv-leak class. No operator mint, no split.
**tfstate caveat:** `random_password.result` + the `tls`-generated Redis key land in
`terraform.tfstate` plaintext (R2, Cloudflare-managed encryption only, no client KMS);
treat tfstate as secret-bearing — R2 credential scope is the control.

### Apply path
- **Phase 2:** highest blast radius (data move off the shared volume); new git-data
  host + `network.tf` are `+create`, cutover is a drained one-time rsync of
  `objects/refs` (capture-first per #5542). Lease table = online Supabase migration (114).
- **Phase 3:** adding a 2nd server is `+create`; the `for_each` refactor needs `moved`
  blocks → verify `0 to destroy`; coordinator + tunnel `service` edit.
- **Phase 4a:** Redis node + Nomad via cloud-init + idempotent bootstrap = pure
  `+create`, zero downtime to the web host (no operator mint — `random_password`).
- **Tunnel → multi-host (open):** (a) multiple `cloudflared` replicas — CF
  load-balances but is **not lease-aware** (wrong host); (b) Cloudflare Load
  Balancer + origin pools (paid, still not lease-aware); (c) **recommended** — keep
  ONE tunnel → a coordinator that proxies to the lease-holder over the private net
  (edits `tunnel.tf` `service` target only).

### Distinctness / drift safeguards
- Root is **prd-only**; dev is a separate Supabase project (`hr-dev-prd`) — never
  share session-Redis creds across configs.
- R2 backend has **no lock** (`use_lockfile=false`); GHA concurrency group
  `terraform-apply-web-platform-host` is the sole serializer — `for_each` state
  churn must not race it.
- `lifecycle.ignore_changes` on new-node `user_data` (bootstrap-driven), as
  `tunnel.tf` already does.
- The new session Redis is a **distinct resource** from the loopback Inngest Redis
  (`inngest-redis.conf` `bind 127.0.0.1`, AOF, dedicated Supabase project). Different
  node, port-binding, password var (`session_redis_password` ≠
  `INNGEST_REDIS_PASSWORD`). Do not co-locate or conflate.

### Vendor-tier reality check
Hetzner has **no managed Redis**. Self-host on a dedicated Hetzner CAX node
(TLS+auth) — cheapest, EU-resident by construction, **no new sub-processor/DPA**,
reuses the AOF+`--requirepass` precedent; cost is you own failover. Alternatives
(Upstash EU free 256MB / Redis Cloud EU / Aiven EU) each add a new sub-processor →
GDPR DPA. **Recommendation: self-host on a dedicated Hetzner CAX node.** Revisit
only if HA failover ops become the bottleneck. *Verify current pricing at the
provider page before budget decisions.*

## Observability

```yaml
liveness_signal:
  what: session-Redis PING + coordinator /healthz + per-host Nomad client status
  cadence: 60s
  alert_target: Better Stack (uptime monitor per host + Redis node)
  configured_in: apps/web-platform/infra/*.tf (betteruptime_monitor) + infra/sentry/*.tf
error_reporting:
  destination: Sentry (server) — new op slugs: session_store_op, control_plane_route, worktree_lease, worktree_checkpoint
  fail_loud: true (mirror silent fallbacks via reportSilentFallback; cq-silent-fallback-must-mirror-to-sentry)
failure_modes:
  - {mode: session-Redis unreachable, detection: client connect error + PING monitor, alert_route: Better Stack + Sentry}
  - {mode: lease acquire conflict / orphaned lease, detection: control_plane_route + worktree_lease op slug, alert_route: Sentry issue alert}
  - {mode: cross-host abort fails to route (TR2), detection: control_plane_route error, alert_route: Sentry}
  - {mode: worktree checkpoint lag/fail, detection: worktree_checkpoint op slug + lag metric, alert_route: Sentry}
  - {mode: host down / reschedule, detection: Nomad client status + per-host uptime monitor, alert_route: Better Stack}
logs:
  where: pino → existing server log pipeline; Inngest/coordinator structured logs
  retention: per existing retention (EU)
discoverability_test:
  command: "curl -sf https://<coordinator-health-route>/healthz && gh api /organizations/<org>/monitors (no shell access required)"
  expected_output: "200 OK + session_store/lease/control_plane op slugs present in Sentry"
```

## Architecture Decision (ADR/C4)

### ADR
- **Create ADR-068** "Multi-host `/workspaces` via shared git-data + per-user
  worktrees + lease-routed coordinator (rejecting Ceph/k8s)" (`status: adopting`).
  Records: affinity-via-Postgres-lease + coordinator-forwarded control; rejection of
  Ceph/k8s and shared-NFS for the live tree; self-hosted EU Redis (Phase 4a, replay
  buffer scope) over managed; `lease_generation` fencing.
- **Supersede ADR-027** (`superseded-by: ADR-068` — ADR-027 self-mandates supersession
  for any multi-replica diff, not an amend): records that live-handle state stays
  host-local and cross-host control routes via the (stateless) coordinator; the
  Bucket-A migration is routing-truth→Postgres + `_locks`→per-workspace lease; add
  "externalize-all-7-Maps to Redis" to `## Alternatives Considered` as rejected
  (5 of 7 hold AbortControllers/timers/SDK Query).
- **Re-open ADR-059** (it rejected Redis: "no multi-instance requirement exists") —
  ADR-068 records the multi-host move as that requirement; the buffer migrates to
  Redis in Phase 4a, preserving counter-outlives-clear.
- ADR-068 records the **coordinator-statelessness** property (holds no live handles →
  N replicas behind one tunnel) as load-bearing.

### C4 views
Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`).
`spec.c4` defines only element kinds (actor/system/container/database/component +
`external` tag) — the new elements are existing kinds, so **spec.c4 needs no change**.
The **Container view** (`view containers of platform`) changes:
- **New `infra` elements (model.c4):** `sessionStore` (database, "Self-hosted Redis
  — session state, control-plane, replay buffer; network-reachable, EU"),
  `gitDataStore` (database, "Shared bare git repos (objects/refs) over private net"),
  `scheduler` (container, "Nomad — placement/reschedule/rolling deploy"),
  `coordinator` (container, "Stateless — routes a session to the lease-holding host
  and forwards control ops; N replicas behind the tunnel, lease in Postgres"). Edit
  `hetzner` description: single host → cluster of Nomad clients (spread placement).
- **New relationships (model.c4):** `api -> sessionStore`, `claude -> sessionStore`,
  `coordinator -> claude "Places/routes sessions (lease-keyed)"`, `claude ->
  gitDataStore "Bare repo data; worktrees local"`, `scheduler -> hetzner
  "Schedules"`, `coordinator -> supabase "Reads worktree lease"`, `tunnel ->
  coordinator "Routes traffic"` (replaces `tunnel -> api` ingress shape).
- **`views.c4`:** add the 4 new elements to the `view containers of platform`
  `include` block so they RENDER.
- Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after
  editing (a `view include` of an undefined element fails there, not at `tsc`).

## Risks & Mitigations
- **Live-handle state can't move to Redis** → host-local *by nature* (a turn's
  AbortController/SDK-Query executes in the owning host's process); cross-host
  control is routed by the Phase-3 coordinator, not serialized.
- **Concurrent git writers corrupt the index** → bare-data + per-user worktrees +
  Postgres single-writer lease; never a shared working tree.
- **Cross-host grace-abort kills a live session (TR2)** → Phase-1 host-local guard
  (race-free on one event loop); Phase-3 **affinity** (reconnect routes to the
  lease-holder, cancel stays host-local). Never a cross-host poll — that reintroduces
  a TOCTOU race (Kieran).
- **Pre-check ≠ atomic fence (TOCTOU)** → a generation check *before* the ref write
  lets a GC-paused holder pass the check then write post-reclaim. The git-data host
  holds the per-ref monotonic max and **CAS-rejects `gen < max` at the write** (Phase
  2). Fencing — not the heartbeat timeout — is the load-bearing invariant.
- **Clock skew across hosts** → expiry uses server-side Postgres `now()` only; hosts
  never self-judge expiry; a stalled host past timeout is safe *because* of fencing.
- **bwrap `denyRead:["/workspaces"]` does NOT cover remote git-data** → the bare-repo
  fetch runs in the Node process outside the sandbox; per-`workspace_id` network authz
  is the only guard (Phase 3, new TR).
- **session-Redis replay frames contain user content** → a shared-password Redis with
  no per-tenant key scoping is a cross-tenant content leak → TLS + per-`workspace_id`
  namespacing (Phase 4a).
- **Coordinator is a new process-level SPOF/bottleneck** → it holds no live handles
  (lease in Postgres) → **stateless, N replicas behind the one tunnel**; single
  instance acceptable for a Phase-3 GA line with honest reconnect (recorded in ADR-068).
- **tfstate is secret-bearing** → `random_password.result` + the Redis TLS key land in
  `terraform.tfstate` (R2, Cloudflare-managed encryption, no client KMS, no lockfile);
  R2 credential scope is the control. Deliver secrets via env, never argv (#5560).
- **Store-switch silently loses state** → capture old in-process state before the
  Redis cutover; never re-read the new empty store (#5542).
- **Session-Redis (Phase 4a) is a new SPOF** → HA failover deferred until ops demands
  it (single-instance + AOF as the Inngest precedent); honest reconnect covers a blip.
- **Shared git-data host is a residual SPOF** vs "user never notices a crash" →
  #5723 (Garage migration) closes it; gated on which phase gates GA (OQ1).
- **Checkpoint cost** (Phase 4b) → cadence/mechanism is OQ2; build only after a real
  crash-loss incident (panel: most likely built-but-not-needed).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder, or omits the threshold will fail `deepen-plan` Phase
  4.6. (This plan's is filled; threshold = single-user incident.)
- Each per-step PR MUST run `/soleur:gdpr-gate` when its concrete migration/schema
  surface materializes — the epic-level carry-forward is not a substitute.
- Dev verification for any phase must use **dev** substrates — never prod
  (`hr-dev-prd-distinct-supabase-projects`): the Phase-2 lease migration against dev
  Supabase, and (Phase 4a) a **dev** Redis, never prod.

## Open Questions (carry to deepen-plan / per-step plans)
1. Shared git-data SPOF: Garage (#5723) from the start vs GitHub-rehydration +
   brief re-clone — gated on which phase gates GA.
2. Worktree-checkpoint cadence/mechanism (shadow-branch vs rsync; value of N for
   "near-zero loss") — Phase 4b.
3. ~~Which phase gates GA~~ **RESOLVED (operator decision, 2026-06-30): Phase 3.**
   Concurrent multi-host, planned-move seamless, committed-state-durable is the GA
   line (panel + deepen consensus). **Phase 4a** (seamless unplanned crash) and
   **Phase 4b** (near-zero uncommitted loss) are **post-GA hardening**, built against
   real load / a real crash-loss incident — not on the GA-blocking path. Recorded as
   a load-bearing property in ADR-068 (Decision §8).
4. ~~Control-plane substrate~~ **RESOLVED (panel + deepen precedent-diff):** the
   Phase-3 coordinator reads the lease and forwards control ops by RPC to the owning
   host; no Redis pub/sub. Deepen confirmed this is a **clean extension** of the
   existing in-process control (`abortSession` registry:190-213, `resolveCcBashGate`
   cc-dispatcher.ts:1281-1328): WS frame → local resolver → on not-found, RPC-forward
   to the lease-holder → same resolver there; it **composes** with the existing
   intra-host prefix broadcast (registry:206-212), does not replace it. Required
   change: `abortSession` returns a found-count (Phase 1) so "finished" vs "lives
   remote" is distinguishable.

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
| "Externalize the 7 process-local Maps to Redis" | Only **1 of 7** needs cross-host visibility AND is serializable: `userWorkspaces` (registry:46) — and it is **already** Postgres-backed via #5338 lazy-rehydrate. `activeTurnConversations` (registry:57) is serializable but read **only by the turn-owning host** during the grace window (Kieran) → host-local, no cross-host value. The other 5 hold **live handles** that cannot be serialized: `activeSessions` = AbortController + Promise resolvers (registry:34); `_locks` = Promise-chain mutex (workspace-permission-lock.ts:44); `pendingDisconnects` = `NodeJS.Timeout` (ws-handler.ts:345); `_ccBashGates` = AgentSession w/ resolvers (cc-dispatcher.ts:1178); `activeQueries` = Timers + live SDK `Query` + input queue (soleur-go-runner.ts:1727). The WS `sessions` map (defined `session-registry.ts:6`) holds the live socket — host-local by definition. | **No state externalization in Phase 1.** Live handles stay host-local *by nature* (a turn's AbortController/SDK-Query executes in the owning host's process; only that host can abort it). The cross-host control problem is solved by **affinity + a coordinator** (Phase 3) that routes control ops (abort, gate-resolve, grace) to the owning host — NOT by serializing handles, and NOT by a separate Phase-1 control-plane module. Redis enters in **Phase 3**, scoped to the genuinely-hot shared structure (the ADR-059 replay buffer), once a reconnect can land on another host. (Panel: DHH + Kieran + Simplicity.) |
| "Add a distributed concurrency counter" | Concurrency slots are **already** Postgres-backed (`concurrency.ts:77-129`, RPC `acquire/touch/release_conversation_slot`, table `user_concurrency_slots`). | Drop from scope — already multi-host-safe. Only the in-process **rate-limiters** (`start-session-rate-limit.ts:56`, `rate-limiter.ts:44`) are process-local; they are serializable timestamp windows, optionally externalized in 1a. |
| "Managed Redis (EU)" | Hetzner has **no** managed Redis. A self-hosted Redis already exists but is **loopback-only** (`infra/inngest-redis.conf:13` `bind 127.0.0.1`), serving **only** Inngest; the Node app has no Redis client dep. | Self-host a **dedicated, network-reachable** Redis on a Hetzner CAX node (TLS+auth, EU, no new sub-processor) per the IaC section. Must NOT be conflated with the loopback Inngest Redis (distinct node, port-binding, password var). |
| Stream-replay buffer "move to Redis" (ADR-059 follow-up) | The buffer is **fully serializable** (`stream-replay-buffer.ts:130-317` — strings/numbers/Frame arrays); counters intentionally **outlive** `clear()` so a resumed cursor never rewinds (honest refetch). | Movable to Redis in 1a, but counter-outlives-clear semantics must be preserved exactly. |
| Ingress routing | **Cloudflare Tunnel is the only ingress** (`tunnel -> api` in model.c4); no load balancer. Client connects to `/ws` at `window.location.host` (`ws-client.ts:722`); affinity today is implicit (one host). | Routing (Step 3) = keep ONE tunnel → a **coordinator that proxies to the lease-holder** over the private net (IaC recommendation (c)). Not CF sticky cookies (pin to a dead host on crash). |

## Implementation Phases

> Each phase below is its own PR (and likely its own `/soleur:plan`). Order de-risks
> by deferring every new substrate (Redis, shared store, Nomad) to the phase that
> actually needs it — plan-review (DHH/Kieran/Simplicity) collapsed the original
> 4-phase shape, killing a premature Phase-1 control-plane and deferring Redis to Phase 3.

### Phase 0 — ADR-068 + C4 (this epic's lifecycle, not deferred)
- [ ] Author **ADR-068** "Multi-host `/workspaces` via shared git-data + per-user worktrees + lease-routed coordinator (rejecting Ceph/k8s)" via `/soleur:architecture` — `status: adopting` (describes target state; the phases realize it). Amend ADR-027 (`## Decision` gains: live-handle state stays host-local, only routing truth is shared; cross-host control routes via the coordinator) and reference ADR-059.
- [ ] C4 edits (`model.c4` + `views.c4`) — see `## Architecture Decision (ADR/C4)`.

### Phase 1 — Host-local correctness (NO new infra; still `replicas = 1`)
- [ ] **TR2 host-local grace guard:** before `runDisconnectGraceAbort` (ws-handler.ts:228-240) aborts, confirm this host still owns the conversation (no live reconnect). On a single event loop this is **race-free** as today (cancel at :2893-2899 and fire are serialized) — no poll, no cross-host call. This is the seam Phase 3 will make affinity-correct.
- [ ] **Confirm `userWorkspaces` restart-survival** via the existing #5338 `resolveUserWorkspaceBinding` lazy-DB-rehydrate (registry:288-327, source `user_session_state.current_workspace_id`). The cross-host routing truth is **Postgres**, not a new store — no Redis in Phase 1.
- [ ] **Audit the legacy abort path:** confirm `agent-runner.ts:944` AbortController state rides inside `activeSessions` (registry:34) and is not an unrouted abort surface (ws-handler:2455 references legacy domain-leaders). Add `session-registry.ts` to the edit set.

### Phase 2 — Split git-data from worktrees + lease + fencing
- [ ] Bare git repos (objects/refs) on a shared store (new `git-data` host over private net); per-user worktrees on host-local NVMe (`worktree-manager.sh`, agent-runner).
- [ ] Per-worktree write-**lease** in Postgres (migration **114**) — durable + audit-visible. `{workspace_id, worktree_id, host_id, lease_generation, acquired_at, heartbeat_at}`. **Fencing token (Kieran):** the monotonic `lease_generation` MUST be checked at the git-data ref-write boundary — durability alone does NOT prevent the netsplit double-write; a stale generation is rejected at write time.
- [ ] One-time cutover: drain sessions, rsync `objects/refs` to the shared store. GitHub remains the durable rehydration source (`ensure-workspace-repo.ts` self-heal, #5546).

### Phase 3 — 2nd host + coordinator routing + Redis (concurrent multi-host)
- [ ] Add a 2nd `hcloud_server` + `hcloud_placement_group type=spread` (no Nomad yet — DHH: the Postgres lease is the placement authority, the coordinator is the router).
- [ ] **Coordinator** routes a session to the host holding/acquiring the workspace lease (keyed by the Postgres lease; consistent-hash as placement hint) AND **forwards control ops** (abort `registry:200-211`, gate-resolve `cc-dispatcher.ts:1296-1388`, grace) to the owning host — this is the cross-host seam that replaces the deferred Phase-1 control-plane. Edit the single tunnel's `service` target → coordinator (IaC option c).
- [ ] **Affinity (TR2 cross-host fix, Kieran):** a reconnect routes back to the lease-holding host, keeping grace cancel host-local — avoids the TOCTOU poll a cross-host check would introduce.
- [ ] Introduce **Redis** here, scoped to the ADR-059 replay buffer (`stream-replay-buffer.ts:130-317`, **preserving counter-outlives-clear**) + any shared hot routing cache, now that a reconnect can land on another host. IaC PR-A/PR-B split (below).
- [ ] **G1 achieved:** two users on one workspace, served by two hosts, each on their own worktree (no shared index).

### Phase 4a — Nomad + health-reschedule + lease-expiry reclaim (seamless crash recovery of committed state)
- [ ] Introduce **Nomad** (placement, health-reschedule, rolling deploys) — earns its cost here, where host-death detection + reschedule are the requirement.
- [ ] Lease-expiry reclaim (fenced): a dead host's leases time out; a surviving host reclaims with a new `lease_generation` + re-provisions (re-clone from shared store / GitHub).
- [ ] FR5: the coordinator places a session on a host **before** session start, so the bwrap sandbox mount set + `cwd` (frozen per `query()`, #5313 lineage) are never re-derived mid-turn.

### Phase 4b — Continuous worktree checkpoint (the expensive tail — build after evidence)
- [ ] **Continuous worktree checkpoint** of uncommitted state to the durability store (extends #5275) — the ONLY thing that makes "near-zero *uncommitted* loss on crash" (G2) real; disposable worktrees + GitHub-rehydration already recover *committed* state. Cadence/mechanism = OQ2. Panel (Simplicity): most likely built-but-not-needed — build only after a real crash-loss incident or once the operator confirms G2 must hold at GA.

## Files to Create
- `knowledge-base/engineering/architecture/decisions/ADR-068-*.md` (Phase 0)
- `apps/web-platform/supabase/migrations/114_worktree_write_lease.sql` (+ `.down.sql`) (Phase 2; includes `lease_generation` fencing column)
- `apps/web-platform/infra/git-data.tf` (Phase 2)
- `apps/web-platform/server/session-coordinator.ts` — lease-keyed routing + cross-host control forwarding (Phase 3; subsumes the dropped control-plane module)
- `apps/web-platform/server/session-store.ts` — typed Redis adapter, scoped to the replay buffer (Phase 3)
- `apps/web-platform/infra/network.tf`, `redis-session.tf`, `redis-session-bootstrap.sh` (Phase 3)
- coordinator service def + `nomad.tf` / Nomad jobspec (Phase 4a)

## Files to Edit
- `apps/web-platform/server/ws-handler.ts` (grace timer :209,:228-240,:345,:2893-2970) — Phase 1
- `apps/web-platform/server/session-registry.ts` (WS `sessions` map :6) — Phase 1 (Kieran: missed in v1)
- `apps/web-platform/server/agent-session-registry.ts` (Maps :34,:46,:57; broadcast abort :200-211) — Phase 1 audit / Phase 3 routing
- `apps/web-platform/server/agent-runner.ts` (legacy AbortController :944) — Phase 1 audit
- `apps/web-platform/server/cc-dispatcher.ts` (`_ccBashGates` :1178,:1296-1388) — Phase 3 control-forward
- `apps/web-platform/server/soleur-go-runner.ts` (`activeQueries` :1727,:2017,:2654) — Phase 3/4a
- `apps/web-platform/server/workspace-permission-lock.ts` (`_locks` :44) — Phase 2/3
- `apps/web-platform/server/stream-replay-buffer.ts` (:130-317) — Phase 3 (Redis-back, keep counter-outlives-clear)
- `apps/web-platform/lib/ws-client.ts` (reconnect/route awareness :722) — Phase 3
- `apps/web-platform/infra/server.tf`, `firewall.tf`, `variables.tf`, `tunnel.tf` — Phase 2/3
- `apps/web-platform/package.json` (Node Redis client dep) — Phase 3
- `knowledge-base/engineering/architecture/decisions/ADR-027-*.md` (amend), `model.c4`, `views.c4` — Phase 0

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
- **Phase 2:** migration 114 applies + reverses on dev; a write carrying a **stale
  `lease_generation` is rejected at the ref-write boundary** (fencing test — the
  load-bearing AC, not just heartbeat timeout); bare-data cutover loses no refs
  (pre/post `git rev-list --all` count match).
- **Phase 3:** two users on one workspace served by two hosts each operate their
  own worktree with no git-index corruption (G1); abort/gate/grace issued on host B
  for a turn on host A routes to host A (coordinator-forward test); a reconnect
  routes back to the lease-holder (affinity test); a drain/deploy is invisible to an
  active user; replay buffer survives a cross-host reconnect with counter-no-rewind.
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
- **Step 1:** new `network.tf` (`hcloud_network` + subnet — removes the
  everything-on-loopback assumption); new `redis-session.tf` (dedicated CAX/ARM
  `hcloud_server`, AOF `hcloud_volume`, firewall 6379+TLS from the private subnet
  only); edit `firewall.tf` (private-net ingress), `server.tf` (attach web host to
  network), `variables.tf` (`session_redis_password`, sensitive, **no default**).
  Lease table is a Supabase migration, not TF.
- **Step 2:** new `git-data.tf` host exporting bare repos over the private net —
  the RWO `hcloud_volume.workspaces` single-attach **cannot** back multiple clients
  (the single-host assumption being removed). Worktrees → each client's local NVMe
  via cloud-init.
- **Step 3:** `hcloud_placement_group` (`type="spread"`); convert
  `hcloud_server.web` to `for_each`/`count` with **`moved` blocks** (else reads as
  destroy+create — verify plan is `0 to destroy`); coordinator + tunnel `service` edit.
- **Step 4:** per-host `betteruptime` monitors; reschedule/checkpoint = Nomad
  jobspec + app, not TF.

**`hr-tf-variable-no-operator-mint` (auto-apply trap):** `session_redis_password`
has no default → `apply-web-platform-infra.yml` **fails closed** if it is absent
from Doppler `prd_terraform` at merge time, failing the *whole* apply. **Split
required:** PR-A provisions `SESSION_REDIS_PASSWORD` into `prd_terraform` first;
PR-B merges the `.tf`. Values are `random`-generated, stored once, read at runtime
via `--requirepass`, never committed.

### Apply path
- **Step 1:** cloud-init + idempotent bootstrap (new Redis node) = pure `+create`,
  zero downtime to the web host. Lease table = online Supabase migration.
- **Step 2:** highest blast radius (data move off the shared volume); new git-data
  host is `+create`, cutover is a drained one-time rsync of `objects/refs`.
- **Step 3:** adding a client is `+create`; the `for_each` refactor needs `moved`
  blocks → verify `0 to destroy`.
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
  command: "curl -sf https://<coordinator-internal-or-health-route>/healthz && gh api .../sentry monitors (no ssh)"
  expected_output: "200 OK + session_store/lease/control_plane op slugs present in Sentry"
```

## Architecture Decision (ADR/C4)

### ADR
- **Create ADR-068** "Multi-host `/workspaces` via shared git-data + per-user
  worktrees + lease-routed coordinator (rejecting Ceph/k8s)" (`status: adopting`).
  Records: affinity-via-Postgres-lease + coordinator-forwarded control; rejection of
  Ceph/k8s and shared-NFS for the live tree; self-hosted EU Redis (Phase 3, replay
  buffer scope) over managed; `lease_generation` fencing.
- **Amend ADR-027:** `## Decision` gains the refinement that live-handle state stays
  host-local and cross-host control routes via the coordinator (only the routing
  truth is shared, and it already lives in Postgres); add "externalize-all-7-Maps to
  Redis" to `## Alternatives Considered` as rejected (live handles can't serialize;
  5 of 7 hold AbortControllers/timers/SDK Query). Reference ADR-059 (buffer is
  serializable, counter-outlives-clear).

### C4 views
Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`).
`spec.c4` defines only element kinds (actor/system/container/database/component +
`external` tag) — the new elements are existing kinds, so **spec.c4 needs no change**.
The **Container view** (`view containers of platform`) changes:
- **New `infra` elements (model.c4):** `sessionStore` (database, "Self-hosted Redis
  — session state, control-plane, replay buffer; network-reachable, EU"),
  `gitDataStore` (database, "Shared bare git repos (objects/refs) over private net"),
  `scheduler` (container, "Nomad — placement/reschedule/rolling deploy"),
  `coordinator` (container, "Routes a session to the lease-holding host"). Edit
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
- **Netsplit double-write on a partitioned lease** → durability alone is
  insufficient; a monotonic **`lease_generation` fencing token** checked at the
  git-data ref-write boundary rejects a stale holder's write (Phase 2).
- **No-default TF var fails the whole auto-apply** → PR-A/PR-B split (IaC).
- **Session-Redis (Phase 3) is a new SPOF** → HA failover deferred until ops demands
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
- Step 1 dev verification must use a **dev** Redis + **dev** Supabase, never prod
  (`hr-dev-prd-distinct-supabase-projects`).

## Open Questions (carry to deepen-plan / per-step plans)
1. Shared git-data SPOF: Garage (#5723) from the start vs GitHub-rehydration +
   brief re-clone — gated on which phase gates GA.
2. Worktree-checkpoint cadence/mechanism (shadow-branch vs rsync; value of N for
   "near-zero loss") — Phase 4b.
3. Which phase gates GA: **Phase 3** (concurrent multi-host, planned-move seamless,
   committed-state-durable) vs **Phase 4a** (seamless unplanned crash) vs **Phase 4b**
   (near-zero uncommitted loss). Panel consensus: Phase 3 is a credible GA line.
4. ~~Control-plane substrate~~ **RESOLVED (panel):** the Phase-3 coordinator already
   reads the lease and knows each host — it forwards control ops by RPC to the owning
   host. No second routing substrate (Redis pub/sub) is added. Deepen-plan should
   precedent-diff the coordinator-forward against the existing broadcast-abort
   (`agent-session-registry.ts:200-211`).

# Brainstorm: Per-tenant executor topology + cluster-scale agent/session scheduling (#9773, #5863)

**Date:** 2026-10-08
**Issues:** #9773 (OPEN — per-tenant executor topology, deferred from #5863) · #5863 (OPEN — per-session mountns isolation, in-flight via PR #9767)
**Branch:** feat-tenant-executor-topology · **PR:** #9832 (draft)
**Lane:** cross-domain · **Brand-survival threshold:** single-user incident (USER_BRAND_CRITICAL)
**Operator prompt:** "how are we going to run Soleur users' agents and sessions at scale in our cluster — pros/cons of executor isolation vs cluster scheduling, separately vs one architecture" · **Scope: ALL hosted execution** (Concierge + cron/CI/dispatch runners)

## What We're Building

The end-state architecture for hosted agent execution: a **unified executor +
placement design** (operator-selected Approach B) in which the unit of isolation
(a tenant-scoped executor — per-tenant uid + mount namespace + dedicated
subprocess) *is* the unit of scheduling (the atom the ADR-068 lease coordinator
places). One ADR + spec; delivery still sequences in independently-shippable
stages:

1. **Executor unit (local):** per-tenant subprocess cells on web-1 — uid +
   mountns boundary built on arm-F's privilege envelope (`cap_sys_admin,
   cap_setuid` file-cap'd bwrap; zero `--unshare-*`). Closes the shared-heap,
   `/proc/<pid>/environ`, and filesystem residuals in one boundary.
2. **Executor host (remote):** a dedicated cpx32-class host (~$38/mo) running
   the same executor contract; the **cron/eval fleet migrates first** — retires
   the #5417-class OOM blast radius on the tenant-serving host and proves
   remote spawn under non-tenant load.
3. **Placement:** tenant sessions migrate onto the executor fabric riding the
   ADR-068 chain (git-data store → lease-keyed session-router/session-proxy →
   reschedule) — the same machinery, now placing executor units instead of
   pinning whole web hosts.

## Why This Approach

The leaders converged on "two tracks, one design artifact" — build isolation
first because it is the GA-gating concern, let scheduling ride the ADR-068
chain. **The operator chose the unified build (B) instead** — recorded as an
explicit override of leader consensus: at the end-state the executor *is* the
placement decision, and designing them apart invites interface drift between a
local-only executor and the later scheduler. The delivery order still keeps
each stage independently valuable; what changes is that the executor's session
identity, event transport, and credential handoff are designed remote-ready
from day one (a socket-shaped channel, not stdio assumptions), so Stage-3
placement is additive, never a rewrite.

Supporting findings:

- **The seam already exists.** `spawnClaudeCodeProcess`/`SpawnedProcess` (the
  arm-F interpose point) and the merged `EngineAdapter` contract
  (`transport: "local" | "remote"`, `EngineBinding`) mean a remote executor
  drops in behind `realSdkQueryFactory` without touching workspace resolution
  or the hook stack.
- **The scheduler is designed-and-dark, not missing.** `worktree_write_lease`
  + `session-router` + `session-proxy` already implement lease-keyed
  user-sticky placement behind three fail-closed flags — the unified build
  promotes this to real placement rather than building a second scheduler.
- **Isolation is the binding constraint, not capacity.** web-1 measures ~1.5 GB
  peak / 0.48 load15 (~5× over-provisioned); the shared-heap + proc-env +
  shared-mount residuals are what block arms-length tenants (and an honest
  DPA Schedule 4), not throughput.
- **Not the Inngest host.** Co-locating the batch fleet on the dedicated
  single-writer control plane (cpx22, 4 GB) would put the platform's scheduler
  inside the #5417 blast radius the split exists to retire — the opposite
  direction.
- **Compliance posture depends on the mechanism wording.** DPA Schedule 4 must
  name the shipped boundary (uid + mountns + subprocess), and the shared-heap
  residual is owed an Art. 30 register entry now, before the build lands.

## Key Decisions

| # | Decision | Rationale | Source |
|---|----------|-----------|--------|
| 1 | **Unified architecture (Approach B)** — one ADR/spec covering the executor unit AND its placement contract; staged delivery | Executor = the atom placement schedules; separate designs drift on the transport/credential seam. **Operator override** of leader consensus (Option A, separate tracks) | Operator |
| 2 | **Executor boundary = per-tenant uid + mountns subprocess** inside the current container posture | arm-F's `cap_setuid` envelope closes `/proc/<pid>/environ` (owner-readable) + heap + FS in one boundary; userns measured dead under Docker masked `/proc`; no `docker.sock` | CTO, platform-strategist |
| 3 | **Remote contract = `SpawnedProcess`-shaped transport + `EngineAdapter transport:"remote"`** — session identity, event channel, and credential handoff survive a network hop from day one | Already-merged seams; makes Stage-3 placement additive | CTO, repo research |
| 4 | **Dedicated cpx32 executor host** (~$38/mo) — fleet moves there; the Inngest host is rejected as the landing spot | Protects the single-writer control plane (ADR-100) from batch load; Inngest cpx22 is 4 GB; fleet OOM = #5417 incident class | Operator + COO + platform-strategist |
| 5 | **Fleet-first migration order:** cron/eval `claude --print` spawns are the first remote-executor consumers; tenant sessions follow once remote spawn is proven | Cron spawns are already per-run subprocesses (cleanest integration); proves the executor under non-tenant load before the paying surface moves | Leaders' consensus |
| 6 | **Placement = ADR-068 machinery brought live** (worktree lease + session-router + session-proxy + git-data) — no second scheduler | The substrate is designed-and-dark; unified build finishes it as executor placement | Learnings, platform-strategist |
| 7 | **#9773 is the tracking issue; its fuzzy re-eval criteria are superseded** — this brainstorm IS the operator-initiated re-evaluation | Operator explicitly reopened the deferral; the ADR carries the satisfied-vs-overridden accounting | Operator |
| 8 | **Shared-heap residual recorded in the Art. 30 register now** (honest-residual pattern per ADR-272/counsel-review-9601), pre-build | Currently unrecorded; the record is owed regardless of architecture | CLO |
| 9 | **DPA Schedule 4 executor clause describes the boundary as built; DPIA re-screening owed** (published §9 "not required" rests on a small-user-base limb this invalidates); #7468 remains the repo-connect precondition | TOM-4 ruling: no safe harbour for mis-description in either direction | CLO |
| 10 | **EU Hetzner DCs only; per-DC live stock probe (`.server_types.available`) before any birth; never per-tenant hosts; never k8s/managed substrate until the AX eval's >100-sustained-concurrent trigger** | 44%-of-price COGS on per-tenant hosts; k8s rejected verbatim 2026-09-25 | COO, CLO, platform-strategist |
| 11 | **Tripwires instrumented as guardrails:** `active_sessions` alert at ≥4 sustained concurrent (existing `/internal/metrics` → Better Stack); un-defer the measurement half of #673's per-session cgroup accounting | Procurement must fire on signal, not hope — lead time is days-to-weeks | CPO, COO |
| 12 | **gdpr-gate at plan Phase 2.7 + work Phase 2 exit** | Regulated-data surfaces (executor assignment rows, migrations, API routes) | CLO (hr-gdpr-gate) |
| 13 | **Cron scratch moves off the tenant `/workspaces` mount** (`CRON_WORKSPACE_ROOT` separate subtree) alongside unifying cron spawns under the executor contract | Cron dirs are siblings of tenant dirs on one LUKS volume today | CTO, repo research |
| 14 | **Scale-tier "dedicated infrastructure" claim ($499) is reconciled against the shipped boundary** in copy/docs | The paid claim must not outrun the mechanism | CPO |
| 15 | Visual design: N/A — no UI surface (infra/orchestration only; upgrade-at-capacity modal already exists and only gains copy fidelity via #14) | ui-surface-terms boundary | — |

## Non-Goals (deferred)

- **Per-tenant containers/microVMs** (the stronger kernel boundary) — subprocess
  cells are #9773's first form; the container-class boundary stays deferred
  with explicit tripwires (Scale-tier signup demanding it, a realized
  cross-tenant event, or the >100-sustained-concurrent substrate trigger).
- **Nomad/k8s/managed runtime** — revisit only at the AX eval's own trigger
  (sustained >100 concurrent sessions, or hibernation becomes a product need);
  a bespoke executor daemon may beat importing a scheduler for one workload.
- **Tenant-pinned hosts** — rejected as general topology; survives only as a
  named-tenant enterprise escape hatch.
- **Session hibernation / checkpoint-resume of in-flight sessions** — ADR-068
  Phase-4b concern; executor drain semantics can be lease-expiry + reschedule.
- **GHA `claude-code-action` surface** — runs on GitHub's own pool, outside the
  cluster by design; out of scope for executor placement.
- **Per-tenant LUKS volumes/keys** — one-key whole-volume posture (ADR-119) is
  retained; per-tenant volumes only re-enter with the escape-hatch topology.
- **Rate limiting / public-launch admission** (#673 3.3) — plan slots already
  exist; a global admission queue is a separate feature.

## Open Questions (for the ADR/plan)

1. **Executor granularity** — persistent per-tenant executor process vs
   per-session subprocess; lifecycle, idle reaping, warm-start cost.
2. **uid allocation strategy** — fixed uid-per-tenant vs pooled; interaction
   with file ownership on the shared volume (host-side git replication +
   `session-sync` must still read executor-uid-written files).
3. **Remote transport** — `SpawnedProcess` over which channel: WS relay
   (session-proxy precedent), SSH, or a small executor-daemon API; and whether
   the Phase-4a scheduler is Nomad or a bespoke daemon.
4. **Private-net membership** — do executor hosts join `10.0.1.0/24`?
   (grok-dogfood precedent keeps agent hosts off the trusted L2; executor hosts
   carry tenant sessions — needs a firewall/trust answer.)
5. **`agent-on-spawn-requested` shape** — the in-process Messages-API loop has
   no CLI subprocess; becomes an executor client or stays in-process bounded.
6. **Credential handoff at spawn** — #9543 broker mints at the executor
   boundary (CLO: the natural home); executor hosts must carry **no** `prd`
   Doppler token (retires the workspaces-luks.tf full-prd-env concession).
7. **Ordering vs ADR-068 Phase-3 GA** — remote executors need workspace state
   off web-1's disk; does tenant-session migration gate on the git-data
   cutover, or is there an interim mount/replication path?
8. **Per-session cgroup accounting mechanism** — systemd-scope precedent
   (ADR-161) vs Docker caps vs the executor daemon's own accounting.
9. **DPIA screening memo owner + Schedule 4 wording timing** — describe interim
   (uid+mountns) vs wait for the executor boundary to ship.
10. **Deploy/drain semantics for executors** — control-plane↔executor version
    skew contract; what a deploy does to in-flight tenant sessions.

## User-Brand Impact

- **Artifact:** the hosted agent-execution layer — the per-tenant executor
  boundary and its placement substrate serving tenant sessions.
- **Vector:** worst case is a cross-tenant exposure realized through the shared
  heap/procfs/env or a placement defect landing a session in another tenant's
  workspace — a wrong-tenant glimpse is unrecoverable brand damage even with no
  write (2026-06-29 bar); a secondary vector is capacity mis-scheduling
  converting the paid concurrency surface into a churn surface.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Mapped every execution surface and the blast-radius table (proc-env
HIGH, shared heap HIGH, file-tier pre-arm-F HIGH, shared volume MEDIUM, no
per-session limits MEDIUM). Key mechanism finding: arm-F's `cap_setuid` makes a
per-tenant uid boundary viable without userns — the cheapest #9773 form. The
`EngineAdapter transport:"remote"` + `SpawnedProcess` seam is the remote-ready
contract; recommended Option A (separate tracks, one design artifact) —
**operator chose B**; CTO's own caveat stands as the design constraint: the
executor interface must be remote-ready from day one.

### Engineering (platform-strategist)

**Summary:** Ranked four topologies under the Terraform+cloud-init contract:
subprocess cells (reversible, ships on PR #9767's rails) → per-tenant
containers on shared host (a local scheduler whether called one or not; punts
the hardest problem) → dedicated executor fleet + scheduler (the decided
end-state; where isolation and placement become the same mechanism) →
tenant-pinned hosts (reject). Executor hosts are the most cattle-shaped thing
in the fleet once workspaces live below the lease/checkpoint layer.

### Product (CPO)

**Summary:** The reopen is premature as a *build* trigger but correct as a
*design* trigger — superseded by the operator's unified-build choice. Flagged:
scheduling without a tenant boundary widens blast radius per placement bug;
"at scale" decomposes into three product thresholds (5+ concurrent, capacity,
Scale-tier dedicated-infra promise); tenant sessions must outrank the internal
fleet in any unified scheduler. Tripwires recorded under Key Decisions #11.

### Legal (CLO)

**Summary:** Defensible either way IF Schedule 4 names the shipped mechanism —
no unqualified "tenant isolation." Required regardless of architecture: record
the shared-heap residual in Art. 30 now; DPIA re-screening (published §9 rests
on a small-user-base limb); #9543 and #9773 are one exposure (injection vector
× blast radius) — the broker belongs at the executor boundary; a new
infra vendor triggers the sub-processor pipeline.

### Operations (COO)

**Summary:** Procure nothing *beyond* the executor host the operator authorized;
current measured load doesn't justify per-tenant cells on cost grounds (the
isolation driver is security/legal, not capacity). Executor-host split is the
best cost-per-risk reduction; flagged the stale CX43 trigger row in
cost-model.md and the Sentry monitor-seat headroom (~39 before the cap
deactivates all monitors) as per-cell monitoring's hidden cost.

## Session Errors

None.

## Notes on Process

- Premise probe: #9773's `deferred from #5863` chain verified intact — #5863
  in-flight (draft PR #9767, arm F), not stale; this brainstorm is a deliberate
  operator-initiated re-evaluation, not a trigger fire. #9773's recorded
  criteria (arms-length tenants + one of exposure/capacity/COGS) are **not
  formally met** — the override is recorded per the overturned-deferral
  convention (stated satisfied-vs-overridden; issue kept as tracker).
- Epic #6641 (L0 tenant production completeness) has no in-repo footprint —
  GitHub-side only; its sequencing (isolation → HITL → visibility → packaging)
  is unaffected by this brainstorm but the executor ADR should cite it.
- Verified probes: PR #9767 OPEN draft; #9723 CLOSED; #9797/#9798 OPEN;
  #4891 CLOSED; #673 OPEN (5+ concurrent trigger); #7468 OPEN (Art. 28(3)
  precondition); #9137 OPEN (placement-aware Inngest); roadmap-reconcile clean.

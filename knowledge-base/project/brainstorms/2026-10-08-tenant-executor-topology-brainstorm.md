# Brainstorm: Per-tenant executor topology + cluster-scale agent/session scheduling (#9773, #5863)

**Date:** 2026-10-08 · **[Updated 2026-10-09: adversarial challenge review + re-brainstorm of the isolation design]**
**Issues:** #9773 (OPEN — per-tenant executor topology, deferred from #5863, tracking issue) · #5863 (OPEN — per-session mountns isolation; arm F shipped as PR #9767, merged 2026-10-09T12:11Z; soak follow-through open)
**Epic:** #9842 (children #9843-#9854) · **Branch:** feat-tenant-executor-topology · **PR:** #9832 (draft)
**Lane:** cross-domain · **Brand-survival threshold:** single-user incident (USER_BRAND_CRITICAL)
**Operator prompt:** "how are we going to run Soleur users' agents and sessions at scale in our cluster — pros/cons of executor isolation vs cluster scheduling, separately vs one architecture" · **Scope: ALL hosted execution** (Concierge + cron/CI/dispatch runners)

## Challenge Review (2026-10-09) — what changed and why

The first pass was reviewed adversarially against the code, the ADR corpus and the
legal record (CTO + CLO reviewers, plus an SDK-loop split map and an
isolation-primitive survey). Findings that changed the design:

| # | Finding (evidence) | Effect |
|---|---|---|
| C1 | The SDK `query()` loop, BYOK leases, in-process MCP servers, `canUseTool` and hooks run in the **parent** Node process (`agent-runner.ts:2113`, `cc-dispatcher.ts:195-205`). `SpawnedProcess` covers only the `claude` child's stdio. A per-tenant-uid child does **not** close the shared-heap residual #9773 names. | Executor must host the **whole SDK loop**; "closes shared-heap" retired for the child-only form (Decision 2 rewritten). |
| C2 | Arm F has no per-tenant uid mechanism: `setcap cap_sys_admin,cap_setuid,cap_setgid+ep /usr/bin/bwrap` (Dockerfile:139), single container user (uid 1001), no `--uid`; `bwrap --uid` requires `--unshare-user`, which arm F forbids and the shim denies (CLONE_NEWUSER). A cap_setuid carrier runnable by the app uid is an escalation surface. | The "arm-F uid envelope" premise is dropped. Per-tenant identity comes from a sandbox boundary, not bwrap uid tricks. |
| C3 | Zero `--unshare-*` leaves net (loopback, `/internal/metrics` Host-header-gated), IPC, PID visibility and abstract sockets shared; no `hidepid`/`ptrace_scope` hardening in infra. | Stronger boundary required (Decision 2). |
| C4 | Cron/eval fleet clones Soleur's own repos (`CRON_WORKSPACE_ROOT`), touches no tenant data; #5417 is partly mitigated (`PROD_MEMORY_CAP=4096m`); web-1 measures ~1.5 GB peak / ~5× over-provisioned (ADR-143); remote Inngest execution collides with ADR-243 single-flight; fleet needs secrets FR3 forbids on executor hosts. | Moving the fleet is a capacity/blast-radius concern, not tenant isolation. Decoupled from Stage 1 delivery (Decision 5). |
| C5 | Remote tenant sessions need workspace state off web-1's LUKS volume = ADR-068 Phase 3 (git-data cutover), not additive. | Tenant-session placement is gated on Phase 3 GA (Decision 6). |
| C6 | PR #9767 was recorded as "draft"; it was open-non-draft and has since **merged**. `spawnClaudeCodeProcess` is now on main; `transport:"remote"` is still an unconsumed Codex-only descriptor. | Seam claims scoped honestly (Decision 3). |
| C7 | Deferral accounting promised but absent. #9773's criteria (a) arms-length tenants live, (b) #4891 capacity motive, (c) COGS/user count: **all unmet**; #4891 closed `NOT_PLANNED`. | Table added below. |
| C8 | Nomad was silently re-gated on the AX trigger; AX record never mentions Nomad (ADR-068 §8 schedules Phase 4a). "k8s rejected verbatim" overstated — the AX record says "do not adopt now; reference architecture". ">100 sustained" trigger lives only in a brainstorm. | Corrected wording; ADR must state it amends ADR-068 §8 / ADR-075 Option B. |
| C9 | #9773 calls the per-tenant executor "the only design that gives a kernel/credential boundary"; a shared-kernel cell downgrades that. | Operator chose gVisor (userspace kernel) from the start — closest non-shared-kernel boundary available on Cloud. |
| C10 | Legal: residual belongs as an Art. 32 TOM bullet (ADR-272/counsel-review-9601 pattern), not an Art. 30 processing activity; Art. 33(5) question for #9723 unasked; DPIA §9 trigger is limb (d) "small user base" (arms-length onboarding), not the build; Hetzner is already a signed processor (no new sub-processor step *for Hetzner*; any **other** provider is one); `data-protection-disclosure.md:291` ("single user-serving host… Helsinki") becomes false; Scale-tier "dedicated infrastructure" is purchasable today. | Legal near-term items independent of the build (Decisions 8, 9, 14). |
| C11 | Citation errors: `ADR-027-state-supersession` does not exist; two ADR-030 files; ADR-118 is a derivation-coupling warning (proxy-cert SANs from `var.web_hosts`), not a roster pattern; roadmap rows 4.6/4.8 not updated. | Fixed in spec TR2; roadmap update owed at plan time. |

**Deferral accounting for #9773** (operator explicitly reopened; issue stays OPEN as tracker):

| Recorded criterion | Status | Disposition |
|---|---|---|
| Arms-length hosted tenants live | Unmet (still blocked by the residuals) | **Overridden** by operator |
| (a) realized cross-tenant exposure judged unacceptable | Unmet (none realized) | **Overridden** — risk-driven, not incident-driven |
| (b) capacity work (#4891-class) motivates subprocesses | Unmet (#4891 closed NOT_PLANNED) | **Overridden** |
| (c) user count/COGS makes it economical | Unmet (COO: load does not justify on cost) | **Overridden** — driver is security/legal |

## What We're Building

The end-state architecture for hosted agent execution: a **unified executor +
placement design** (operator-selected Approach B, recorded override of the
leaders' separate-tracks consensus) in which the unit of isolation — a
**sandboxed tenant executor** — is the unit of scheduling. One ADR + spec;
**delivery gates are decoupled** so the GA-gating isolation work never waits on
the capacity/placement work.

**The executor (re-brainstormed, operator decision 2026-10-09):** one **gVisor
(`runsc`, systrap platform) sandbox per tenant session** that hosts the *entire*
agent: the SDK `query()` loop, MCP tool servers, hooks, and the `claude` CLI
child. The shared control plane keeps only routing: WebSocket, the runner that
turns `SDKMessage`s into frames, cost persistence, and lifecycle. It never holds
tenant plaintext secrets in its heap beyond what the credential broker policy
allows.

**Host-side supervisor.** gVisor runs most naturally as a host-level OCI runtime,
not inside the unprivileged app container (no `docker.sock`, masked `/proc`,
shim-denied userns). So a small **executor supervisor** (host systemd unit,
narrow authenticated API) launches sandboxes. This makes an "executor-capable
host" a prerequisite of Stage 1 — first co-resident on web-1's host, then the
same contract on dedicated hosts. *(Inferred; confirmed by the Stage-0 canary.)*

**Provider-portable by contract.** The executor host is defined by a
provider-neutral contract — Linux x86_64/arm64, cgroup v2, systemd, pinned and
checksum-verified `runsc`, **systrap platform (no nested virtualisation
required)** — plus a conformance suite that runs on any host. This is what makes
OVH, Scaleway, GCP, AWS, Azure and Hetzner all viable. KVM-platform gVisor and
microVMs (Firecracker/Kata) are *optional rungs* only where the provider offers
nested virt or bare metal. IaC is a thin per-provider root over a shared module
interface; **only Hetzner is built now** (existing sub-processor, EU pin). Any
other provider is a new sub-processor + residency decision, gated on need.

### Delivery stages (independently shippable; each has its own gate)

0. **Stage 0 — de-risk + record (no executor code on prod):** gVisor canary on the
   real workload (go/no-go criteria below); executor-conformance suite; Art. 32
   TOM residual entry; Art. 33(5) assessment of the #9723 window; DPD §291 and
   Scale-tier copy corrections; DPIA re-screening memo; Schedule-4 wording plan.
1. **Stage 1 — local sandboxed executor (cc path first):** supervisor on web-1's
   host; executor protocol; `RemoteQuery` behind the runner; broker for the
   Anthropic key; flag-gated canary tenants. Closes heap/proc/env/FS/net.
2. **Stage 2 — executor hosts + cron/eval fleet (evidence-gated):** only if
   capacity/blast-radius evidence (#5417 residue, concurrency tripwires) justifies
   it; requires ADR-243 reconciliation and a non-`prd` secret path for the fleet.
3. **Stage 3 — legacy-runner tool triage + tenant placement:** service-role tool
   families get an RPC proxy or stay out of the executor tool set; tenant-session
   placement rides ADR-068 and is **gated on Phase 3 GA**.

**Stage-0 canary go/no-go (numbers fixed in the ADR before the run):** cold-start,
`git clone`, bun/npm install, tool-call latency, memory per sandbox, and
streaming-delta latency on the real Node + `claude` CLI workload vs. a bare
baseline. **Fallback rung if gVisor fails the canary:** a hardened shared-kernel
launcher (separate minimal setuid launcher owning the uid map; fresh
pid/net/ipc/uts namespaces; seccomp deny of userns/bpf/perf_event_open/keyctl/
io_uring/ptrace; `no_new_privs`; `hidepid=2`; `ptrace_scope=2`; per-uid egress),
recorded honestly as shared-kernel in the Art. 32 TOM.

## Why This Approach

- **The seam is narrower than first claimed.** `spawnClaudeCodeProcess`/`SpawnedProcess`
  (now on main via #9767) moves only the CLI child. The SDK loop, `canUseTool`,
  review gates and `createSdkMcpServer` stay in the parent, so the executor needs
  a **new seam above `query()`**: a `RemoteQuery` implementing the `Query` surface
  the runner uses, behind a `QueryFactory` (`soleur-go-runner.ts` `QueryFactoryArgs`).
  Estimated 25–35 files / 2.5–4k LOC for the cc path (±50%), +1.5–2k for the
  legacy runner. `EngineAdapter transport:"remote"` and the Codex app-server
  launcher are precedents, not wired production paths.
- **Hardest coupling: `canUseTool`/review gates.** They need DB writes,
  WebSocket, offline notify and an ack-posture race. Collapse to one
  `approval_request`/`approval_decision` pair; decision logic and
  `bashApprovalCache` move into the executor; DB status write, WebSocket and
  notify stay in the parent.
- **Isolation is the binding constraint, not capacity.** web-1 ~1.5 GB peak /
  0.48 load15 (ADR-143, 30-day sample; peaks may be under-sampled). The residuals,
  not throughput, block arms-length tenants and an honest DPA Schedule 4.
- **Non-shared-kernel is available on Cloud only via gVisor.** Hetzner Cloud does
  not expose nested virt (vendor FAQ), so Firecracker/Kata need bare metal
  (~€100+/mo, outside Terraform/cloud-init). gVisor systrap needs no virt
  extensions, so it also ports to other clouds.
- **Not the Inngest host.** Co-locating the batch fleet on the single-writer
  control plane (cpx22, 4 GB) would recreate the #5417 blast radius.
- **Compliance depends on the mechanism wording.** Schedule 4 and the TOM entry
  must name the shipped boundary — and while only the interim exists, must not
  claim more.

## Key Decisions

| # | Decision | Rationale | Source |
|---|----------|-----------|--------|
| 1 | **Unified architecture (Approach B)** — one ADR/spec for executor + placement; **delivery gates decoupled** (Stages 0–3) | Operator override of separate-tracks consensus kept; challenge review showed coupled *delivery* would delay the GA-gating fix | Operator, challenge review |
| 2 | **[Updated] Executor = gVisor (runsc/systrap) sandbox per tenant session hosting the whole SDK loop + MCP + hooks + CLI.** Fallback rung: hardened shared-kernel launcher if the Stage-0 canary fails | Child-only cells leave the parent heap open (C1); arm F has no uid mechanism (C2); only gVisor is a non-shared-kernel boundary on Cloud | Operator (2026-10-09), CTO, platform-strategist |
| 3 | **[Updated] Remote contract = new `RemoteQuery`/executor protocol over an inherited socketpair/stream (no filesystem/abstract sockets); `EngineAdapter transport:"remote"` is the adapter shape, not a wired path** | Messages: `init`(versioned), `user_message`, `approval_decision`, `ack_posture`, `jwt_refresh`, `interrupt`, `close` ↔ `sdk_message`, `approval_request`, `tool_rpc`, `telemetry`, `session_id`, `fatal`, `exit` | CTO map |
| 4 | **[Updated] Executor hosts: provider-neutral host contract + conformance suite; Hetzner (cpx32-class, EU) is the only provider built now** | OVH/Scaleway/GCP/AWS/Azure portability by contract, not by building 6 IaC roots; each extra provider = sub-processor + EU residency decision | Operator, platform-strategist, CLO |
| 5 | **[Updated] Fleet-first is no longer the proving ground.** Cron/eval migration is Stage 2, evidence-gated; Stage 1 proves the executor on canary tenant sessions | Fleet is capacity, not isolation (C4); ADR-243 single-flight; secrets conflict | Challenge review |
| 6 | **[Updated] Placement = ADR-068 machinery, gated on Phase 3 GA** (workspace state off web-1's volume); no second scheduler; bespoke supervisor, not Nomad, unless ADR-068 §8 triggers | C5, C8 | Learnings, challenge review |
| 7 | **#9773 is the tracking issue; deferral accounting recorded** (table above); ADR states it amends ADR-068 §8 / ADR-075 Option B | Overturned-deferral convention | Operator |
| 8 | **[Updated] Residual recorded as an Art. 32 TOM bullet** (named-gap form per ADR-272/counsel-review-9601) **now**, plus an **Art. 33(5) assessment of the #9723 `/proc` window** | C10; the record is owed regardless of architecture | CLO |
| 9 | **[Updated] Schedule 4 names the shipped mechanism (interim: mountns+uid-less; target: gVisor sandbox); DPIA re-screen keyed to limb (d) — arms-length onboarding;** confirm which Schedule-4 section carries it (TOM-4 is RLS) | TOM-4 ruling: no safe harbour for mis-description | CLO |
| 10 | **[Updated] EU DCs only on every provider; per-DC live stock probe before any birth on Hetzner; never per-tenant hosts; never k8s/managed runtime until a recorded trigger.** Triggers live in the ADR, not only a brainstorm | Fixes C8 | COO, CLO, platform-strategist |
| 11 | **Tripwires as guardrails:** `active_sessions` alert ≥4 sustained; ADR-161 per-session scopes supply the accounting; promotion rungs: (i) named customer/DPA needs non-shared kernel → gVisor/dedicated, (ii) ≥~30 concurrent/host or >100 fleet → more hosts, (iii) public LPE on pinned kernel without patch in 72h → move sensitive tenants to dedicated servers, (iv) any sandbox-escape probe event | Procurement fires on signal | CPO, COO, platform-strategist |
| 12 | **gdpr-gate at plan Phase 2.7 and work Phase 2 exit** | Executor assignment rows, migrations, API routes | CLO |
| 13 | Cron scratch moves off the tenant `/workspaces` mount (`CRON_WORKSPACE_ROOT`) — in Stage 2, not Stage 1 | Sibling dirs on one LUKS volume today | CTO |
| 14 | **[Updated] Scale-tier "dedicated infrastructure" copy reconciled in Stage 0**, not after the build; checkout route and `upgrade-copy.ts` reviewed (tier is purchasable today) | C10 present-tense risk | CPO, CLO |
| 15 | Visual design: N/A — no UI surface (the Scale/upgrade copy edit is text-only) | ui-surface-terms boundary | — |
| 16 | **New: credential broker is a separate small process**, not the web heap. Preferred: header-injecting `ANTHROPIC_BASE_URL` proxy so the Anthropic key never enters the sandbox; tenant JWT 600s with `jwt_refresh` independent of the user being online; service-role tools stay **out** of the executor bundle, enforced by a second-bundle import-boundary gate seeded from `.service-role-allowlist` | "No secrets in the control plane" is false unless plaintext bypasses the web heap (CTO map risk 4); master secrets never leave the platform | CTO map, #9543 |
| 17 | **New: supervisor trust surface is minimal and itself threat-modelled** (peer-credential authN, signed tenant claim per launch, mounts only that tenant's workspace, no tenant data in supervisor) | Placement defect landing a session in another tenant's workspace is the brand-ending vector | Challenge review |
| 18 | **New: build-vs-adopt (web survey 2026-10-09).** Adopt `runsc` + containerd (`io.containerd.runsc.v1`); adapt Anthropic's worker-contract shape, unix-socket credential-proxy pattern and multi-tenant SDK settings; build only the supervisor reaper/reconcile, thin injector and conformance suite. Managed vendors rejected (new US Art. 28 sub-processors, no Hetzner BYOC, exit cost). Add S0 comparison spike: bespoke supervisor vs k3s + `agent-sandbox` v1.0.x. S1 gates on a file-I/O benchmark (Anthropic reports 10-200x on open/close-heavy I/O). Full table in spec "Build vs Adopt" | Operator question "did we research existing OSS?" - first pass had surveyed isolation primitives only | Operator, research agents |

## Non-Goals (deferred)

- **Per-tenant containers/dedicated servers** as the general boundary — named
  enterprise escape hatch only (tripwire (i)/(iii) in Decision 11).
- **Firecracker/Kata microVMs** — only where a provider offers nested virt or
  bare metal *and* a customer/DPA requires a hardware boundary.
- **Nomad/k8s/managed runtime** — only at a recorded ADR trigger (ADR-068 §8
  Phase 4a or the AX eval's sustained-concurrency trigger once it is recorded in
  an ADR).
- **Building non-Hetzner IaC roots now** — contract + conformance suite only.
- **Session hibernation / checkpoint-resume** — ADR-068 Phase-4b.
- **GHA `claude-code-action` surface** — outside the cluster by design.
- **Per-tenant LUKS volumes/keys** — one-key posture (ADR-119) retained.
- **Rate limiting / public-launch admission** (#673 3.3) — separate feature.
- **A dedicated follow-up issue tracks the residual kernel-boundary gap** if the
  fallback rung ships instead of gVisor (to be filed at plan time and linked from
  #9773; not filed in this brainstorm).

## Open Questions (for the ADR/plan)

1. **Sandbox granularity** — per-session vs per-tenant-persistent; warm pool;
   idle reaping; cold-start budget from the canary.
2. **gVisor canary results** — go/no-go numbers; `runsc` version pin, upgrade and
   advisory cadence; fallback rung trigger.
3. **Supervisor placement and API** — co-resident on web-1's host (what changes
   vs. ADR-122's boot-time control delivery?) vs executor host; authN; blast
   radius if the supervisor is compromised.
4. **Workspace attach into the sandbox** — bind of own workspace only; gofer/9p
   or overlay performance for git-heavy work; `session-sync`/`replicateToGitData`
   reads of sandbox-written files.
5. **Broker design for the Anthropic key** — header-injecting proxy vs lease
   delivery over a socketpair; interaction with #9543's localhost vending
   endpoint (which is silent on the Anthropic key).
6. **Resume** — CLI transcripts live in the executor-local `$HOME`; per-tenant
   persistence across redeploy/reschedule, or lean on prefill-guard drop-resume
   (#9538).
7. **Legacy runner (`agent-runner.ts`)** — service-role/installation-token tool
   families: RPC proxy vs left in-process (then the exposure remains on that path
   — must be recorded as a residual).
8. **`realSdkQueryFactory` split** — the ~1,360-line control-plane-prep vs
   query-construction cut; lease-closure ordering around `setDelegationContext`;
   the #4767 cwd/workspace divergence class.
9. **Executor-host private-net membership** — gVisor netstack + per-session
   egress allowlist (reuse `cron-egress-nftables.sh`); block metadata
   `169.254.169.254` and `10.0.1.0/24` from every sandbox.
10. **Provider list and order** beyond Hetzner; which need a new sub-processor
    entry and EU-residency validation; ADR-118 proxy-cert SAN coupling for any new
    host roster.
11. **Deploy/drain and version skew** — SIGTERM drain must reap executors
    (`--die-with-parent` equivalent); `init.protocolVersion` refusal path.
12. **Arm-F bounding-set change** — #9767 added `--cap-add SYS_ADMIN` to the app
    container; reassess whether the control-plane container can drop it once
    isolation moves to the supervisor.
13. **Kernel patch cadence and tenancy cap per host** — the residual under every
    shared-host option is a host-kernel LPE or `runsc` escape.
14. **DPIA memo owner and Schedule-4 wording timing** (Stage 0).

## User-Brand Impact

- **Artifact:** the hosted agent-execution layer — the per-tenant executor
  sandbox, its supervisor, and the placement substrate serving tenant sessions.
- **Vector:** worst case is a cross-tenant exposure realized through shared
  heap/procfs/env/network, a sandbox escape, or a placement/supervisor defect
  landing a session in another tenant's workspace — a wrong-tenant glimpse is
  unrecoverable brand damage even with no write (2026-06-29 bar); secondary
  vector is capacity mis-scheduling converting the paid concurrency surface into a
  churn surface.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Mapped every execution surface and blast radius. Original finding
that arm-F's `cap_setuid` makes a per-tenant uid boundary viable is **retracted**
(C2). Challenge review: the executor must host the SDK loop; smallest protocol
and size estimate recorded in Why This Approach and Decision 3. Operator chose
Approach B; CTO's caveat (remote-ready from day one) stands.

### Engineering (platform-strategist)

**Summary:** Original ranking superseded by the primitive survey: shared-kernel
cells with a hardened launcher (fallback) → **gVisor systrap (chosen, portable,
no nested virt)** → Firecracker/Kata (bare metal only on Hetzner) → dedicated
per-tenant servers (enterprise escape hatch). Systemd-unit options only work on
an executor host, not inside the container.

### Product (CPO)

**Summary:** Reopen is a design trigger; operator chose unified build. Flagged
scheduling-without-boundary widens blast radius; three product thresholds (5+
concurrent, capacity, Scale-tier dedicated-infra promise); tenant sessions
outrank the internal fleet. Scale-tier copy risk is present-tense (Decision 14).

### Legal (CLO)

**Summary:** Defensible IF documents name the shipped mechanism. Corrected after
challenge review: Art. 32 TOM bullet (not Art. 30 activity); Art. 33(5)
assessment for #9723; DPIA trigger is limb (d); Hetzner already signed (other
providers are new sub-processors); DPD §291 single-host statement and the
Scale-tier purchasable claim are near-term fixes; Schedule-4 section to confirm.

### Operations (COO)

**Summary:** Procure only what the operator authorized; current load does not
justify cells on cost grounds (security/legal driver). cpx32 ≈ €35.49/mo net
(`variables.tf`); a cx33 8 GB option is far cheaper but stock-constrained.
Stale CX43 trigger row in cost-model.md; Sentry monitor-seat headroom (~39) is
per-cell monitoring's hidden cost.

## Session Errors

- Original brainstorm recorded PR #9767 as "draft"/in-flight with arm F as a
  buildable foundation; it was open-non-draft and then merged during review. The
  foundation it assumed (a uid mechanism) did not exist even post-merge (C2).
- Original brainstorm accepted CTO's "viable without userns" claim without
  measurement and an ADR corpus mis-citation (`ADR-027-state-supersession`).
  Re-verified here; unmeasured claims now carry INFERRED/UNVERIFIED tags in the spec.

## Notes on Process

- Premise probe: #9773's `deferred from #5863` chain verified; the operator
  explicitly reopened the deferral (accounting table above).
- Epic #6641 (L0 tenant production completeness) has GitHub-side footprint only;
  the ADR should cite it.
- Challenge-review sources: CTO technical verification, CLO ADR/legal review,
  SDK-loop split map, isolation-primitive survey (Hetzner FAQ, gVisor platforms
  doc). External facts are vendor-doc-sourced; `/dev/kvm` on ccx and gVisor
  Node/CLI performance remain **UNVERIFIED** until Stage 0.

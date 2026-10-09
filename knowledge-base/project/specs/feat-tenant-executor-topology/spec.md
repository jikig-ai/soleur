---
title: Per-Tenant Sandboxed Executor + Cluster-Scale Session Placement
status: draft (revised 2026-10-09 after adversarial challenge review)
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-08-tenant-executor-topology-brainstorm.md
issues: [9773, 5863]
branch: feat-tenant-executor-topology
pr: 9832
created: 2026-10-08
updated: 2026-10-09
---

# Spec: Per-Tenant Sandboxed Executor + Cluster-Scale Session Placement

Evidence tags used below: **CONFIRMED** (read in code/vendor doc), **INFERRED**
(reasoned, not measured), **UNVERIFIED** (must be proven in Stage 0).

## Problem Statement

Every hosted agent execution surface resolves locally inside one multi-tenant
web-platform container. Concierge runs the Agent SDK `query()` loop **in the
shared Node process** (`agent-runner.ts:2113`), together with all tenants' BYOK
leases, session state, in-process MCP servers, `canUseTool` and hooks, and
spawns the `claude` CLI as a child. Cron/eval work spawns `claude --print` in the
same container; `agent-on-spawn-requested` runs an in-process Messages-API loop.

Arm F (#5863, PR #9767, **merged 2026-10-09**) removes sibling *filesystem*
presence per session via a mountns-only bwrap wrap. It does **not** close: the
shared parent heap (the exposure #9773 tracks), shared network/IPC/PID visibility
and abstract sockets, `/proc/<pid>/environ` of same-uid processes, or provide any
per-tenant uid (CONFIRMED: single container user, `setcap cap_sys_admin,cap_setuid,cap_setgid+ep /usr/bin/bwrap`,
no `--uid`; `bwrap --uid` requires `--unshare-user`, which the shim denies).

Cluster-scale *placement* is designed-but-dark: ADR-068's lease + session-router
+ session-proxy are fail-closed inert, tenant workspaces live on one LUKS volume
attached to web-1 (CONFIRMED), and no admission/scheduler consumes capacity
signals.

Operator decisions: **one unified architecture** (executor = placement atom),
**gVisor sandbox per session from the start**, **cloud-provider portable by
contract**, with **decoupled delivery gates** so isolation never waits on
capacity/placement.

## Goals

- **G1.** A per-session **gVisor (runsc, systrap) sandbox** hosts the whole agent
  — SDK loop, MCP servers, hooks, `claude` CLI — so no tenant state shares a heap,
  procfs, network namespace or IPC with another tenant or with the control plane.
- **G2.** A narrow executor protocol (`RemoteQuery` behind the runner's
  `QueryFactory`) over an inherited stream, remote-ready (version-checked, no
  filesystem/abstract sockets), so a remote executor host is additive.
- **G3.** A host-side **executor supervisor** launches sandboxes; the
  control plane never gains Docker/host privileges.
- **G4.** A **provider-neutral executor-host contract + conformance suite**;
  Hetzner (EU) is the only provider built now.
- **G5.** The control plane holds no tenant plaintext secrets beyond what the
  broker policy allows; the Anthropic key is delivered without transiting the web
  heap.
- **G6.** Compliance record stays honest through the build (Art. 32 TOM residual,
  Art. 33(5) assessment, DPD/Scale-tier corrections, DPIA re-screen, Schedule 4).
- **G7.** Placement rides ADR-068 after Phase 3 GA; cron/eval fleet moves only on
  evidence (Stage 2).
- **G8.** Tripwires instrumented so capacity and boundary-promotion decisions
  fire on signal.

## Non-Goals

- **NG1.** Per-tenant containers/dedicated servers as the *general* boundary
  (named enterprise escape hatch; tripwires in brainstorm Decision 11).
- **NG2.** Firecracker/Kata — only where a provider offers nested virt/bare metal
  and a customer/DPA requires a hardware boundary (Hetzner Cloud does not expose
  nested virt — CONFIRMED vendor FAQ).
- **NG3.** Nomad/k8s/managed runtime — only at a trigger recorded **in an ADR**
  (ADR-068 §8 Phase 4a, or the AX eval's sustained-concurrency trigger once
  recorded).
- **NG4.** Session hibernation / checkpoint-resume — ADR-068 Phase-4b.
- **NG5.** GHA `claude-code-action` surface.
- **NG6.** Per-tenant LUKS volumes/keys (ADR-119 retained).
- **NG7.** Public-launch rate limiting / global admission (#673 3.3).
- **NG8.** Moving Inngest — control plane stays a dedicated singleton host.
- **NG9.** Non-Hetzner IaC roots now (contract + conformance suite only).
- **NG10.** If the Stage-0 canary forces the shared-kernel fallback rung, the
  residual kernel-boundary gap gets a named follow-up issue linked from #9773.

## Delivery Stages (independently gated)

| Stage | Scope | Gate to start | Exit |
|---|---|---|---|
| **0** | gVisor canary; conformance suite; Art. 32 TOM entry; Art. 33(5) #9723 assessment; DPD §291 + Scale-tier copy fixes; DPIA memo; ADR draft | none | Canary go/no-go recorded; legal items merged |
| **1** | Supervisor on web-1's host; executor protocol; `RemoteQuery`; broker; cc path only; flag-gated canary tenants | Stage 0 go (else fallback rung) | cc-path sessions run in sandboxes with parity tests; gdpr-gate passed |
| **2** | Executor hosts; cron/eval fleet migration; `CRON_WORKSPACE_ROOT` off tenant mount | Evidence: #5417 residue and/or concurrency tripwire; ADR-243 reconciled; non-`prd` secret path | Fleet off tenant-serving host |
| **3** | Legacy-runner tool triage; tenant placement via ADR-068 | Phase 3 GA (git-data cutover) | Tenant sessions placeable across executor hosts |

## Threat Model (Stage-0 deliverable; seed list)

Adversaries: (A1) malicious tenant or prompt-injected agent with full tool use
inside its sandbox; (A2) compromised dependency/MCP tool; (A3) curious tenant
probing neighbours; (A4) network attacker on the private net; (A5) compromised
control plane or supervisor.

| ID | Threat | Control | Residual |
|---|---|---|---|
| T1 | Read another tenant's heap/session state | Separate sandbox (own userspace kernel + process space) per session; no shared parent heap holds tenant plaintext | `runsc` escape; shared host kernel beneath it |
| T2 | `/proc/<pid>/environ`, `/proc` enumeration | Sandbox-private procfs; supervisor-owned env | — |
| T3 | Cross-tenant filesystem access | Sandbox mounts only own workspace; supervisor verifies signed tenant claim per launch | Gofer/overlay bugs |
| T4 | Network lateral movement (loopback `/internal/metrics`, abstract sockets, private `10.0.1.0/24`, metadata `169.254.169.254`, Inngest, git-data) | Own netns/netstack per sandbox; per-session egress allowlist (reuse `cron-egress-nftables.sh`); explicit metadata/private-net blocks | Allowlisted egress exfil of own data |
| T5 | Sandbox escape / host kernel LPE | gVisor reduces host syscall surface; pinned `runsc` + checksum; patch cadence; tenancy cap per host; tripwire (iii) | Unpatched LPE window; fallback rung is shared-kernel |
| T6 | Supervisor compromise | Host systemd unit; peer-credential authN; narrow API; no tenant data held; every launch audited | Supervisor is a privileged component — must be minimal and reviewed |
| T7 | Credential exposure | Broker process (not web heap); Anthropic key never in sandbox where `ANTHROPIC_BASE_URL` proxy works; 600s tenant JWT; service-role tools excluded by CI gate | Tenant data readable by its own sandbox, by design |
| T8 | Control-plane compromise → all tenants | Control plane holds routing + master secrets (service role, BYOK master key); no tenant plaintext at rest in heap | Master secrets remain in the control plane — **accepted, documented** |
| T9 | Resource exhaustion/noisy neighbour | ADR-161 transient scopes per sandbox + `pids.max`; fleet cap | Host-level DoS |
| T10 | Placement defect lands session in wrong tenant's workspace | Lease-keyed placement + supervisor claim check + per-launch workspace bind; negative tests | — |
| T11 | Stream/replay cross-tenant mix-up in control plane (`stream-replay-buffer`, runner) | Per-conversation/tenant keying; isolation tests with two tenants | — |
| T12 | Supply chain (`runsc` binary, executor bundle) | Pinned version + checksum; second-bundle import-boundary gate; SBOM | — |
| T13 | Executor crash/hang mid-turn leaks or corrupts state | Crash maps to CLI-exit-equivalent in iterator; gate cancellation; reaping with parent death | Resume depends on transcript persistence (OQ6) |

## Functional Requirements

- **FR1 Supervisor.** Host-level unit that launches one runsc sandbox per session
  (OCI bundle), applies an ADR-161 transient scope, mounts only the tenant's
  workspace, wires egress policy, and reaps on parent death. Authenticated via
  peer credentials + signed launch claim.
- **FR2 Executor protocol.** Parent→executor: `init` (versioned: persona, cwd,
  system prompt, resume id, credential handle, tenant JWT, tool-set id, flags),
  `user_message`, `approval_decision`, `ack_posture`, `jwt_refresh`, `interrupt`,
  `close`. Executor→parent: `sdk_message`, `approval_request`, `tool_rpc`,
  `telemetry`, `session_id`, `fatal`, `exit`. `RemoteQuery` implements the `Query`
  surface the runner uses (iteration + `close()`); plugs in via `QueryFactoryArgs`.
- **FR3 Approval channel.** `canUseTool`/review gates collapse into
  `approval_request`/`approval_decision`; decision logic and `bashApprovalCache`
  run in the executor; DB status write, WebSocket and offline notify stay in the
  parent; pending gates cancelled on executor death.
- **FR4 Credentials.** Separate broker process; Anthropic key via
  header-injecting `ANTHROPIC_BASE_URL` proxy where feasible; tenant JWT with
  `jwt_refresh` that does not depend on the user being online; GitHub
  installation token scoped at launch; no `prd` Doppler env on executor hosts.
  Service-role tool families excluded from the executor bundle (CI gate).
- **FR5 Control-plane split.** Cut `realSdkQueryFactory` (~1,360 lines,
  CONFIRMED) into control-plane prep vs query construction without regressing the
  workspace/cwd divergence class (#4767) or lease-closure ordering.
- **FR6 Executor-host contract.** Linux x86_64/arm64, cgroup v2, systemd, pinned +
  checksummed `runsc`, systrap platform, no nested virt required; conformance
  suite (runsc smoke, egress blocks incl. metadata/private net, cgroup limits,
  supervisor authN, reap-on-parent-death) runnable on any host.
- **FR7 Host IaC (Hetzner).** `for_each` roster, cloud-init only, fresh-boot
  readiness gate (`hr-fresh-host-provisioning-reachable-from-terraform-apply`),
  per-DC live stock probe, EU-pin validation; ADR-118 proxy-cert SAN coupling
  addressed for any host that joins the proxy mesh.
- **FR8 Observability.** Executor lifecycle, spawn/crash classification
  (`classifySandboxStartupError`-equivalent), approval latency, per-session
  resource use, `active_sessions` ≥4 alert — each citing its observability layer
  (`hr-observability-layer-citation`) and mirrored to Sentry/Better Stack.
- **FR9 Stage-2 (gated).** `spawnClaudeEval` through the executor contract;
  `CRON_WORKSPACE_ROOT` off the tenant mount; ADR-243 single-flight reconciled.

## Technical Requirements

- **TR1.** Provisioning is Terraform; host config via cloud-init; prod changes via
  immutable re-provision (`hr-prod-host-config-change-immutable-redeploy`).
  Supervisor delivery/enforcement follows ADR-122's boot-time model.
- **TR2.** ADR required: executor topology. Relates to ADR-068 (**amends §8
  Phase 4a placement and trigger wording**), ADR-075 (**amends Option B**),
  ADR-122, ADR-143, ADR-161, ADR-243, ADR-100 (Inngest singleton), ADR-119
  (LUKS), ADR-272 (credentials), and the two ADR-030 files (cite by filename);
  ADR-118 as a coupling constraint. Verify every ADR number→mechanism mapping
  against the filename at ADR time. `ADR-027-state-supersession` does not exist —
  removed.
- **TR3.** gdpr-gate at plan Phase 2.7 and work Phase 2 exit. Art. 32 TOM bullet
  (named-gap form), Art. 33(5) assessment, DPIA memo, DPD §291, Schedule-4
  wording, Scale-tier copy/`upgrade-copy.ts`/checkout review ride Stage 0 PRs.
- **TR4.** Stage-0 canary criteria fixed in the ADR **before** the run: cold
  start, `git clone`, bun/npm install, tool-call latency, memory per sandbox,
  streaming-delta latency vs bare baseline; fallback-rung trigger defined.
- **TR5.** Fallback rung (shared-kernel hardened launcher: separate minimal
  setuid launcher owning the uid map, fresh pid/net/ipc/uts ns, seccomp deny of
  userns/bpf/perf_event_open/keyctl/io_uring/ptrace, `no_new_privs`, `hidepid=2`,
  `ptrace_scope=2`, per-uid egress) is specified but built only if the canary
  fails; documented honestly as shared-kernel.
- **TR6.** Import-boundary gate for the executor bundle (second esbuild entry);
  `.service-role-allowlist` extended so service-role clients cannot enter it.
- **TR7.** Two-tenant isolation tests (heap/procfs/FS/net/replay-buffer) are a
  merge gate for Stage 1; negative tests for placement/claim mismatch.
- **TR8.** Roadmap rows 4.6 and 4.8 updated at plan time; `roadmap-reconcile`
  re-run.

## Domain Review (carry-forward)

Triad + COO + platform-strategist assessments, then the 2026-10-09 CTO/CLO
challenge review, are recorded in the brainstorm's Challenge Review and Domain
Assessments. Operator overrode leader consensus on Approach A (separate tracks)
in favour of B (unified design) and selected gVisor-from-the-start with
provider portability; delivery gates were decoupled as a result of the review.

## Open Questions

See brainstorm `## Open Questions` (14 items: sandbox granularity, canary
results, supervisor placement/API, workspace attach, broker design, resume,
legacy runner, factory split, network policy, provider list, drain/version skew,
bounding-set change, kernel patch cadence, DPIA/Schedule-4 timing).

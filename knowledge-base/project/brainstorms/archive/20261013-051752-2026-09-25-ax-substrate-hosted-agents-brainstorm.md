---
date: 2026-09-25
topic: ax-substrate-hosted-agents
lane: cross-domain
issue: none
---

# Google AX + Agent Substrate as Soleur's hosted agent runtime — evaluation

## What We're Evaluating

Whether [Google AX](https://github.com/google/ax) running on
[Agent Substrate](https://github.com/agent-substrate/substrate) should replace
(or underlie) Soleur's hand-rolled hosted agentic system — the
`apps/web-platform` agent-runner + bwrap-sandbox + per-tenant LUKS workspace
stack — for Soleur users in the hosted webapp/PWA-mobile model (not CLI mode).

Sources read: both READMEs (2026-09-25), `DESIGN.md`/`docs/` table of contents
on AX, ADR-233 (pluggable web agent engine boundary), ADR-075 (agent sandbox
tenant read isolation), `apps/web-platform/infra/main.tf` + `server.tf`.

## What the Projects Are

**Agent Substrate** (`agent-substrate/substrate`, ~3.8k stars, pre-1.0,
"not making any guarantees about backward compatibility"): a
secure-by-default agent *execution runtime*. It maps a large set of "actors"
(agent processes) onto a smaller pool of ready "workers", exploiting the fact
that agent workloads are idle most of the time to get 10x+ density vs standard
container runtimes. Full-state snapshot suspend/resume (<500ms resume,
500+ activations/sec), gVisor/microVM isolation, framework-agnostic (Claude
Code, Codex, ADK, LangChain named explicitly). **Hard dependency: Kubernetes**
— actors schedule onto Pods via an atelet DaemonSet, with PostgreSQL and
rustfs (S3-compatible) for control and snapshot state.

**Google AX** (`google/ax`, ~11k stars, pre-stable: "We will likely introduce
major breaking changes prior to a stable release"): a declarative *orchestrator*
on top of Substrate, deliberately `kubectl`-shaped. Three primitives:

| Primitive | Purpose |
|---|---|
| `Task` | Run untrusted agent code in a sandbox with CPU/memory limits |
| `Workspace` | Pre-wire git repos, MCP servers, skill packages so agents start warm |
| `Model` | Which LLM the platform uses, credentials from a K8s secret |

Plus `ax suspend`/`ax resume` (checkpoint + pause) and `ax ssh` (shell into a
running sandbox). Control plane = Redis + gRPC, deployed with `ko`. It is a
**task** orchestrator — declare a unit of work, run it, suspend/resume it —
built for billions of autonomous workloads per cluster.

## Fit Against Soleur's Stack

| Soleur today | AX/Substrate equivalent |
|---|---|
| `server/agent-runner.ts` + `ws-handler.ts`: interactive bidirectional sessions, mid-turn approvals, cursor resume, stream replay | Nothing equivalent. AX Tasks are declare-run-suspend with `watch`/`ssh`; no approval flow, no per-user streaming session model |
| ADR-233 `agent_engine_runs` pluggable engine boundary (Claude/Codex adapters: start/continue/cancel/reconcile/cursor-resume/approval/erasure/disposal) | Wrong layer — ADR-233's seam is the *engine* boundary; AX slots *below* agent-runner as an execution backend |
| bwrap + seccomp + AppArmor + userns tenant isolation on Docker web hosts (ADR-075, ADR-122; `infra/apparmor-soleur-bwrap.profile`, `seccomp-bwrap.json`) | **This is the layer it would replace** — actor sandboxes multiplexed onto worker pods |
| Per-tenant LUKS workspace volumes (`workspaces-luks.tf`), connected-repo seeding | `Workspace` primitive — conceptually identical (git + MCP pre-wiring) |
| BYOK engine binding resolved per run | `Model` resource — same idea, K8s-secret-backed |
| Hetzner VMs + Terraform + cloud-init, immutable `-replace` redeploys | **Requires Kubernetes** — Hetzner has no managed K8s; adoption means self-managed k3s/kubeadm on hcloud or a GKE pivot |

## Verdict

**Right idea, wrong time, wrong layer. Track, don't adopt.**

1. **Adopting AX/Substrate is ~80% an "adopt Kubernetes" decision.** Soleur
   has zero K8s footprint. Every infra invariant in this repo (immutable
   `terraform -replace` redeploys, LUKS volume lifecycle, vector telemetry,
   hcloud firewall model, no-SSH runbook posture) assumes the VM model. This
   is a foundational pivot, not a component swap.
2. **Scale mismatch.** Substrate's payoff is density at millions of sandboxes
   and billions of tasks. Soleur is at one alpha user recruiting toward ten
   (roadmap row 4.1). The bwrap-on-host model comfortably carries Phase 4 and
   well beyond.
3. **Layer mismatch.** What Soleur would keep is the session plane
   (approvals, streaming, RLS'd persistence, erasure, BYOK binding) — none of
   which AX provides. What AX would replace is only the isolation/lifecycle
   layer, which is the cheapest part of what Soleur already built. The
   integration shape would be "agent-runner dispatches to an AX Task instead
   of local bwrap", which then needs event streaming back through the atenet
   router — real work for no near-term gain. There is no hosted AX; you run
   the whole control plane yourself.
4. **Maturity risk.** Both projects explicitly warn of breaking changes.
   Betting a GDPR surface (tenant workspaces holding user data and connected
   repos) on pre-1.0 control planes contradicts this repo's reliability
   posture.
5. **What is genuinely valuable:** the architecture as a reference. Actor/
   worker multiplexing fits Soleur's session shape exactly (interactive,
   mostly idle). Whole-environment snapshot suspend/resume beats engine-level
   cursor resume for hibernating in-progress work. Warm workspace pools map
   onto connected-repo + workspaces-luks. `kagent` (CNCF, also on Substrate)
   is a second datapoint that this substrate is becoming the standard shape
   for k8s-native agent hosting — when Soleur outgrows the few-VM model, this
   is the strongest open-source path and better than inventing it.

## User-Brand Impact

- **Artifact:** the hosted agent execution substrate (tenant session isolation
  and workspace persistence).
- **Vector:** a premature control-plane migration could regress tenant
  isolation or lose in-flight sessions silently — the worst outcome is one
  user's session/workspace corrupted or exposed during the transition.
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per the standing brainstorm rule).

## Key Decisions

- Do not adopt AX/Substrate now; the gating dependency is Kubernetes, not the
  projects themselves.
- Treat the pair as the reference architecture for the eventual scale-out
  path. Revisit when concurrent hosted sessions outgrow the single-host/
  few-VM bwrap model (order-of-magnitude trigger: sustained >100 concurrent
  agent sessions, or when session hibernation/SQL-less resume becomes a
  product need).
- Steal now, adopt later: the three ideas worth porting into the current
  stack independent of any migration are (a) warm workspace pools (pre-seeded
  connected-repo checkouts), (b) suspend/resume semantics for idle sessions
  (today: engine-level cursor resume only, no whole-environment checkpoint),
  (c) an explicit idle-actor multiplexer before adding raw capacity.
- No GitHub issue filed: the "revisit when" triggers above are the durable
  record, satisfying the defer-in-place preference; a tracking issue would be
  phantom backlog at current scale.

## Open Questions

- Does Substrate's actor model support the mid-turn approval round-trip
  Soleur needs (inbound signals to a suspended-able actor)? Worth a spike
  only if the k8s decision ever flips.
- Could the workspaces-luks per-tenant encrypted-volume model map onto
  Substrate snapshot storage, or does that fight the rustfs snapshot path?
- kagent vs AX as the higher-level layer if k8s is ever adopted — unexamined
  here.

## Domain Assessments

**Assessed:** Engineering, Operations, Product (others: not material — no
marketing surface, no legal/compliance document touched).

### Engineering

**Summary:** Clean seam exists (agent-runner → execution backend) but the
replaced layer is small relative to migration cost. The engine-adapter
boundary (ADR-233) is unaffected either way.

### Operations

**Summary:** A second orchestration stack (k8s + Redis + rustfs + atenet)
alongside Terraform/hcloud contradicts the immutable-redeploy and no-SSH
operating model. Ops cost dominates the benefit at current scale.

### Product

**Summary:** No user-visible capability gained; adoption is invisible
infrastructure work. Phase 4 validation milestones are unaffected.

## Next Steps

None beyond this record. If a future session hits the revisit triggers
above, re-run this evaluation against the then-current Substrate release —
both projects will likely be materially different post-1.0.

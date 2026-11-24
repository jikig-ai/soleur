---
title: Perplexity SPACE as a Stage-0 sandbox spike candidate
date: 2026-10-19
status: complete
epic: 9842
related: [9859, 9867, 9845, 9847, 9864, 9865, 9866, 9854]
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Perplexity SPACE as a Stage-0 spike candidate (epic #9842)

## What We're Building

Not a feature. A decision on whether Perplexity's SPACE (https://github.com/perplexityai/SPACE) belongs in the Stage-0 spike set of the tenant sandboxed executor epic (#9842), and if so where, with what criteria, and with what kill rules. The deliverable is a scoped evaluation plan that amends two existing spikes. It is not an adoption decision.

## What SPACE Is

Self-hosted sandbox platform that runs agent code in Firecracker microVMs, driven by an HTTP API. Rust, Apache-2.0. Repo created 2026-10-01, v0.8.0, 1,602 stars, 133 forks, 100 open issues, last push 2026-10-19 (GitHub API, 2026-10-19).

## Evidence Status

Nothing was deployed or run. Every behaviour claim comes from Perplexity's own README and docs. "Doc-verified" below means the sentence exists in SPACE's docs or source, not that it works.

| Claim | Status | Source |
|---|---|---|
| Repo age, stars, forks, open issues, license | Verified (GitHub API) | `gh api repos/perplexityai/SPACE` |
| Needs Linux x86_64, `/dev/kvm`, `/dev/net/tun`, loop devices, btrfs | Doc-verified | `docs/installation.md` |
| API state in PostgreSQL; templates and snapshots in object storage | Doc-verified | `docs/architecture.md` |
| Direct (non-Kubernetes) adapter and a Kubernetes adapter | Doc-verified | `docs/architecture.md` |
| Pause (memory resident, not durable) vs suspend (memory + runtime + rootfs snapshot) vs wake | Doc-verified | `docs/architecture.md` |
| Default auto-suspend after 6 hours idle | Doc-verified | `docs/architecture.md` |
| Credential rules exist, require `tls_interception=on`, inject headers for GET/POST/HEAD | Doc-verified (source error string + `docs/ecw-network-policy.md`) | `crates/libs/net/common/src/lib.rs` |
| TLS interception exemptions bypass credential injection | Doc-verified | `docs/architecture.md` |
| Breaking changes planned up to 0.9.0, then stabilisation; guest versions `>=0.1.0 <0.9.0` supported by 0.8 hosts | Doc-verified | `docs/versioning.md` |
| E2B wrapper tested with the Python SDK only; `mcp`, `volumeMounts`, `iam` create capabilities unsupported | Doc-verified | `docs/ecw.md` |
| Telemetry: Datadog or OTLP, selector-driven, off when no backend is built or configured | Doc-verified | `docs/observability.md` |
| Private vulnerability reporting channel exists | Verified | `SECURITY.md` |
| Credential key never visible inside the guest (env, fs, /proc, snapshots) | **Unverified** | needs spike |
| Streaming (SSE) and Node fetch work under TLS interception with the CLI trust store | **Unverified** | needs spike |
| Default-deny holds against DNS exfiltration and the metadata endpoint | **Unverified** | needs spike |
| Cannot run under agent-sandbox | **Inferred, not verified.** SPACE brings its own controller and sandbox pod; it is not a Kata RuntimeClass | architecture reading |
| No hidden phone-home | **Unverified** | needs egress capture |
| Hetzner/EU deployment path | **Gap.** Reference deployments are Kind and AWS EKS only | `README.md` |

## Fit Against the Epic

| Epic need | SPACE | Assessment |
|---|---|---|
| Hardware isolation (KVM) | One Firecracker microVM per sandbox | Fits. Hetzner Cloud has no KVM, so it needs the same Robot AX42 node as Arm C |
| Credential broker (S3/S12): Anthropic key never in sandbox | Gateway credential rules with TLS interception | Closest match to the goal. Nothing verified |
| Per-sandbox egress (S5) | Default-deny, domain/CIDR allow, operator egress profiles | Fits on paper. S5 adversarial probes still required |
| Session resume (S10) | Suspend/wake snapshot of memory and rootfs | Strong match to the lifecycle half that has no OSS equivalent on a KVM-less host |
| Warm pool (S9) | Warm pools on Kubernetes, base snapshots on a single node | Partial. S9 asks for late-bound LUKS tenant volume attach; SPACE guests use its own btrfs/loop disks and ECW rejects `volumeMounts`. Weakest fit |
| Provider-portable contract (S7) | Plain HTTP API plus E2B wrapper | Fits |
| GDPR | Self-hosted, no new sub-processor if no phone-home | Fine for the spike; see Legal |
| Ops surface | PostgreSQL, object store, controller, API, data plane, workers | Heavy. Replaces the bespoke supervisor with a larger system |

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Fold SPACE into S0 as an optional, time-boxed "Arm E" and into S12 as a second contender next to OpenSandbox. Do not open a new spike and do not reject it. Result is evidence-only until SPACE is past 0.9. SPACE is a competing runtime and control plane, not a Kata drop-in. Biggest technical risk: TLS interception is a trust-boundary risk, not a streaming bug. A MITM CA trusted in every guest, if shared or held on the host, exposes every tenant's plaintext traffic and credentials. Pre-1.0 churn is a close second and is bounded by pinning a commit.

### Product (CPO)

**Summary:** Dissent on S0 placement. A "1-day" Arm E will realistically cost 3-5 days because KVM readiness (S11 #9866) is unverified, and it could delay the Stage-0 gate. Snapshots hold tenant memory, which is the worst surface to trial first on an 18-day-old project. Suspend/wake is real user value but belongs to S10, which is not a Stage-1 requirement, so it must not drive the Stage-0 choice. CPO would add SPACE to S12 only, paper-only, with a go/no-go trigger.

### Legal (CLO)

**Summary:** Spike with synthetic data and no tenant personal data does not engage sub-processor duties; use a spike-only Anthropic key and revoke it afterwards. Apache-2.0 internal use triggers no NOTICE or patent obligation; redistribution would. Production would make the gateway a new processing activity (it decrypts prompts and completions) needing an Art. 30 row and updates to Privacy Policy, Data Protection Disclosure and GDPR Policy, plus #9851, #9852, #9853. Unverified by CLO: Anthropic's current terms on proxying/inspection, SPACE license text, telemetry behaviour, Perplexity relicensing history.

### Marketing, Operations, Sales, Finance, Support

Not relevant to a Stage-0 infrastructure evaluation. Operations overlaps with the KVM node (S11) and is covered under Engineering.

## Reconciliation of CTO and CPO

The two leaders disagree on S0. Per the technical-fork rule the CTO's ruling stands: SPACE enters both S12 and S0 Arm E. CPO's risk guards are adopted as conditions on Arm E, which the CTO already called optional, so they do not contradict the ruling:

- **Ruled by CTO agent:** fold into S0 (Arm E) and S12; no new spike.
- S12 goes first; it is off the critical path.
- Arm E runs only after Arms A-C are complete and only if the S11 KVM node is live and EU-resident. Otherwise Arm E is dropped without penalty.
- Hard timebox of 1 day. Overrun is a drop, not an extension.
- Arm E never blocks the ADR (#9854) or the Stage-0 gate.
- Spike runs use synthetic data and a spike-only Anthropic key.

## Why This Approach

A new spike would duplicate the S0/S3/S5/S9/S10/S11 harness for one candidate. Rejecting outright forgoes the only candidate that targets the lifecycle half (claim, pool, snapshot, resume) which the epic found has no OSS equivalent on a KVM-less host. Fold-in reuses existing workload and probes and keeps the cost of a negative answer to about a day.

## Key Decisions

| Decision | Choice |
|---|---|
| Where SPACE lands | S0 Arm E (conditional) and S12 second contender; no new spike |
| Outcome weight | Evidence only, no adoption, until SPACE is past 0.9 |
| Commit | Pin an exact commit SHA before any run |
| Data | Synthetic workload, spike-only Anthropic key, revoked after |
| Criteria | Fixed in the ADR before the run, not after |
| Productize Candidate | None |

## Criteria To Fix Before The Run (from CTO ruling)

1. Pinned commit SHA; same Claude CLI streaming workload and S5/S3 probes as the other arms.
2. Anthropic key absent from guest env, filesystem, `/proc`, and every suspend snapshot in object storage.
3. Interception CA: per-tenant or shared, where its private key lives, rotation. A shared or host-resident CA is a stop.
4. SSE streaming works under interception with the CA trusted in the Claude CLI's Node trust store; usage and cost data intact.
5. Default-deny holds against DNS exfiltration, metadata endpoint, private nets, loopback, domain fronting, allowed-domain exfiltration.
6. Suspend/wake survives node reboot (S10). Compare against the S9 late-bound LUKS attach.
7. Cold start with and without warm pool or base snapshot, RAM per session, density, and host privilege the control plane needs.
8. EU residency of the object store; ops footprint (Postgres + object store) vs bespoke supervisor.
9. Egress capture to confirm no unexpected outbound traffic (telemetry or phone-home).
10. Pass bar: matches or beats the Kata baseline.

## Stop Conditions

- Credential rules cannot keep the key out of the sandbox.
- Streaming breaks under TLS interception.
- CA key is shared across tenants or held on the host.
- Postgres + object-store footprint exceeds the effort of the bespoke supervisor.
- Not KVM-ready on the EU node within the timebox.

## User-Brand Impact

- **Artifact:** the SPACE evaluation within S0 Arm E and S12 (a sandbox runtime and credential-injection gateway under evaluation).
- **Vector:** a TLS-intercepting gateway sees tenant prompts, completions and the provider key, and suspend snapshots hold tenant memory; a mistake here exposes one tenant's data or the platform key.
- **Threshold:** single-user incident.

Mitigation for the spike itself: no tenant data, spike-only key, pinned SHA, no production traffic.

## Open Questions

1. Does SPACE phone home? Needs an egress capture in the spike. (Parked)
2. Anthropic's current terms on proxying or inspecting API traffic. CLO did not verify. (Parked, needed before any production use)
3. Perplexity relicensing history and long-term stewardship. (Parked)
4. Can SPACE's Kubernetes adapter coexist with agent-sandbox on one k3s node, or does it need its own cluster? (Parked, answer comes from Arm E)
5. LUKS late-bind: any SPACE hook to attach an encrypted tenant volume, given ECW rejects `volumeMounts`. (Parked, S9)
6. Whether Node 24+ `NODE_USE_ENV_PROXY=1` and CA injection behave under SPACE's interception. (Parked, S12)

## Capability Gaps

- Hetzner/EU reference deployment for SPACE does not exist. Evidence: `README.md` repository layout lists only `infra/space/kind/` and `infra/space/aws/reference/`.

## Next Step

Amend S0 (#9859) and S12 (#9867) with the Arm E and second-contender text, the criteria list and the stop conditions above. Posting those amendments to the issues is held until the operator approves.

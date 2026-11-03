---
title: Per-session ephemeral containers for hosted agent sessions are recorded, not adopted
status: proposed
date: 2026-11-03
issue: 9602
related: [9602, 9601, 9543, 9842, 9854, 9773, 9859]
related_adrs: [ADR-075, ADR-068, ADR-079, ADR-272, ADR-311, ADR-122, ADR-119, ADR-052, ADR-096, ADR-078, ADR-062, ADR-027]
tags: [sandbox, isolation, containers, agent-runtime, security, capacity]
brand_survival_threshold: single-user incident
---

# ADR-315: Per-session ephemeral containers for hosted agent sessions are recorded, not adopted

## Status

Proposed. This ADR ships no control. The control in force today is ADR-075 (bwrap sandboxing of Bash commands inside one shared container, with the seccomp and AppArmor controls ADR-075 records). As of 2026-11-03; if this ADR and ADR-075 disagree on the control in force, ADR-075 governs.

- Coverage of that control is the Bash tier.
  File tools run in the CLI process outside bwrap and are covered by the `createSandboxHook` realpath containment, as ADR-075 records (label: read from ADR-075, addendum "2026-10-08 (#5863)", anchor "the file tools run in the CLI process itself"; containment per ADR-075's opening paragraph, anchor "realpath-containment covers file-tools").
- This ADR relates to ADR-075. It amends nothing and supersedes nothing.
- The topology of record belongs to #9854, the pending decision record under epic #9842.
  Its issue body says it amends ADR-068 section 8 (the Phase 4a placement and trigger wording) and ADR-075 Option B (label: unverified, mutable source: issue body, 2026-11-03).
  If #9854's decision merges first with overlapping content, this ADR stays `proposed` and gains one Status line: "Topology of record: the ADR for #9854; this ADR keeps only the option record and measurement gate".
  It is not marked superseded.
- Flip to `adopting` requires all of the following.
  - #9854's merged decision names per-session ephemeral containers on a runc-class runtime as the topology. A #9854 decision for per-tenant containers, or for a gVisor- or Kata-class runtime, leaves this ADR `proposed`, adds the Status line "closed as an option record by the ADR for #9854", and does not flip it.
  - The measurements P2 to P5 in the Decision section are recorded in a dated amendment. P1 is an estimate and is recorded as an estimate, not as a measurement. They are necessary and not sufficient.
  - Before that amendment merges, a CTO ruling records a ceiling for each of P2, P3, P4 and P5 (cold start, memory and CPU per session, concurrency per host, image-pull and warm-pool cost in time and capacity terms), and states that each ceiling was set after the data was seen. A ceiling the data misses leaves this ADR `proposed`.
  - The cost-per-hosted-session ceiling and the go-ahead to adopt are operator-class (money), put as a plain-words question when the measurements land. Any monetary ceiling for P5 is part of that operator-class question, not of the CTO ceiling.
  - The flip is made by the PR that adds the dated amendment, authored by the engineering owner of #9602.
- `adopting` is a decision to plan, not to ship: shipping needs its own PR and operator approval.
  A first trigger starts measurement and does not flip the status.
- "Not adopted" is a sequencing decision gated on evidence. It is not acceptance of the residual risk in ADR-075.
- Residual-risk owner: ADR-075. This ADR neither closes nor accepts that risk.

Labels. Every claim about the system in the ledger rows below, and every claim marked in the text, is labelled `measured`, `read from <file>` (with a content anchor, and the line coordinate where it helps a reader) or `unverified`; option descriptions, pros and cons are unlabelled prose unless marked.
Sources were re-read at origin/main on 2026-11-03.
Claims from an issue body are mutable and carry the read date.

## Context

Driver, at ADR-075's published granularity: the open residuals named in ADR-075's 2026-10-09 addendum (#9873 disposition, anchor "The open residual"). The expectation that this option would close any of them is unverified, and the amendment must say which residual its measurements address.

Terms (glossary.md pins "sandbox" to the bwrap surface and defines no other term used here).
A hosted agent session is one tenant's agent conversation run by the SDK.
"Sandbox" names the bwrap surface; where a gVisor design is meant the text says so. "Container" is the Docker container. "Host" is the Hetzner machine.
"Ephemeral" means created for one hosted agent session and destroyed when it ends.
"Broker" means the credential broker (#9543), which is not shipped. "Canary" means the faithful canary of ADR-079.
"Session" here means the hosted agent session; ADR-075's per-sandboxed-command wording is not restated and no sandbox instances are counted here.
"Per-session container" means one container per hosted agent session; the "per-session" of #5863 is process-level isolation, which is not a container.

Today's shape is recorded by existing ADRs and restated here only as far as they publish it.
The rows below are the claims this ADR rests on; each carries one label.

| # | Claim | Label | Anchor |
|---|---|---|---|
| C1 | Hosted agent sessions run in-process in one multi-tenant container; bwrap is the filesystem isolation between tenants as ADR-075 frames it | read from file:line | ADR-075-agent-sandbox-tenant-read-isolation.md:12-18, anchor "bwrap is the only filesystem isolation between tenants" |
| C2 | The workspace tree is one shared directory visible to every hosted agent session in the container | read from file:line | ADR-075-agent-sandbox-tenant-read-isolation.md:13-14, anchor "one shared host directory"; no host path is restated here |
| C3a | The container memory cap is set in `ci-deploy.sh`, with its derivation in ADR-062; ADR-079 restates the production cap | read from file:line | apps/web-platform/infra/ci-deploy.sh, anchor "PROD_MEMORY_CAP"; ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md:823, anchor "PROD_MEMORY_CAP"; no number is restated here |
| C3b | The per-session overhead of a container is unmeasured here | unverified | the P3 gate below; no measurement is cited |
| C4a | Option B of ADR-075 exits only with #9773 Stage 1 | read from file:line | ADR-075-agent-sandbox-tenant-read-isolation.md:289, anchor "exits only with **#9773 Stage 1**"; the term "#9773 Stage 1" comes from ADR-075 and is not a stage list in #9773's own body |
| C4b | The interim outer-wrap elevation arm was dropped | read from file:line | ADR-075-agent-sandbox-tenant-read-isolation.md:252, anchor "arm-F elevation dropped" |
| C4c | The outer wrap stays flag-off on the shared container | read from file:line | ADR-075-agent-sandbox-tenant-read-isolation.md:281, anchor "stays flag-off on the shared prod container" |
| C5 | Epic #9842 selects a gVisor sandbox per tenant session as its direction; #9854 is the pending decision record | unverified (mutable source: issue body, 2026-11-03) | issue #9842 body ("operator-selected Approach B, gVisor sandbox per session"); issue #9854 body ("ADR for the tenant sandboxed executor topology") |
| C6 | The recorded adoption trigger for the executor topology belongs to #9854 | unverified (mutable source: issue body, 2026-11-03) | issue #9854 body, scope list ("Record the Nomad/k8s and sustained-concurrency triggers in the ADR itself") |
| C7 | Roadmap row 4.6 is "Container-per-workspace isolation" with Trigger column "5+ concurrent users" and issue #673 | read from file:line | knowledge-base/product/roadmap.md:341, anchor "Container-per-workspace isolation" |
| C8 | The credential-broker mechanism was measured, not shipped | read from file:line | ADR-311-credential-broker-mechanism-measured-before-built.md:17, anchor "It ships no broker" |
| C9 | No recorded cold-start, per-session-memory or tenant-count result for a per-session container exists in the searched scope | measured (absence in scope: `git grep -il -E -e 'per-session (ephemeral )?container' -e 'ephemeral container' -e 'container[- ]per[- ]session' origin/main -- apps scripts .github knowledge-base`, paths apps, scripts, .github and knowledge-base, 2026-11-03; every one of the 13 hit files was read and none records such a result); other spellings were not searched, the count excludes this ADR and ADR-316, and whether any record exists outside that scope is unverified | the P2 to P5 gate below |
| C10 | The faithful canary replays the SDK's captured bwrap setup argv against the loaded profile and never reaches `query()`; a topology change needs its own verification path | read from file:line | ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md:120-124, anchor "it never reaches `query()`" |

Why this option is recorded.
Issue #9602 deferred it from #9601 during a brainstorm on 2026-10-06, as an architecture-scale item.
It is to be revisited after slice 1 of #9601 and the credential broker, or on a cross-tenant isolation incident, or on a sandbox-escape vulnerability in bwrap or the SDK sandbox, or when the tenant count makes the shared-container blast radius unacceptable (label: unverified, mutable source: issue body, 2026-11-03).
No decision in this ADR rests only on that issue body; the gate below stands on the measurements it asks for.

Prior deferrals of the same shape.
ADR-075 records per-tenant volume and container isolation as its Option B, "the correct end-state, but ... unbuilt infra", with the status "Deferred (tracked in #5863)" (read from ADR-075, anchor "Deferred (tracked in #5863)").
The #9773 issue body says per-tenant containers were deferred twice on capacity grounds, and #5863 closed on 2026-10-09 as per-session process-level isolation, which is not a container (label: unverified, mutable source: issue bodies, 2026-11-03).
The 2026-09-25 AX/Substrate evaluation recorded in knowledge-base/project/brainstorms/archive/20261013-051752-2026-09-25-ax-substrate-hosted-agents-brainstorm.md recommended not adopting a managed runtime then, because it needed Kubernetes (label: unverified; this ADR did not re-read the evaluation beyond its verdict line).
Row 4.6 of the roadmap is the standing tenant-count trigger (C7).

What per-session containers would change, and what they would not.
The option moves the unit of isolation from a bwrap sandbox inside one shared container (C1) to one container per hosted agent session.
It does not by itself change where the agent loop runs: that depends on the executor protocol of epic #9842 (C5; label: unverified).
Its interaction with the credential controls is also unverified.
A per-session container would be a separate layer from the credential deny of ADR-272 and from the broker, and nothing here measures how they compose.

Relation to the credential broker.
#9543 is open and no broker is shipped (C8).
ADR-311 records that only the mechanism was measured.
Nothing in this ADR depends on a broker existing, and nothing here changes what ADR-272 denies.

Relation to epic #9842.
Epic #9842 and its pending record #9854 own the executor topology (C5, C6).
PR #9832 is open and carries a brainstorm and a spec for that epic and no decision record (label: unverified, mutable source: PR #9832 file list, 2026-11-03), so there is no file collision, only a scope overlap.
#9773 is the earlier per-tenant executor issue that ADR-075 names as the exit for Option B (C4).
#9859 is the epic's three-way comparison spike (label: unverified, mutable source: issue body, 2026-11-03).
If #9854 later claims content this ADR carries, #9854 wins on topology and this ADR gets a follow-up edit that points to it.

### Relations (informational; none implies a dependency, a shipped control or adoption)

- ADR-075: the control in force and the owner of the residual risk; this ADR is its option record for the per-container end-state (C1, C4).
- ADR-068: placement and lease routing across hosts; a per-session container would sit under whatever placement it defines (label: unverified).
- ADR-079: the verification path (C10); it restates the production container memory cap (C3a).
- ADR-272: the credential deny in force for sandboxed Bash; a separate control from anything recorded here.
- ADR-311: records that only the broker mechanism was measured and that it ships no broker (C8).
- ADR-122: delivery and enforcement of container sandbox controls at boot; a per-session container would need the same controls delivered and enforced (label: unverified).
- ADR-119: the encrypted workspace volume and its attach path, which a per-session container would have to reuse (label: unverified).
- ADR-052: the host-level egress allowlist (DOCKER-USER chain); a per-session container would need an egress path under the same allowlist (label: unverified). The per-dispatch egress forwarder is recorded in ADR-278 and ADR-311, and its lifecycle under a per-session container is unverified.
- ADR-096: image pull from the self-hosted registry, which sets the image-pull and warm-pool cost in P5 (label: unverified).
- ADR-078: the deploy swap and cron drain that a per-session container would interact with (label: unverified).
- ADR-062: the derivation of the container memory cap that P3 reads against (C3a).
- ADR-027: the declaring record of AP-013 (process-local state for runners); a per-session container would put runner state under a container lifecycle (label: unverified).

## Considered Options

Dispositions below use only "the control in force", "may be evaluated" and "not evaluated".
No option is called rejected in this ADR.

Option 1, keep ADR-075 as it is.
This is the control in force (C1, C4).
Pros: it exists, the faithful canary replays its setup argv under the loaded profile at deploy (C10; this checks that the sandbox starts, not that tenants are isolated), and it adds no per-session cost.
Cons: it is the shared-container shape whose residual risk ADR-075 records and owns.
Disposition: the control in force.

Option 2, per-session ephemeral containers.
May be evaluated once the gate is met; no commitment to proceed. The flip conditions are in Status.
Pros: a container boundary per hosted agent session instead of a sandbox inside a shared container (label: unverified as a benefit; nothing here measures it).
Cons, naming only costs and dependencies that are already public:

- cold start per session;
- memory and CPU per session on top of what ADR-079 caps;
- image pull and warm pool (ADR-096);
- session resume across teardown;
- workspace attach (ADR-119);
- per-session egress path (ADR-052) and per-dispatch forwarder lifecycle (ADR-278);
- interplay with the deploy swap and the cron drain recorded in ADR-078 (read from ADR-078, title "Graceful cron drain before container swap");
- it does not by itself change where the agent loop runs.

All of these are `unverified` as costs until P2 to P5 are measured.

Option 3, per-tenant long-lived containers.
May be evaluated only under its own gate; P2 to P5 are defined for option 2 and do not transfer.
Pros (label: unverified): no per-session cold start; a tenant's session state would sit in a boundary shared with no other tenant, if the container boundary holds, which nothing here measures.
Cons: residue between one tenant's own sessions, and idle cost against cold start (label: unverified).
The #9842 work names this shape as an option (label: unverified, mutable source: an unmerged spec document carried by PR #9832, 2026-11-03).

Option 4, runtime-level isolation per tenant session.

A gVisor sandbox per tenant session is the operator-selected direction under epic #9842 (Approach B, Stage 0 spikes pending). A Kata-class runtime is a Stage 0 comparison candidate (#9859, #9863), and the issue body does not name it as selected. This ADR neither decides nor ships either; its topology decision is reserved to #9854. Label: unverified (mutable source: issue body #9842, 2026-11-03).

Option 4 carries no disposition word here by design: it is #9854's to decide, and this ADR neither endorses nor dismisses it.

## Decision

Not adopted now. Adoption is gated on the measured preconditions below.

This is a sequencing decision gated on evidence.
It is not acceptance of the residual risk in ADR-075.
Residual-risk owner: ADR-075; this ADR neither closes nor accepts that risk, and no reader should take "not adopted" as "accepted".

Preconditions.
Each of P2 to P5 is a measurement.
For each, the public record carries the machine class and the date only.
The exact kernel release and image digest live in a private measurement record, cited from the dated amendment by an opaque id.
That private record must exist before the amendment merges, or the gate fails.

- P1, tenant-count threshold. This is an estimate and not a measurement.
  The only number quoted is the public roadmap row 4.6 trigger, "5+ concurrent users" with issue #673 (C7).
  Whether that number is sufficient as an adoption threshold for per-session containers is unverified.
  The trigger recorded in #9854 wins on conflict (C6), and alert and capacity thresholds stay in #9854 and are not restated here.
- P2, cold start. p50 and p95 for a per-session container, against a baseline arm that is the production configuration today: the SDK's inner bwrap only, with the outer wrap flag-off (C4).
- P3, memory and CPU per hosted agent session, with and without a per-session container, read against the cap recorded in ADR-079 and ADR-062 (C3a).
- P4, the maximum number of concurrent hosted agent sessions per host, with and without per-session containers.
- P5, image-pull and warm-pool cost, on the registry path ADR-096 records.
- P6, a consistency condition and not a measurement: #9854's merged decision names per-session ephemeral containers on a runc-class runtime as the topology (C5, C6). P2 to P5 are defined for that shape only.

First triggers.
Any of these starts the measurement; none flips the status.

- A cross-tenant isolation incident.
- A vulnerability in bwrap or the SDK sandbox.
- The criteria in the #9602 issue body: slice 1 of #9601 and the credential broker shipped, or a tenant count that makes the shared-container blast radius unacceptable (label: unverified, mutable source: issue body, 2026-11-03). On 2026-11-03 the broker (#9543) is open, so the first criterion is not met. The #673 body also lists a security audit that flags shared-filesystem risk (label: unverified, mutable source: issue body, 2026-11-03).

The response to an actively exploitable sandbox vulnerability is patching and incident handling, outside this ADR.
These triggers govern only this option's evidence gate. They define only when it starts. They are not the only reason to start it, and no trigger having fired is not a finding that none is warranted.

Numbers.
The numbers here are internal tripwires and estimates, not a commitment, a schedule or a statement that risk below them is acceptable.

No public claim.
At any future adoption, flag creation and legal wording stay operator-class.
No public security claim is made or changed ahead of a measured control, and no claim wider than ADR-075 states is made or implied.
Nothing in this ADR is a statement about how any tenant's hosted agent session is isolated today beyond what ADR-075 already publishes.

## Consequences

- Positive: the option, its evidence gate and its cost axes are recorded in one place, so a later topology decision in #9854 starts from named measurements and not from a blank page.
- Positive: nothing runs differently after this ADR merges. The control in force, its verification path (C10) and its residual risk (ADR-075) are exactly as they were.
- Negative: a record that does not ship a control can be read as one.
  The Status line, the paired "not acceptance of the residual risk in ADR-075" sentence and the no-public-claim clause exist to prevent that reading.
  A security answer is operator-class wording and does not quote this ADR; engineering facts about the control in force are read from ADR-075.
- Negative: the overlap with #9854 means a later edit may be needed to point at the topology of record. That edit is expected and cheap, and it does not change this ADR's status.
- Neutral: the option stays reachable from #9602, which remains open as the tracker; this ADR names no schedule for the measurements.
- Risk: the cost figures P2 to P5 ask for are unverified until measured, and a number measured on one machine class does not carry to another; each measurement records its machine class for that reason.

## Cost Impacts

No spend now. The ADR is a record and changes no runtime.
Adoption cost per hosted agent session is unverified and is driven by P3 to P5: memory and CPU per session, image pull and warm pool, and concurrency per host.
Memory caps are recorded in ADR-079 and ADR-062 and are cited, not restated.
The cost-per-hosted-session ceiling is an operator-class decision made after the measurements land, not before.

## NFR Impacts

- NFR-010 (Linear Horizontal Scalability): the register records the Agent Runtime as Partial, with natural per-user sharding.
  Per-session containers would change how that shards, which is why P4 measures concurrency per host.
  No row changes tier now and the register is not edited.
- NFR-019 (Auto-Scaling): ADR-068 is the governing record for the multi-host shape.
  A per-session container would sit under the placement it defines (label: unverified); the register is not edited.
- NFR-038 (Least Privilege Container Images): the register records the Agent Runtime as Partial (nearest register row; its evidence is image hardening, not runtime isolation).
  A per-session container would need its own hardening and image, which is why ADR-122 and ADR-096 are related; nothing in this ADR changes the current rating.

## Principle Alignment

- AP-011 (ADRs for architecture decisions): Aligned.
  An option that is architecture-scale and deferred gets a decision record with an evidence gate, as the principle asks, and not a silent backlog entry.
- AP-013 (Process-local state for runner sessions): N/A, not changed by this ADR.
  A per-session container would put runner-session state under a container lifecycle, and session resume across teardown is one of the unverified costs in option 2.
  The principle's declaring record in the register is ADR-027; ADR-068 makes process-local state host-affine (NFR-019). This ADR relates to ADR-027 and ADR-068 and amends neither.
- AP-021 (Diagnostic honesty): Aligned, applied by analogy (the register scopes AP-021 to operator-facing messages).
  Every ledger claim is labelled measured, read from a file or unverified, and a negative search carries its command, paths and date (C9).
  No cause or benefit is named that a job did not measure.

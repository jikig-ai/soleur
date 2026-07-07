---
date: 2026-07-07
topic: extract inngest to its own dedicated singleton host
issue: 6178
branch: feat-inngest-dedicated-host
pr: 6180
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm — Extract Inngest to Its Own Dedicated Host (#6178)

## What We're Building

Extract the self-hosted Inngest server (Soleur's durable trigger / cron-scheduler
control plane) **off the web backends** onto its **own dedicated private-network
Hetzner host**, modelled on the `git-data.tf` / `registry.tf` precedent. Inngest
becomes a **network-reachable singleton**: web backends reach it over the private
subnet instead of loopback, and the Inngest server is **removed from web
`cloud-init`** so exactly-one-instance is *enforced by topology*, not by
convention.

This is scoped to a **single dedicated host** (accept a ~seconds restart gap,
covered by Postgres durability + Inngest cron catch-up). A failover-pair HA
topology is **explicitly deferred** to a follow-up ADR increment, gated on a
measured need.

## Why This Approach

The issue was filed against a co-location that couples cold-boot and pollutes the
deploy tunnel. Investigation reframed it twice:

1. **The two cited failures are real but were only half the story.** The
   `/var/lib/inngest` hard mount (`webhook.service:45`, no optional `-` prefix)
   bricks a fresh host with 226/NAMESPACE; the shared `deploy.soleur.ai` tunnel
   (id `6410c1ec`) let a half-provisioned web-2 round-robin-poison the deploy
   control-plane → 502s. Both are decoupling bugs.

2. **The load-bearing constraint is the operator's target-state, not the bugs.**
   The goal is **active-active** web-1 + web-2 (and more backends later) all
   serving traffic — NOT web-1-primary/web-2-failover. The current "web-2 pinned
   at LB weight 0" is a temporary bootstrap state.

Under active-active-N, co-located loopback Inngest is a **correctness defect**:
every web host boots its own Inngest against the *same* prd-scoped Supabase
Postgres backend with **no leader gate and no cron dedup**, so N schedulers fire
every cron → guaranteed N-times double-fire. Inngest is a **singleton control
plane** that must fire each scheduled function exactly once regardless of backend
count. Therefore extraction to a network-reachable singleton is **mandatory**,
independent of any availability goal.

**Why a single host (not an HA pair) now:** self-hosted OSS Inngest v1.x is
**single-process / single-writer** — multi-server HA is an unreleased roadmap
item (vendor-confirmed). A true active-active Inngest is *impossible* with the
OSS server; the only vendor-supported HA is managed Inngest Cloud. So "HA host"
in the issue title can only mean a self-managed **primary/standby failover** pair
(still not active-active, and the hard part is shared/HA Redis) or a **single
dedicated host** relying on Postgres durability + cron catch-up across a brief
restart. The operator chose the single host: it removes the double-fire defect
and both couplings, unblocks active-active web immediately, at ~1/N the scope of
a failover pair. Because Inngest is now **stateless compute** (durable state in
external Supabase Postgres + local Redis AOF), the `git-data.tf` precedent (a
stateful durable-volume host) transfers for the *provisioning pattern* but not
its *durable-host rationale*.

**Why extraction retires the tunnel coupling for free:** a private-net-only
Inngest host needs no public Cloudflare tunnel at all (only the app talks to it,
over the private subnet). The `deploy.soleur.ai` pollution class disappears
rather than being patched. Expose the Inngest dashboard via its own dedicated
tunnel only if operators need it.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Extract Inngest to a dedicated single private-net Hetzner host** | Active-active-N web makes co-located loopback Inngest a guaranteed cron-double-fire defect; singleton must live off the data-plane |
| 2 | **Single host now; failover-pair HA deferred** | OSS Inngest is single-writer (no active-active HA); single host + Postgres durability + cron catch-up is the smallest correct step |
| 3 | **Remove Inngest from web `cloud-init`** | Enforce the singleton by topology, not convention — otherwise a new backend re-introduces the double-fire |
| 4 | **Retire the shared `deploy.soleur.ai` tunnel coupling** | Private-net-only host needs no public tunnel; kills the deploy-control-plane 502 class as a side-effect |
| 5 | **Fix `/var/lib/inngest` hard mount** (`webhook.service:45` + `cloud-init.yml:245`) | Same-step non-negotiable: otherwise the new host cold-boot-bricks 226/NAMESPACE |
| 6 | **IaC precedent = `git-data.tf` / `registry.tf`** | Private-subnet-attached host, bootstrapped purely from `terraform apply` + cloud-init, no public ingress; new TF must carry attestation (`hr-every-new-terraform-root`) |
| 7 | **Local Redis on the Inngest host's own volume; keep external EU Supabase Postgres** | Single-server Redis is fine (per-host local); Postgres residency unchanged (no CLO trigger) |
| 8 | **Record an ADR** superseding #6178's premise | The singleton-extraction + single-vs-HA + Connect-vs-VIP choices are cross-boundary architecture decisions |
| 9 | **Coordinate sequencing with the in-flight Phase-2 datastore cutover** | Cutover (ADR-030 `status: adopting`) is built but not confirmed-run; don't compound two unverified state changes — extraction touches host/topology, cutover touches storage, so they're separable but must not interleave on the host state slot |

## Open Questions

1. **Fan-out mechanism — `--sdk-url` VIP vs. Inngest Connect (`:8289`).** The
   research agent confirmed self-hosted accepts multiple `--sdk-url` targets (or a
   single private LB VIP fronting N backends) — the clearly-documented path. The
   platform-strategist favored **Connect** (backends dial *out* to the `:8289`
   gateway, auto-scaling as hosts join). Picking VIP-now-Connect-later = two
   migrations of every backend's Inngest wiring, so **the ADR must settle this up
   front.** Current lean: **VIP-first** (lowest risk, documented), Connect as a
   fast-follow if backend churn makes registration drift painful. **Needs a
   short plan-time spike to confirm Connect stability on self-hosted v1.19.4.**
2. **Redis continuity across an Inngest restart/host-recreate.** Redis AOF holds
   the in-flight queue; run history is in Postgres. Confirm Inngest re-derives
   pending work from Postgres on restart vs. needing Redis continuity — the
   Phase-2 cutover's `verify-wiped-volume` op is the existing machinery to test
   this. Determines the Redis volume's backup/attach requirements.
3. **`--sdk-url` reachability + private-network wiring.** The app→Inngest (event
   send) and Inngest→app (function invoke) paths become private-subnet hops.
   Confirm firewall rules (`firewall.tf`) and `hcloud_server_network`
   (`network.tf`) attach the Inngest host to the same subnet; confirm the app
   container's `INNGEST_BASE_URL` moves from `host.docker.internal:8288` to the
   Inngest host's private IP.
4. **Deferral trigger for the failover-pair HA (#follow-up).** Define the
   measured signal that promotes B2 from deferred to scoped (e.g., cumulative
   Inngest downtime measurably delaying agent-run SLAs; or an availability
   requirement that a ~seconds restart gap violates).

## User-Brand Impact

- **Artifact:** the Inngest durable trigger / cron-scheduler control plane (the
  substrate that fires Soleur's autonomous agent runs and scheduled work).
- **Vector:** a mis-extraction (or the un-fixed double-fire) causes crons/agent
  runs to fire zero or N times, or a fresh backend to cold-boot-brick — silently
  dropping or duplicating a user's scheduled agent work with no error surfaced.
- **Threshold:** single-user incident.

Tagged **user-brand-critical** (auto, per #5175). The plan derived from this
brainstorm inherits `Brand-survival threshold: single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Initially recommended in-place decouple (host = YAGNI) under the
single-active premise; on the corrected active-active-N premise, extraction to a
singleton is mandatory (co-located loopback = cron double-fire). Enforce the
singleton by removing Inngest from web cloud-init; fix the `/var/lib/inngest`
mount in the same step; record an ADR superseding #6178's premise.

### Engineering / Infra (platform-strategist)

**Summary:** Under active-active-N, recommends **B1 single dedicated host now**
(local Redis on own volume, external Postgres), **B2 HA-pair deferred** (hard
part is shared/HA Redis, not Inngest), **B3 coordinated cluster rejected** (OSS
`start` is single-node). `git-data.tf`/`registry.tf` are the right IaC
precedent; extraction retires the `deploy.soleur.ai` tunnel coupling. The
Connect-vs-VIP fan-out fork must be decided in the ADR up front.

### Product (CPO)

**Summary:** Both cited failure classes (226/NAMESPACE brick, tunnel-pollution
502s) are single-user-incident-grade because autonomous agent runs are the
product and Inngest is their trigger spine. Gate scope to the minimal correct
step; the single-active guard / singleton enforcement is load-bearing, not
optional defense-in-depth (verified: nothing in code prevents a second active
Inngest today).

### Legal (CLO)

**Summary:** No data-residency / sub-processor / GDPR / Article-30 obligation is
triggered by moving the Inngest binary between EU Hetzner hosts or giving it its
own tunnel; durable state already lives in the dedicated EU Supabase project +
host-local Redis. **Caveat:** the deferred *managed Inngest Cloud* option WOULD
reverse this posture (new sub-processor + residency change) and require CLO
sign-off — it was declined in favor of staying self-hosted.

## Session Errors

1. **Concurrent `cleanup-merged` wiped the freshly-created worktree** before its
   branch was pushed (the exact race in
   `2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md`), despite the
   session lease. First `draft-pr` failed with a `getcwd` error because the
   directory was removed mid-operation. Recovered by recreating the worktree and
   pushing immediately. Reinforces: push the branch the instant the worktree
   exists, before any other command.
2. **Premise pivoted twice.** The issue framed the fix as "extract to an HA host";
   the first leader round (premised on "single-active by design, HA moot")
   recommended in-place decouple + close as YAGNI. The operator then supplied the
   real target-state (active-active-N web cluster), which *reversed* the verdict
   to mandatory extraction. Lesson: the target-state assumption fed to leaders is
   load-bearing — surface and confirm it with the operator BEFORE the first
   leader spawn, not after. The `hr-verify-repo-capability-claim-before-assert`
   discipline caught the second load-bearing fact (OSS single-writer) before it
   shaped a wrong "active-active Inngest cluster" design.

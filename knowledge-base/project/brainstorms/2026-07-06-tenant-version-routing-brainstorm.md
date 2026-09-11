---
date: 2026-07-06
topic: tenant-targeted version routing (canary / hold-back)
issue: 6080
branch: feat-tenant-version-routing
pr: 6089
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Tenant-Targeted Version Routing — Brainstorm

## What We're Building

A way to route **specific users/organizations to a specific app version** — so we
can canary a new build to a hand-picked cohort (dogfood orgs first) or **hold a
regressed tenant on the last-good build** while we fix forward, **without affecting
any other tenant**. This is the *fine-grained, tenant-targeted* counterpart to
**#6027** (the *coarse* all-traffic LB-weight GA cutover).

It composes on top of **ADR-068** (multi-host `/workspaces`, web-1 + web-2), whose
Phase 3 GA amendment already chose **user-sticky routing**: a session routes to the
host holding *that user's* worktree write-lease. Version is therefore **host-granular**
today (one Node process = one baked `BUILD_SHA`, `health.ts:97`), so a version pin is
really a **placement constraint** on *which host* may serve a pinned tenant.

**Scope decision (operator):** ship the control plane **now** (single-host-today
increment) and **design** the routing enforcement for activation at the ADR-068 3.D
multi-host cutover. Refined by CTO+CPO convergence (see Domain Assessments): the pin
*table* routes to nothing at `replicas=1`, but two now-shippable pieces have real
standalone value:
1. **Version-tagged observability** — today Sentry emits **no** `release`/version tag
   at all; add it so per-version × per-cohort error/request splits work the *day* a
   second version exists.
2. **The Postgres pin table + agent-invokable pin skill + audit ledger** — the durable,
   testable operator/agent interface and audit trail, resolving to a no-op default
   (GA) until enforcement activates.
The **routing enforcement** (lease-acquisition version constraint) is **designed now,
built when multi-host is live** — it is unexercisable and risky before `replicas>1`
with heterogeneous image tags exists.

## Why This Approach

The issue asked us to *compare* three enforcement points. The design cycle produced a
**decisive** answer rather than a menu:

| Enforcement point | Verdict |
|---|---|
| **Owner-side router / lease** (extend `session-router.ts`) | **Chosen.** The only point coherent with ADR-068's lease-as-placement-authority. Routing already *derives from* the lease, so the version pin must too. |
| Cloudflare LB / Worker on a signed tenant claim | **Rejected** — dies for the exact reason ADR-068 rejected edge affinity (Option D): a signed claim can *route* a request but cannot *guarantee* the lease-holding host runs the pinned image → split-brain. |
| App-level version-pin read at request time | **Impossible** — one process = one `BUILD_SHA`; a host physically cannot serve two versions without in-process multi-version (sub-process pool / module federation), which is large and out of scope. |

**The pin must bind at lease *acquisition*, not only at read-time routing.** Because
ADR-068 failover moves a user's lease to another host on crash, a read-time-only pin
would silently bounce a held-back tenant onto a new-version host — defeating the pin's
purpose. Binding version-eligibility into `acquireWorktreeLease` makes the placement
authority and the pin resolve **transactionally** in one store.

**Control plane = Postgres pin table** (not Flagsmith, not Doppler): it resolves
transactionally with the worktree lease, is per-tenant hot-editable + auditable, and
its schema **cannot express "everyone"** (RLS/CHECK forbids a null/wildcard principal),
making the blast-radius contract fail-safe *by construction*. Flagsmith segments
(ADR-043 precedent) were considered but are a request-time read → failover-bounce risk
+ two sources of truth. Doppler config has no per-pin TTL/audit and isn't agent-native.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Enforcement point = **owner-side router / lease** (`session-router.ts` + `worktree-write-lease.ts`) | Only point coherent with ADR-068 lease-as-placement-authority; edge + app-level both fail. |
| D2 | Pin binds at **lease acquisition**, not read-time routing only | Failover would otherwise bounce a held-back tenant onto the new version. |
| D3 | Control plane = **Postgres `tenant_version_pin` table** | Transactional with the lease; auditable; hot-editable; TTL-capable. |
| D4 | Blast-radius contract enforced **in schema** (RLS/CHECK forbids null/wildcard principal) | Default cohort "everyone else → current GA" is fail-safe by construction; a pin can only ADD. |
| D5 | **Hold-back = fail-closed** on missing pinned host; **canary = fall through to GA** | Branch on pin `reason`. Serving a held-back tenant the new build re-introduces the exact regression the pin exists to avoid. |
| D6 | Ship **now**: version-tagged observability + pin table + agent-invokable pin skill (no-op default). **Design now, build at 3.D**: routing enforcement. | Table routes to nothing at `replicas=1`; observability + interface + audit have standalone value; enforcement is unexercisable/risky pre-multi-host. |
| D7 | Pin control plane is **operator-only + agent-invokable** (skill/MCP tool, modeled on `flag-set-role`), never UI-only | Agent-user parity (hard requirement); customers don't pick their build. |
| D8 | Every pin carries a **TTL / `expires_at`** | A forgotten hold-back silently strands a customer on an unpatched build (security/GDPR debt) — the CPO "sleeper" guardrail. |
| D9 | Author an **ADR** extending ADR-068's placement model | This changes the lease-acquisition contract; a plan deliverable per workflow gate. |
| D10 | Version routing is **distinct from Flagsmith flags**, but reuses their *shape* (per-org segment, audit, agent-skill, Doppler mirror) | Flags toggle behavior *within* one image; version routing selects *which image* serves. |

## Open Questions

- **OQ1 — Principal granularity precedence.** Both `organization_id` and `user_id` are
  valid pin keys. When both a user-level and an org-level pin match, which wins? (Likely
  most-specific-wins = user over org, but confirm at plan time against the lease's
  per-user `worktree_id`.)
- **OQ2 — Fail-closed UX.** What exactly does a held-back tenant see when their pinned
  version has no live host? (Maintenance page? Retry-with-backoff until the host
  returns? Operator alert?) A design detail for the enforcement build.
- **OQ3 — `SOLEUR_HOST_ROSTER` host→tag annotation.** The roster is host_id→address
  today; version routing needs host_id→image-tag too. Confirm whether this annotation
  lives in the roster JSON or is read from each host's `/health` `BUILD_VERSION` at
  routing time (freshness vs. config-drift trade-off).
- **OQ4 — Canary promotion / rollback flow.** Out of MVP scope (YAGNI: no weighted
  rollout, no auto-promotion, no experiment framework), but note the eventual promote
  ("canary cohort → GA") and rollback verbs the pin skill will need.

## User-Brand Impact

- **Artifact:** the `tenant_version_pin` control plane + the lease-acquisition version
  constraint in `session-router.ts` / `worktree-write-lease.ts` (the thing that decides
  which app version a given tenant is served).
- **Vector:** a routing/enforcement defect lets a pin touch the **default cohort** —
  inverting the canary tool's purpose by taking down GA for everyone; or a silently
  fallen-through hold-back re-exposes a regressed customer to the exact broken build.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Engineering, Product, Legal

### Engineering (CTO)

**Summary:** Only the owner-side router / lease enforcement point is coherent (edge dies
like ADR-068 Option D; app-level is impossible — one process, one `BUILD_SHA`). The pin
must bind at **lease acquisition** or failover defeats hold-back. Recommends a Postgres
`tenant_version_pin` table transactional with the lease, an additive-only blast-radius
invariant enforced in schema (no null/wildcard principal), and `reason`-branched
failover (canary→GA, hold-back→fail-closed). **Biggest risk: premature** — single-host
cannot run two versions at all; zero substrate until #6027 lands `replicas>1` with
heterogeneous tags. Cheapest observability: stamp `(version=BUILD_SHA, cohort)` as
Sentry scope tags + a Better Stack field inside `observability.ts`. No capability gaps.

### Product (CPO)

**Summary:** Design now, build enforcement when the substrate lands — the pin table is
inert at `replicas=1`. The genuinely early-shippable piece is **version-tagged telemetry**
(cohort-split works the day a 2nd version exists). Operator-only + **agent-invokable**
(hard parity requirement, model on `flag-set-role`), never UI-only. MVP = pin table + GA
default + pins-only-ADD fail-safe + cohort-split observability; **no** weighted rollout /
auto-promotion / experiment framework (YAGNI). Use-case ranking: **canary #1** (only live
subject pre-GA), **hold-back #2** (rank-1 the moment paying users exist), A/B #3 (no
traffic, no statistical power). Top guardrails: (1) default-never-affected invariant in
code + audit; (2) **pin auto-expiry/TTL** (the sleeper); (3) write confirmation. Distinct
from Flagsmith flags but reuse their *shape*.

### Legal (CLO)

**Summary:** **PROCEED, no legal gate.** The tenant→version map is ordinary operational
routing metadata (LB-config class, Art. 6(1)(f) legitimate interest) — **no Article 30
register row**, mirrors the `inbox_item` precedent. No SLA/consumer-transparency exposure
today (no arms-length paid tenant with an uptime/fix contract). **Forward trigger, not a
live gate:** once the first arms-length paid tenant with an SLA exists, deliberately
pinning them to a build with a *known data-integrity/security defect* could create
SLA/consumer-transparency exposure — note in design. No statutory WORM mandate for the
pin ledger (audit hygiene is a CTO/security concern, not legal).

## Capability Gaps

None. The CTO confirmed existing engineering agents cover the eventual build; no missing
stack/tooling. The only "gap" is substrate readiness (multi-host live at `replicas>1`),
which is tracked by #6027 / ADR-068 Phase 3 — a sequencing dependency, not a capability
gap.

## Productize Candidate

None net-new — the pin control plane *is itself* the reusable artifact (an
agent-invokable pin skill modeled on `flag-set-role`), captured as an MVP deliverable
(D7), not a follow-up.

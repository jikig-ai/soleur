---
feature: tenant-version-routing
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
issue: 6080
date: 2026-07-06
branch: feat-tenant-version-routing
pr: 6089
brainstorm: knowledge-base/project/brainstorms/2026-07-06-tenant-version-routing-brainstorm.md
related:
  - knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md
  - "#6027 (coarse all-traffic GA cutover orchestrator)"
---

# Spec — Tenant-Targeted Version Routing (canary / hold-back)

## Problem Statement

Today a deploy swaps the running app version for **everyone** on the serving origin at
once (`ci-deploy.sh` pulls one image tag; every host runs the same `BUILD_SHA`). There
is no way to canary a new version to a hand-picked cohort before general rollout, nor to
hold a regressed tenant on the last-good build while fixing forward — both without
affecting other tenants. This is the fail-safe primitive that lets us ship confidently,
and the *fine-grained* counterpart to the *coarse* all-traffic cutover (#6027).

Version is **host-granular**: one Node process = one baked `BUILD_SHA`. ADR-068 already
routes each user to the host holding their per-user worktree write-lease (user-sticky
routing). A version pin is therefore a **placement constraint** on which host may serve a
pinned tenant, and must compose with the lease, not fight it.

## Goals

- G1: An auditable, hot-editable, agent-invokable **tenant→version control plane** (a
  Postgres `tenant_version_pin` table + a pin skill modeled on `flag-set-role`).
- G2: A **blast-radius contract** that is fail-safe *by construction*: a pin can only ADD
  a per-principal override; the default cohort ("everyone else → current GA") is never
  affected. Enforced in schema (no null/wildcard principal expressible).
- G3: **Version-tagged observability** — per-version × per-cohort request/error splits via
  Sentry scope tags + a Better Stack field, shippable now (Sentry emits no version tag
  today).
- G4: A **designed** enforcement mechanism (lease-acquisition version constraint) that
  activates at the ADR-068 3.D multi-host cutover, with `reason`-branched failover
  (canary→GA, hold-back→fail-closed).

## Non-Goals

- NG1: Building the routing **enforcement** now. It is unexercisable at `replicas=1` and
  risky before heterogeneous-tag multi-host is live (#6027 / ADR-068 Phase 3). Designed
  now; built then.
- NG2: In-process multi-version (sub-process pool / module federation) so one host serves
  two versions — large, out of scope.
- NG3: Weighted/percentage rollout, auto-promotion, or an A/B experiment framework (YAGNI:
  no traffic, no statistical power pre-beta).
- NG4: Edge (Cloudflare LB / Worker) or app-level enforcement — both proven incoherent in
  the design cycle (see FR/brainstorm).
- NG5: A customer-facing UI to self-select a build. Operator-only + agent-invokable.

## Functional Requirements

- **FR1** — `tenant_version_pin` table: `(principal_type ['org'|'user'], principal_id,
  target_tag, reason ['canary'|'hold-back'], expires_at, created_by, created_at)`. Same
  Postgres store as `worktree_write_lease` so pin + placement resolve transactionally.
- **FR2** — Schema-enforced blast-radius invariant: RLS/CHECK forbids a null / empty /
  wildcard `principal_id`; the table cannot express "everyone". Default = row absence → GA.
- **FR3** — Agent-invokable pin skill (set / clear / list), modeled on `flag-set-role`,
  with a write-confirmation and a per-pin audit record. Never UI-only (agent-user parity).
- **FR4** — Every pin carries a TTL (`expires_at`); an expired pin resolves to GA. Prevents
  a forgotten hold-back silently stranding a customer on an unpatched build.
- **FR5** — Version-tagged observability: stamp `(version=BUILD_SHA, cohort)` as Sentry
  scope tags + a Better Stack structured field in `observability.ts`; emit the same pair on
  session metrics. Ships independently of enforcement.
- **FR6** (designed, built at 3.D) — Enforcement in `session-router.ts` /
  `worktree-write-lease.ts`: the version pin becomes a **host-eligibility constraint at
  lease acquisition**. A pinned tenant may only acquire/hold a lease on a host running the
  pinned tag.
- **FR7** (designed, built at 3.D) — `reason`-branched failover: if no host runs the pinned
  tag, `canary` falls through to GA; `hold-back` **fails closed** (maintenance/refuse)
  rather than serve the regressed-against new build.

## Technical Requirements

- **TR1** — Enforcement point is owner-side (router/lease) only. Edge (signed claim) is
  rejected for the same reason ADR-068 rejected Option D (routes but can't guarantee the
  lease-holder's image → split-brain); app-level read is impossible (one process, one SHA).
- **TR2** — `SOLEUR_HOST_ROSTER` gains a host_id→image-tag annotation (or the router reads
  each host's `/health` `BUILD_VERSION`) so it can map a target tag to eligible hosts. (OQ3.)
- **TR3** — Enforcement gated behind `isGitDataStoreEnabled()` — entirely inert until the
  3.D cutover, exactly like the existing `session-router.ts`.
- **TR4** — Authored **ADR** extending ADR-068's placement model (the lease-acquisition
  contract changes). Plan deliverable.
- **TR5** — Most-specific-principal precedence when both a user and an org pin match (OQ1) —
  resolve at plan time against the per-user `worktree_id`.

## Open Questions

Carried from the brainstorm: OQ1 principal precedence, OQ2 fail-closed UX, OQ3 roster
host→tag annotation vs `/health` read, OQ4 promote/rollback verbs. See brainstorm.

## Legal / Compliance Note

CLO: PROCEED, no gate today (operational routing metadata, no Art. 30 row). **Forward
trigger:** once an arms-length paid tenant with an SLA exists, deliberately holding them on
a build with a *known* data-integrity/security defect could create SLA/consumer-transparency
exposure — revisit then.

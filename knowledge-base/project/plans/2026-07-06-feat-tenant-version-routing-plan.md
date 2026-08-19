---
title: "feat(infra): tenant-targeted version routing — control plane + observability (Slice 1)"
issue: 6080
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-06
branch: feat-tenant-version-routing
pr: 6089
brainstorm: knowledge-base/project/brainstorms/2026-07-06-tenant-version-routing-brainstorm.md
spec: knowledge-base/project/specs/feat-tenant-version-routing/spec.md
related:
  - knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md
  - "#6027 (coarse all-traffic GA cutover orchestrator — the enforcement-slice sequencing dependency)"
---

# Tenant-Targeted Version Routing — Implementation Plan

## Overview

Pin specific orgs/users to a specific app version (canary / hold-back) without
affecting other tenants — the fine-grained counterpart to #6027's coarse
all-traffic cutover. Per the brainstorm design cycle, the enforcement point is
**decisively owner-side (the lease)**; edge LB/Worker and app-level reads were
both rejected (see ADR-091 §Alternatives).

**This PR ships Slice 1 only** (operator's "ship the control plane now"):

1. **Control plane** — a Postgres `tenant_version_pin` table (migration 123,
   modeled 1:1 on `122_inbox_item.sql`) + an agent-invokable `version-pin` skill
   (set/clear/list, modeled on `flag-set-role`). Blast-radius contract enforced
   **in schema** (principal_id `NOT NULL`, no wildcard → default cohort fail-safe
   by construction). Every pin carries a TTL.
2. **Observability** — a per-request **cohort** Sentry scope tag (`ga` | `canary`
   | `hold-back`), so a pinned tenant's error/request rate is splittable the day a
   pin is set — even before routing enforcement exists.
3. **ADR-091 + C4** — records the lease-acquisition version-constraint design as
   the target state (`status: adopting`), extending ADR-068's placement model.

**Slice 2 (routing enforcement) is DESIGNED here (ADR-091 + spec FR6/FR7) and
BUILT LATER** — deferred to a tracking issue gated on ADR-068 Phase 3 being live
at `replicas>1` (#6027). It is unexercisable and risky at `replicas=1` (one host
runs one image; there is nothing to route *to*). Slice 1's pin table + cohort tag
are inert-safe at `replicas=1`: pins resolve to a no-op default (GA) and only
label telemetry.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "Sentry emits **no** release/version tag today" (FR5) | **Partially false.** `sentry.server.config.ts:22` + `sentry.client.config.ts:106` already set `release: sentryRelease` (from `BUILD_VERSION`/`BUILD_SHA`, `health.ts:96-97`). Process-version IS on every event. | Net-new observability narrows to the **cohort** tag (which pin cohort a tenant is in) — NOT a redundant `version=BUILD_SHA` scope tag. A *per-served-version* tag (serving host's version ≠ coordinator's `release` when proxied cross-host) is meaningful only in Slice 2 and is designed there. |
| CTO cited "migration 116" for the lease | Confirmed: `116_worktree_write_lease.sql`; latest migration is `122_inbox_item`. | Pin table = **migration 123**. |
| Pin table needs RLS + no-null-principal + write-path + retention | `122_inbox_item.sql` is a near-exact template: RLS + `REVOKE INSERT/UPDATE/DELETE FROM authenticated` + SECURITY-DEFINER-RPC-only writes + CHECK enums + partial-unique dedup + pg_cron retention sweep. | Model 123 on 122 verbatim; reuse `is_workspace_owner` (mig 098) for org-principal auth. |
| Enforcement in `session-router.ts` / `worktree-write-lease.ts` | Confirmed: `resolveSessionRoute` (`session-router.ts:82`), `acquireWorktreeLease` (`worktree-write-lease.ts:175`), `resolveWorktreeId` (:62), all gated on `isGitDataStoreEnabled()` (`workspace-resolver.ts:56`, default false → inert). | Slice 2 binds the version constraint at `acquireWorktreeLease`; deferred. |
| ADR extends ADR-068 | ADR-068 exists (`...decisions/ADR-068-*.md`), status `adopting`; latest ADR is 090. | New **ADR-091**, `status: adopting`, lineage = ADR-068. |
| Skill-description budget | `SKILL_DESCRIPTION_WORD_BUDGET = 2327` in `components.test.ts:15` at **zero headroom** (2327/2327). | Convention = bump the constant by the new skill's word count with a ledger comment (as the flag family did, +126). NOT a sibling-trim. |

## User-Brand Impact

**If this lands broken, the user experiences:** a routing/enforcement defect (Slice
2) lets a pin touch the **default cohort** — inverting the canary tool by degrading
GA for every tenant; or a silently fallen-through hold-back re-exposes a
regressed customer to the exact broken build. In Slice 1 (this PR), the worst case
is a mislabeled cohort tag (telemetry only, no routing impact).

**If this leaks, the user's data is exposed via:** the `tenant_version_pin` table
holds org/user IDs + a version tag (operational routing metadata — CLO: ordinary,
Art. 6(1)(f), no Art. 30 row). RLS + SECURITY-DEFINER-RPC-only writes bound
exposure exactly as `inbox_item`.

**Brand-survival threshold:** `single-user incident`. `requires_cpo_signoff: true`
(carried from brainstorm; CPO participated in the framing triad). `user-impact-reviewer`
runs at PR review.

## Implementation Phases (Slice 1)

### Phase 0 — Preconditions

- Verify migration 123 is the next free number; `is_workspace_owner(uuid,uuid)`
  exists (mig 098); `ci-deploy.sh:860` `ALLOWED` tag regex `^v[0-9]+\.[0-9]+\.[0-9]+$`
  (reuse verbatim as the `target_tag` CHECK so a pin can never name an
  un-deployable tag).
- Measure current `SKILL_DESCRIPTION_WORD_BUDGET` headroom (0 today) and draft the
  `version-pin` description ≤ ~30 words.

### Phase 1 — Control-plane migration (`123_tenant_version_pin`)

**Files to Create:**
- `apps/web-platform/supabase/migrations/123_tenant_version_pin.sql`
- `apps/web-platform/supabase/migrations/123_tenant_version_pin.down.sql`

Model on `122_inbox_item.sql`:
- Table `public.tenant_version_pin`: `id uuid PK`, `principal_type text NOT NULL
  CHECK (principal_type IN ('org','user'))`, `principal_id uuid NOT NULL` (the
  blast-radius invariant — **no null/wildcard principal is expressible**),
  `target_tag text NOT NULL CHECK (target_tag ~ '^v[0-9]+\.[0-9]+\.[0-9]+$')`,
  `reason text NOT NULL CHECK (reason IN ('canary','hold-back'))`, `expires_at
  timestamptz NOT NULL` (TTL — FR4), `created_by uuid`, `created_at timestamptz
  NOT NULL DEFAULT now()`. `LAWFUL_BASIS` comment mirroring inbox_item.
- Unique index `(principal_type, principal_id)` (one active pin per principal;
  most-specific precedence resolved in the resolver, OQ1).
- RLS: `ENABLE ROW LEVEL SECURITY`; `REVOKE INSERT/UPDATE/DELETE FROM PUBLIC, anon,
  authenticated`; a SELECT policy scoped to workspace Owners (reuse
  `is_workspace_owner`). Writes ONLY via SECURITY DEFINER RPCs
  `set_tenant_version_pin(...)` / `clear_tenant_version_pin(...)` (search_path
  pinned `public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`;
  auth.uid() Owner check; same-error-no-oracle).
- pg_cron sweep `tenant_version_pin_expiry` (guarded like mig 122) deleting rows
  past `expires_at` (an expired pin resolves to GA — FR4).

**Files to Edit:** none (self-contained migration).

### Phase 2 — Agent-invokable `version-pin` skill

**Files to Create:**
- `plugins/soleur/skills/version-pin/SKILL.md` (description ≤ ~30 words,
  third-person voice; sub-commands `set` / `clear` / `list`)
- `plugins/soleur/skills/version-pin/scripts/*.sh` (call the RPCs; write-confirm
  gate + a per-pin audit line, mirroring `flag-set-role`)

**Files to Edit:**
- `plugins/soleur/test/components.test.ts` — bump `SKILL_DESCRIPTION_WORD_BUDGET`
  by exactly the new description's word count; append a ledger comment (`bumped +N
  for #6080 (version-pin skill description, N words, against a 2327/2327
  zero-headroom baseline)`).
- `plugins/soleur/plugin.json` + `README.md` component counts (release-docs).

Agent-user parity (CPO hard requirement): the skill is agent-invokable; no in-app
MCP tool is needed (pinning is an operator/agent rollout action, not an end-user
in-product action — there is no UI surface).

### Phase 3 — Cohort observability tag

**Files to Edit:**
- `apps/web-platform/server/observability.ts` — add `resolveCohort(principalId):
  Promise<'ga'|'canary'|'hold-back'>` (reads the pin table; row absence → `ga`)
  and a helper that stamps `scope.setTag('cohort', ...)` on session events (mirror
  the `sentry-correlation.ts:72` `scope.setTag` shape). Do **NOT** add a
  `version=BUILD_SHA` tag — `release` already carries it (see Reconciliation).
- The session emit site (first-message-auth in `session-router.ts` call path, or
  `session-metrics`) — call the cohort stamp once per session.

**Files to Create:**
- `apps/web-platform/test/tenant-version-pin.test.ts` — RLS shape (pg_policy),
  CHECK-rejects-null-principal, RPC Owner-auth, cohort resolves to `ga` on no-pin
  and to `canary`/`hold-back` on a pin. Runner: vitest via
  `./node_modules/.bin/tsc --noEmit` + `vitest run` (per repo convention — NOT
  `npm run -w`).

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** — `123_tenant_version_pin.sql` creates the table; `pg_policy` returns the
  SELECT policy and zero INSERT/UPDATE/DELETE policies for `authenticated`
  (writes are RPC-only). Verify read-only via `BEGIN; SET LOCAL ROLE ...; ...;
  ROLLBACK;` against DEV (never prod, per `hr-dev-prd-distinct-supabase-projects`).
- **AC2** — a `principal_id = NULL` INSERT is rejected by `NOT NULL`; a
  `target_tag = 'latest'` INSERT is rejected by the semver CHECK. (Schema cannot
  express "everyone" — blast-radius invariant.)
- **AC3** — `set_tenant_version_pin` / `clear_tenant_version_pin` are SECURITY
  DEFINER, `search_path = public, pg_temp`, and reject a non-Owner with the same
  error as a missing row (no existence oracle).
- **AC4** — `version-pin` skill: `set`/`clear`/`list` sub-commands present; each
  write requires confirmation and emits an audit line. Skill-budget test green
  after the `SKILL_DESCRIPTION_WORD_BUDGET` bump.
- **AC5** — `resolveCohort` returns `ga` on no pin; `canary`/`hold-back` mirroring
  the pin `reason`. Cohort tag emitted on session events (unit test asserts the
  `scope.setTag('cohort', ...)` call).
- **AC6** — ADR-091 exists (`status: adopting`); `model.c4` edge
  `coordinator -> supabase` description updated; `c4-code-syntax.test.ts` +
  `c4-render.test.ts` green.
- **AC7** — `tsc --noEmit` clean; full suite green.

### Post-merge (operator / automated)
- **AC8** — migration 123 applied via `web-platform-release.yml#migrate` on merge
  (automated; no operator SSH). `/soleur:ship` verifies migration applied.
- **AC9** — a deferred tracking issue exists for **Slice 2 (routing enforcement)**,
  gated on ADR-068 Phase 3 live at `replicas>1` (#6027), milestone from roadmap.

## Open Code-Review Overlap

1 open scope-out touches a planned file:
- **#3739** (`extract reportSilentFallbackWithUser helper — collapse 11-site
  withIsolationScope+setUser duplication`) touches `observability.ts`, which
  Phase 3 also edits (adds `resolveCohort` + the cohort-tag helper).
  **Disposition: Acknowledge.** Different concern — #3739 refactors the *existing*
  11-site `reportSilentFallback`+`setUser` duplication; this plan *adds* a new
  cohort helper. Constraint carried into Phase 3: write the cohort helper to
  **compose with** (not duplicate) the `reportSilentFallback` shape so a future
  #3739 extraction is not fought. #3739 remains open.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm
`## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward)
**Assessment:** Owner-side/lease is the only coherent enforcement point; pin must
bind at lease **acquisition** (Slice 2) or failover defeats hold-back. Postgres
pin table transactional with the lease; additive-only blast-radius invariant in
schema; `reason`-branched failover. Biggest risk: premature — single-host cannot
run two versions, so enforcement is deferred. No capability gaps.

### Product (CPO)
**Status:** reviewed (carry-forward)
**Assessment:** Design enforcement, ship control plane now; the genuinely early
piece is cohort telemetry. Operator-only + agent-invokable (hard parity), never
UI-only. MVP = pin table + GA default + pins-only-ADD + cohort split; no weighted
rollout / auto-promotion / experiment framework (YAGNI). Guardrails: default-never-
affected (in schema), pin TTL (the sleeper), write confirmation.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** PROCEED, no gate. Operational routing metadata (Art. 6(1)(f)),
mirrors `inbox_item` — no Art. 30 row. Forward trigger only: once an arms-length
paid tenant with an SLA exists, deliberately holding them on a *known-defective*
build could create SLA/consumer-transparency exposure.

### Product/UX Gate
**Tier:** none — no UI surface (operator/agent skill + Postgres table only; no
path matches `components/**`, `app/**/page.tsx`, or the UI-surface term list).

**Brainstorm-recommended specialists:** none (CTO reported no capability gaps).

## Architecture Decision (ADR/C4)

An architectural decision is made (a version-eligibility dimension is added to the
ADR-068 lease-acquisition contract; a new resolver/trust boundary at placement
time). Per `wg-architecture-decision-is-a-plan-deliverable`, the ADR + C4 edits are
in-scope tasks of THIS PR.

### ADR
- **Create `ADR-091-tenant-targeted-version-routing.md`** (`status: adopting`,
  lineage ADR-068). Decision: version pin is a **host-eligibility constraint bound
  at `acquireWorktreeLease`**; control plane = `tenant_version_pin` (Postgres);
  blast-radius additive-only in schema; `reason`-branched failover (canary→GA,
  hold-back→fail-closed). Alternatives (rejected): edge LB/Worker signed-claim
  (same failure as ADR-068 Option D — split-brain), app-level read (impossible,
  one process = one `BUILD_SHA`), Flagsmith per-version segments (request-time
  read, not lease-transactional; two sources of truth). Note the ordinal is
  provisional (ship re-verifies against `origin/main`).
- **Amend ADR-068 §2/§5** with a one-line pointer to ADR-091 (the lease now also
  carries a version-eligibility predicate at acquisition).

### C4 views
Checked all three `.c4` files (not a keyword grep). Enumeration:
- **External human actors:** `founder` (the pinner) and `contributor` (the pinned
  tenant) — both already modeled (`views.c4` context + containers).
- **External systems/vendors:** none new (GHCR image registry already modeled).
- **Containers/data stores:** the pin table is **below C4-container granularity**
  (routing config inside the `supabase` database element) — unlike
  `operationalInbox`, which is a distinct user-facing feed. **No new C4 element.**
- **Access-relationship changes:** (a) update `model.c4:339`
  `coordinator -> supabase "Reads worktree lease"` →
  `"Reads worktree lease + tenant version pins (placement + version constraint)"`;
  (b) add an agent-parity control-plane relationship
  `engine -> supabase "version-pin skill set/clear/list (agent-native)"` mirroring
  the `engine -> operationalInbox` parity edge (`model.c4:283`).
- No `views.c4` `include` change needed (coordinator + supabase + engine already in
  the containers view; edges render automatically). Run
  `c4-code-syntax.test.ts` + `c4-render.test.ts` after the edit.

### Sequencing
The enforcement is only *true* after Slice 2 lands (gated on ADR-068 Phase 3);
ADR-091 is authored now describing the target state with `status: adopting`, not
postponed to its own issue.

## Observability

```yaml
liveness_signal:
  what: cohort tag (ga|canary|hold-back) on session Sentry events + the existing
        release tag (process build)
  cadence: per session (first-message-auth)
  alert_target: Sentry (per-cohort error-rate split); Better Stack for aggregate
  configured_in: apps/web-platform/server/observability.ts; sentry.server.config.ts:22 (release, pre-existing)
error_reporting:
  destination: Sentry (reportSilentFallback helper, observability.ts:216)
  fail_loud: a pin-table read failure in resolveCohort mirrors to Sentry and
             falls safe to cohort='ga' (never blocks the session; telemetry-only)
failure_modes:
  - mode: resolveCohort DB read fails
    detection: reportSilentFallback event op=version-pin.cohort-resolve-failed (in-path, server-side)
    alert_route: Sentry issue alert on the op slug
  - mode: pin set to a non-deployed tag (semver-valid but never built)
    detection: skill-side warning + (Slice 2) enforcement fail-closed for hold-back
    alert_route: skill audit line; Slice-2 Sentry event
  - mode: cohort tag never emitted (wiring regression)
    detection: unit test asserts the setTag call; a Sentry saved search for cohort presence
    alert_route: CI (unit) + dashboard
logs:
  where: Sentry breadcrumbs + Better Stack structured field
  retention: per existing Sentry/Better Stack retention
discoverability_test:
  command: "psql $DEV_DB -c \"SELECT * FROM pg_policies WHERE tablename='tenant_version_pin'\"  # NO ssh"
  expected_output: one SELECT policy for authenticated; zero write policies
```

Slice 1 touches only inspectable server surfaces (no agent sandbox / container
readiness gate / cron worker), so the 2.9.2 blind-surface extension does not fire.
No soak-gated close criterion in Slice 1 → no follow-through enrollment (Slice 2's
`replicas>1` gate is a dependency, not a soak on this PR).

## Infrastructure (IaC)

Slice 1 introduces **no new Terraform root, vendor, secret, or DNS**. The migration
applies via the existing `web-platform-release.yml#migrate` pipeline on merge (not
operator SSH). Slice 2 (deferred) will add a `SOLEUR_HOST_ROSTER` host→image-tag
annotation (a Doppler `prd_terraform` env value, or a runtime `/health`
`BUILD_VERSION` read — OQ3); that IaC is designed in ADR-091 and lands with the
enforcement build, not here.

## GDPR / Compliance Gate

Migration touched → gate assessed. **CLO domain-leader verdict (brainstorm): PROCEED,
no gate.** The pin map is operational routing metadata (Art. 6(1)(f) legitimate
interest), mirroring the `inbox_item` precedent (`122_inbox_item.sql` LAWFUL_BASIS
comment) — **no Article 30 register row**, no special-category data, no privacy-doc
lockstep. Erasure: `principal_id`/workspace FK `ON DELETE CASCADE` (Art. 17 intact).
**Forward trigger (documented, not a live gate):** once an arms-length paid tenant
with an SLA exists, deliberately pinning them to a build with a *known
data-integrity/security defect* could create SLA/consumer-transparency exposure —
revisit ADR-091 then.

## Open Questions

Carried from brainstorm: OQ1 principal precedence (user vs org pin — most-specific
wins, confirm against per-user `worktree_id`), OQ2 fail-closed UX (Slice 2), OQ3
roster host→tag annotation vs `/health` read (Slice 2), OQ4 promote/rollback verbs.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Edge LB / Cloudflare Worker on a signed tenant claim | Rejected — routes but can't guarantee the lease-holder's image (split-brain); same reason ADR-068 rejected edge affinity (Option D). |
| App-level version-pin read at request time | Rejected — impossible; one Node process = one baked `BUILD_SHA`. |
| Flagsmith per-version segments (ADR-043 shape) | Rejected as the control plane — request-time read, not lease-transactional (failover-bounce risk), two sources of truth. Reuse its *shape* (per-org segment, audit, agent-skill), not its store. |
| Build enforcement now | Rejected — unexercisable at `replicas=1`; deferred to Slice 2 tracking issue gated on #6027. |

**Deferred item (tracking issue to file at Phase 6):** Slice 2 — the
lease-acquisition version-eligibility enforcement + `reason`-branched failover +
roster host→tag annotation. Re-evaluation criteria: ADR-068 Phase 3 live at
`replicas>1` with heterogeneous image tags (#6027 merged + soaked).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold will
  fail `deepen-plan` Phase 4.6 — it is filled above (`single-user incident`).
- Do NOT add a `version=BUILD_SHA` Sentry scope tag — `release` (sentry.*.config.ts)
  already carries process-version; a second tag is redundant at `replicas=1` and
  the *served*-version tag only becomes distinct under Slice 2 cross-host proxy.
- The pin table's blast-radius invariant is a `NOT NULL` on `principal_id` +
  semver CHECK on `target_tag` — verify BOTH reject their bad input (AC2); a green
  "table created" is not proof the invariant holds.
- `SKILL_DESCRIPTION_WORD_BUDGET` is at zero headroom — the bump must equal the new
  description's exact word count with a ledger comment, or the budget test fails.

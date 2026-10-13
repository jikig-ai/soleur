---
spec: feat-audit-env-flags-flagsmith-policy
date: 2026-05-25
status: ready-for-plan
worktree: .worktrees/feat-audit-env-flags-flagsmith-policy
branch: feat-audit-env-flags-flagsmith-policy
pr: 4455
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
related_adr: ADR-038
follow_on_adr: ADR-043  # Corrected at plan-time: ADR-039 already taken
brainstorm: knowledge-base/project/brainstorms/2026-05-25-audit-env-flags-flagsmith-policy-brainstorm.md
related_issues: [4229, 4232, 4284, 4365, 4444]
---

# Spec: Audit ENV-vs-RUNTIME flag policy + migrate per-org flags to Flagsmith

## Problem Statement

Three runtime feature flags currently live in `ENV_FLAGS` (`team-workspace-invite`, `byok-delegations`, `dev-signin`) — toggled via Doppler env vars + container restart. ADR-038 (2026-05-22) introduced Flagsmith SaaS for runtime flag evaluation with per-role segmentation (`role-prd`/`role-dev`), but the existing 3 ENV flags were not migrated. Operator wants Claude-operable rollout for the two tenant-boundary flags (`team-workspace-invite`, `byok-delegations`) without container restarts.

Migration is non-trivial because:

1. **Per-org targeting is the load-bearing cohort axis** for `team-workspace-invite` and `byok-delegations` — both use a two-key gate (`FLAG_X=1` AND `orgId ∈ ALLOWLIST`). ADR-038's per-role segments cannot express per-org without new capability.
2. **Flagsmith is not disclosed as a sub-processor** in any legal artifact (Privacy Policy, DPA, Article 30 register, DPD). Adding `orgId` as a Flagsmith trait reclassifies Flagsmith under PA-1 + PA-2 recipients (GDPR Art. 4(1)).
3. **`byok-delegations` lives on the hot path** — `byok-resolver.ts` uses a local `envOnly()` sync helper to avoid async chains on the money path; migration must preserve this without naive `await` in the hot loop.
4. **`dev-signin` has a DCE tripwire** (`assert-dev-signin-eliminated.sh`) that depends on sync `getFlag()` calls and `process.env.NODE_ENV !== "development"` literals for SWC/Terser dead-code elimination. Migration would regress security posture.
5. **CI workflow `scheduled-membership-health.yml`** reads `vars.FLAG_TEAM_WORKSPACE_INVITE` to gate paging — needs a new strategy when the flag moves to Flagsmith.

## Goals

1. Build the missing per-org Flagsmith targeting capability (ADR-043 — ADR-039 already taken) so the migration is meaningful rather than a no-op.
2. Close the Flagsmith legal-disclosure gap before any code PR adds `orgId` egress.
3. Add a WORM audit shim for flag-flip operations on tenant-boundary flags (GDPR Art. 32(1)(d), SOC2 CC8.1).
4. Migrate `team-workspace-invite` to RUNTIME with **dual-control** (Flagsmith boolean + env-allowlist preserved as defense-in-depth).
5. Migrate `byok-delegations` to RUNTIME with the same dual-control and explicit hot-path latency preservation.
6. Reaffirm `dev-signin` stays ENV; amend ADR-038 with a "Why these stay ENV" partition rule for future flags of similar shape.

## Non-Goals

- Migrating `dev-signin` to RUNTIME (regresses DCE; explicit exclusion).
- Removing `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` or `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS` env-allowlists (dual-control architecture retains them).
- Flipping `TEAM_WORKSPACE_INVITE` ON in prd as part of this work (gated separately on #4444 + legal-PR completion per umbrella #4229).
- Adding per-identity (per-user) Flagsmith overrides — out of scope; ADR-039 introduces per-org segment/trait targeting only.

## Functional Requirements

- **FR1** — `getRuntimeFlag(name, identity)` accepts an extended `Identity` that includes `orgId: string | null` and passes it as a Flagsmith trait.
- **FR2** — Flagsmith segment model is extended to support per-org targeting via either (a) `org-<id>` per-org segments or (b) a single `org-targeted` segment with rule `orgId in [...]`. Choice decided in ADR-043 draft.
- **FR3** — `isTeamWorkspaceInviteEnabled(orgId)` resolves through `getRuntimeFlag("team-workspace-invite", identity)` AND `getTeamWorkspaceAllowlist().has(orgId)` (dual-control).
- **FR4** — `isByokDelegationsEnabled(orgId)` resolves through `getRuntimeFlag("byok-delegations", identity)` AND `getByokDelegationsAllowlist().has(orgId)` (dual-control).
- **FR5** — `byok-resolver.ts` hot path introduces an async boundary at `resolveKeyOwnerThenLease()` boundary; downstream sync paths preserved. No naive `await getRuntimeFlag()` inside the BYOK fast loop.
- **FR6** — `scheduled-membership-health.yml` workflow probes `/api/flags?role=prd` to determine flag state (no `vars.FLAG_TEAM_WORKSPACE_INVITE` read). Fail semantics: 5xx → fail-closed-to-OFF (no page) per Brainstorm OQ#4.
- **FR7** — A new Supabase WORM table `flag_flip_audit` (suffix-led `_audit` per codebase convention: precedent `tenant_deploy_audit` mig 043, `audit_byok_use` mig 037) records every flag-flip operation on tenant-boundary flags (`team-workspace-invite`, `byok-delegations`) with `(flag_name, env, target_role_or_org, action, actor, before_state, after_state, ts)`. Insert-only RLS. Skill-side append on every `soleur:flag-set-*` invocation.
- **FR8** — A new `soleur:flag-set-org` skill (or extension of `soleur:flag-set-role` with `--target org|role` arg) enables per-org flag flips. Skill-name decision per Brainstorm OQ#6.
- **FR9** — ADR-038 amended with "Why these stay ENV" appendix codifying the partition rule.
- **FR10** — `dev-signin` reaffirm-stay PR adds an explanatory comment in `lib/feature-flags/server.ts:16-24` pointing to the ADR-038 appendix.

## Technical Requirements

- **TR1** — `Identity` type extended in `lib/feature-flags/server.ts`: `{ userId, role, orgId }`. `resolveIdentity()` extended to derive `orgId` from `workspace_members` lookup or null for anonymous.
- **TR2** — Flagsmith client call upgraded to pass `orgId` trait: `getIdentityFlags(identifier, { role, orgId })`. Identifier strategy decided in ADR-039 (per-user `user:<userId>`, per-org `org:<orgId>`, or composite).
- **TR3** — Cache key for `_roleCache` extended to `(role, orgId)` composite. Cap revisited; current Map shape inadequate.
- **TR4** — Migration introduces a new Supabase table via migration file `migrations/071_flag_flip_audit.sql` (next monotonic; 070 is latest). Insert-only RLS (zero policies — service-role-only via SECURITY DEFINER writer RPC; no owner-insert policy per learning `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md`). REVOKE matrix on writer RPC.
- **TR5** — `scheduled-membership-health.yml` workflow gets HTTP probe step; secrets and base URL pulled from existing workflow context (no new infra).
- **TR6** — Hot-path async boundary in `byok-resolver.ts`: `resolveKeyOwnerThenLease()` becomes the single `await getRuntimeFlag()` site; called from `agent-runner.ts` (2 sites), `cc-dispatcher.ts` (1 site), 2 Inngest functions. Per-request memoization added to prevent N+1 Flagsmith calls within one request.
- **TR7** — `soleur:flag-set-role` skill (renamed or extended per FR8) writes audit row before Flagsmith mutation; failure to write audit row fails the flag-flip (no silent skip).
- **TR8** — E2E tests cover Flagsmith outage (envFallback path) and Flagsmith misconfig (segment includes all orgs accidentally; allowlist gates blast radius to allowlisted orgs only). Both `team-workspace-invite` and `byok-delegations`.
- **TR9** — `verify-required-secrets.sh` extended to assert `FLAG_TEAM_WORKSPACE_INVITE` and `FLAG_BYOK_DELEGATIONS` env-fallback vars still mirror Flagsmith prd-segment state post-migration (existing invariant from ADR-038 §"Fallback semantics").

## Sequencing (Multi-PR Plan)

Per Brainstorm §"PR Sequence":

**Collapsed to 3 PRs (2026-05-25, plan-review v2)** per DHH + Code Simplicity consensus. Per-org capability + WORM ledger ship inside PR-2 with the consumers that need them, not as standalone scaffolding.

1. **PR-1** legal: Flagsmith sub-processor disclosure — blocks PR-2
2. **PR-2** feat(flags): migrate both flags + per-org capability (ADR-043) + WORM `flag_flip_audit` ledger inline — blocked by PR-1
3. **PR-3** docs(flags): `dev-signin` stay-ENV inline comment in `lib/feature-flags/server.ts` (no ADR-038 appendix — comment alone suffices) — parallel-OK

## Acceptance Criteria

- **AC1** — `dev-signin` remains in `ENV_FLAGS`; DCE tripwire (`assert-dev-signin-eliminated.sh`) passes unchanged.
- **AC2** — `team-workspace-invite` and `byok-delegations` resolve through Flagsmith RUNTIME path AND retain env-allowlist gate; both must hold (dual-control).
- **AC3** — Flagsmith DPA executed; sub-processor disclosed in Privacy Policy, DPD (root + Eleventy mirror), Article 30 register PA-1 + PA-2, `compliance-posture.md` Vendor DPA table.
- **AC4** — `flag_flip_audit` Supabase table exists; every `soleur:flag-set-*` invocation appends a row BEFORE the Flagsmith mutation; zero RLS policies; two separate triggers (`_no_update` + `_no_delete`) per mig 043 precedent; row-state retention bypass (`OLD.retention_until < now()`), NOT `session_replication_role` GUC; `actor` CHECK constraint + lowercase normalization.
- **AC5** — `scheduled-membership-health.yml` probes `/api/flags?role=prd` (not `vars.FLAG_TEAM_WORKSPACE_INVITE`); fail-closed-to-OFF on 5xx; CI green.
- **AC6** — `byok-resolver.ts` hot-path latency regression test: per-request Flagsmith call count ≤ 1 under N≥10 BYOK ops. Inngest contexts memoize via AsyncLocalStorage.
- **AC7** — `lib/feature-flags/server.ts:16-24` carries the partition-rule comment (PR-3); references ADR-038 + ADR-043.
- **AC8** — `verify-required-secrets.sh` env-fallback mirror invariant extended to cover both migrated flags.
- **AC9** — Operator-facing skill UX: `soleur:flag-set-role <flag> --target org=<orgId> on|off` works end-to-end against dev-segment first, then prd-segment. Per-org capability ships in PR-2.
- **AC10** — Pre-merge guard on PR-2: `tenant-dpa-register.md` row count for `status: dpa-signed` is zero. Non-zero → §6.1 30-day notice clock applies → halt merge and escalate to CLO.

## Out of Scope / Future Work

- Per-identity (per-user) Flagsmith targeting — explicit V1 ADR-038 exclusion preserved.
- Flag-flip approval workflow (multi-actor sign-off) — single-operator skill model retained.
- Flagsmith local-evaluation mode — current `enableLocalEvaluation: false` preserved.
- `dev-signin` migration — permanent exclusion.

---
title: BYOK delegations — per-workspace grantor-funded runs (resolver + WORM ledger + atomic cap RPC)
status: accepted
date: 2026-05-22
related: [4232, 4229, 4225, 4290]
related_adrs: [ADR-038, ADR-039, ADR-026, ADR-028]
related_plans:
  - knowledge-base/project/plans/2026-05-22-feat-byok-delegations-pr-a-plan.md
brand_survival_threshold: single-user incident
---

# ADR-040: BYOK delegations — per-workspace grantor-funded runs

## Status

**Accepted** (2026-05-22, PR #4290; PR-A of the byok-delegations feature). PR-B (UI surfaces + Delegation Consent Side Letter) parallel-tracks; both land before `FLAG_BYOK_DELEGATIONS` flips ON in prd.

## Context

The runtime BYOK lease split at `apps/web-platform/server/byok-lease.ts:101-122` (PR #4225) raises `MissingByokKeyError` whenever `keyOwnerUserId` lacks an `api_keys` row, and the embedded ADR comment names #4232 as the eventual opt-in remediation: "NEVER falls back to another user's key — the `byok_delegations` table (#4232) is the future opt-in remediation." This ADR captures that remediation.

The dogfood trigger is concrete: Jikigai itself runs as a two-person workspace (Jean + Harry the intern). Harry needs to start running agents on day one; Jean wants Harry's runs to bill against Jean's Anthropic key under a daily + hourly cap, expirable, revocable, and audit-traced. The legacy `runtime_cost_cap_cents` kill-switch (mig 046) groups by `founder_id` only — there is no per-grantee cap, no expiry, no revoke. PR-A ships the table + the resolver + the atomic cap RPC + the 5-site sentinel sweep + the CLI surface, all behind a flag-OFF feature gate.

GDPR posture: the delegation row is a joint-controllership artifact between grantor and grantee, lawful-basis Art. 6(1)(b) (contract). DPD §2.3 + AUP §5.6 + the Delegation Consent Side Letter ship in PR-B. The 7y retention reflects the joint-controllership audit trail; the WORM trigger enforces append-only mutation shapes; Art. 17 anonymisation cascades through the existing `account-delete.ts` chain.

Brand-survival threshold: **single-user incident.** Two failure modes carry that weight:
1. Cross-tenant grant — a member of OrgA inserts a `byok_delegations` row naming a user in OrgB as grantor. That stranger leases the grantor's Anthropic key. GDPR Art. 33 territory (72h notification clock).
2. Revoke-grace leak — Jean clicks "revoke" on Harry's delegation; the resolver's stale read keeps using Jean's key for the next 30 minutes of Harry's runs; Jean's Anthropic invoice shows hundreds of dollars he never authorized.

CPO + CLO + CTO sign-offs carried forward from the brainstorm; the `user-impact-reviewer` agent runs at PR-review time per the brand-survival threshold.

## Decision

PR-A introduces a single migration (`064_byok_delegations.sql`), a thin TS resolver (`server/byok-resolver.ts`), a sentinel sweep across 5 prod `runWithByokLease` invocations, a widening of `persistTurnCost` to route cap-aware audit writes, an account-delete cascade phase, two CLI scripts, and a two-key feature flag [Updated 2026-05-26: env-allowlist removed; Flagsmith segment is now the sole per-org gate. See ADR-043.]. Twelve sub-decisions land in v3 (post-3-agent-review + 3-agent-deepen-plan); the table below enumerates them with their forcing function.

| # | Decision | Forcing function | Alternatives weighed |
|---|---|---|---|
| 1 | **Merged atomic RPC** `check_and_record_byok_delegation_use` does SELECT FOR UPDATE → grace check → expired check → hourly cap SUM → daily cap SUM → audit INSERT — all in a single transaction under one row lock. | DIG F4: a v2-style split (cap check RPC then audit write RPC) admits a TOCTOU window where two concurrent calls at cap boundary both pass and both INSERT. | (a) Advisory lock on `delegation_id` and split into 2 RPCs — same effect but more wire roundtrips. (b) Serializable isolation per call — heavier on the planner; library client choice would leak the isolation level upward. Merged RPC is the lowest-friction shape that still proves the invariant at SQL boundary. |
| 2 | **`clock_timestamp()` (not `now()`) for grace / expiry / cap windows** inside the merged RPC. | SS F1: a long-running Inngest step opened pre-revoke can see `now()` as the txn-start timestamp and pass the grace check after the row was already revoked outside its txn. `clock_timestamp()` returns wall-clock-at-statement-evaluation. | (a) Force re-fetch by `pg_advisory_xact_lock` + statement-level snapshot reset — viable but more complex than the trivial primitive swap. |
| 3 | **Hourly + daily caps on the delegation row.** Both with CHECK constraints and both consulted in the merged RPC. | Arch A1: the per-founder kill-switch from PR-G (#3947) is the eventual brake but its global wiring is deferred. Without a secondary brake on the delegation surface itself, a runaway loop under an active delegation has no rate-limit until the daily ceiling hits — that's $10K of unauthorized spend. The hourly cap gives a ~$500/hr ceiling by default (daily/4) that fails closed in ~1 hour. | (a) Block on PR-G #3947 wiring — pushes delegations behind a workstream we don't own. (b) Hourly-only — admits long-tail steady-state overspend. (c) Daily-only — admits hourly burst. Both is the only shape that brackets both failure modes. |
| 4 | **$10K/day ceiling** (`daily_usd_cap_cents BETWEEN 1 AND 1000000`) enforced at both table CHECK and RPC body. | SS F2: brand-survival floor. The original spec admitted any positive cap, which includes $10B/day. At single-user-incident threshold, a typo at grant time (`200000` cents intended → `2000000` typed = $20K instead of $2K) is exactly the failure the threshold names. | (a) Soft warning only — same incident shape. (b) Configurable ceiling — adds infra surface for a feature that doesn't yet warrant it. |
| 5 | **WORM Shape 1 attribution constraint:** revoke flip requires `revoked_by_user_id ∈ {grantor, grantee, created_by}` of THIS row. | DIG F1: without the constraint, an admin RPC that accepts `p_actor_user_id` could revoke any row attributing to any user — the audit ledger becomes poisoned ("Harry revoked Jean's delegation" appears as a valid row). The constraint binds revocation attribution to the parties of record. | (a) Soft check in TS — admits direct-SQL revoke paths. (b) Separate `revocation_attributions` table — over-engineers for a 5-line trigger constraint. |
| 6 | **WORM Shape 3: cap-update flip.** `daily_usd_cap_cents` and/or `hourly_usd_cap_cents` may change accompanied by `cap_updated_at` + `cap_updated_by_user_id` non-NULL; everything else unchanged. | Arch A6: enables "raise Harry's budget" UX without breaking audit continuity. Without Shape 3, raising a cap requires revoke + new-grant, which destroys the `delegation_id` reference on every prior audit row and complicates reconciliation. | (a) Always revoke-and-regrant — see above. (b) Cap-change ledger as a separate table — splits the audit surface; future operators must JOIN to reconstruct a delegation's lifecycle. |
| 7 | **TS-layer workspace_id resolution.** The resolver derives `workspaceId` via `getDefaultWorkspaceForUser(workspaceContextUserId)` BEFORE invoking `resolve_byok_key_owner` and passes it as an explicit RPC parameter. | DIG F3: a SQL-side JOIN-inside-resolver would have to infer the caller's intended workspace from `workspace_members`, which over-returns for multi-workspace grantees and could surface a delegation from the wrong workspace. The TS layer knows the caller's intended workspace unambiguously. | (a) JOIN inside SQL with a "first workspace" rule — wrong-workspace inference (see DIG F3). (b) Pass `workspace_id` as JWT claim — adds an Auth-Hook dependency for a 1-line derivation. |
| 8 | **HMAC-SHA256 with `SENTRY_TAG_PEPPER` for delegation-related Sentry tags** (`delegation_id_hash`, `workspace_id_hash`, `grantor_user_id_hash`, `grantee_user_id_hash`). 16-hex prefix. Separate pepper from the org-wide `SENTRY_USERID_PEPPER`. | SS F6: small-population reversibility risk. Raw SHA-256 of a known set of ~20 user IDs is brute-forceable by anyone with Sentry read access. HMAC with a server-side pepper closes the reversal vector. | (a) Reuse `SENTRY_USERID_PEPPER` — couples delegation-domain rotation to the org-wide hash space. (b) No pepper, accept reversibility — fails SS F6 explicitly. |
| 9 | **WORM column-enumeration smoke test.** Test queries `information_schema.columns` for `byok_delegations` and `pg_get_functiondef` for `byok_delegations_no_mutate`; asserts every column appears in the trigger body. | SS F4: the structural-diff trigger enumerates columns explicitly. A future migration that adds a column to `byok_delegations` without updating the trigger creates a fail-OPEN — the new column's mutation becomes silently permitted by every shape. The test fails fast on that divergence. | (a) Document the constraint, hope future authors follow — fails the brand-survival threshold on its own terms. (b) Reflective trigger that auto-discovers columns — admits the same fail-OPEN under future column additions (the trigger would auto-accept the new column's mutation). |
| 10 | **Abstract `ByokDelegationError` base + 5 thin sibling classes** carrying a `.reason` discriminator. Catch sites use one `instanceof ByokDelegationError` clause. | Five distinct error classes (revoked / expired / hourly-cap / daily-cap / cross-tenant) would force five `instanceof` clauses per catch site — every future call site is a five-times-violation surface. The base + discriminator keeps the catch surface single-shape. | (a) One concrete class with an enum field — loses the type-level distinguishability; `if (err.reason === 'expired')` is run-time. (b) Tagged union without classes — same loss of `instanceof` introspection. |
| 11 | **Admin + self consolidated RPCs.** `grant_byok_delegation` and `revoke_byok_delegation` each branch on `auth.uid() IS NULL` to route to the admin (service-role) vs. self (authenticated) path. GRANT EXECUTE to BOTH `authenticated` AND `service_role`. | Arch A3: halves the surface vs. four separate RPCs (`_as_admin` + `_as_self` for each verb). The branching shape is < 10 lines per RPC and the security invariant (authenticated caller cannot impersonate) is enforced inside the body, not at the GRANT boundary. | (a) Four RPCs — operator must keep them in lockstep on every change; doubled review surface. (b) One RPC with mandatory `p_actor` — drops `auth.uid()` defense-in-depth on the authenticated path. |
| 12 | **Rolling 24h cap window** (not UTC-midnight reset). Matches the existing `record_byok_use_and_check_cap` idiom. | Operator-friendly: a typo at 23:50 doesn't suddenly unlock another $X at 00:00. Trailing-window semantics also makes the cap predictable across time zones; a UTC-anchored reset is an integration surprise. | (a) UTC midnight — surprise reset, see above. (b) Per-grantor-time-zone — needs a `time_zone` column on `users`, deferred. |

Two additions sit on top of the v3 decisions to support eventual reconciliation:

- **`audit_byok_use.attribution_shift_reason` column** (`CHECK IN ('revoked_post_grace', 'expired')`). The merged RPC writes this on post-grace / expired audit rows so a future reconciliation flow can identify rows where the cost was billed to the grantor's key but the attribution shifted to the caller for audit purposes (Arch A2). PR-A does not ship the reconciliation flow itself; this is the data substrate.
- **`audit_byok_use.invocation_id UNIQUE`** constraint added in this migration (Phase 0.9 prereq). The merged RPC's `ON CONFLICT (invocation_id) DO NOTHING` makes Inngest retries idempotent against the audit surface. Down migration intentionally KEEPS this constraint — dropping it on rollback would silently re-open the double-write window.

## Out of scope (deferred to PR-B and beyond)

- Per-action ACLs (NG1).
- Time-window auto-expiry scheduler (NG2; the merged RPC's expiry check is the runtime gate).
- Multi-grantor delegations (NG3).
- `prefer_delegation` boolean (NG4).
- Out-of-band reimbursement (NG5).
- Mid-token-stream abort (NG6).
- Per-grantee dashboard (NG7; PR-B brings UI).
- Cap aggregation across multiple delegations from the same grantor (NG8).
- Materialized view for active delegations (NG9).
- UI grant-from-global-settings (NG10; PR-B).
- Per-founder hourly kill-switch global wiring (NG12; PR-G #3947 owns the global path; PR-A's per-delegation hourly cap is the brake until that lands).
- `byok_admin_audit` caller-IP/host table (NG13).
- Replacing the legacy SHA-256 hash at `byok-lease.ts:140-168` with the new HMAC pepper (NG15; separate follow-up).

## Open follow-ups within PR-A scope

- **cc-dispatcher closure-capture.** The lease opens inside `realSdkQueryFactory` (`cc-dispatcher.ts:890`) and closes before `onResult` (`:1721`) fires; the `delegationId` is unreachable from the cost-writer caller in that path. Phase 3 annotates the gap inline. Closing it needs a closure-captured `delegationContext` threaded from `realSdkQueryFactory` through `getSoleurGoRunner`'s state class into the `onResult` callback signature. Tracked for Phase 4 alongside the integration tests that can validate the closure-capture end-to-end. Until then, cc-soleur-go runs under an active delegation silently audit-attribute via the solo path — RPC-level cap checks DO NOT fire on the cc-soleur-go surface; `FLAG_BYOK_DELEGATIONS=0` in prd is the operational guard.
- **Migration 064 apply to dev-Supabase** via the Doppler `DATABASE_URL_POOLER` fallback (port rewrite :6543 → :5432 for session-mode DDL, single-txn apply with `_schema_migrations` tracking row). Phase 4 acceptance criterion.

## Implications and migration

`runWithByokLease` and `getCurrentByokLease` are stable; the new TS surface (`resolveKeyOwnerThenLease`) is the canonical entry point and the resolver internally re-enters the lease primitive. Solo callers + flag-OFF callers (every prd caller as of merge) go through a single env-var check then directly to the legacy `runWithByokLease` path — zero behavior change.

The 5 prod sentinel sites are enumerated in the PR body with their `callerUserId` provenance; future call sites MUST be added to that enumeration (the security invariant in `byok-resolver.ts` is load-bearing — see SS F3 in the plan).

Down migration preserves `audit_byok_use.invocation_id UNIQUE`; everything else reverses cleanly in dependency-safe order.

## References

- Plan: `knowledge-base/project/plans/2026-05-22-feat-byok-delegations-pr-a-plan.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-byok-delegations-4232/spec.md`
- Migration: `apps/web-platform/supabase/migrations/064_byok_delegations.sql`
- ADR-038 (team workspace foundation; sibling): `ADR-038-team-workspace-multi-user-organizations-and-workspace-members.md`
- ADR-039 (workspace_member_removals ledger; precedent for WORM-with-anonymise): `ADR-039-departed-member-removal-ledger.md`
- ADR-026 (data-integrity / GDPR boundary): `ADR-026-*.md`
- WORM precedent: `apps/web-platform/supabase/migrations/048_scope_grants.sql`
- Lease split: `apps/web-platform/server/byok-lease.ts:101-122`

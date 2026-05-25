---
title: "BYOK Delegations PR-A — Tasks"
plan: knowledge-base/project/plans/2026-05-22-feat-byok-delegations-pr-a-plan.md
spec: knowledge-base/project/specs/feat-byok-delegations-4232/spec.md
issue: 4232
branch: feat-byok-delegations-4232
pr: 4290
date: 2026-05-22
revisions:
  - v1 — initial draft (8 phases)
  - "v2 — plan-review applied, 8 phases preserved"
  - "v3 — deepen-plan applied, collapsed to 5 phases; merged atomic RPC; hourly+daily caps; WORM Shape 3"
lane: cross-domain
brand_survival_threshold: single-user incident
estimate_days: "4-5"
---

# Tasks: BYOK Delegations PR-A (v3)

Derived from `2026-05-22-feat-byok-delegations-pr-a-plan.md` v3 (post-3-agent-review + 3-agent-deepen). 5 phases; TDD per phase (RED → GREEN → REFACTOR).

## Phase 0 — Preconditions

- [ ] 0.1 Worktree clean; `git rev-parse --abbrev-ref HEAD == feat-byok-delegations-4232`
- [ ] 0.2 `git grep -n 'runWithByokLease' apps/web-platform/server/` returns 5 invocations at expected lines
- [ ] 0.3 Read `byok-lease.ts:58-75`, `:88-113`, `:182-196`; confirm sibling-class precedent + exhaustive switch shape unchanged
- [ ] 0.4 `git grep 'record_byok_use_and_check_cap' apps/web-platform/server/` returns ZERO matches (v3 doesn't touch it; verifies no drift)
- [ ] 0.5 `git grep -n 'persistTurnCost' apps/web-platform/server/` returns 2 known sites (agent-runner.ts:1891, cc-dispatcher.ts onResult)
- [ ] 0.6 Read `lib/feature-flags/server.ts` FLAG_VARS + `isTeamWorkspaceInviteEnabled` two-key gate
- [ ] 0.7 Read `account-delete.ts:75-300`; identify phase 5.9 insertion point
- [ ] 0.8 Read `workspace-resolver.ts:66` `getDefaultWorkspaceForUser`
- [ ] 0.9 Verify `audit_byok_use.invocation_id UNIQUE` exists in mig 037; if absent, add to mig 064
- [ ] 0.10 Verify `SENTRY_TAG_PEPPER` exists in Doppler dev + prd; if absent, operator-set first (32-byte hex)
- [ ] 0.11 `mcp__plugin_supabase_supabase__list_migrations` (dev): 053-063 applied; 064 not yet; if drift, reconcile via `execute_sql` schema introspection (rebase reconciliation 2026-05-22 → 2026-05-23: 062 + two distinct 063_* slots taken by sibling PRs; renumbered 063→064 mid-PR. Plan §0.11 DIG F9 sibling-race scenario)
- [ ] 0.12 Baseline `bun run typecheck` exits 0; capture `bun test` pass count

## Phase 1 — Migration 064: Full Schema (Table + Triggers + RPCs + Down)

### 1.A — Table + Indexes + audit_byok_use Additions

- [ ] 1.1 RED: `byok-delegations.test.ts` skeleton with table-creation assertions
- [ ] 1.2 Create `apps/web-platform/supabase/migrations/064_byok_delegations.sql` with full header (LAWFUL_BASIS + RETENTION + DEPENDENCY + WORM-column-enum-sentinel reminder + trigger-not-CHECK rationale)
- [ ] 1.3 Define `public.byok_delegations` table with v3 columns: id, grantor_user_id, grantee_user_id, workspace_id (FK ON DELETE RESTRICT), daily_usd_cap_cents (CHECK BETWEEN 1 AND 1000000), hourly_usd_cap_cents (CHECK BETWEEN 1 AND daily_usd_cap_cents), created_by_user_id, created_at, expires_at, revoked_at, revoked_by_user_id, revocation_reason, cap_updated_at, cap_updated_by_user_id; table-level CHECKs (grantor <> grantee; revoked_at >= created_at; expires_at > created_at)
- [ ] 1.4 Create partial unique index `(grantor, grantee, workspace_id) WHERE revoked_at IS NULL` (v3 — drop `expires_at > now()` from predicate per DIG F10)
- [ ] 1.5 Create resolver hot-path index `(grantee_user_id, workspace_id) WHERE revoked_at IS NULL`
- [ ] 1.6 ALTER `audit_byok_use` ADD COLUMN `delegation_id uuid NULL` (FK RESTRICT) + ADD COLUMN `attribution_shift_reason text NULL CHECK IN ('revoked_post_grace','expired')`
- [ ] 1.7 Create `audit_byok_use_delegation_ts_idx` partial index `(delegation_id, ts) WHERE delegation_id IS NOT NULL`

### 1.B — Triggers

- [ ] 1.8 Define `byok_delegations_check_same_workspace()` BEFORE INSERT OR UPDATE OF (grantor, grantee, workspace_id); raises P0001 `byok_delegations:cross-tenant`
- [ ] 1.9 Define `byok_delegations_no_mutate()` WORM trigger with v3 three shapes:
  - Shape 1 (revoke flip): adds `revoked_by_user_id IN (grantor, grantee, created_by)` attribution constraint (DIG F1)
  - Shape 2 (Art. 17 anonymise): nulls all 4 user-id cols PLUS workspace_id together (DIG F6)
  - Shape 3 (cap-update flip): cap cols change + cap_updated_at + cap_updated_by_user_id non-NULL (Arch A6)
  - DELETE rejected
- [ ] 1.10 Attach BEFORE UPDATE + BEFORE DELETE triggers on byok_delegations
- [ ] 1.11 Define `byok_delegations_on_member_delete()` AFTER DELETE on workspace_members; sets `revoked_by_user_id = OLD.user_id`
- [ ] 1.12 Attach AFTER DELETE trigger

### 1.C — RLS + Grants

- [ ] 1.13 ALTER TABLE ENABLE RLS
- [ ] 1.14 CREATE POLICY `byok_delegations_select_for_parties` (USING `is_workspace_member(workspace_id, auth.uid()) AND (grantor = auth.uid() OR grantee = auth.uid())`)
- [ ] 1.15 REVOKE INSERT, UPDATE, DELETE FROM PUBLIC, anon, authenticated

### 1.D — RPCs (v3 consolidated)

- [ ] 1.16 Define `grant_byok_delegation(p_grantor_user_id NULL, p_grantee, p_workspace_id, p_daily_cap_cents, p_hourly_cap_cents, p_expires_at, p_actor_user_id NULL) RETURNS uuid`; branches on `auth.uid() IS NULL` (service-role → admin path; authenticated → self path); asserts cap bounds with distinct SQLSTATE; GRANT EXECUTE to both authenticated AND service_role
- [ ] 1.17 Define `revoke_byok_delegation(p_delegation_id, p_actor_user_id NULL, p_reason)` similarly branching; constrains `p_reason IN ('grantor_revoke','grantee_decline','admin_revoke')` (SS F9)
- [ ] 1.18 Define `resolve_byok_key_owner(p_caller_user_id, p_workspace_id) RETURNS TABLE(key_owner_user_id, delegation_id)` — **v3: `p_workspace_id` is explicit param (DIG F3)**; uses `clock_timestamp()` for expires check; SECURITY DEFINER service_role only
- [ ] 1.19 Define `check_and_record_byok_delegation_use(p_delegation_id, p_invocation_id, p_token_count, p_unit_cost_cents, p_caller_user_id, p_agent_role)` — **v3 merged atomic RPC (DIG F4)**:
  - SELECT FOR UPDATE on byok_delegations row
  - Grace check via `clock_timestamp() > revoked_at + interval '60 seconds'` → insert audit row with attribution_shift_reason='revoked_post_grace' AND raise SQLSTATE
  - Expired check via `clock_timestamp() > expires_at` → same with 'expired'
  - Hourly cap SUM `WHERE delegation_id = X AND ts > clock_timestamp() - interval '1 hour'` → raise on exceed (no audit row)
  - Daily cap SUM with `interval '24 hours'` → raise on exceed (no audit row)
  - Pass → insert audit row with grantor attribution
  - SECURITY DEFINER service_role only
- [ ] 1.20 Define `anonymise_byok_delegations(p_user_id uuid)` — **v3: also nulls workspace_id**; first writes Shape 1 revoke for any active rows (SS F7 active-row guard) then Shape 2 anonymise; SECURITY DEFINER service_role only
- [ ] 1.21 Verify ALL new DEFINER RPCs: `SET search_path = public, pg_temp` + `REVOKE ALL FROM PUBLIC, anon, authenticated` + correct `GRANT EXECUTE` targets

### 1.E — Down Migration

- [ ] 1.22 Write `064_byok_delegations.down.sql` in reverse order; restores audit_byok_use columns; drops table/triggers/functions cleanly
- [ ] 1.23 GREEN: migration test apply + down + re-apply cycle passes

## Phase 2 — TS Layer: byok-resolver.ts + Abstract Error Hierarchy + Type Widening + Sentry HMAC

- [ ] 2.1 RED: `byok-resolver.test.ts` skeleton (resolver semantics + flag-off bypass + multi-workspace regression)
- [ ] 2.2 Edit `byok-lease.ts:58-75`: add `delegationId?: string` to `ByokLeaseArgs`
- [ ] 2.3 Edit `byok-lease.ts:198`: add `readonly delegationId?: string` to `ByokLease`
- [ ] 2.4 Edit `byok-lease.ts:338`: thread `args.delegationId` into lease slot; NO changes to `ByokLeaseError.cause` enum
- [ ] 2.5 Edit `observability.ts`: add `hashUserIdForSentryTag(userId: string): string` HMAC-SHA256 helper using `SENTRY_TAG_PEPPER` env (SS F6)
- [ ] 2.6 Create `apps/web-platform/server/byok-resolver.ts` with:
  - Abstract `ByokDelegationError` base + 5 thin sibling classes (Revoked / Expired / HourlyCap / DailyCap / CrossTenant) carrying `.reason` discriminator + shared structured fields (delegationId, workspaceIdHash)
  - `resolveKeyOwnerThenLease(callerUserId, workspaceContextUserId, fn)`: flag-off fast path → direct lease; flag-on → derive `workspaceId` via `getDefaultWorkspaceForUser` → `.rpc('resolve_byok_key_owner', {p_caller_user_id, p_workspace_id}).maybeSingle()` → handle null/error/data
  - **Load-bearing invariant comment (SS F3):** callerUserId MUST be server-derived
- [ ] 2.7 GREEN: `byok-resolver.test.ts` cases pass
- [ ] 2.8 REFACTOR: consumer grep of `ByokLeaseArgs` / `ByokLease` / `ByokLeaseError` per `hr-type-widening-cross-consumer-grep`; record in PR body

## Phase 3 — Sentinel Sweep + cost-writer + Cascade Wire-Up

### 3.A — 5-Site Sentinel Sweep

- [ ] 3.1 RED: extend `byok-delegations.test.ts` with cost-attribution test cases
- [ ] 3.2 Edit `agent-runner.ts:882`: wrap with `resolveKeyOwnerThenLease(userId, userId, ...)`
- [ ] 3.3 Edit `agent-runner.ts:2401`: same
- [ ] 3.4 Edit `cc-dispatcher.ts:890`: same
- [ ] 3.5 Edit `inngest/functions/cfo-on-payment-failed.ts:199`: same
- [ ] 3.6 Edit `inngest/functions/github-on-event.ts:208`: same

### 3.B — cost-writer.ts (v3 single merged RPC call)

- [ ] 3.7 Edit `cost-writer.ts persistTurnCost`: extend signature with optional `delegationId?: string` + `callerUserId?: string`; when `delegationId !== undefined`, call `supabase.rpc('check_and_record_byok_delegation_use', {...})` (ONE atomic RPC — v3); on SQLSTATE P0001 with `^byok_delegations:` map to sibling errors + `reportSilentFallback`; when `delegationId === undefined`, continue calling `write_byok_audit` unchanged
- [ ] 3.8 Edit `agent-runner.ts:1891` (`persistTurnCost` caller): thread `lease.delegationId` + `lease.workspaceContextUserId`
- [ ] 3.9 Edit `cc-dispatcher.ts onResult` (`persistTurnCost` caller): same

### 3.C — account-delete.ts Phase 5.9

- [ ] 3.10 Edit `account-delete.ts`: add phase 5.9 between 5.8 (`anonymise_organization_membership`) and phase 6 (`auth.admin.deleteUser`); call `supabase.rpc("anonymise_byok_delegations", { p_user_id: userId })` with sibling error-handling shape
- [ ] 3.11 Update docstring header at lines 75-82 to include phase 5.9
- [ ] 3.12 GREEN: sentinel sweep + cost-writer + cascade cases pass
- [ ] 3.13 REFACTOR: catch-site grep for `instanceof ByokLeaseError` / `instanceof MissingByokKeyError`; add `instanceof ByokDelegationError` clauses where appropriate

## Phase 4 — CLI + Feature Flag + WORM Smoke Test + Tests + ADR

### 4.A — CLI

- [ ] 4.1 RED: extend `byok-delegations.test.ts` with CLI E2E cases (with `--yes` flag for non-interactive)
- [ ] 4.2 Create `apps/web-platform/scripts/byok-grant.ts` (bun shebang; hand-rolled argv: --actor, --grantor, --to, --workspace, --cap-cents, --hourly-cap-cents, --expires-in, --yes); resolve emails via `auth.admin.listUsers`; resolve workspace via `getDefaultWorkspaceForUser`; **v3 confirmation prompt** (SS F5) — print resolution chain + require interactive `y` unless `--yes`; call `grant_byok_delegation` (service-role); print JSON delegation_id on success
- [ ] 4.3 Create `apps/web-platform/scripts/byok-revoke.ts` (mirror shape; constrained `--reason admin_revoke`; `--yes` flag)
- [ ] 4.4 Edit `apps/web-platform/package.json`: add `"byok-grant": "bun scripts/byok-grant.ts"` + `"byok-revoke": "bun scripts/byok-revoke.ts"`

### 4.B — Feature Flag

- [ ] 4.5 Edit `apps/web-platform/lib/feature-flags/server.ts`: add `"byok-delegations": "FLAG_BYOK_DELEGATIONS"` to FLAG_VARS
- [ ] 4.6 Add `isByokDelegationsEnabled(orgId?: string): boolean` two-key gate (env + `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS`)

### 4.C — Tests

- [ ] 4.7 Fixture isolation: every test file has `beforeEach` TRUNCATE + synthesize per `cq-test-fixtures-synthesized-only`
- [ ] 4.8 Time-boundary test: clock_timestamp +30s = grantor attribution; +90s = caller attribution + `attribution_shift_reason='revoked_post_grace'`; document controlled-clock technique in test header
- [ ] 4.9 RLS dual-shape: explicit 42501 + 42P17
- [ ] 4.10 Cross-tenant trigger: insert with cross-workspace pair → P0001; Sentry event with `art_33_breach: "true"` HMAC-pepper hash captured
- [ ] 4.11 WORM Shape 1 attribution: revoke with `revoked_by_user_id` outside `(grantor, grantee, created_by)` → P0001 reject (DIG F1)
- [ ] 4.12 WORM Shape 2 anonymise: nulls all 4 user-id cols + workspace_id together → pass
- [ ] 4.13 WORM Shape 3 cap-update: change cap cols + set cap_updated_at + cap_updated_by_user_id → pass; without those cols → reject (Arch A6)
- [ ] 4.14 WORM Shape 1 partial transition: 2-of-3 NULL→non-NULL → reject (DIG F2 negative test)
- [ ] 4.15 Member-departure: DELETE workspace_members → byok_delegations row revoked + revoked_by_user_id = OLD.user_id + revocation_reason = 'member_departed'
- [ ] 4.16 Hourly cap: exceeds at hourly_usd_cap_cents → P0001 `^byok_delegations:hourly_cap_exceeded`; no audit row
- [ ] 4.17 Daily cap: exceeds at daily_usd_cap_cents → P0001 `^byok_delegations:daily_cap_exceeded`; no audit row
- [ ] 4.18 Anonymise active-row guard (SS F7): first Shape 1 then Shape 2; both pass in single txn
- [ ] 4.19 Cap upper-bound: $1,000,001 cents → RPC body raises distinct SQLSTATE (SS F2)
- [ ] 4.20 Resolver multi-workspace regression (DIG F3): grantee in W_A + W_B; explicit `p_workspace_id = W_B` returns W_B delegations only
- [ ] 4.21 pg_default_acl audit: canonical query asserts no leaked grants on byok_delegations + new RPCs
- [ ] 4.22 Create `apps/web-platform/test/server/byok-delegations-worm-column-enum.test.ts` (v3 — SS F4): query `information_schema.columns` + `pg_get_functiondef(byok_delegations_no_mutate)`; assert every column appears in trigger body
- [ ] 4.23 Create `apps/web-platform/test/migration/064_byok_delegations.migration.test.ts`: apply + down + re-apply cycle against dev-Supabase
- [ ] 4.24 `bun run typecheck` exits 0
- [ ] 4.25 `bun test` exits 0 (baseline + all new cases)

### 4.D — ADR

- [ ] 4.26 Run `/soleur:architecture create "BYOK delegations: per-workspace grantor-funded runs"` to draft ADR capturing 9 decisions (v3: merged atomic RPC + clock_timestamp + hourly+daily caps + $10K ceiling + WORM Shape 1 attribution constraint + Shape 3 + TS-layer workspace resolution + HMAC pepper + WORM column-enum smoke + abstract base hierarchy + admin/self consolidation + rolling 24h)

## Phase 5 — PR Body + Verification

- [ ] 5.1 PR title: `feat(byok): PR-A — byok_delegations migration + SQL resolver + sentinel sweep + cap enforcement + CLI (Ref #4232)`
- [ ] 5.2 PR body enumerates: 5 sentinel-sweep sites + `callerUserId` provenance at each (SS F3); type widening sweep result; mig 064 LAWFUL_BASIS + RETENTION; ADR link; "v3 deepen-plan refinements" note
- [ ] 5.3 PR body uses `Ref #4232` (NOT `Closes`)
- [ ] 5.4 Verify `FLAG_BYOK_DELEGATIONS=0` in prd Doppler: `doppler secrets get FLAG_BYOK_DELEGATIONS -c prd`
- [ ] 5.5 Verify `SENTRY_TAG_PEPPER` non-empty in prd Doppler: `doppler secrets get SENTRY_TAG_PEPPER -c prd`
- [ ] 5.6 Mark PR ready via `gh pr ready 4290`

## Post-merge (operator + auto)

- [ ] P.1 Migration 064 applied to prd via `web-platform-release.yml#migrate` (auto-triggered; verify `gh run watch`)
- [ ] P.2 PostgREST schema reload post-apply (container restart per learning `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md`); automatable via `mcp__plugin_supabase_supabase__authenticate` flow or deploy hook
- [ ] P.3 Sentry alert rule for `art_33_breach=true` tag with distinct action shape (one-time setup; automatable via Sentry API)
- [ ] P.4 Release-time assertion in `web-platform-release.yml`: `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS` parses to valid UUIDs only, count ≤ N ceiling (SS F8 defense-in-depth)
- [ ] P.5 Issue #4232 remains OPEN until PR-B lands; `Ref #4232` records PR-A progress

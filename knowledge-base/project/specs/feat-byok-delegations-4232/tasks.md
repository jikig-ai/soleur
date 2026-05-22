---
title: "BYOK Delegations PR-A — Tasks"
plan: knowledge-base/project/plans/2026-05-22-feat-byok-delegations-pr-a-plan.md
spec: knowledge-base/project/specs/feat-byok-delegations-4232/spec.md
issue: 4232
branch: feat-byok-delegations-4232
pr: 4290
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
estimate_days: "3-4"
---

# Tasks: BYOK Delegations PR-A

Derived from `2026-05-22-feat-byok-delegations-pr-a-plan.md` v2 (post-3-agent-review). 8 phases; TDD per phase (RED → GREEN → REFACTOR).

## Phase 0 — Preconditions

- [ ] 0.1 `git status --short` clean; `git rev-parse --abbrev-ref HEAD == feat-byok-delegations-4232`
- [ ] 0.2 `git grep -n 'runWithByokLease' apps/web-platform/server/` returns 5 invocations at expected lines (`agent-runner.ts:882`, `agent-runner.ts:2401`, `cc-dispatcher.ts:890`, `cfo-on-payment-failed.ts:199`, `github-on-event.ts:208`)
- [ ] 0.3 Read `byok-lease.ts:58-75` (ByokLeaseArgs), `:88-113` (ByokLeaseError + MissingByokKeyError siblings), `:182-196` (mapByokLeaseCauseToErrorCode exhaustive switch); confirm sibling-class precedent
- [ ] 0.4 `git grep 'record_byok_use_and_check_cap' apps/web-platform/server/` returns ZERO matches (still no live TS callers); abort if drift
- [ ] 0.5 `git grep -n 'persistTurnCost' apps/web-platform/server/` returns 2 known sites (`agent-runner.ts:1891`, `cc-dispatcher.ts` `onResult`)
- [ ] 0.6 Read `apps/web-platform/lib/feature-flags/server.ts` FLAG_VARS + `isTeamWorkspaceInviteEnabled` two-key gate
- [ ] 0.7 Read `apps/web-platform/server/account-delete.ts:75-300`; identify phase 5.9 insertion point (between 5.8 and phase 6)
- [ ] 0.8 Read `apps/web-platform/server/workspace-resolver.ts:66` (`getDefaultWorkspaceForUser`)
- [ ] 0.9 Verify `audit_byok_use.invocation_id UNIQUE` constraint exists in mig 037 (required for Inngest-retry idempotency / R4); if absent, add to mig 062
- [ ] 0.10 `mcp__plugin_supabase_supabase__list_migrations` (dev project) shows 053-061 applied; 062 not yet
- [ ] 0.11 Baseline `bun run typecheck` exits 0; capture baseline `bun test` pass count

## Phase 1 — Migration 062: Table + Triggers + RLS + Indexes

- [ ] 1.1 RED: `byok-delegations.test.ts` skeleton with table-creation assertions (will fail until 1.2 lands)
- [ ] 1.2 Create `apps/web-platform/supabase/migrations/062_byok_delegations.sql` header with LAWFUL_BASIS + RETENTION + DEPENDENCY + trigger-not-CHECK rationale
- [ ] 1.3 Define `public.byok_delegations` table (11 columns, FKs ON DELETE RESTRICT, 3 table-level CHECKs)
- [ ] 1.4 Create partial unique index `byok_delegations_active_uniq` + resolver hot-path index `byok_delegations_grantee_lookup_idx`
- [ ] 1.5 Define `byok_delegations_check_same_workspace()` trigger function (BEFORE INSERT OR UPDATE OF grantor_user_id, grantee_user_id, workspace_id); raises P0001 `byok_delegations:cross-tenant`
- [ ] 1.6 Define `byok_delegations_no_mutate()` WORM trigger (2 shapes: revoke flip + Art. 17 anonymise; DELETE rejected); pin search_path; REVOKE ALL
- [ ] 1.7 Attach BEFORE UPDATE + BEFORE DELETE triggers
- [ ] 1.8 ENABLE RLS + `byok_delegations_select_for_parties` SELECT policy
- [ ] 1.9 REVOKE INSERT, UPDATE, DELETE FROM PUBLIC, anon, authenticated
- [ ] 1.10 `ALTER TABLE audit_byok_use ADD COLUMN delegation_id uuid NULL REFERENCES byok_delegations(id) ON DELETE RESTRICT`
- [ ] 1.11 Create `audit_byok_use_delegation_ts_idx` (delegation_id, ts) partial index
- [ ] 1.12 GREEN: `byok-delegations.test.ts` table-creation cases pass

## Phase 2 — Migration 062: RPCs

- [ ] 2.1 RED: extend `byok-delegations.test.ts` with RPC contract cases (grant + revoke + resolver + cap-check happy/sad paths)
- [ ] 2.2 Define `grant_byok_delegation(p_grantor_user_id, p_grantee_user_id, p_workspace_id, p_daily_usd_cap_cents, p_expires_at, p_actor_user_id) RETURNS uuid` (admin-form only; service_role GRANT EXECUTE)
- [ ] 2.3 Define `revoke_byok_delegation(p_delegation_id, p_actor_user_id, p_reason) RETURNS void` (admin-form only)
- [ ] 2.4 Define `resolve_byok_key_owner(p_caller_user_id, p_workspace_context_user_id) RETURNS TABLE(key_owner_user_id uuid, delegation_id uuid)` with own-key precedence, workspace resolution, active-delegation lookup
- [ ] 2.5 Define `check_byok_delegation_cap(p_delegation_id, p_token_count, p_unit_cost_cents, p_caller_user_id) RETURNS TABLE(current_spent_cents, cap_cents, outcome)` with 60s grace, expired check, rolling 24h cap-SUM, SELECT FOR UPDATE
- [ ] 2.6 DROP + CREATE `write_byok_audit` 7-arg form (add `p_delegation_id`); restore 6-arg path in down.sql
- [ ] 2.7 Define `anonymise_byok_delegations(p_user_id uuid) RETURNS void` (UK spelling; service_role only; Shape 2 WORM-compatible)
- [ ] 2.8 Define `byok_delegations_on_member_delete()` trigger function + attach AFTER DELETE ON workspace_members trigger; sets `revoked_by_user_id = OLD.user_id` (v2 — collapses WORM shape edge case)
- [ ] 2.9 Verify all DEFINER RPCs: `SET search_path = public, pg_temp` pinned + `REVOKE ALL FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE` to correct role only
- [ ] 2.10 GREEN: RPC contract cases pass

## Phase 3 — Migration 062 down.sql

- [ ] 3.1 RED: extend `062_byok_delegations.migration.test.ts` with down → re-apply assertion
- [ ] 3.2 Write `062_byok_delegations.down.sql` in reverse order (cascade trigger, anonymise, check_cap, resolver, revoke + grant, restore `write_byok_audit` 6-arg form verbatim from mig 061:34-78, `ALTER audit_byok_use DROP COLUMN`, WORM + same-workspace triggers, functions, indexes, table)
- [ ] 3.3 GREEN: migration test apply + down + re-apply cycle passes

## Phase 4 — `byok-resolver.ts` + Abstract Error Hierarchy + Type Widening

- [ ] 4.1 RED: `byok-resolver.test.ts` skeleton (resolver semantics + flag-off bypass)
- [ ] 4.2 Edit `byok-lease.ts:58-75`: add `delegationId?: string` to `ByokLeaseArgs`
- [ ] 4.3 Edit `byok-lease.ts:198`: add `readonly delegationId?: string` to `ByokLease`
- [ ] 4.4 Edit `byok-lease.ts:338`: thread `args.delegationId` into lease slot
- [ ] 4.5 Create `apps/web-platform/server/byok-resolver.ts` with abstract `ByokDelegationError` base + 4 thin sibling classes (`ByokDelegationRevokedError`, `ByokDelegationExpiredError`, `ByokDelegationCapExceededError`, `ByokDelegationCrossTenantError`) — each carries `.reason` discriminator + shared structured fields (delegationId, workspaceIdHash)
- [ ] 4.6 Implement `resolveKeyOwnerThenLease(callerUserId, workspaceContextUserId, fn)`: flag-off fast-path → direct `runWithByokLease`; flag-on → `supabase.rpc('resolve_byok_key_owner').maybeSingle()`; handle null + error fallback gracefully
- [ ] 4.7 GREEN: `byok-resolver.test.ts` cases pass
- [ ] 4.8 REFACTOR: consumer grep of `ByokLeaseArgs` / `ByokLease` / `ByokLeaseError` per `hr-type-widening-cross-consumer-grep`; record in PR body

## Phase 5 — 5-Site Sentinel Sweep + cost-writer Cap-Check + Audit Threading

- [ ] 5.1 RED: extend `byok-delegations.test.ts` with cost-attribution test cases (cap-exceeded → no audit row; revoke-grace → caller attribution)
- [ ] 5.2 Edit `agent-runner.ts:882`: wrap `runWithByokLease` with `resolveKeyOwnerThenLease(userId, userId, ...)`
- [ ] 5.3 Edit `agent-runner.ts:2401`: same wrap
- [ ] 5.4 Edit `cc-dispatcher.ts:890`: same wrap
- [ ] 5.5 Edit `inngest/functions/cfo-on-payment-failed.ts:199`: same wrap
- [ ] 5.6 Edit `inngest/functions/github-on-event.ts:208`: same wrap
- [ ] 5.7 Edit `cost-writer.ts persistTurnCost`: extend signature with optional `delegationId?: string` + `callerUserId?: string`; when delegationId set, call `check_byok_delegation_cap` first; on SQLSTATE P0001 map to sibling errors + `reportSilentFallback`; on pass, call `write_byok_audit` with 7-arg form including delegation_id
- [ ] 5.8 Edit `agent-runner.ts:1891` (`persistTurnCost` caller): thread `lease.delegationId` + `lease.workspaceContextUserId`
- [ ] 5.9 Edit `cc-dispatcher.ts` `onResult` `persistTurnCost` caller: same threading
- [ ] 5.10 GREEN: sentinel sweep cases pass; PR body enumerates all 5 sites + conversion details
- [ ] 5.11 REFACTOR: catch-site grep for `instanceof ByokLeaseError` / `instanceof MissingByokKeyError`; add `instanceof ByokDelegationError` clauses where appropriate

## Phase 6 — Art. 17 Cascade Wire-Up in account-delete.ts

- [ ] 6.1 RED: extend `byok-delegations.test.ts` with anonymise integration case (full account-delete cascade)
- [ ] 6.2 Edit `account-delete.ts`: add phase 5.9 between phase 5.8 (`anonymise_organization_membership`) and phase 6 (`auth.admin.deleteUser`); call `supabase.rpc("anonymise_byok_delegations", { p_user_id: userId })` with sibling error-handling shape
- [ ] 6.3 Update docstring header at `account-delete.ts:75-82` to include phase 5.9
- [ ] 6.4 GREEN: anonymise cascade case passes

## Phase 7 — CLI grant/revoke + package.json + Feature Flag

- [ ] 7.1 RED: extend `byok-delegations.test.ts` with feature-flag-off bypass case (resolver short-circuits to direct lease)
- [ ] 7.2 Create `apps/web-platform/scripts/byok-grant.ts` (bun shebang; hand-rolled argv with `--actor`, `--grantor`, `--to`, `--workspace`, `--cap-cents`, `--expires-in`; resolve emails → userIds; resolve workspace via `getDefaultWorkspaceForUser`; call `grant_byok_delegation` admin-form; print JSON)
- [ ] 7.3 Create `apps/web-platform/scripts/byok-revoke.ts` (mirror shape; calls `revoke_byok_delegation` admin-form)
- [ ] 7.4 Edit `apps/web-platform/package.json`: add `"byok-grant": "bun scripts/byok-grant.ts"` + `"byok-revoke": "bun scripts/byok-revoke.ts"`
- [ ] 7.5 Edit `apps/web-platform/lib/feature-flags/server.ts`: add `"byok-delegations": "FLAG_BYOK_DELEGATIONS"` to FLAG_VARS
- [ ] 7.6 Add `isByokDelegationsEnabled(orgId?: string): boolean` mirroring `isTeamWorkspaceInviteEnabled` two-key gate (env `FLAG_BYOK_DELEGATIONS === "1"` AND orgId in `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS`)
- [ ] 7.7 GREEN: flag-off bypass case passes
- [ ] 7.8 CLI E2E in dev: `doppler run -p soleur -c dev -- bun run byok-grant -- --actor jean@jikigai.com --grantor jean@jikigai.com --to harry@jikigai.com --workspace auto --cap-cents 2000` returns delegation_id; `byok-revoke -- --id $ID --actor jean@jikigai.com --reason admin_revoke` succeeds

## Phase 8 — Tests Finalize + ADR + PR Body

- [ ] 8.1 Test fixture isolation: every test file has `beforeEach` that TRUNCATEs `byok_delegations` + relevant `audit_byok_use` rows; synthesizes fixtures via helper (per `cq-test-fixtures-synthesized-only`)
- [ ] 8.2 Time-boundary test: revoke-grace at +30s (passes; attribution = grantor) vs +90s (raises `revoked_post_grace`; attribution shifts to caller); document controlled-clock technique in test header
- [ ] 8.3 RLS dual-shape: explicit 42501 (grant) vs 42P17 (policy) cases per learning `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.md`
- [ ] 8.4 Cross-tenant test: insert via admin RPC with grantor in OrgA + grantee in OrgB → P0001 from `byok_delegations_check_same_workspace`; Sentry event with `art_33_breach: "true"` captured
- [ ] 8.5 Member-departure test: DELETE workspace_members → byok_delegations row has revoked_at + revoked_by_user_id = OLD.user_id + revocation_reason = 'member_departed'
- [ ] 8.6 Cap-exceeded test: write past cap raises `cap_exceeded`; grantor cap-window spend unchanged; NO audit row inserted on rejected call
- [ ] 8.7 pg_default_acl audit assertion (folded; not a dedicated test file): query `pg_default_acl` + per-relation grants; assert no `authenticated` EXECUTE on admin-form RPCs, no leaked grants on `byok_delegations`
- [ ] 8.8 `bun run typecheck` exits 0
- [ ] 8.9 `bun test` exits 0 (baseline + new cases)
- [ ] 8.10 Run `/soleur:architecture create "BYOK delegations: per-workspace grantor-funded runs"` to draft ADR with 9 decisions (v2 — kill-switch re-arch, abstract base hierarchy, admin-only RPCs, rolling 24h, member-departure trigger collapse)
- [ ] 8.11 Verify `FLAG_BYOK_DELEGATIONS=0` in prd Doppler: `doppler secrets get FLAG_BYOK_DELEGATIONS -c prd`
- [ ] 8.12 Mark PR ready via `gh pr ready 4290`; verify Closes references use `Ref #4232` NOT `Closes #4232`
- [ ] 8.13 PR body enumerates: 5 sentinel sweep sites + conversion details + type widening sweep result + ADR link + v2 plan-review refinements note

## Post-merge (operator + auto)

- [ ] P.1 Migration 062 applied to prd via `web-platform-release.yml#migrate` (auto-triggered on merge; verify `gh run watch`)
- [ ] P.2 PostgREST schema reload post-apply (container restart per learning `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md`); automatable via `mcp__plugin_supabase_supabase__authenticate` flow or container deploy hook
- [ ] P.3 Sentry alert rule for `art_33_breach=true` tag created with distinct action shape (one-time; automatable via Sentry API in follow-up issue)
- [ ] P.4 Issue #4232 remains OPEN until PR-B lands; `Ref #4232` records progress

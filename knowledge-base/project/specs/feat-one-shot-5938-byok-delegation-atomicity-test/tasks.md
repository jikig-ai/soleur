# Tasks — test(observability): byok delegation atomicity (#5938, Ref #5920)

Plan: `knowledge-base/project/plans/2026-07-03-test-byok-delegation-atomicity-plan.md`
Lane: cross-domain (no spec.md — TR2 fail-closed default)

## Phase 0 — Preconditions
- [ ] 0.1 Verify `pg_get_functiondef('public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)'::regprocedure)` returns a body (dev, `DATABASE_URL_POOLER`).
- [ ] 0.2 Verify service-role INSERT into `audit_byok_use` with explicit backdated `ts` + `delegation_id` succeeds (daily-isolation seed).
- [ ] 0.3 Confirm `unit` project glob `test/**/*.test.ts` (`vitest.config.ts:44`) matches the new path.

## Phase 1 — New test file scaffold
- [ ] 1.1 Create `apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts`.
- [ ] 1.2 Header: cite cap-RPC precedent + existing partial hourly test (`byok-delegations.tenant-isolation.test.ts:537`); `cq-test-fixtures-synthesized-only`.
- [ ] 1.3 `describe.skipIf(!INTEGRATION_ENABLED)` on `TENANT_INTEGRATION_TEST === "1"`.
- [ ] 1.4 Guarded porsager `postgres` diagnostic connection from `DATABASE_URL_POOLER` (`ssl.rejectUnauthorized:false`, dev-only, mirrors cap test); `null` when unset.
- [ ] 1.5 `fetchLiveDelegationRpcBody()` — guarded, never throws, fallback string.
- [ ] 1.6 Named constants `COST_CENTS=100`, `CAP_CENTS=500`, `N=10`, `K=5`; assert `CAP_CENTS % COST_CENTS === 0` in `beforeAll`.
- [ ] 1.7 `grantDelegation` helper: `createSyntheticUser` (grantor+grantee) → `addMember` → `grant_byok_delegation`; fresh delegation per test; NO acceptance/withdrawal rows.
- [ ] 1.8 `afterAll` orphan-acceptance (WORM + ON DELETE RESTRICT); `sql.end()`.

## Phase 2 — Test cases
- [ ] 2.1 Test A (hourly strict-`>` boundary, sequential): `== cap` call passes; K+1 raises `hourly_cap_exceeded`; audit count `== K`; self-diagnosis embed.
- [ ] 2.2 Test B (daily strict-`>` boundary, aged-seed): pre-seed aged rows (`ts=now()−2h`) summing to `CAP_CENTS−COST_CENTS`; live call at `==cap` passes; next raises `daily_cap_exceeded`; assert hourly did NOT raise; self-diagnosis embed.
- [ ] 2.3 Test C (concurrency/FOR UPDATE): `Promise.allSettled` N calls; exactly K admitted, N−K raise hourly marker; audit count `== K` and spend `== CAP_CENTS` (no double-spend); partition on `.error`; self-diagnosis embed.

## Phase 3 — Verify
- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 3.2 Un-gated run reports suite `skipped` (no env).
- [ ] 3.3 Live gated run (dev Doppler, `TENANT_INTEGRATION_TEST=1`) → A/B/C pass.
- [ ] 3.4 (Optional) deliberate-drift ROLLBACK smoke confirms embedded body appears on failure.

## Acceptance
- [ ] All Pre-merge ACs in the plan satisfied. No post-merge operator steps (tenant-integration.yml auto-runs the heavy suite on the PR).

# Tasks — fix: "Share a key" toggle no-ops (delegation RPC param mismatch)

Plan: `knowledge-base/project/plans/2026-06-01-fix-share-a-key-delegation-rpc-param-mismatch-plan.md`

## Phase 1 — RED (failing test first)

- [ ] 1.1 Create `apps/web-platform/test/api-delegation-grant-route.test.ts` mirroring the mock
  pattern in `apps/web-platform/test/api-delegation-withdraw-route.test.ts`
  (`mockServiceRpc`, `mockGetUser`, `mockValidateOrigin`, `mockIsByokDelegationsEnabled`,
  `mockResolveCurrentOrganizationId`).
- [ ] 1.2 Assert `mockServiceRpc` called with `toHaveBeenCalledWith("grant_byok_delegation", { p_grantor_user_id, p_grantee_user_id, p_workspace_id, p_daily_usd_cap_cents, p_hourly_usd_cap_cents, p_expires_at: null, p_actor_user_id })`.
- [ ] 1.3 Add cases: 200 happy path (returns `delegationId`), 403 non-owner, 400 missing fields, 404 flag-off.
- [ ] 1.4 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-delegation-grant-route.test.ts` → confirm it FAILS against current route.

## Phase 2 — GREEN (fix the route)

- [ ] 2.1 In `apps/web-platform/app/api/workspace/delegations/route.ts` POST, rename RPC args:
  `p_daily_cap_cents`→`p_daily_usd_cap_cents`, `p_hourly_cap_cents`→`p_hourly_usd_cap_cents`,
  `p_created_by_user_id`→`p_actor_user_id`.
- [ ] 2.2 Add `p_expires_at: null`.
- [ ] 2.3 Default hourly to daily when client omits it: `p_hourly_usd_cap_cents: body.hourlyCapCents ?? body.dailyCapCents`.
- [ ] 2.4 Re-run the grant-route test → GREEN.
- [ ] 2.5 Verify: `grep -nE 'p_daily_cap_cents|p_hourly_cap_cents|p_created_by_user_id' apps/web-platform/app/api/workspace/delegations/route.ts` returns zero.

## Phase 3 — Client UX guard

- [ ] 3.1 In `apps/web-platform/components/settings/delegation-toggle.tsx` `handleToggle`, surface
  non-OK POST/DELETE responses (inline error or `window.alert`, matching the remove-member pattern
  in `team-membership-list.tsx:114`). Keep `setActive(true)` only on success.

## Phase 4 — Verify

- [ ] 4.1 `grep -rn 'grant_byok_delegation' apps/web-platform --include=*.ts | grep -v migrations | grep -v test` → only `route.ts` + `byok-grant.ts`, both canonical names.
- [ ] 4.2 Run the full web-platform test suite via `apps/web-platform/package.json` test script → green.
- [ ] 4.3 (Optional, if dev Supabase reachable) end-to-end: owner toggles "Share a key" on a keyless
  member → delegation row created, toggle stays on.

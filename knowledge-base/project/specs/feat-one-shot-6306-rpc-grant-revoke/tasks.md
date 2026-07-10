# Tasks — fix(security): revoke residual anon/authenticated EXECUTE on service-role-only DEFINER RPCs (#6306)

Plan: `knowledge-base/project/plans/2026-07-11-fix-revoke-definer-rpc-residual-grants-plan.md`
Lane: single-domain · Threshold: single-user incident · requires_cpo_signoff: true

## Phase 0 — Preconditions
- [ ] 0.1 Re-check next-free migration ordinal against `origin/main`; `128` is provisional — renumber migration+verify+down+test together if taken.
- [ ] 0.2 Re-confirm live `proacl` on the 5 targets is still `revoke-from-public`-only.

## Phase 1 — Migration + down
- [ ] 1.1 Create `apps/web-platform/supabase/migrations/128_revoke_definer_rpc_residual_grants.sql` (model on `069_jti_deny_grant_restore.sql`).
- [ ] 1.2 For each of the 5 FIX targets: `revoke execute … from anon, authenticated;` + defense-in-depth `from public;`.
    - `find_stuck_active_conversations(integer)`
    - `acquire_conversation_slot(uuid, uuid, integer, uuid)`
    - `release_conversation_slot(uuid, uuid)`
    - `touch_conversation_slot(uuid, uuid)`
    - `release_slot_on_archive()`
- [ ] 1.3 Add `COMMENT ON FUNCTION find_stuck_active_conversations` — service-role-only intent + Ref #6306.
- [ ] 1.4 Create `128_revoke_definer_rpc_residual_grants.down.sql` restoring the pre-fix grants (rollback-only, mirror `069_*.down.sql`). MUST carry a `093.down`-style caveat: "KNOWINGLY re-opens #6306 IDOR — do NOT run in production; rollback-machinery only".
- [ ] 1.5 Use EXACT current signatures — `acquire_conversation_slot` is the 4-arg `(uuid, uuid, integer, uuid)` (093), NOT the dropped 3-arg (029). A wrong sig hard-fails run-verify under ON_ERROR_STOP=1.

## Phase 2 — Verify sentinel
- [ ] 2.1 Create `apps/web-platform/supabase/verify/128_definer_rpc_residual_grants_revoked.sql` with the `(check_name, bad)` contract.
- [ ] 2.2 Per target: `anon` deny + `authenticated` deny + `public` deny checks (bad=1 when EXECUTE still held).
- [ ] 2.3 For the 4 non-trigger targets: `service_role` grant-present check (bad=1 when service_role LACKS EXECUTE). Omit for `release_slot_on_archive()`.

## Phase 3 — Migration content test
- [ ] 3.1 Create `apps/web-platform/test/supabase-migrations/128-revoke-definer-rpc-residual-grants.test.ts` (mirror `036-release-slot-on-archive.test.ts`).
- [ ] 3.2 Assert migration 128 contains the anon/authenticated revoke for each of the 5 functions and verify/128 asserts the deny state.
- [ ] 3.3 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/128-revoke-definer-rpc-residual-grants.test.ts`.

## Phase 4 — Cross-reference + follow-up (no code)
- [ ] 4.1 Record in `decision-challenges.md`: when #6256 harness lands, `rpc-cases.ts` entry for these RPCs must be a plain denial (not baselined `test.fails`).
- [ ] 4.2 `/ship` files a `type/security` follow-up issue for the repo-wide `ALTER DEFAULT PRIVILEGES` / migration-lint baseline (root-cause hardening, deferred from this hotfix).

## Verification
- [ ] V1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] V2 Reaper + concurrency-slot regression suites green (service-role path unchanged).
- [ ] V3 PR body uses `Closes #6306`; `/ship` posts cross-ref comment on #6256.

---
date: 2026-05-18
related: [3947, 3984, 3853]
related_migrations:
  - 043_tenant_deploy_audit.sql
  - 044_add_tc_acceptances_ledger.sql
  - 048_scope_grants.sql
category: security-issues
---

# WORM-trigger `current_user = 'service_role'` bypass check silently always-false under PostgREST routing

## The finding

Migrations 043, 044, and 048 (drafted) all use the same WORM-trigger pattern: an INVOKER trigger function gates UPDATEs on an append-only table, bypassing only when (a) a GUC is set inside the legitimate anonymise RPC and (b) `current_user = 'service_role'`. The author's comment in 044 explains the INVOKER choice:

> "Trigger function is INVOKER (NOT SECURITY DEFINER). DEFINER would evaluate `current_user` to the function owner (`postgres`), making the `current_user = 'service_role'` Art. 17 bypass gate always false and breaking the legitimate anonymise flow."

PR #3984's integration test for `anonymise_scope_grants` (the first live test of this pattern against PostgREST routing) revealed the comment's theory is wrong. The role-check is silently always-false in BOTH 044 and 048. The bypass gate never fires when called via the Supabase JS client / PostgREST.

## Why the role check fails

PostgREST request path:

1. PostgREST connects to Postgres as the `authenticator` role.
2. Per request, PostgREST runs `SET LOCAL ROLE <role>` using the `role` claim from the JWT. For a service-role-key request, the role becomes `service_role`. At this point, statements run with `current_user = service_role`.
3. PostgREST calls `SELECT anonymise_scope_grants(p_user_id)`.
4. The function is `SECURITY DEFINER`. Function body executes with `current_user = <function owner>`, typically `postgres` for migrations applied via Supabase CLI / Management API.
5. The function body runs `SET LOCAL app.scope_grants_anonymise_in_progress = 'on'` then `UPDATE scope_grants SET founder_id = NULL WHERE ...`.
6. The BEFORE UPDATE trigger fires. The trigger function is INVOKER.

**The miscalculation is at step 6.** The author assumed INVOKER would propagate the caller's PostgREST-set role (`service_role`) to the trigger function. It does not. The INVOKER trigger function inherits the current execution context, which is still inside the SECURITY DEFINER scope — so `current_user = postgres` (the function owner), NOT `service_role`. The trigger's bypass check `current_user = 'service_role'` evaluates to `false`. The bypass never fires. The trigger's general "WORM violation" RAISE EXCEPTION path runs instead.

INVOKER vs DEFINER for triggers controls WHOSE PRIVILEGES are used for permission checks (search, grant) and what side-effects can be observed (e.g., recursion). It does not give the trigger function visibility into a "previous" role that existed before a SECURITY DEFINER call elevated `current_user`. There is no PostgreSQL feature that lets a trigger inside a DEFINER function see the pre-DEFINER `current_user`.

## Why this gap survived from migration 043 → 044 → 048

- **043** introduced the pattern. The integration test that would have caught it never existed.
- **044** copied the pattern. The migration ships a lint test (`migration-044-tc-acceptances.test.ts`) that checks the SQL text statically — REVOKE-from-all-roles on the trigger function, INVOKER-not-DEFINER, BEFORE UPDATE + BEFORE DELETE wiring. The lint passes. The behavior is never run against a live database.
- **`account-delete.test.ts`** (the consumer of `anonymise_tc_acceptances`) is fully MOCKED. The Supabase service client's `.rpc(...)` is replaced with a `vi.fn()` that records the call name and returns `{ data: 0, error: null }`. The actual SQL never runs. So the bypass check has never been live-exercised in CI from 2026-05-15 (#3853 merge) through 2026-05-18 (#3984 integration test).
- **048** copied 044's pattern. PR #3984 added a tenant-isolation integration test that exercises `anonymise_scope_grants` against the real dev Supabase. The test failed with `P0001 scope_grants is append-only; only NULL->value revocation is permitted` — the WORM violation path the bypass was supposed to skip.

## The fix in 048

Drop the role check. The bypass becomes:

```sql
IF v_anonymise_flag <> '' THEN
  RETURN COALESCE(NEW, OLD);
END IF;
```

Defense in depth WITHOUT the role check rests on three load-bearing properties:

1. **Single SET-site.** `app.scope_grants_anonymise_in_progress` is set in exactly one place: the body of `anonymise_scope_grants`. Grep-verified at write time; the comment block documents the invariant; the lint test for migration 048 (TBD) will assert it going forward.
2. **GRANT EXECUTE TO service_role only.** `REVOKE EXECUTE FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE TO service_role`. Only service-role-authenticated callers can invoke `anonymise_scope_grants` and thus set the GUC. PostgREST enforces this via the JWT-role check before the SECURITY DEFINER function body runs.
3. **`SET LOCAL` transaction scope.** The GUC is set with `SET LOCAL`, scoped to the current transaction. On COMMIT or ROLLBACK it reverts to empty. It cannot leak across requests; a malicious request that somehow set the GUC (impossible per #2) would still revert before any subsequent trigger could observe it.

The chain "service_role caller → SECURITY DEFINER function → SET LOCAL GUC → trigger sees GUC" is the cryptographic-chain equivalent of the legitimate cascade. The role-check was meant to harden #2 (defense in depth), but in practice it added no coverage (always-false) and broke the bypass entirely. Removing it makes the trigger work as designed.

## What this means for migrations 043 and 044

Both have the same broken bypass. The bypass would fire if:

- 043's anonymise path: `apps/web-platform/supabase/migrations/043_tenant_deploy_audit.sql` — operator-side; production usage is low/zero in alpha.
- 044's anonymise path: `anonymise_tc_acceptances`, called from `account-delete.ts:200-225`. Production usage = every user-initiated account deletion.

If a user has ever successfully deleted their account on prd (Art. 17), one of two things is true:
- (a) The cascade silently failed at `anonymise_tc_acceptances` and the deletion never reached `auth.admin.deleteUser` — leaving the user in a half-deleted state.
- (b) The bypass DID fire somehow, and our INVOKER+SECURITY-DEFINER analysis is incomplete.

Investigation TODO (separate follow-up issue): query prd for users with `auth.users` row deleted but `tc_acceptances` rows still bound to that user_id. Any matches confirm path (a) — a silent Art. 17 violation that needs remediation.

The same pattern should be removed from 043 and 044 in a follow-up migration. The 048 fix sets the precedent; the follow-up applies it retroactively. Migrations 043 and 044 cannot be edited in place (already merged to main), so the fix lands as `050_fix_worm_anonymise_bypass.sql` or similar, replacing the trigger functions via `CREATE OR REPLACE FUNCTION`.

## Pattern to enforce going forward

**Every SECURITY DEFINER RPC that includes a GUC-gated trigger bypass MUST be exercised by a live integration test against the dev database.** Mocked tests (vi.fn-replaced .rpc) are not sufficient — they prove the orchestrator-level cascade order, not that the SQL works. The integration test should:

1. Insert a fixture row.
2. Call the anonymise RPC via the Supabase service client.
3. Assert `error` is null and the row's discriminator column is now NULL.
4. Assert the row is still present (no DELETE).

PR-G's `lifecycle.test.ts` ships this for `scope_grants`. The follow-up to fix 043/044 must ship the equivalent for `tenant_deploy_audit` and `tc_acceptances`.

## Cross-reference

This sits next to `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md` (the REVOKE-from-PUBLIC class — adjacent to this finding, both about SECURITY DEFINER discipline) and `security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md` (RLS write-path FOR ALL trap — another class of "the security gate doesn't fire the way the author expected"). Theme: SQL-layer security primitives often have non-obvious semantic gaps that surface only under live-DB testing.

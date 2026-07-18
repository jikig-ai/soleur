---
title: "Verifying RLS/SECURITY-DEFINER migrations locally — savepoint for post-raise queries, oidvectortypes for signature-scoped sentinels, docker-exec psql fallback"
date: 2026-07-11
category: database-issues
module: apps/web-platform/supabase, test/rls-fuzz
tags: [rls, security-definer, verify-sentinel, postgres, savepoint, rls-fuzz, migrations]
issues: [6334, 6336]
pr: 6342
---

# Verifying RLS / SECURITY DEFINER migrations locally (#6334, #6336)

## Problem

Shipping two tenant-boundary DB fixes (RLS `WITH CHECK` + a SECURITY DEFINER ownership guard) with `test.fails`→plain-test un-baseline contracts and fail-closed `verify/` sentinels. Three reusable frictions surfaced while proving RED→GREEN on a live local Postgres.

## Key insights

### 1. A guard that RAISEs aborts the enclosing txn — a security test that runs a *follow-up query* after the raise needs a SAVEPOINT

The `authorize_template` ownership guard `RAISE 42501`s for a cross-founder grant. The harness denial test drives the RPC then queries `count(*) from template_authorizations` **in the same rolled-back transaction** to assert 0 rows were created. A bare `try/catch` around the RPC call does NOT contain a Postgres transaction abort — the subsequent count query fails with SQLSTATE `25P02` ("current transaction is aborted"). Wrap the raising call in a subtransaction:

```ts
try {
  await t.savepoint((sp) => sp.unsafe(`select authorize_template(...)`));
} catch (e) { caught = e; }   // postgres.js re-throws AFTER `ROLLBACK TO`, so the catch is still load-bearing
const r = await t.unsafe(`select count(*)::int as n from ...`);  // outer txn survives
```

Non-vacuity is preserved: pre-fix the RPC does NOT raise → savepoint releases → the INSERT is retained in the outer txn → `count=1` → RED. The single-statement row-hijack UPDATE test needs no savepoint (it returns a Verdict and rolls back immediately, no intervening query on an aborted txn). Corollary (from review): a `catch{}`/count-only oracle false-greens on a *wrong-reason* raise (42883/22023/23xxx also yield 0 rows) — route the caught error through the harness `classifyRpcOutcome` and assert the denial SQLSTATE ∈ {42501, P0001, P0002}.

### 2. Scope a verify sentinel to a function signature with `oidvectortypes(proargtypes)`, NOT `pg_get_function_identity_arguments`

`pg_get_function_identity_arguments(oid)` returns the arg **names + types** (`p_template_hash text, p_action_class text, p_grant_id uuid`), so `= 'text, text, uuid'` matches zero rows and a fail-closed `CASE WHEN count(*)=1` sentinel reds falsely. Use `pg_catalog.oidvectortypes(p.proargtypes) = 'text, text, uuid'` for a names-free type signature.

### 3. `verify` owner-binding assertions must pin the literal predicate, not a shared sub-token

A `with_check ILIKE '%auth.uid()%'` intended to prove the `user_id = auth.uid()` owner-binding is retained is **tautological**: `is_workspace_member(workspace_id, auth.uid())` already contains `auth.uid()`. A regression dropping the owner-binding (keeping only the membership call) false-greens. Assert the literal `%user_id = auth.uid()%` (pg_policies.with_check deparses as `(user_id = auth.uid())`).

### 4. Local migration apply when `psql` is not on the host PATH but the supabase_db container is running

`run-migrations.sh` needs `psql` on PATH. When the host lacks it but `supabase start` is running, apply via the container, mirroring the canonical tracking-row idiom (body + `content_sha` in one transaction):

```bash
sha=$(git hash-object "$f")
{ cat "$f"; printf "\nINSERT INTO public._schema_migrations (filename, content_sha) VALUES ('%s','%s');\n" "$f" "$sha"; } \
  | docker exec -i supabase_db_web-platform psql -U postgres -d postgres -v ON_ERROR_STOP=1 --single-transaction
```

Down-migrations can be proven reversible without persisting by running them inside `BEGIN; <down>; <state assertion>; ROLLBACK;` via the same `docker exec`.

## Session Errors

- **`run-migrations.sh` exited 1: `psql not found on PATH`.** Recovery: applied via `docker exec supabase_db_web-platform psql` with the tracking-row idiom (insight #4). Prevention: the local-apply fallback is now documented here; consider a `run-migrations.sh` fallback to a running `supabase_db_*` container when host `psql` is absent.
- **verify/130 scoped by `pg_get_function_identity_arguments` returned 0 (false bad=1).** Recovery: switched to `oidvectortypes(proargtypes)` (insight #2). Prevention: this learning; prefer `oidvectortypes` for signature-scoped `pg_proc` sentinels.
- **rls-rpc denial test failed with a propagated 42501 (txn-abort) post-fix.** Recovery: SAVEPOINT-wrapped the raising RPC (insight #1). Prevention: this learning documents that any post-raise follow-up query in a rolled-back-txn test needs a subtransaction.
- **`ls .../supabase/migrations/` → No such file or directory** (one-off): CWD had drifted into `apps/web-platform`. Prevention: chain `cd <abs> && <cmd>` in one Bash call (the Bash tool does not persist CWD).

## Related

- Plan: `knowledge-base/project/plans/2026-07-11-fix-rls-tenant-boundary-with-check-and-authorize-template-plan.md`
- ADR-111 (RLS/authz-fuzz harness); un-baseline contracts in `apps/web-platform/test/rls-fuzz/`
- Sibling: [[2026-07-10-supabase-default-privileges-defeat-revoke-from-public]] (why the kb_files column-REVOKE is inert — a table-level UPDATE grant subsumes it)
- [[2026-05-25-migration-body-no-top-level-begin-commit]]

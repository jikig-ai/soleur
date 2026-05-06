---
date: 2026-05-06
session: PR-B agent-runtime-platform — §1.3 tenant isolation
class: security-issue
severity: high
related-pr: PR-B / #3244
---

# Supabase `ALTER DEFAULT PRIVILEGES` defeats `REVOKE ALL FROM PUBLIC` on `public`-schema functions

## What happened

Migration 037 (PR-B) declared three SECURITY DEFINER RPCs intended to be service-role-only: `write_byok_audit`, `precheck_jwt_mint`, `is_jti_denied`. The migration ended each with the standard hardening pair:

```sql
REVOKE ALL ON FUNCTION public.<fn>(...) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.<fn>(...) TO service_role;
```

This is the canonical Postgres pattern for "service-role-only RPC." The migration's file-parse contract test asserted both lines were present and applied successfully against dev.

The integration test (`agent-runner.tenant-isolation.test.ts`) then exercised the RPCs through an `authenticated` client (founder A's runtime JWT) and expected SQLSTATE `42501` (insufficient_privilege). **Both calls succeeded.** The `authenticated` role had `EXECUTE` despite the migration's `REVOKE ALL FROM PUBLIC`.

Live grant inspection showed:

```
write_byok_audit / precheck_jwt_mint / is_jti_denied
  grantee     | privilege
  ------------+-----------
  anon        | EXECUTE
  authenticated | EXECUTE
  postgres    | EXECUTE
  service_role | EXECUTE
```

`pg_default_acl` confirmed the cause:

```
schema=public defaclobjtype=f
acl={postgres=X/postgres,
     anon=X/postgres,
     authenticated=X/postgres,
     service_role=X/postgres}
```

Supabase initializes `public` with:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS
  TO anon, authenticated, service_role;
```

So every new function in `public` is auto-granted to the three Supabase wire-roles **as a sibling effect of `CREATE FUNCTION`**, not as part of the migration. `REVOKE ALL ... FROM PUBLIC` revokes only the `PUBLIC` pseudo-role; the three explicit named-role grants survive.

## Why it's a hidden constraint

1. **Default Postgres pedagogy is wrong here.** The `REVOKE ALL FROM PUBLIC` pattern is the documented "lock down to definer-only" pattern in every Postgres book and tutorial. It works on vanilla Postgres because `PUBLIC` is the only default grantee. Supabase changes the rule without surfacing a warning.
2. **`pg_default_acl` is not in any security checklist most teams maintain.** It's discoverable in the docs but invisible in normal migration review.
3. **File-parse migration tests pass.** The strings `REVOKE ALL ... FROM PUBLIC` and `GRANT EXECUTE ... TO service_role` are present, so the file-parse test (an in-repo defense) reads the intent and reports green.
4. **Live RPC calls succeed silently.** A `GRANT EXECUTE` on a SECURITY DEFINER function is not a discovery surface; the tenant just gets to call the privileged code.

## The fix

Always revoke from `PUBLIC, anon, authenticated` (and `service_role` too if the function should not be callable as definer through its own context). Pattern:

```sql
-- Service-role-only: keep service_role grant.
REVOKE ALL ON FUNCTION public.<fn>(...) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.<fn>(...) TO service_role;

-- Trigger function (no direct callers): revoke from everyone including service_role.
REVOKE ALL ON FUNCTION public.<trigger_fn>() FROM PUBLIC, anon, authenticated, service_role;
```

For migration 037 in PR-B, all four functions were patched to the explicit-role-revoke pattern, and the corrective `REVOKE` statements were applied to dev directly via Mgmt API SQL exec (the table data was empty, no cleanup needed).

## Surfaces caught vs. missed it

- **Caught (live):** the integration test's `expect(error).not.toBeNull()` against an authenticated client. Without that test, the migration would have shipped to prd with `authenticated` having direct EXECUTE on tenant-data writers.
- **Missed (file-parse):** asserting the literal `REVOKE ALL FROM PUBLIC` string is necessary but **not sufficient**. A migration linter test must require named-role revokes too.
- **Missed (SQL review heuristic):** "REVOKE FROM PUBLIC + GRANT TO service_role = locked down" is wrong on Supabase.

## Followups landed in the same edit cycle

- Migration 037 amended: `REVOKE ALL ... FROM PUBLIC, anon, authenticated` for all three caller-facing fns, plus `service_role` revoke on the trigger fn (no direct callers).
- File-parse test 037 amended: assertion regex now requires `PUBLIC\s*,\s*anon\s*,\s*authenticated` in the revoke list.
- Corrective `REVOKE` applied to dev via Mgmt API SQL exec (no migration history change; dev was empty so no data integrity risk).

## Followups deferred

- **Audit existing `public`-schema SECURITY DEFINER functions** across migrations 001-036 for the same gap. Specifically: `release_slot_on_archive` (036), `release_conversation_slot` (029_plan_tier_and_concurrency_slots), `migrate_api_key_to_v2` (033), and any other `SECURITY DEFINER` body in earlier migrations. Each must either explicitly revoke from `anon, authenticated` OR be a trigger function (no direct caller).
- **Write a CI gate** (probably as a script invoked from `lint.yml`) that scans `apps/web-platform/supabase/migrations/*.sql` for `CREATE OR REPLACE FUNCTION public\.\w+` and asserts each is followed by either:
  - `REVOKE ... FROM PUBLIC, anon, authenticated` (named-role explicit), OR
  - A comment explaining why the function is intentionally callable by anon/authenticated.

  This is more reliable than per-migration file-parse tests and it covers existing migrations.
- **Document the pattern in `knowledge-base/engineering/conventions/postgres-security-definer.md`** if/when that file exists; otherwise inline in `cq-pg-security-definer-search-path-pin-pg-temp` rule's pointer.

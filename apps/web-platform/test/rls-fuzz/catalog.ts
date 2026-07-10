// Live-catalog derivation of the attack surface (#6256, ADR-103, AC1/AC8).
//
// The target sets are enumerated from `pg_policies` / `pg_proc` on the migrated
// DB — NEVER from a migration-source grep. mig 068 creates its jti-deny policies
// via a `format('%I_jti_not_denied', t)` DO-loop, so the table literals never
// appear in source; the only faithful enumerator is the live catalog. This makes
// the harness self-tracking: a new isolated table or a new SECURITY DEFINER RPC
// granted to `authenticated` shows up here automatically and the coverage gates
// (AC1/AC8) fail until it has an attack case.

import type postgres from "postgres";

type Sql = ReturnType<typeof postgres>;

/**
 * The isolation set (AC1): public tables carrying a PERMISSIVE policy `TO
 * authenticated` whose qual/with_check references `is_workspace_member` — the
 * workspace-tenancy predicate. This is the invariant the harness proves; the
 * jti-deny set is an overlaid *dimension*, not the enumerator.
 */
export async function isolationSet(sql: Sql): Promise<string[]> {
  const rows = await sql<{ tablename: string }[]>`
    select distinct tablename
    from pg_policies
    where schemaname = 'public'
      and permissive = 'PERMISSIVE'
      and 'authenticated' = any(roles)
      and (qual ilike '%is_workspace_member%' or with_check ilike '%is_workspace_member%')
    order by tablename`;
  return rows.map((r) => r.tablename);
}

/** The jti-deny dimension: tables carrying a RESTRICTIVE `%_jti_not_denied` policy (mig 068). */
export async function jtiDenySet(sql: Sql): Promise<string[]> {
  const rows = await sql<{ tablename: string }[]>`
    select distinct tablename
    from pg_policies
    where schemaname = 'public'
      and permissive = 'RESTRICTIVE'
      and policyname ilike '%jti_not_denied%'
    order by tablename`;
  return rows.map((r) => r.tablename);
}

export interface SecDefFn {
  proname: string;
  /** identity arg signature, e.g. "p_workspace_id uuid, p_status text". */
  args: string;
}

/**
 * The RPC bypass set (AC8): every `SECURITY DEFINER` function in `public` that
 * `authenticated` may EXECUTE. A definer fn that trusts a caller-supplied
 * tenancy param instead of re-deriving `is_workspace_member(param, auth.uid())`
 * is a cross-tenant bypass invisible to base-table RLS.
 */
export async function securityDefinerAuthenticatedFns(sql: Sql): Promise<SecDefFn[]> {
  return sql<SecDefFn[]>`
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    order by p.proname, args`;
}

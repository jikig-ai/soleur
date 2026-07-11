// Live-catalog derivation of the attack surface (#6256, ADR-111, AC1/AC8).
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

/**
 * The broader workspace-tenancy surface (AC1b): every RLS-enabled `public` table
 * carrying a `workspace_id` OR `message_id` column. This is a SUPERSET of
 * {@link isolationSet} (which keys on the literal `is_workspace_member` predicate)
 * — it also catches tables isolated by a different predicate (`is_workspace_owner`,
 * an `EXISTS` join through `messages`, etc.) that the predicate-based enumerator
 * misses. The coverage gate requires each to be a target OR an explicit
 * exclusion-with-rationale, so a new workspace-scoped table cannot silently escape
 * the harness the way `message_attachments`/`inbox_item` otherwise would.
 */
export async function workspaceTenancyTables(sql: Sql): Promise<string[]> {
  const rows = await sql<{ tablename: string }[]>`
    select distinct c.relname as tablename
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join information_schema.columns col
      on col.table_schema = 'public' and col.table_name = c.relname
    where n.nspname = 'public'
      and c.relkind = 'r'
      and c.relrowsecurity
      and col.column_name in ('workspace_id', 'message_id')
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

/**
 * EVERY `SECURITY DEFINER` function in `public` (regardless of who may EXECUTE it) —
 * the non-vacuity/parity superset of {@link securityDefinerAuthenticatedFns}. The
 * static migration-lint pre-filter (test/migration-lint/definer-grants.ts, #6328,
 * ADR-112) must detect all of these from migration source; a live fn it fails to
 * match means the static tier under-detects and cannot be trusted (parity guard).
 */
export async function allSecurityDefinerFns(sql: Sql): Promise<SecDefFn[]> {
  return sql<SecDefFn[]>`
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
    order by p.proname, args`;
}

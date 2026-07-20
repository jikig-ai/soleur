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

/**
 * The USER-ISOLATION dimension (AC3): purely user-keyed public RLS tables — a
 * PERMISSIVE policy (TO authenticated, or the implicit `public` superset that
 * covers authenticated) whose qual/with_check references `auth.uid()` AND the table
 * carries a `user_id`/`founder_id` column — MINUS the workspace dimensions. Disjoint
 * FROM AC1/AC1b BY CONSTRUCTION (a SQL set-difference, not human judgment): subtract
 * the is_workspace_member set (AC1) AND the workspace_id/message_id-carrying set
 * (AC1b), so a table satisfying BOTH predicates (e.g. conversations/kb_files —
 * user-keyed rows with workspace visibility overlaid) lands in the workspace
 * dimensions only and never double-counts or escapes both. AC1/AC3 mutual
 * exhaustiveness is then a proven property, not an assertion. The distinct leak this
 * models: a CO-MEMBER of wsA reading another member's `user_id = auth.uid()`-keyed
 * rows — invisible to the base matrix's non-member (userB) attacker, whom a
 * workspace-only policy denies even when the user_id clause is missing.
 */
export async function userIsolationTables(sql: Sql): Promise<string[]> {
  const rows = await sql<{ tablename: string }[]>`
    with uid_keyed as (
      select distinct pol.tablename
      from pg_policies pol
      join information_schema.columns col
        on col.table_schema = 'public' and col.table_name = pol.tablename
       and col.column_name in ('user_id', 'founder_id')
      where pol.schemaname = 'public' and pol.permissive = 'PERMISSIVE'
        and ('authenticated' = any(pol.roles) or 'public' = any(pol.roles))
        and (pol.qual ilike '%auth.uid()%' or pol.with_check ilike '%auth.uid()%')
    ),
    ws_member as (
      select distinct tablename from pg_policies
      where schemaname = 'public' and permissive = 'PERMISSIVE'
        and ('authenticated' = any(roles) or 'public' = any(roles))
        and (qual ilike '%is_workspace_member%' or with_check ilike '%is_workspace_member%')
    ),
    ws_tenancy as (
      select distinct c.relname as tablename
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      join information_schema.columns col
        on col.table_schema = 'public' and col.table_name = c.relname
      where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
        and col.column_name in ('workspace_id', 'message_id')
    )
    select tablename from uid_keyed
    where tablename not in (select tablename from ws_member)
      and tablename not in (select tablename from ws_tenancy)
    order by tablename`;
  return rows.map((r) => r.tablename);
}

/**
 * AC6 row-hijack set: workspace_id-carrying public tables with a PERMISSIVE
 * UPDATE-or-ALL policy `TO authenticated` (or the `public` superset). These are the
 * ONLY tables where a WITH-CHECK tenancy-key-reassignment probe (`SET workspace_id =
 * wsB` under the OWNER's own claims) is non-vacuous: a SELECT/INSERT-only table has
 * no UPDATE policy, so the hijack returns 0 rows *because no policy exists* — a
 * vacuous "denied" — and its positive control ("owner updates a non-tenancy column")
 * is impossible (the owner has no UPDATE policy either). The probe catches a policy
 * whose USING gate (owns the row) is satisfied but whose WITH CHECK fails to re-check
 * membership on the NEW workspace_id.
 */
export async function rowHijackTables(sql: Sql): Promise<string[]> {
  const rows = await sql<{ tablename: string }[]>`
    select distinct pol.tablename
    from pg_policies pol
    join information_schema.columns col
      on col.table_schema = 'public' and col.table_name = pol.tablename and col.column_name = 'workspace_id'
    where pol.schemaname = 'public' and pol.permissive = 'PERMISSIVE'
      and ('authenticated' = any(pol.roles) or 'public' = any(pol.roles))
      and pol.cmd in ('UPDATE', 'ALL')
    order by pol.tablename`;
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

/**
 * The anon-EXECUTE definer set — every `SECURITY DEFINER` public fn the `anon`
 * (unauthenticated) role may EXECUTE. A DISTINCT dimension from the authenticated
 * set: under anon `auth.uid()` is NULL, so every `founder_id = auth.uid()` /
 * `is_workspace_member(param, auth.uid())` premise a definer fn relies on
 * evaporates, and a caller-override param (`COALESCE(p_caller, auth.uid())`)
 * becomes fully attacker-controlled. The #6306 exposure was exactly a residual
 * CREATE-time default EXECUTE grant to anon that migration 037 failed to revoke;
 * this enumerator is the FORWARD tripwire — any future anon-granted definer fn
 * surfaces here and the anon coverage gate reds until it is classified. It would
 * have auto-caught #6306. (Closed today: mig 128 revoked those grants, so this set
 * is currently empty — the gate is a near-tautology by design, ENUMERATION-coverage
 * only, not a proof that anon isolation holds under attack.)
 */
export async function securityDefinerAnonFns(sql: Sql): Promise<SecDefFn[]> {
  return sql<SecDefFn[]>`
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and has_function_privilege('anon', p.oid, 'EXECUTE')
    order by p.proname, args`;
}

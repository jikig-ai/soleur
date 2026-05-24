import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * FK-reverse cleanup for synthetic tenant-isolation users.
 *
 * Mig 053's `handle_new_user` trigger backfills every new `auth.users` row
 * with a solo organization, workspace, and workspace_members row. Each of
 * those references the user via FKs that are ON DELETE RESTRICT (or were
 * pre-mig-065 — see below). Raw `service.auth.admin.deleteUser` cascades
 * `auth.users → public.users` and then hits the RESTRICT references,
 * returning the opaque Supabase admin error "Database error deleting user".
 *
 * This helper runs the FK-reverse anonymise sequence — a subset of
 * `account-delete.ts`'s production cascade — before the auth delete so
 * tenant-isolation tests can clean up after themselves without going
 * through the heavyweight `deleteAccount` path (storage purge, workspace
 * directory delete, dsar-jobs abort).
 *
 * Mig 065 covers the remaining structural RESTRICT FKs (organizations.
 * owner_user_id, audit_byok_use.founder_id) via ON DELETE SET NULL — the
 * cascade succeeds without explicit anonymise steps for those tables.
 *
 * Pattern source: `tearDownSharedWorkspace` in workspace-members-fixtures.ts
 * (which targets a multi-member fixture); this helper covers the solo-
 * canary case used in `*tenant-isolation.test.ts`.
 *
 * Errors are best-effort — anonymise RPCs are idempotent and may legitimately
 * no-op when the user has no rows in the target table. The final auth-delete
 * is the load-bearing step; its error (other than "not found") is surfaced
 * to the caller.
 */
export async function tearDownTenantUser(
  service: SupabaseClient,
  user: { id: string | undefined; email: string },
): Promise<void> {
  if (!user.id) return;

  // FK-reverse anonymise sequence. Order mirrors account-delete.ts
  // steps 3.82–3.93. Each RPC is idempotent (SECURITY DEFINER + UPDATE
  // … WHERE user_id matches; second-call ROW_COUNT = 0).
  const anonymiseSequence: Array<[string, Record<string, unknown>]> = [
    ["anonymise_action_sends", { p_user_id: user.id }],
    ["anonymise_template_authorizations", { p_user_id: user.id }],
    ["anonymise_scope_grants", { p_user_id: user.id }],
    ["anonymise_tc_acceptances", { p_user_id: user.id }],
    ["anonymise_workspace_member_attestations", { p_user_id: user.id }],
    ["anonymise_workspace_member_removals", { p_user_id: user.id }],
    ["anonymise_workspace_members", { p_user_id: user.id }],
    ["anonymise_workspace_member_actions", { p_user_id: user.id }],
  ];

  for (const [rpc, args] of anonymiseSequence) {
    try {
      await service.rpc(rpc, args);
    } catch {
      // best-effort — RPCs are idempotent; a failure here usually means
      // the user had no rows in that table (RPC returned 0). If a real
      // permission error fires, the subsequent auth-delete will surface
      // the cascade block.
    }
  }

  const { error } = await service.auth.admin.deleteUser(user.id);
  if (error && !/not found/i.test(error.message)) {
    throw new Error(
      `tearDownTenantUser: deleteUser(${user.email}) failed: ${error.message}`,
    );
  }
}

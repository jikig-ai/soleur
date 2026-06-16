import type { SupabaseClient } from "@supabase/supabase-js";
import { withGoTrueRetry } from "./gotrue-retry";

/**
 * Synthetic-only allowlist gate for tenant-isolation test users.
 *
 * Boundary sentinel (per `hr-write-boundary-sentinel-sweep-all-write-sites`):
 * the helper refuses to run against any email that doesn't match the
 * canonical tenant-isolation synthetic pattern. Mirrors the call-site
 * `assertSynthetic` guards but pulls the check into the helper itself so
 * a future caller copying the pattern cannot accidentally drop the guard.
 */
const SYNTHETIC_EMAIL_PATTERN =
  /^tenant-isolation-[a-f0-9]{16}@soleur\.test$/;

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
 * Pattern source: `tearDownSharedWorkspace` (apps/web-platform/test/
 * helpers/workspace-members-fixtures.ts:142). That helper targets a
 * multi-member fixture; this one covers the solo-canary case used in
 * `*tenant-isolation.test.ts`.
 *
 * Anonymise-RPC errors are NOT silently swallowed. Per
 * `cq-silent-fallback-must-mirror-to-sentry`: a real RPC error (GRANT
 * inversion, REVOKE drift, PGRST202 from a future signature change, P0001
 * from a WORM-trigger regression) is exactly the class of regression that
 * tenant-integration is designed to catch. The helper continues to the
 * auth-delete step (cleanup must complete) but emits a structured warning
 * with the error code so the CI signal is visible.
 */
export async function tearDownTenantUser(
  service: SupabaseClient,
  user: { id: string | undefined; email: string },
): Promise<void> {
  if (!user.id) return;

  // Boundary sentinel: refuse non-synthetic emails. The 7 current call
  // sites also assertSynthetic at the call point; this in-helper check
  // is the canonical guard.
  if (!SYNTHETIC_EMAIL_PATTERN.test(user.email)) {
    throw new Error(
      `tearDownTenantUser: refusing non-synthetic email ${user.email}`,
    );
  }

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
    const { error } = await service.rpc(rpc, args);
    if (error) {
      // A no-row RPC returns { data: 0, error: null } — it does not error.
      // An error here means a real failure: REVOKE/GRANT drift, search_path
      // inversion, schema-cache miss (PGRST202), or a WORM trigger regression.
      // Continue with the cascade (cleanup must finish) but make the failure
      // visible via stderr so CI captures it.
      // eslint-disable-next-line no-console
      console.warn(
        `tearDownTenantUser: ${rpc} failed for ${user.email}: ` +
          `code=${(error as { code?: string }).code ?? "?"} ` +
          `message=${error.message}`,
      );
    }
  }

  // Retry past GoTrue rate limits and the opaque transient
  // "Database error deleting user" (the FK-reverse anonymise above is
  // idempotent, so a retried delete is safe).
  const { error } = await withGoTrueRetry(`deleteUser:${user.email}`, () =>
    service.auth.admin.deleteUser(user.id!),
  );
  if (error && !/not found/i.test(error.message)) {
    throw new Error(
      `tearDownTenantUser: deleteUser(${user.email}) failed: ${error.message}`,
    );
  }
}

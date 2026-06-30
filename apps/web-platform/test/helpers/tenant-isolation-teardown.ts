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
 * Mig 065 flipped two structural FKs to ON DELETE SET NULL
 * (organizations.owner_user_id, audit_byok_use.founder_id) — the cascade
 * scrubs those natively, so their anonymise RPCs are non-fatal here.
 *
 * Pattern source: `tearDownSharedWorkspace` (apps/web-platform/test/
 * helpers/workspace-members-fixtures.ts:142). That helper targets a
 * multi-member fixture; this one covers the solo-canary case used in
 * `*tenant-isolation.test.ts`.
 *
 * FK-cascade parity (#5582). The sequence below mirrors the full set of
 * anonymise_* RPCs `server/account-delete.ts` runs before
 * `auth.admin.deleteUser`, in production order. The earlier 8-RPC subset
 * was frozen at a pre-migration-064 snapshot and was missing ~13 RPCs —
 * every one behind an `ON DELETE RESTRICT` FK to `users` (notably
 * `anonymise_email_triage_items`, mig 102) deterministically blocked the
 * auth-delete with an opaque GoTrue `500 unexpected_failure`, which
 * `withGoTrueRetry` then masked as 5× transient retries.
 *
 * Each RPC carries a fatality class (`cq-silent-fallback-must-mirror-to-sentry`):
 *   - `restrict`  — FK is ON DELETE RESTRICT; a real error (or a missing-
 *                   function PGRST202/42883, which almost always means an
 *                   arg-name typo) leaves the FK unbroken and the delete
 *                   500s. FATAL: collected and thrown BEFORE deleteUser so
 *                   a future regression is a red test, not a buried warn.
 *   - `set-null`  — FK is ON DELETE SET NULL; the auth-delete cascade scrubs
 *                   it natively, so any error is warn-and-continue.
 *   - `graceful`  — RESTRICT FK but production documents a graceful-degrade
 *                   branch for a possibly-undeployed function (scoped to
 *                   `anonymise_workspace_invitations`): a missing-function
 *                   error is tolerated; any OTHER error is fatal.
 *
 * Each RPC is idempotent (SECURITY DEFINER + UPDATE … WHERE matches; a
 * no-op returns `{ data: 0, error: null }`), so fail-loud is safe even for
 * empty synthetic users.
 */
type FatalityClass = "restrict" | "set-null" | "graceful";

// Production order + arg names derived from server/account-delete.ts; the
// `restrict`/`set-null` class is derived from the FK-defining migration's
// ON DELETE clause (the parity drift guard in
// test/server/teardown-anonymise-parity.test.ts re-derives it from source +
// migrations so a mislabel here cannot codify a wrong fatality silently).
const ANONYMISE_SEQUENCE: ReadonlyArray<
  readonly [rpc: string, argName: string, klass: FatalityClass]
> = [
  ["anonymise_dsar_export_audit_pii", "p_user_id", "restrict"],
  ["anonymise_action_sends", "p_user_id", "restrict"],
  ["anonymise_template_authorizations", "p_user_id", "restrict"],
  ["anonymise_scope_grants", "p_user_id", "restrict"],
  ["anonymise_tc_acceptances", "p_user_id", "restrict"],
  ["anonymise_audit_github_token_use", "p_founder_id", "set-null"],
  ["anonymise_workspace_member_attestations", "p_user_id", "restrict"],
  ["anonymise_workspace_invitations", "p_user_id", "graceful"],
  ["anonymise_departed_user_across_workspaces", "p_departing_user", "restrict"],
  ["anonymise_workspace_member_removals", "p_user_id", "restrict"],
  ["anonymise_workspace_members", "p_user_id", "restrict"],
  ["anonymise_organization_membership", "p_user_id", "restrict"],
  ["anonymise_workspace_member_actions", "p_user_id", "restrict"],
  ["anonymise_workspace_activity", "p_user_id", "set-null"],
  ["anonymise_byok_delegations", "p_user_id", "restrict"],
  ["anonymise_byok_delegation_acceptances", "p_user_id", "restrict"],
  ["anonymise_byok_delegation_withdrawals", "p_user_id", "restrict"],
  ["anonymise_email_triage_items", "p_user_id", "restrict"],
  ["anonymise_email_suppression", "p_user_id", "restrict"],
  ["anonymise_outbound_sends", "p_user_id", "restrict"],
  ["anonymise_routine_runs", "p_user_id", "restrict"],
];

// A schema-cache miss (function not found) — distinct from a real failure.
// PGRST202 = PostgREST cannot find the function; 42883 = Postgres
// undefined_function. On a `restrict` RPC this almost always means an
// arg-name typo (the function exists under a different parameter name), so
// it is treated as FATAL there; only the `graceful` class tolerates it.
function isMissingFunction(error: { code?: string }): boolean {
  return error.code === "PGRST202" || error.code === "42883";
}

export async function tearDownTenantUser(
  service: SupabaseClient,
  user: { id: string | undefined; email: string },
): Promise<void> {
  if (!user.id) return;

  // Boundary sentinel: refuse non-synthetic emails. The current call
  // sites also assertSynthetic at the call point; this in-helper check
  // is the canonical guard.
  if (!SYNTHETIC_EMAIL_PATTERN.test(user.email)) {
    throw new Error(
      `tearDownTenantUser: refusing non-synthetic email ${user.email}`,
    );
  }

  const fatalErrors: string[] = [];

  for (const [rpc, argName, klass] of ANONYMISE_SEQUENCE) {
    const { error } = await service.rpc(rpc, { [argName]: user.id });
    if (!error) continue;

    const code = (error as { code?: string }).code ?? "?";
    const detail =
      `${rpc} failed for ${user.email}: code=${code} message=${error.message}`;

    const tolerable =
      klass === "set-null" ||
      (klass === "graceful" && isMissingFunction(error as { code?: string }));

    if (tolerable) {
      // SET-NULL FK (cascade scrubs natively) or a documented graceful
      // missing-function — warn and continue, but make it visible in CI.
      // eslint-disable-next-line no-console
      console.warn(`tearDownTenantUser: ${detail} (non-fatal: ${klass})`);
    } else {
      // RESTRICT FK real error, or an arg-name-typo PGRST202/42883 on a
      // RESTRICT/graceful RPC — these are the deterministic deleteUser-500
      // causes. Collect and throw before the auth delete so the regression
      // is a red test, not a retry storm masked by withGoTrueRetry.
      fatalErrors.push(detail);
      // eslint-disable-next-line no-console
      console.error(`tearDownTenantUser: ${detail} (FATAL: ${klass})`);
    }
  }

  if (fatalErrors.length > 0) {
    throw new Error(
      `tearDownTenantUser: ${fatalErrors.length} RESTRICT-class anonymise ` +
        `failure(s) for ${user.email} — auth-delete would 500 on the FK ` +
        `block. Fix the anonymise RPC(s) before retrying:\n  ` +
        fatalErrors.join("\n  "),
    );
  }

  // Retry past GoTrue rate limits and the opaque transient
  // "Database error deleting user". With FK-cascade parity above, this now
  // only fires for genuinely transient errors (the anonymise sequence is
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

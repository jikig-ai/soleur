import type { SupabaseClient } from "@supabase/supabase-js";
import { withGoTrueRetry } from "./gotrue-retry";

/**
 * Synthetic-only prefix allowlist for integration-suite test users.
 *
 * Boundary sentinel (per `hr-write-boundary-sentinel-sweep-all-write-sites`):
 * the helper refuses to run against any email outside the enumerated
 * synthetic prefixes. Mirrors the call-site `assertSynthetic` guards but
 * pulls the check into the helper itself so a future caller copying the
 * pattern cannot accidentally drop the guard.
 *
 * Every member suite generates `<prefix>-<16 lowercase hex>@soleur.test`
 * (`randomBytes(8).toString("hex")` — verified in-file per suite). Adding a
 * suite's prefix is a one-line, review-visible edit; the `[a-f0-9]{16}`
 * suffix pin is load-bearing — a permissive `<prefix>.*@` shape lets a
 * fixture's leftovers match (the PR #2597 permissive-regex incident class).
 * mu1.integration.test.ts uses a different domain (@soleur-test.invalid)
 * and is deliberately NOT listed — its teardown is #9995's scope.
 */
export const SYNTHETIC_PREFIXES = [
  "tenant-isolation-",
  "byok-isolation-",
  "beta-crm-",
  "cc-cross-tenant-",
  "conv-rail-cross-tenant-",
  "dsar-cross-tenant-",
  "workspace-fixture-",
] as const;

const escapeRegExp = (s: string): string =>
  s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

const SYNTHETIC_EMAIL_PATTERN = new RegExp(
  `^(?:${SYNTHETIC_PREFIXES.map(escapeRegExp).join("|")})[a-f0-9]{16}@soleur\\.test$`,
);

/**
 * Reusable surface for consumers validating against the pinned shape —
 * export the PREDICATE, never the pattern, so a caller cannot drop the
 * `[a-f0-9]{16}` suffix pin by reconstructing the regex.
 */
export function isSyntheticTestEmail(email: string): boolean {
  return SYNTHETIC_EMAIL_PATTERN.test(email);
}

/**
 * FK-reverse cleanup for synthetic integration-suite users.
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
 * helpers/workspace-members-fixtures.ts). That helper targets a
 * multi-member fixture; this one covers the solo-user teardown for every
 * suite whose synthetic prefix is enumerated in `SYNTHETIC_PREFIXES`
 * (adopted beyond tenant-isolation for #9994).
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
  // Entry stays "restrict" deliberately though the FK is ON DELETE SET
  // NULL (mig 041): its fatality isn't for the FK — it's for the PII the
  // cascade leaves intact (requester_ip/user_agent must be scrubbed
  // before erasure; the SET NULL only clears user_id). Downgrading this
  // label would silently retain PII post-delete.
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
  ["anonymise_agent_engine_data", "p_user_id", "restrict"],
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
      `tearDownTenantUser: refusing non-synthetic email ${user.email} — ` +
        `not in SYNTHETIC_PREFIXES (<prefix>-[a-f0-9]{16}@soleur.test). ` +
        `New synthetic suite? Register its prefix in SYNTHETIC_PREFIXES ` +
        `(test/helpers/tenant-isolation-teardown.ts).`,
    );
  }

  // id<->email binding: the sentinel gates on email but every destructive
  // op below acts on user.id — verify the pair resolves to the same auth
  // user before touching anything (a mismatched pair would scrub+delete a
  // real user under a synthetic-looking email). A missing auth row is
  // tolerated: deleteUser's not-found path below is the idempotent exit.
  // The error half is checked — a transient GoTrue failure must not read
  // as "no auth row" and silently skip the binding (fail-closed).
  const { data: existing, error: lookupErr } = await withGoTrueRetry(
    `getUserById:${user.id}`,
    () => service.auth.admin.getUserById(user.id!),
  );
  if (lookupErr && !/not found/i.test(lookupErr.message)) {
    throw new Error(
      `tearDownTenantUser: getUserById(${user.id}) failed — binding ` +
        `unverifiable, refusing teardown: ${lookupErr.message}`,
    );
  }
  if (existing?.user && existing.user.email !== user.email) {
    throw new Error(
      `tearDownTenantUser: id/email mismatch — ${user.id} resolves to ` +
        `"${existing.user.email}", refusing teardown declared as ` +
        `"${user.email}"`,
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
      `tearDownTenantUser: ${fatalErrors.length} anonymise ` +
        `failure(s) for ${user.email} — auth-delete would 500 on the FK ` +
        `block (or retain PII). Fix the anonymise RPC(s) before retrying:\n  ` +
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

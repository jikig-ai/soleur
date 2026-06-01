/**
 * Single source of truth for the `needsReconnect` signal (#4712).
 *
 * The #4706 incident froze a Knowledge Base for ~5 weeks: the workspace had
 * `repo_status='ready'` but `github_installation_id IS NULL`, so the push
 * webhook reconcile (which selects by `github_installation_id`) never matched
 * it — silent staleness with no in-product signal. This predicate is the
 * deterministic flag both derivation sites (`/api/kb/tree` + `settings/page`)
 * import. Do NOT re-derive it inline anywhere — selector divergence is the
 * incident's own bug class.
 */
export function repoNeedsReconnect(
  repoStatus: string | null,
  installationId: number | bigint | null | undefined,
): boolean {
  // Loose `== null` is intentional: matches null OR undefined (the SELECT may
  // return either). The rest of the codebase is `===`; this is the exception.
  return repoStatus === "ready" && installationId == null;
}

/**
 * Capability-aware reconnect signal (#4712 follow-up).
 *
 * `repoNeedsReconnect` above reads ONLY `users.github_installation_id`, but for
 * an org-owned / workspace-shared install (the ADR-044 membership case) that
 * column is NULL *by design* — `detect-installation` never writes it, yet sync
 * resumes via the workspace-scoped credential (`resolve_workspace_installation_id`
 * RPC). The pure predicate therefore reports `needsReconnect=true` forever even
 * though syncing works, leaving the orange banner stuck on after a successful
 * reconnect. This resolver reads the SAME sync-capability signal the manual sync
 * path uses (`app/api/kb/sync/route.ts`: `users.github_installation_id ||
 * resolveInstallationId(userId)`) so the banner reflects true capability.
 *
 * Short-circuits before the RPC on the common paths (non-ready status, or a
 * personal install already on the user column) so only the `ready + NULL user
 * column` cohort pays the extra workspace-credential read.
 *
 * Fail toward the alarm: resolveInstallationId converts the expected failure
 * modes (non-member, no install, RPC error, tenant-auth error) to `null`
 * itself (all Sentry-mirrored), and `null` keeps `needsReconnect=true` so the
 * genuine #4706 silent freeze still surfaces the banner. A truly unexpected
 * (non-RuntimeAuthError) throw propagates and fails loud — matching the
 * `kb/sync` precedent rather than being swallowed to `false`. Do NOT add a
 * catch that returns `false`.
 */
export async function resolveNeedsReconnect(
  repoStatus: string | null,
  userInstallationId: number | bigint | null | undefined,
  userId: string,
): Promise<boolean> {
  // Cheap paths first — no RPC round-trip on non-ready or personal-install rows.
  if (repoStatus !== "ready") return false;
  if (userInstallationId != null) return false;

  // ready + NULL user column: only NOW resolve the workspace-scoped credential.
  // Dynamic import mirrors the kb/sync precedent and keeps the server-only
  // Supabase deps out of any eager import graph of this lib module.
  const { resolveInstallationId } = await import(
    "@/server/resolve-installation-id"
  );
  const wsInstall = await resolveInstallationId(userId);
  return wsInstall == null;
}

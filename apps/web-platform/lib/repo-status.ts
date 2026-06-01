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

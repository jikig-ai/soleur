import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";

/**
 * Resolve the GitHub App installation ID for a user's ACTIVE workspace.
 *
 * `workspaceId` MUST be derived from the caller's JWT `current_workspace_id`
 * claim — NEVER from `req.body`/`req.query` (IDOR). When the claim is
 * undefined/null (un-refreshed session after migration 079, or the
 * workspace was deleted → `ON DELETE SET NULL` nulled the claim), we
 * default to the caller's SOLO workspace (`= userId` per ADR-038 N2),
 * never an arbitrary sibling workspace.
 *
 * The credential is read ONLY via the membership-checked
 * `resolve_workspace_installation_id` SECURITY DEFINER RPC (ADR-044). The
 * `workspaces.github_installation_id` column is revoked from the
 * `authenticated` table grant, so a direct tenant SELECT cannot read it.
 * The RPC returns NULL for non-members (its deny path), which surfaces
 * here as `null` — indistinguishable from "no installation connected".
 *
 * The pre-existing `.ilike("repo_url", …)` sibling fallback (LIKE-injection
 * surface) and the unscoped `workspace_members … LIMIT 1` sibling lookup
 * (cross-tenant read) are DELETED — a null/undefined claim must resolve the
 * caller's own solo workspace, never a sibling.
 */
export async function resolveInstallationId(
  userId: string,
  workspaceId?: string | null,
): Promise<number | null> {
  // Undefined/null claim → caller's solo workspace (= userId). Never a sibling.
  const targetWorkspaceId = workspaceId ?? userId;

  try {
    const tenant = await getFreshTenantClient(userId);
    const { data, error } = await tenant.rpc(
      "resolve_workspace_installation_id",
      { p_workspace_id: targetWorkspaceId },
    );

    if (error) {
      reportSilentFallback(error, {
        feature: "resolve-installation-id",
        op: "rpc-read",
        extra: { userId, workspaceId: targetWorkspaceId },
        message: "resolve_workspace_installation_id RPC failed",
      });
      return null;
    }

    return (data as number | null) ?? null;
  } catch (err) {
    if (!(err instanceof RuntimeAuthError)) throw err;
    reportSilentFallback(err, {
      feature: "resolve-installation-id",
      op: "tenant-read",
      extra: { userId, workspaceId: targetWorkspaceId },
    });
    return null;
  }
}

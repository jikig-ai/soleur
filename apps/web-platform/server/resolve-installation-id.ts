import { createServiceClient } from "@/lib/supabase/service";
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";

/**
 * Resolve a GitHub App installation ID for a user. Tries the user's own
 * `github_installation_id` first; falls back to a workspace-sibling lookup
 * via `workspace_members` when the user's row is NULL.
 *
 * The sibling fallback uses a service-role client because the `users`
 * RLS policy restricts SELECT to `auth.uid() = id` — the tenant client
 * can't read sibling user rows directly.
 *
 * The sibling lookup also verifies the resolved installation belongs to a
 * user whose `repo_url` matches the caller's, preventing cross-repo token
 * leakage in a future multi-workspace scenario.
 */
export async function resolveInstallationId(
  userId: string,
): Promise<number | null> {
  let callerRepoUrl: string | null = null;

  try {
    const tenant = await getFreshTenantClient(userId);
    const { data } = await tenant
      .from("users")
      .select("github_installation_id, repo_url")
      .eq("id", userId)
      .single();

    if (data?.github_installation_id) {
      return data.github_installation_id;
    }
    callerRepoUrl = data?.repo_url ?? null;
  } catch (err) {
    if (!(err instanceof RuntimeAuthError)) throw err;
    reportSilentFallback(err, {
      feature: "resolve-installation-id",
      op: "tenant-read",
      extra: { userId },
    });
    return null;
  }

  // Fallback: find a workspace sibling with a non-null installation ID
  // whose repo_url matches the caller's. Service-role bypasses users RLS.
  const service = createServiceClient();

  // Use .limit(1) explicitly — each user belongs to exactly one workspace
  // today, but this is defensive for a future multi-workspace scenario.
  const { data: memberRow } = await service
    .from("workspace_members")
    .select("workspace_id")
    .eq("user_id", userId)
    .limit(1)
    .maybeSingle();

  if (!memberRow?.workspace_id) return null;

  const { data: siblingRows } = await service
    .from("workspace_members")
    .select("user_id")
    .eq("workspace_id", memberRow.workspace_id)
    .neq("user_id", userId);

  if (!siblingRows?.length) return null;

  const siblingIds = siblingRows.map((r) => r.user_id);

  // Resolve from a sibling whose repo_url matches the caller's.
  let query = service
    .from("users")
    .select("github_installation_id")
    .in("id", siblingIds)
    .not("github_installation_id", "is", null)
    .limit(1);

  if (callerRepoUrl) {
    query = query.eq("repo_url", callerRepoUrl);
  }

  const { data: userRow } = await query.maybeSingle();
  return userRow?.github_installation_id ?? null;
}

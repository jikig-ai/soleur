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
 */
export async function resolveInstallationId(
  userId: string,
): Promise<number | null> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const { data } = await tenant
      .from("users")
      .select("github_installation_id")
      .eq("id", userId)
      .single();

    if (data?.github_installation_id) {
      return data.github_installation_id;
    }
  } catch (err) {
    if (!(err instanceof RuntimeAuthError)) throw err;
    reportSilentFallback(err, {
      feature: "resolve-installation-id",
      op: "tenant-read",
      extra: { userId },
    });
    return null;
  }

  // Fallback: find a workspace sibling with a non-null installation ID.
  // Service-role bypasses users RLS to read sibling rows.
  const service = createServiceClient();
  const { data: memberRow } = await service
    .from("workspace_members")
    .select("workspace_id")
    .eq("user_id", userId)
    .maybeSingle();

  if (!memberRow?.workspace_id) return null;

  const { data: siblingRows } = await service
    .from("workspace_members")
    .select("user_id")
    .eq("workspace_id", memberRow.workspace_id)
    .neq("user_id", userId);

  if (!siblingRows?.length) return null;

  const siblingIds = siblingRows.map((r) => r.user_id);
  const { data: userRow } = await service
    .from("users")
    .select("github_installation_id")
    .in("id", siblingIds)
    .not("github_installation_id", "is", null)
    .limit(1)
    .maybeSingle();

  return userRow?.github_installation_id ?? null;
}

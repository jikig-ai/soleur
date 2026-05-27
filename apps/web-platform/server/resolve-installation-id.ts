import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";

export function extractGitHubOwner(repoUrl: string): string | null {
  const match = repoUrl.match(/^https:\/\/github\.com\/([^/]+)\//);
  return match?.[1] ?? null;
}

/**
 * Resolve a GitHub App installation ID for a user. Tries the user's own
 * `github_installation_id` first; falls back to a workspace-sibling lookup
 * via `workspace_members` when the user's row is NULL.
 *
 * The sibling fallback lazy-imports the service-role client to avoid
 * pulling @/lib/supabase/service (which reads SUPABASE_URL at module scope)
 * into test bundles that don't set the env var.
 *
 * The sibling lookup matches on GitHub org (owner) via `.ilike()` rather
 * than exact `repo_url`, since GitHub App installations are org-level and
 * cover all repos under the same owner.
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
  const { createServiceClient } = await import("@/lib/supabase/service");
  const service = createServiceClient();

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

  let query = service
    .from("users")
    .select("github_installation_id")
    .in("id", siblingIds)
    .not("github_installation_id", "is", null)
    .limit(1);

  if (callerRepoUrl) {
    const owner = extractGitHubOwner(callerRepoUrl);
    if (owner) {
      query = query.ilike("repo_url", `https://github.com/${owner}/%`);
    }
  }

  const { data: userRow } = await query.maybeSingle();
  return userRow?.github_installation_id ?? null;
}

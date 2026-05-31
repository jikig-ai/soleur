import type { SupabaseClient } from "@supabase/supabase-js";
import * as Sentry from "@sentry/nextjs";
import {
  findInstallationForLogin,
  listInstallationRepos,
} from "@/server/github-app";

/**
 * Resolve the full set of GitHub App installation IDs a user can reach:
 *  1. their personal install (login-matched), plus
 *  2. every install owned by an org/workspace they are a member of.
 *
 * Pure resolver: receives the service client, never constructs one (keeps it
 * out of the service-role allowlist scope).
 */
export async function resolveReachableInstallationIds(
  serviceClient: SupabaseClient,
  userId: string,
  githubLogin: string | null,
): Promise<number[]> {
  const ids = new Set<number>();

  // 1. Personal install (login-matched)
  if (githubLogin) {
    const personalId = await findInstallationForLogin(githubLogin);
    if (personalId != null) ids.add(personalId);
  }

  // 2. Org/workspace installs via membership
  const { data: memberships, error } = await serviceClient
    .from("workspace_members")
    .select("workspace_id, workspaces(github_installation_id)")
    .eq("user_id", userId);

  if (error) {
    Sentry.captureException(error, {
      tags: { area: "reachable-installations", op: "membership-query" },
    });
    // Degrade: return what we have (personal install only)
    return Array.from(ids);
  }

  for (const m of memberships ?? []) {
    const ws = (
      m as { workspaces?: { github_installation_id?: number | null } }
    ).workspaces;
    const wsId = ws?.github_installation_id;
    if (wsId != null) ids.add(wsId);
  }

  return Array.from(ids);
}

/**
 * Given a specific owner/repo, return the installation ID (from the reachable
 * set) that actually has access to it. Returns null if none do.
 *
 * Used by setup/route.ts to resolve the correct install at connect time when
 * users.github_installation_id is NULL (org-owned repo, no personal install).
 */
export async function resolveOwningInstallationForRepo(
  serviceClient: SupabaseClient,
  userId: string,
  githubLogin: string | null,
  owner: string,
  repo: string,
): Promise<number | null> {
  const reachable = await resolveReachableInstallationIds(
    serviceClient,
    userId,
    githubLogin,
  );
  if (reachable.length === 0) return null;

  const target = `${owner}/${repo}`.toLowerCase();

  for (const installId of reachable) {
    try {
      const repos = await listInstallationRepos(installId);
      const match = repos.some((r) => r.fullName.toLowerCase() === target);
      if (match) return installId;
    } catch (err) {
      Sentry.captureException(err, {
        tags: { area: "reachable-installations", op: "owning-install-probe" },
        extra: { installId, target },
      });
      // Probe failed for this install; try the next.
    }
  }

  return null;
}

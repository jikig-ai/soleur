import { reportSilentFallback } from "@/server/observability";

// Service-role-safe GitHub-App installation-id resolver (#5470, ADR-044 amendment).
//
// Reads `workspaces.github_installation_id` directly via an INJECTED service-role
// client, keyed on an explicit `workspaceId`. This is the distinct service-role
// path required by Inngest/cron contexts: the canonical authenticated reader
// `resolve_workspace_installation_id` (mig 079) gates on
// `is_workspace_member(p_workspace_id, auth.uid())` and is REVOKE'd from
// `service_role`, so it returns NULL whenever `auth.uid()` is NULL (no session).
//
// Why a direct read and not a new RPC: mig 079 §2 and mig 110 revoked the
// `github_installation_id` column SELECT from `authenticated` ONLY — `service_role`
// retains its default table grant, so it reads the credential column today. A new
// SECURITY DEFINER RPC would add a privileged surface to audit for zero capability
// gain. Mirrors the existing injected-service-client precedents
// (`workspace-identity-resolver.ts`, `org-memberships-resolver.ts`) — same shape,
// minus their `auth.getUser()` gate (intentional: this path has no `auth.uid()`).
//
// Membership-bypass justification (trusted server context ONLY): the credential is
// a GitHub App installation-token grant (write access to the user's repos). Callers
// MUST key on a SERVER-DERIVED id (`founderId` / the user's own solo workspace id),
// never a request-supplied workspace id — a request-keyed call would be a
// cross-tenant read. The resolver takes an explicit `workspaceId` and does a single
// `eq("id", …)` read; there is no sibling discovery (CLO forbid: no unscoped
// membership scan, no first-membership MIN(created_at) lookup).
//
// Returns the installation id, or `null` for: not-found row, NULL install (genuine
// "not connected"), or a db error (mirrored to Sentry). Both callers already treat
// `null` as "no install".

interface ServiceClient {
  from: (table: string) => unknown;
}

type MaybeSingleChain<T> = {
  select: (cols: string) => MaybeSingleChain<T>;
  eq: (col: string, val: string) => MaybeSingleChain<T>;
  maybeSingle: () => Promise<{ data: T | null; error: unknown }>;
};

export async function resolveInstallationIdForWorkspace(
  workspaceId: string,
  service: ServiceClient,
): Promise<number | null> {
  const chain = service.from("workspaces") as MaybeSingleChain<{
    github_installation_id: number | null;
  }>;
  const { data, error } = await chain
    .select("github_installation_id")
    .eq("id", workspaceId)
    .maybeSingle();

  if (error) {
    reportSilentFallback(error, {
      feature: "resolve-installation-id-for-workspace",
      op: "workspaces-read",
      extra: { workspaceId },
      message: "workspaces.github_installation_id service-role read failed",
    });
    return null;
  }

  return data?.github_installation_id ?? null;
}

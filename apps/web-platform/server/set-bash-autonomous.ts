import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

/**
 * Set the `bash_autonomous` toggle for a user's ACTIVE workspace
 * (Issue B part 2). Write goes ONLY through the OWNER-only
 * `set_workspace_bash_autonomous` SECURITY DEFINER RPC, which RAISES for a
 * non-owner / unauthenticated caller (enabling an approval-bypass is an
 * ownership-grade decision).
 *
 * On any error (owner-deny raise, RPC fault) the failure is mirrored to
 * Sentry and re-thrown so the caller (settings API route) surfaces it as a
 * 4xx/5xx — unlike the READ path, a write must NOT silently swallow failure.
 * Returns the persisted boolean on success.
 */
export async function setBashAutonomous(
  userId: string,
  value: boolean,
  workspaceId?: string | null,
): Promise<boolean> {
  const tenant = await getFreshTenantClient(userId);
  const targetWorkspaceId =
    workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));
  const { data, error } = await tenant.rpc("set_workspace_bash_autonomous", {
    p_workspace_id: targetWorkspaceId,
    p_value: value,
  });

  if (error) {
    reportSilentFallback(error, {
      feature: "set-bash-autonomous",
      op: "rpc-write",
      extra: { userId, workspaceId: targetWorkspaceId, value },
      message: "set_workspace_bash_autonomous RPC failed (owner-deny or fault)",
    });
    throw new Error("Failed to set bash_autonomous");
  }

  return (data as boolean | null) ?? value;
}

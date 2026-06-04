import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

/**
 * Resolve whether `userId` OWNS their ACTIVE workspace
 * (feat-bash-autonomous-default-on). Used by the first-run consent soft-gate to
 * decide whether to surface the disclosure ack (owner) or fall through to the
 * review-gate (non-owner — no ack button they can't grant).
 *
 * Reads the caller's OWN membership row via the cookie/tenant RLS client
 * (workspace_members has a members_select_peers policy, so the caller can read
 * its own row without service-role). Mirrors the Privacy/Scope-Grants page
 * pattern.
 *
 * FAIL-CLOSED to `false`: any error / null / RuntimeAuthError resolves `false`
 * — the SAFE direction, since a non-owner is held by the review-gate rather
 * than auto-bypassed. Mirrored to Sentry so a persistent read fault is visible.
 */
export async function resolveIsWorkspaceOwner(
  userId: string,
  workspaceId?: string | null,
): Promise<boolean> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const targetWorkspaceId =
      workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));
    const { data, error } = await tenant
      .from("workspace_members")
      .select("role")
      .eq("workspace_id", targetWorkspaceId)
      .eq("user_id", userId)
      .maybeSingle();

    if (error) {
      reportSilentFallback(error, {
        feature: "resolve-workspace-owner",
        op: "membership-read",
        extra: { userId, workspaceId: targetWorkspaceId },
        message: "workspace_members role read failed; fail-closed not-owner",
      });
      return false;
    }

    return (data as { role?: string } | null)?.role === "owner";
  } catch (err) {
    if (!(err instanceof RuntimeAuthError)) throw err;
    reportSilentFallback(err, {
      feature: "resolve-workspace-owner",
      op: "tenant-read",
      extra: { userId, workspaceId: workspaceId ?? null },
    });
    return false;
  }
}

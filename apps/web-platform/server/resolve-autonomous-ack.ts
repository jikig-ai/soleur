import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

/**
 * Resolve the autonomous-mode first-run consent ack timestamp for a user's
 * ACTIVE workspace (feat-bash-autonomous-default-on). Mirrors
 * `resolveBashAutonomous` (ADR-044): the active workspace is server-derived
 * from `user_session_state.current_workspace_id` (never request input — no
 * IDOR); an explicit `workspaceId` overrides.
 *
 * Read goes ONLY through the membership-checked
 * `get_workspace_autonomous_ack` SECURITY DEFINER RPC, which returns NULL for
 * non-members / unauthenticated / not-yet-acked.
 *
 * FAIL-CLOSED to `null`: any error, RPC-null, or RuntimeAuthError resolves
 * `null`. **This is the OPPOSITE boolean direction from
 * `resolve-bash-autonomous.ts`'s `?? false`.** Here, `null` means "not acked"
 * which the soft-gate callsite treats as HOLD the first auto-run — the safe
 * direction. A read failure must NEVER silently mark the workspace acked (that
 * would let the first auto-run proceed without the owner ever seeing the
 * disclosure). The failure is mirrored to Sentry so a persistent read fault is
 * visible even though the command is safely held.
 */
export async function resolveAutonomousAck(
  userId: string,
  workspaceId?: string | null,
): Promise<string | null> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const targetWorkspaceId =
      workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));
    const { data, error } = await tenant.rpc("get_workspace_autonomous_ack", {
      p_workspace_id: targetWorkspaceId,
    });

    if (error) {
      reportSilentFallback(error, {
        feature: "resolve-autonomous-ack",
        op: "rpc-read",
        extra: { userId, workspaceId: targetWorkspaceId },
        message:
          "get_workspace_autonomous_ack RPC failed; fail-closed null (HOLD)",
      });
      return null;
    }

    return (data as string | null) ?? null;
  } catch (err) {
    if (!(err instanceof RuntimeAuthError)) throw err;
    reportSilentFallback(err, {
      feature: "resolve-autonomous-ack",
      op: "tenant-read",
      extra: { userId, workspaceId: workspaceId ?? null },
    });
    return null;
  }
}

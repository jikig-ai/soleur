import {
  getFreshTenantClient,
  mapRuntimeAuthCauseToErrorCode,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import {
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

/**
 * Resolve the `web_egress` ("Agent web access") grant for a user's ACTIVE
 * workspace (feat-open-web-egress, #9534). Mirrors `resolveDebugMode` (101)
 * and `resolveBashAutonomous` (097 / ADR-044): the active workspace is
 * server-derived from `user_session_state.current_workspace_id` (never from
 * request input — no IDOR); an explicit `workspaceId` overrides.
 *
 * Read goes ONLY through the membership-checked `get_workspace_web_egress`
 * SECURITY DEFINER RPC, which returns NULL for non-members / unauthenticated.
 *
 * FAIL-CLOSED: any error, RPC-null, or RuntimeAuthError resolves `false`.
 * A settings-read failure must NEVER silently ENABLE open-web egress — the
 * inverse of the intended security posture (default-deny is the standing
 * invariant). The failure is mirrored to Sentry so a persistent read fault
 * is visible even though the session proceeds with egress OFF.
 */
export async function resolveWebEgress(
  userId: string,
  workspaceId?: string | null,
): Promise<boolean> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const targetWorkspaceId =
      workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));
    const { data, error } = await tenant.rpc("get_workspace_web_egress", {
      p_workspace_id: targetWorkspaceId,
    });

    if (error) {
      reportSilentFallback(error, {
        feature: "resolve-web-egress",
        op: "rpc-read",
        extra: { userId, workspaceId: targetWorkspaceId },
        message: "get_workspace_web_egress RPC failed; fail-closed false",
      });
      return false;
    }

    return (data as boolean | null) ?? false;
  } catch (err) {
    if (!(err instanceof RuntimeAuthError)) throw err;
    // Per-cause severity split mirrors resolveDebugMode: a transient
    // founder-JWT mint blip (`jwt_mint`) is fully recovered here (fail-closed
    // to safe `false`, egress stays OFF), so it lands at WARNING and does not
    // pollute the error budget. Genuinely actionable causes — `denied_jti`
    // (session revoked) and `rotation` (mint rate-ceiling exhausted) — stay
    // at ERROR. The `code` tag is queryable in Sentry across both severities.
    const code = mapRuntimeAuthCauseToErrorCode(err.cause);
    const emit =
      err.cause === "jwt_mint" ? warnSilentFallback : reportSilentFallback;
    emit(err, {
      feature: "resolve-web-egress",
      op: "tenant-read",
      extra: { userId, workspaceId: workspaceId ?? null, code },
      message: `founder tenant auth unavailable (${code}); fail-closed false (web egress OFF)`,
    });
    return false;
  }
}

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
 * Resolve the `debug_mode` toggle for a user's ACTIVE workspace
 * (feat-debug-mode-stream). Mirrors `resolveBashAutonomous` (097 / ADR-044):
 * the active workspace is server-derived from
 * `user_session_state.current_workspace_id` (never from request input — no
 * IDOR); an explicit `workspaceId` overrides.
 *
 * Read goes ONLY through the membership-checked `get_workspace_debug_mode`
 * SECURITY DEFINER RPC, which returns NULL for non-members / unauthenticated.
 *
 * FAIL-CLOSED: any error, RPC-null, or RuntimeAuthError resolves `false`. A
 * settings-read failure must NEVER silently ENABLE the harness-instruction
 * stream — the inverse of the intended safety posture. The failure is
 * mirrored to Sentry so a persistent read fault is visible even though the
 * conversation proceeds with the (safe) stream OFF.
 */
export async function resolveDebugMode(
  userId: string,
  workspaceId?: string | null,
): Promise<boolean> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const targetWorkspaceId =
      workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));
    const { data, error } = await tenant.rpc("get_workspace_debug_mode", {
      p_workspace_id: targetWorkspaceId,
    });

    if (error) {
      reportSilentFallback(error, {
        feature: "resolve-debug-mode",
        op: "rpc-read",
        extra: { userId, workspaceId: targetWorkspaceId },
        message: "get_workspace_debug_mode RPC failed; fail-closed false",
      });
      return false;
    }

    return (data as boolean | null) ?? false;
  } catch (err) {
    if (!(err instanceof RuntimeAuthError)) throw err;
    // Per-cause severity split mirrors resolveBashAutonomous: a transient
    // founder-JWT mint blip (`jwt_mint`) is fully recovered here (fail-closed
    // to safe `false`, stream stays OFF), so it lands at WARNING and does not
    // pollute the error budget. Genuinely actionable causes — `denied_jti`
    // (session revoked) and `rotation` (mint rate-ceiling exhausted) — stay at
    // ERROR. The `code` tag is queryable in Sentry across both severities.
    const code = mapRuntimeAuthCauseToErrorCode(err.cause);
    const emit =
      err.cause === "jwt_mint" ? warnSilentFallback : reportSilentFallback;
    emit(err, {
      feature: "resolve-debug-mode",
      op: "tenant-read",
      extra: { userId, workspaceId: workspaceId ?? null, code },
      message: `founder tenant auth unavailable (${code}); fail-closed false (debug stream OFF)`,
    });
    return false;
  }
}

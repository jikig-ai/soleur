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
 * Resolve the `bash_autonomous` toggle for a user's ACTIVE workspace
 * (Issue B part 2). Mirrors `resolveInstallationId` (ADR-044): the active
 * workspace is server-derived from `user_session_state.current_workspace_id`
 * (never from request input — no IDOR); an explicit `workspaceId` overrides.
 *
 * Read goes ONLY through the membership-checked
 * `get_workspace_bash_autonomous` SECURITY DEFINER RPC, which returns NULL
 * for non-members / unauthenticated.
 *
 * FAIL-CLOSED: any error, RPC-null, or RuntimeAuthError resolves `false`. A
 * settings-read failure must NEVER silently ENABLE the approval-bypass — the
 * inverse of the intended safety posture. The failure is mirrored to Sentry
 * so a persistent read fault is visible even though the conversation proceeds
 * with the (safe) review-gate intact.
 */
export async function resolveBashAutonomous(
  userId: string,
  workspaceId?: string | null,
): Promise<boolean> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const targetWorkspaceId =
      workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));
    const { data, error } = await tenant.rpc("get_workspace_bash_autonomous", {
      p_workspace_id: targetWorkspaceId,
    });

    if (error) {
      reportSilentFallback(error, {
        feature: "resolve-bash-autonomous",
        op: "rpc-read",
        extra: { userId, workspaceId: targetWorkspaceId },
        message: "get_workspace_bash_autonomous RPC failed; fail-closed false",
      });
      return false;
    }

    return (data as boolean | null) ?? false;
  } catch (err) {
    if (!(err instanceof RuntimeAuthError)) throw err;
    // Per-cause severity split: a transient founder-JWT mint blip
    // (`jwt_mint` — GoTrue 429, RPC hiccup, missing secret) is fully
    // recovered here (fail-closed to safe `false`, approval gate stays ON),
    // so it lands at WARNING and does not pollute the error budget. Genuinely
    // actionable causes — `denied_jti` (session revoked) and `rotation`
    // (mint rate-ceiling exhausted) — stay at ERROR so on-call keeps the
    // signal. The `code` tag is queryable in Sentry across both severities.
    const code = mapRuntimeAuthCauseToErrorCode(err.cause);
    const emit =
      err.cause === "jwt_mint" ? warnSilentFallback : reportSilentFallback;
    emit(err, {
      feature: "resolve-bash-autonomous",
      op: "tenant-read",
      extra: { userId, workspaceId: workspaceId ?? null, code },
      message:
        "founder JWT mint transiently unavailable; fail-closed false (approval gate ON)",
    });
    return false;
  }
}

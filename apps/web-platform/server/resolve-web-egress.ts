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
/** The same read WITHOUT the fail-closed swallow: RPC faults and auth
 *  faults propagate to the caller. Callers that may legitimately lose the
 *  session's live forwarder (the cc-dispatcher warm-path revocation) need
 *  to distinguish "the grant is off" from "the read failed" — the wrapper
 *  below is for grant-decision sites (spawn-time), this one for
 *  revocation sites where a blip must NOT kill a live grant. */
async function readWebEgressGrant(
  userId: string,
  workspaceId?: string | null,
): Promise<boolean> {
  const tenant = await getFreshTenantClient(userId);
  const targetWorkspaceId =
    workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));
  const { data, error } = await tenant.rpc("get_workspace_web_egress", {
    p_workspace_id: targetWorkspaceId,
  });
  if (error) throw error;
  return (data as boolean | null) ?? false;
}

/** Strict variant for revocation call sites: rethrows RPC and auth faults so
 *  a Supabase blip cannot masquerade as a definitive off-grant and tear down
 *  a legitimately-entitled session's forwarder (review P1). */
export async function resolveWebEgressStrict(
  userId: string,
  workspaceId?: string | null,
): Promise<boolean> {
  return readWebEgressGrant(userId, workspaceId);
}

export async function resolveWebEgress(
  userId: string,
  workspaceId?: string | null,
): Promise<boolean> {
  try {
    return await readWebEgressGrant(userId, workspaceId);
  } catch (err) {
    if (!(err instanceof RuntimeAuthError)) {
      // RPC / generic read fault — same fail-closed false as before, mirrored.
      reportSilentFallback(err, {
        feature: "resolve-web-egress",
        op: "rpc-read",
        extra: { userId, workspaceId: workspaceId ?? null },
        message: "get_workspace_web_egress read failed; fail-closed false",
      });
      return false;
    }
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

import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

/**
 * Thrown when the owner-only `set_workspace_debug_mode` RPC rejects a
 * non-owner caller (Postgres `RAISE EXCEPTION`, SQLSTATE P0001). Lets the API
 * route map an authorization denial to 403 while a genuine infrastructure
 * fault (connection error, timeout) maps to 500 — a fault must not be
 * mislabeled "not authorized" and slip past 5xx alerting.
 */
export class DebugModeOwnerDeniedError extends Error {
  constructor(message = "not authorized to set debug_mode") {
    super(message);
    this.name = "DebugModeOwnerDeniedError";
  }
}

/**
 * Set the `debug_mode` toggle for a user's ACTIVE workspace
 * (feat-debug-mode-stream). Write goes ONLY through the OWNER-only
 * `set_workspace_debug_mode` SECURITY DEFINER RPC, which RAISES for a
 * non-owner / unauthenticated caller (enabling the harness instruction stream
 * is an ownership-grade decision).
 *
 * On any error (owner-deny raise, RPC fault) the failure is mirrored to
 * Sentry and re-thrown so the caller (settings API route) surfaces it as a
 * 4xx/5xx — unlike the READ path, a write must NOT silently swallow failure.
 * Returns the persisted boolean on success.
 */
export async function setDebugMode(
  userId: string,
  value: boolean,
  workspaceId?: string | null,
): Promise<boolean> {
  const tenant = await getFreshTenantClient(userId);
  const targetWorkspaceId =
    workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));
  const { data, error } = await tenant.rpc("set_workspace_debug_mode", {
    p_workspace_id: targetWorkspaceId,
    p_value: value,
  });

  if (error) {
    // P0001 is the SQLSTATE for the RPC's owner-check `RAISE EXCEPTION` — an
    // authorization denial (→ 403), distinct from an infra fault (→ 500).
    const ownerDenied = (error as { code?: string }).code === "P0001";
    reportSilentFallback(error, {
      feature: "set-debug-mode",
      op: "rpc-write",
      extra: { userId, workspaceId: targetWorkspaceId, value, ownerDenied },
      message: "set_workspace_debug_mode RPC failed (owner-deny or fault)",
    });
    if (ownerDenied) {
      throw new DebugModeOwnerDeniedError();
    }
    throw new Error("Failed to set debug_mode");
  }

  return (data as boolean | null) ?? value;
}

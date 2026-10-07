import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import { emitWorkspaceActionContext } from "@/server/workspace-action-audit";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

/**
 * Thrown when the owner-only `set_workspace_web_egress` RPC rejects a
 * non-owner caller (Postgres `RAISE EXCEPTION`, SQLSTATE P0001). Lets the
 * API route map an authorization denial to 403 while a genuine
 * infrastructure fault (connection error, timeout) maps to 500 — a fault
 * must not be mislabeled "not authorized" and slip past 5xx alerting.
 */
export class WebEgressOwnerDeniedError extends Error {
  constructor(message = "not authorized to set web_egress") {
    super(message);
    this.name = "WebEgressOwnerDeniedError";
  }
}

/**
 * Set the `web_egress` ("Agent web access") grant for a user's ACTIVE
 * workspace (feat-open-web-egress, #9534). Write goes ONLY through the
 * OWNER-only `set_workspace_web_egress` SECURITY DEFINER RPC, which RAISES
 * for a non-owner / unauthenticated caller (granting open-web egress to all
 * workspace agent sessions is an ownership-grade decision).
 *
 * On any error (owner-deny raise, RPC fault) the failure is mirrored to
 * Sentry and re-thrown so the caller (settings API route) surfaces it as a
 * 4xx/5xx — unlike the READ path, a write must NOT silently swallow failure.
 * Returns the persisted boolean on success.
 */
export async function setWebEgress(
  userId: string,
  value: boolean,
  workspaceId?: string | null,
): Promise<boolean> {
  const tenant = await getFreshTenantClient(userId);
  const targetWorkspaceId =
    workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));
  const { data, error } = await tenant.rpc("set_workspace_web_egress", {
    p_workspace_id: targetWorkspaceId,
    p_value: value,
  });

  if (error) {
    // P0001 is the SQLSTATE for the RPC's owner-check `RAISE EXCEPTION` — an
    // authorization denial (→ 403), distinct from an infra fault (→ 500).
    const ownerDenied = (error as { code?: string }).code === "P0001";
    reportSilentFallback(error, {
      feature: "set-web-egress",
      op: "rpc-write",
      extra: { userId, workspaceId: targetWorkspaceId, value, ownerDenied },
      message: "set_workspace_web_egress RPC failed (owner-deny or fault)",
    });
    if (ownerDenied) {
      throw new WebEgressOwnerDeniedError();
    }
    throw new Error("Failed to set web_egress");
  }

  // AC11-class audit (plan §persistence): record the workspace this flip
  // landed in at commit time — the "scope-grant" action family. The grant
  // is keyed to the ACTIVE workspace (server-resolved above), so the
  // audited tenant is targetWorkspaceId, NOT userId (contrast with the
  // scope-grants grant route, whose grant is solo-workspace-scoped).
  emitWorkspaceActionContext({
    action: value ? "web-egress-grant" : "web-egress-revoke",
    userId,
    workspaceId: targetWorkspaceId,
  });

  return (data as boolean | null) ?? value;
}

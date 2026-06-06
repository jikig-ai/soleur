import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

/**
 * Thrown when an owner-only ack RPC rejects a non-owner caller (Postgres
 * `RAISE EXCEPTION`, SQLSTATE P0001). Lets the route map an authorization
 * denial to 403 while a genuine infra fault maps to 500 — a fault must not be
 * mislabeled "not authorized" and slip past 5xx alerting. Mirrors
 * `BashAutonomousOwnerDeniedError`.
 */
export class AutonomousAckOwnerDeniedError extends Error {
  constructor(message = "not authorized to ack autonomous disclosure") {
    super(message);
    this.name = "AutonomousAckOwnerDeniedError";
  }
}

/**
 * Write the autonomous-mode first-run consent ack for a user's ACTIVE
 * workspace (feat-bash-autonomous-default-on). Mirrors `setBashAutonomous`.
 *
 * The ack write goes through the OWNER-only `set_workspace_autonomous_ack`
 * SECURITY DEFINER RPC (idempotent COALESCE), which RAISES for a non-owner.
 *
 * `keepAutonomous` semantics (existing-workspace opt-out prompt):
 *   - `true`  → "Keep autonomous on": flip the toggle via the EXISTING
 *               owner-checked `set_workspace_bash_autonomous(.., true)` RPC
 *               (097, untouched) BEFORE writing the ack. Two owner-checked
 *               calls — the ack migration never writes the toggle column.
 *   - `false`/undefined → "Ask me each time" / soft-gate "Got it": ack only,
 *               leave `bash_autonomous` as-is.
 *
 * On any error the failure is mirrored to Sentry and re-thrown so the caller
 * surfaces a 4xx/5xx — a write must NOT silently swallow failure. Returns the
 * persisted ack timestamp on success.
 */
export async function setAutonomousAck(
  userId: string,
  opts: { keepAutonomous?: boolean; workspaceId?: string | null } = {},
): Promise<string | null> {
  const tenant = await getFreshTenantClient(userId);
  const targetWorkspaceId =
    opts.workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));

  // "Keep autonomous on" — flip the toggle FIRST via the existing owner-checked
  // RPC. Ordered before the ack so an owner-deny on the toggle aborts the whole
  // flow (no ack written for a flip that failed authz).
  if (opts.keepAutonomous === true) {
    const { error: flipError } = await tenant.rpc(
      "set_workspace_bash_autonomous",
      { p_workspace_id: targetWorkspaceId, p_value: true },
    );
    if (flipError) {
      const ownerDenied = (flipError as { code?: string }).code === "P0001";
      reportSilentFallback(flipError, {
        feature: "set-autonomous-ack",
        op: "rpc-keep-autonomous",
        extra: { userId, workspaceId: targetWorkspaceId, ownerDenied },
        message: "set_workspace_bash_autonomous (keep-on) RPC failed",
      });
      if (ownerDenied) throw new AutonomousAckOwnerDeniedError();
      throw new Error("Failed to keep autonomous mode on");
    }
  }

  const { data, error } = await tenant.rpc("set_workspace_autonomous_ack", {
    p_workspace_id: targetWorkspaceId,
  });

  if (error) {
    const ownerDenied = (error as { code?: string }).code === "P0001";
    reportSilentFallback(error, {
      feature: "set-autonomous-ack",
      op: "rpc-write",
      extra: { userId, workspaceId: targetWorkspaceId, ownerDenied },
      message: "set_workspace_autonomous_ack RPC failed (owner-deny or fault)",
    });
    if (ownerDenied) throw new AutonomousAckOwnerDeniedError();
    throw new Error("Failed to set autonomous disclosure ack");
  }

  return (data as string | null) ?? null;
}

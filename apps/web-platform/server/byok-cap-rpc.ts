/**
 * TS wrapper around the 6-arg `record_byok_use_and_check_cap` SQL RPC at
 * `apps/web-platform/supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:81-148`.
 *
 * Layer 1 of the three-layer cap enforcement model per ADR-041. Called at
 * the top of each per-turn `step.run` in the Anthropic-SDK leader loop
 * (PR-B #4379) — BEFORE `anthropic.messages.create`. If `killTripped` is
 * true, the loop short-circuits with `failure_reason = "byok_cap_exceeded"`
 * and the Anthropic call is NEVER issued.
 *
 * Fail-closed semantics (ADR-041 Decision Layer 1):
 *   - Any RPC error THROWS rather than returning `killTripped: false`.
 *     A transient DB error must NOT allow an uncapped Anthropic call.
 *   - Empty/null response also throws (defensive — server returned no row).
 *
 * N2 invariant (per `cost-writer.ts:65-69` and PA-21 §TOMs):
 *   `workspaceId === founderId` for solo-canary workspaces. Pre-flight
 *   assertion raises BEFORE issuing the RPC so the network round-trip is
 *   never wasted on an invalid arg shape.
 *
 * Service-role: this wrapper uses `getServiceClient()` (RLS-bypassing). The
 * service-role allowlist (`apps/web-platform/.service-role-allowlist`)
 * pins this path; CI rejects any other importer.
 */

import { getServiceClient } from "@/lib/supabase/service";

export interface RecordByokUseAndCheckCapArgs {
  invocationId: string;
  founderId: string;
  /**
   * Workspace UUID for cost attribution. Per N2 invariant: must equal
   * founderId for solo-canary workspaces (the only shape PR-B ships).
   * Future non-solo callers should resolve via
   * `workspace-resolver.getDefaultWorkspaceForUser`.
   */
  workspaceId: string;
  agentRole: "agent.spawn.requested";
  /**
   * Token count for THIS call. Pre-call cap-check passes 0 (no tokens
   * incurred yet) — the RPC reads cumulative spend from `audit_byok_use`
   * rows. Post-call cost recording happens separately via
   * `persistTurnCost`.
   */
  tokenCount: number;
  /** Same: pre-call cap-check passes 0. */
  unitCostCents: number;
}

export interface RecordByokUseAndCheckCapResult {
  cumulativeCents: number;
  killTripped: boolean;
}

export async function recordByokUseAndCheckCap(
  args: RecordByokUseAndCheckCapArgs,
): Promise<RecordByokUseAndCheckCapResult> {
  // N2 invariant — fail-fast BEFORE the network round-trip.
  if (args.workspaceId !== args.founderId) {
    throw new Error(
      `byok-cap-rpc: N2 invariant violated — workspaceId must equal founderId for solo workspaces. ` +
        `Got founderId=${args.founderId}, workspaceId=${args.workspaceId}.`,
    );
  }

  const supabase = getServiceClient();
  const { data, error } = await supabase.rpc("record_byok_use_and_check_cap", {
    p_invocation_id: args.invocationId,
    p_founder_id: args.founderId,
    p_workspace_id: args.workspaceId,
    p_agent_role: args.agentRole,
    p_token_count: args.tokenCount,
    p_unit_cost_cents: args.unitCostCents,
  });

  if (error) {
    // Fail-closed: a transient DB error must NOT let the caller issue
    // the next Anthropic call uncapped.
    throw new Error(
      `byok cap rpc: record_byok_use_and_check_cap failed — ${error.message ?? String(error)}`,
    );
  }

  if (data === null || data === undefined) {
    throw new Error(
      "byok cap rpc: record_byok_use_and_check_cap returned empty response",
    );
  }

  // The RPC returns a single row; supabase-js may unwrap or wrap in array
  // depending on the function shape. Normalise.
  const row = Array.isArray(data) ? data[0] : (data as Record<string, unknown>);
  if (!row) {
    throw new Error(
      "byok cap rpc: record_byok_use_and_check_cap returned empty response",
    );
  }

  const cumulativeCents = Number(
    (row as Record<string, unknown>).cumulative_cents ?? NaN,
  );
  const killTripped = Boolean(
    (row as Record<string, unknown>).kill_tripped ?? false,
  );

  if (!Number.isFinite(cumulativeCents)) {
    throw new Error(
      `byok cap rpc: malformed cumulative_cents in RPC result — got ${JSON.stringify(
        row,
      )}`,
    );
  }

  return { cumulativeCents, killTripped };
}

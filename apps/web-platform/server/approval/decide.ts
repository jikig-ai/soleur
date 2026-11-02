/**
 * The Owner's decision on an approval request (#4672).
 *
 * This is the ONLY module that calls `decide_approval`, and it takes whichever client the CALLER holds. The HTTP
 * route passes the user's JWT client; the WebSocket handler passes the tenant client minted for the socket's
 * verified `userId`. The actor is `auth.uid()` inside the RPC (migration 180): there is no actor parameter, so a
 * forged payload cannot name a different user. Never hand this a service-role client (auth.uid() is NULL there and
 * the RPC refuses; the grant is `authenticated` only).
 *
 * Boundary (sentinel test, test/approval/decide-boundary.test.ts): no module reachable from the MCP tool builders or the `canUseTool` deps may
 * import this file. The agent shares the process, so that is the only thing keeping it from deciding its own
 * requests.
 */

import { ApprovalServiceError, parseApprovalRow, type ApprovalRow, type ApprovalRpcClient } from "./service";

export const APPROVAL_DECISIONS = ["approve", "deny"] as const;
export type ApprovalDecision = (typeof APPROVAL_DECISIONS)[number];

/**
 * - decided: this call recorded the decision.
 * - unchanged: the SAME decider repeated the SAME decision (idempotent repeat).
 * - already_decided: a DIFFERENT Owner repeated the decision that is already recorded; `approval` is the current row.
 * - conflict: the OPPOSITE decision was already recorded, or the request was already used (consumed); `approval` is
 *   the current row (the loser of a two-Owner race; UI: "already used" for a consumed row).
 * - revoked: an Owner denied an APPROVED, unconsumed request (`approved -> rejected`); the frame status is `rejected`.
 * - expired: the request was overdue (pending or approved); flipped to expired, nothing was recorded as approved.
 * - closed: the conversation is archived or gone (pending requests only); nothing recorded.
 */
export const DECIDE_OUTCOMES = ["decided", "unchanged", "already_decided", "conflict", "revoked", "expired", "closed"] as const;
export type DecideOutcome = (typeof DECIDE_OUTCOMES)[number];

export interface DecideResult {
  outcome: DecideOutcome;
  approval: ApprovalRow;
}

export async function decideApproval(
  client: ApprovalRpcClient,
  p: { id: string; decision: ApprovalDecision },
): Promise<DecideResult> {
  // Validate before the database: "Approve all", free text and case variants cannot be expressed.
  if (!(APPROVAL_DECISIONS as readonly string[]).includes(p.decision)) {
    throw new ApprovalServiceError("decide_approval", "bad_decision");
  }
  const { data, error } = await client.rpc("decide_approval", { p_id: p.id, p_decision: p.decision });
  if (error) throw new ApprovalServiceError("decide_approval", error.code);
  const d = data as { outcome?: unknown; approval?: unknown } | null;
  if (!d || typeof d.outcome !== "string" || !(DECIDE_OUTCOMES as readonly string[]).includes(d.outcome)) {
    throw new ApprovalServiceError("decide_approval", "bad_payload");
  }
  return { outcome: d.outcome as DecideOutcome, approval: parseApprovalRow("decide_approval", d.approval) };
}

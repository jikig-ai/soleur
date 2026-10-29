import { getRuntimeFlag } from "@/lib/feature-flags/server";

/**
 * The `approval-queue` flag read (#4672, ADR-307).
 *
 * Everything that would create, show or emit an approval request reads the flag through THIS function and nothing
 * else. It is evaluated once per gate (never per poll), per workspace identity so a cohort can be targeted by a
 * per-workspace segment override, and any error, timeout or absent feature means OFF (fail closed: an unreadable flag
 * must never turn the approval path ON). getRuntimeFlag already falls back to the `FLAG_APPROVAL_QUEUE=0` env mirror on
 * a Flagsmith outage. This module never creates or flips the flag; that is the operator's flag-create hand-over.
 */

export interface ApprovalFlagIdentity {
  userId: string;
  /** Null when the caller has not resolved the workspace; the flag is then evaluated without a workspace segment. */
  workspaceId: string | null;
}

export async function isApprovalQueueEnabled(identity: ApprovalFlagIdentity): Promise<boolean> {
  try {
    return await getRuntimeFlag("approval-queue", {
      userId: identity.userId,
      role: "prd",
      orgId: identity.workspaceId,
      email: null,
      subscriptionStatus: null,
    });
  } catch {
    return false;
  }
}

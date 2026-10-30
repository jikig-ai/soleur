import { getRuntimeFlag } from "@/lib/feature-flags/server";
import { reportApprovalOp } from "./ops";

/**
 * The `approval-queue` flag read (#4672, ADR-309).
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

/** A persistent flag-service outage is re-reported at most this often, so it can neither flood Sentry nor stay silent after one event. */
export const FLAG_READ_FAILURE_REPORT_TTL_MS = 10 * 60 * 1000;

let lastReadFailureReportedAt: number | null = null;

/** Test seam: forget that a read failure was already reported in this process. */
export function resetFlagReadFailureReport(): void {
  lastReadFailureReportedAt = null;
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
  } catch (err) {
    // Fail closed AND visible: a silently-off flag would look like a healthy dormant feature. Debounced (one report per
    // TTL window per process), so a flag-service outage cannot flood Sentry (the gate reads the flag on every gated
    // call) and a long outage still re-surfaces instead of latching silent after the first event.
    const now = Date.now();
    if (lastReadFailureReportedAt === null || now - lastReadFailureReportedAt >= FLAG_READ_FAILURE_REPORT_TTL_MS) {
      lastReadFailureReportedAt = now;
      reportApprovalOp("flagReadFailed", err);
    }
    return false;
  }
}

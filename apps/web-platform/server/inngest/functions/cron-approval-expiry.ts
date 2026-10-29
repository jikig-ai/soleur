// cron-approval-expiry — the 5-minute sweep of durable approval requests (#4672, ADR-307 provisional).
//
// WHY THIS SHAPE: an approval request outlives the agent session that made it (the Owner may answer hours later), so
// something must age rows out without a session. One `sweep_approvals()` RPC does all three database jobs in one
// transaction, each a conditional UPDATE guarded by a write-once marker, so a double fire or a retry finds nothing the
// second time (idempotent, which is why this cron needs no exactly-once handling at the cutover):
//   (1) expire due rows (an `approved` row past expiry becomes `expired` with decided_at kept = "unconsumed"),
//   (2) flag `pending` rows older than 15 minutes once (`unanswered_flagged_at`),
//   (3) null `canonical_action` 30 days after the terminal state (the retention scrub).
// The RPC returns the rows to tell people about; this function does only that, in a SECOND step so a notification
// failure can never re-run (or roll back) the sweep: Inngest memoizes the sweep step's result across retries.
//
// FLAG-INDEPENDENT BY DESIGN: the `approval-queue` flag gates row CREATION only. This cron stays live while the flag is
// off, so turning the flag off never strands a pending request, and it emits SOLEUR_APPROVAL_SWEEP every run so the
// Better Stack probe is valid on a dark deploy. With the flag never on there are no rows and the run is three empty
// reads: no push, no Sentry op, no card.
//
// Notifications are GENERIC (lib/approval-copy.ts; nothing from the action reaches a lock screen, #8532): the owner's
// inbox item was already moved to FYI by the RPC; an `unanswered` expiry also sends the generic "expired" push, an
// `unconsumed` expiry (approved, agent never asked again) is inbox-only.
//
// ADR-033 invariants: all IO inside step.run (I1); no claude / BYOK (I2); no subprocess (I3); deterministic step.run
// returns (I5); emits no Inngest events (I6). The Sentry heartbeat owns SENTRY_MONITOR_SLUG.

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { logApprovalMarker, reportApprovalOp } from "@/server/approval/ops";
import { notifyApprovalExpired } from "@/server/approval/notify";
import { sweepApprovals, type ApprovalRpcClient, type SweepResult } from "@/server/approval/service";
import { postSentryHeartbeat, type HandlerArgs } from "./_cron-shared";

export const SENTRY_MONITOR_SLUG = "scheduled-approval-expiry";

const CRON_NAME = "cron-approval-expiry";

export interface ApprovalExpiryResult {
  ok: boolean;
  expired: number;
  flagged: number;
  scrubbed: number;
  notifyFailed: number;
}

export async function cronApprovalExpiryHandler({ step, logger }: HandlerArgs): Promise<ApprovalExpiryResult> {
  // Step 1: the one RPC. A failure is ONE Sentry op, a red heartbeat, and the next tick (5 minutes) retries; the RPC
  // is idempotent, so there is nothing to compensate.
  const swept = await step.run("approval-sweep", async (): Promise<{ ok: true; result: SweepResult } | { ok: false }> => {
    try {
      const { createServiceClient } = await import("@/lib/supabase/service");
      const result = await sweepApprovals(createServiceClient() as unknown as ApprovalRpcClient);
      return { ok: true, result };
    } catch (err) {
      reportApprovalOp("sweepFailed", err, { extra: { fn: CRON_NAME } });
      return { ok: false };
    }
  });

  let notifyFailed = 0;
  let expired = 0;
  let flagged = 0;
  let scrubbed = 0;

  if (swept.ok) {
    const { result } = swept;
    expired = result.expired.length;
    flagged = result.flagged.length;
    scrubbed = result.scrubbed;

    // Step 2: tell people. Never throws: each failure is the existing `approval-notify-failed` op and the inbox row
    // (already FYI) remains the fallback surface.
    notifyFailed = await step.run("approval-notify", async () => {
      let failed = 0;
      for (const f of result.flagged) {
        reportApprovalOp("gateUnanswered", null, { approvalId: f.id, toolName: f.toolName, workspaceId: f.workspaceId });
      }
      for (const e of result.expired) {
        reportApprovalOp("expired", null, {
          approvalId: e.id,
          toolName: e.toolName,
          workspaceId: e.workspaceId,
          extra: { reason: e.reason, seen_by: "cron" },
        });
        logApprovalMarker("SOLEUR_APPROVAL_EXPIRED", {
          approval_id: e.id,
          tool: e.toolName,
          workspace_id: e.workspaceId,
          reason: e.reason,
          seen_by: "cron",
        });
        if (e.reason !== "unanswered") continue;
        let delivered = false;
        try {
          delivered = await notifyApprovalExpired(e.id);
        } catch {
          delivered = false;
        }
        if (!delivered) {
          failed += 1;
          reportApprovalOp("notifyFailed", null, {
            approvalId: e.id,
            toolName: e.toolName,
            workspaceId: e.workspaceId,
            extra: { kind: "expired" },
          });
        }
      }
      return failed;
    });
  }

  // Every run, flag on or off: the lifecycle probe for a dark deploy (one grep proves the marker reaches Better Stack).
  await step.run("approval-sweep-marker", async () => {
    try {
      logApprovalMarker("SOLEUR_APPROVAL_SWEEP", { ok: swept.ok, expired, flagged, scrubbed, notify_failed: notifyFailed });
    } catch (err) {
      reportSilentFallback(err, {
        feature: CRON_NAME,
        op: "approval-sweep-marker-failed",
        message: "Approval expiry cron: the sweep marker could not be logged",
        extra: { fn: CRON_NAME },
      });
    }
  });

  // Heartbeat: ok = the sweep RAN. A missed check-in (scheduler dead / function dropped) is what the monitor catches;
  // a failed RPC posts ?status=error.
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: swept.ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: CRON_NAME,
      logger,
    });
  });

  return { ok: swept.ok, expired, flagged, scrubbed, notifyFailed };
}

// =============================================================================
// Registration
// =============================================================================

export const cronApprovalExpiry = inngest.createFunction(
  {
    id: "cron-approval-expiry",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
    triggers: [
      // Every 5 minutes: bounds how long an expired or unanswered request waits to be noticed.
      { cron: "*/5 * * * *" },
      { event: "cron/approval-expiry.manual-trigger" },
    ],
  },
  cronApprovalExpiryHandler as unknown as Parameters<typeof inngest.createFunction>[1],
);

/**
 * The push/email nudge for a freshly created approval request (#4672).
 *
 * `create_approval_request` writes the inbox_item row in the request's own transaction; this runs AFTER it returns, finds
 * that row by (workspace_id, dedup_key = the approval id: the only index the lookup can use) and hands it to
 * `dispatchInboxPush`, which sends the fixed, content-free copy deck strings (never the row title, never the action). The
 * expiry date comes from the create RPC result: `approval_request` has no service-role table grant, so nothing here reads
 * it. A failure returns false so the gate reports its own `approval-notify-failed` op; the inbox row already exists, so
 * the request is never invisible.
 *
 * Never imports the decide path (gate side).
 */

import { createServiceClient } from "@/lib/supabase/service";
import type { ApprovalNotifyKind } from "@/lib/approval-copy";
import { dispatchInboxPush } from "../notifications";

async function dispatchForApproval(
  approvalId: string,
  workspaceId: string,
  kind: ApprovalNotifyKind,
  approvalExpiresAt: string | null,
): Promise<boolean> {
  const supabase = createServiceClient();
  const { data, error } = await supabase
    .from("inbox_item")
    .select("id")
    .eq("workspace_id", workspaceId)
    .eq("source", "approval_required")
    .eq("dedup_key", approvalId)
    .maybeSingle();
  const id = (data as { id?: unknown } | null)?.id;
  if (error || typeof id !== "string") return false;
  return dispatchInboxPush(id, { kind, approvalExpiresAt });
}

export function notifyApprovalRequested(approvalId: string, workspaceId: string, expiresAt: string | null): Promise<boolean> {
  return dispatchForApproval(approvalId, workspaceId, "requested", expiresAt);
}

/** The expiry cron's generic "expired before it was decided" push (the `unanswered` case only). The copy has no date. */
export function notifyApprovalExpired(approvalId: string, workspaceId: string): Promise<boolean> {
  return dispatchForApproval(approvalId, workspaceId, "expired", null);
}

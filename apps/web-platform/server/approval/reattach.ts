/**
 * Re-send live approval cards when a client attaches to a conversation (#4672).
 *
 * The stream replay ring buffer does not carry approval frames (a reconnected client would otherwise get no card while
 * the agent stays blocked), so on every session attach the server reads the conversation's `pending` and `approved`
 * rows and emits one `approval_request` per row. The client upserts by approval id, so a re-send is idempotent.
 *
 * Gated by the same flag seam as the gate (zero database reads while dormant). Each card is rebuilt from the STORED
 * canonical action and re-verified against the stored hash before it is shown: a card that does not hash to the bound
 * value is never rendered (P6: the text the Owner reads cannot disagree with the action that would be consumed).
 */

import type { WSMessage } from "@/lib/types";
import { CANONICAL_VERSION, computeActionHash, type CanonicalAction } from "./canonical";
import { isApprovalQueueEnabled } from "./flag";
import { reportApprovalOp } from "./ops";
import { renderApprovalView } from "./render";
import { hasWaiter } from "./waiters";
import { listLiveApprovals, type ApprovalRpcClient } from "./service";
import { isApprovalRequiredTool } from "./tools";

export interface ReemitArgs {
  userId: string;
  conversationId: string;
  send: (userId: string, payload: WSMessage) => boolean;
  /** Service-role client (list_live_approvals is service-only). */
  client: () => ApprovalRpcClient;
  /** Role of the viewing user in the approval's workspace; failure = member (read-only). */
  viewerRole: (workspaceId: string) => Promise<"owner" | "member">;
  /**
   * The workspace of the session that is attaching (REQUIRED: the flag is evaluated per workspace, so reading it with no
   * workspace would lose the live card for a workspace-scoped cohort that the gate itself serves). Each row is then
   * checked again against its own `workspace_id`.
   */
  workspaceId: string;
  /** Test seam; defaults to the flag read for `{userId, workspaceId}`. */
  isEnabled?: (workspaceId: string) => Promise<boolean>;
}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

function asCanonical(v: unknown): CanonicalAction | null {
  if (!isObj(v) || v.v !== CANONICAL_VERSION || typeof v.tool !== "string" || !isApprovalRequiredTool(v.tool) || !isObj(v.fields)) return null;
  return v as unknown as CanonicalAction;
}

/** Returns the number of cards re-sent. Never throws: a failure is one op and the inbox row remains the fallback. */
export async function reemitLiveApprovals(a: ReemitArgs): Promise<number> {
  let sent = 0;
  try {
    // The flag, per workspace, memoised for this attach. An error is OFF (an unreadable flag never shows a card).
    const flagByWorkspace = new Map<string, Promise<boolean>>();
    const enabledFor = (workspaceId: string): Promise<boolean> => {
      let p = flagByWorkspace.get(workspaceId);
      if (!p) {
        p = (async () => {
          try {
            return (await (a.isEnabled ?? ((w: string) => isApprovalQueueEnabled({ userId: a.userId, workspaceId: w })))(workspaceId)) === true;
          } catch {
            return false;
          }
        })();
        flagByWorkspace.set(workspaceId, p);
      }
      return p;
    };
    // Dormant: zero database reads while the flag is off for the attaching session's workspace.
    if (!(await enabledFor(a.workspaceId))) return 0;

    const live = await listLiveApprovals(a.client(), a.conversationId);
    for (const { approval, requestCount } of live) {
      if (approval.status !== "pending" && approval.status !== "approved") continue;
      // The row's own workspace decides whether the flow is on for it (a conversation's rows can sit in another workspace
      // than the one the attaching session is bound to).
      if (!(await enabledFor(approval.workspace_id))) continue;
      const action = asCanonical(approval.canonical_action);
      let verified = false;
      if (action) {
        try {
          verified =
            computeActionHash({
              toolName: approval.tool_name,
              workspaceId: approval.workspace_id,
              conversationId: approval.conversation_id,
              action,
            }) === approval.action_sha256;
        } catch {
          verified = false;
        }
      }
      if (!action || !verified) {
        reportApprovalOp("reattachFailed", null, {
          approvalId: approval.id,
          toolName: approval.tool_name,
          conversationId: a.conversationId,
          extra: { cause: action ? "hash-mismatch" : "no-canonical-action" },
        });
        continue;
      }
      let viewerRole: "owner" | "member";
      try {
        viewerRole = await a.viewerRole(approval.workspace_id);
      } catch (err) {
        reportApprovalOp("viewerRoleFailed", err, { approvalId: approval.id, toolName: approval.tool_name, conversationId: a.conversationId });
        viewerRole = "member";
      }
      a.send(a.userId, {
        type: "approval_request",
        approvalId: approval.id,
        conversationId: approval.conversation_id,
        toolName: approval.tool_name,
        view: renderApprovalView(action),
        status: approval.status,
        expiresAt: approval.expires_at,
        requestCount,
        viewerRole,
        // True only when this process still holds the agent's live wait for the request (the session is on this host).
        agentWaiting: hasWaiter(approval.id),
      });
      sent += 1;
    }
  } catch (err) {
    reportApprovalOp("reattachFailed", err, { conversationId: a.conversationId, userId: a.userId });
  }
  return sent;
}

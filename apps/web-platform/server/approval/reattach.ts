/**
 * Re-send live approval cards when a client attaches to a conversation (#4672).
 *
 * The stream replay ring buffer does not carry approval frames (a reconnected client would otherwise get no card while
 * the agent stays blocked), so on every session attach the server reads the conversation's `pending` and `approved`
 * rows and emits one `approval_request` per row. The client upserts by approval id, so a re-send is idempotent.
 *
 * Gated by the same flag seam as the gate (no `approval_request` read while the flag is off for the attaching workspace). Each card is rebuilt from the STORED
 * canonical action and re-verified against the stored hash before it is shown: a card that does not hash to the bound
 * value is never rendered (P6: the text the Owner reads cannot disagree with the action that would be consumed).
 *
 * Who sees the action (#9601, ADR-309 flip item 1): the full card goes only to a verified Owner or to the row's verified
 * requester (`canSeeAction`). A redacted waiting frame (`view: null`, `toolName: "redacted"`, no requester key, no field
 * value) is sent for PENDING rows only; an approved row, and a row whose viewer role could not be read, send NO frame to a
 * viewer who cannot see the action. An Owner's card names the requester (`requester`) unless two or more live requests
 * share the conversation and action (the one label would then be ambiguous: only the literal "you" stays). Attach is
 * conversation-creator-only today, so for a non-Owner non-requester this is a defence-in-depth invariant that becomes
 * reachable with shared conversations; test/approval/render-sink-scan.test.ts pins that this file has exactly one gate and
 * one render call.
 */

import { REQUESTER_SELF } from "@/lib/approval-copy";
import type { WSMessage } from "@/lib/types";
import { ApprovalCanonicalError, CANONICAL_VERSION, computeActionHash, type CanonicalAction } from "./canonical";
import { isApprovalQueueEnabled } from "./flag";
import { reportApprovalOp } from "./ops";
import { renderApprovalView } from "./render";
import { canSeeAction, isVerifiedRequester, type RequesterLabelFn } from "./card-visibility";
import { hasWaiter } from "./waiters";
import { listLiveApprovals, type ApprovalRpcClient } from "./service";
import { isApprovalRequiredTool } from "./tools";

export interface ReemitArgs {
  userId: string;
  conversationId: string;
  send: (userId: string, payload: WSMessage) => boolean;
  /** Service-role client (list_live_approvals is service-only). */
  client: () => ApprovalRpcClient;
  /** Role of the viewing user in the approval's workspace; failure = member (read-only). Read once per workspace per attach. */
  viewerRole: (workspaceId: string) => Promise<"owner" | "member">;
  /**
   * The workspace of the session that is attaching (REQUIRED: the flag is evaluated per workspace, so reading it with no
   * workspace would lose the live card for a workspace-scoped cohort that the gate itself serves). Each row is then
   * checked again against its own `workspace_id`.
   */
  workspaceId: string;
  /**
   * The requester label for an Owner viewer (REQUIRED: a call site that stops passing it fails type-check instead of
   * silently dropping the label). Called with the ROW's workspace, never the attaching session's.
   */
  requesterLabel: RequesterLabelFn;
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
    // The viewer's role, per workspace, memoised for this attach (a conversation's rows share a workspace almost always). A
    // failed read is memoised too, so `viewerRoleFailed` is reported once per workspace, and stays fail-closed (member).
    const roleByWorkspace = new Map<string, Promise<{ role: "owner" | "member"; failed: boolean }>>();
    const roleFor = (row: { id: string; tool_name: string; workspace_id: string }): Promise<{ role: "owner" | "member"; failed: boolean }> => {
      let p = roleByWorkspace.get(row.workspace_id);
      if (!p) {
        p = (async () => {
          try {
            // Only a literal "owner" is an Owner; any other value (a runtime garbage role included) is a member.
            return { role: (await a.viewerRole(row.workspace_id)) === "owner" ? ("owner" as const) : ("member" as const), failed: false };
          } catch (err) {
            reportApprovalOp("viewerRoleFailed", err, { approvalId: row.id, toolName: row.tool_name, conversationId: a.conversationId });
            return { role: "member" as const, failed: true };
          }
        })();
        roleByWorkspace.set(row.workspace_id, p);
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
      let keyUnavailable = false;
      if (action) {
        try {
          verified =
            computeActionHash({
              toolName: approval.tool_name,
              workspaceId: approval.workspace_id,
              conversationId: approval.conversation_id,
              action,
            }) === approval.action_sha256;
        } catch (err) {
          verified = false;
          if (err instanceof ApprovalCanonicalError && err.code === "key_unavailable") keyUnavailable = true;
        }
      }
      if (keyUnavailable) {
        // The hash key is unset: no card can be verified. Same op as the gate's, so one alert covers a mis-deployed container.
        reportApprovalOp("keyUnavailable", null, {
          approvalId: approval.id,
          toolName: approval.tool_name,
          conversationId: a.conversationId,
          extra: { code: "key_unavailable", stage: "reattach" },
        });
        continue;
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
      const { role: viewerRole, failed: roleReadFailed } = await roleFor(approval);
      const mayView = canSeeAction(a.userId, viewerRole === "owner", approval.requested_by_user_id);
      // A viewer who cannot see the action gets no frame for an approved request (it is not a waiting card), and none when
      // their role could not be read: a redacted "waiting" card shown to an Owner we could not identify would mislead. The
      // next attach recovers; the inbox row and the landing page remain.
      if (!mayView && (roleReadFailed || approval.status === "approved")) continue;
      // The requester line: "you" for the verified requester (no read); an Owner viewer gets the labeler's value only while ONE
      // live request exists (two or more make a single label ambiguous); everyone else gets no key.
      let requester: string | undefined;
      try {
        requester = isVerifiedRequester(a.userId, approval.requested_by_user_id)
          ? REQUESTER_SELF
          : viewerRole === "owner" && requestCount <= 1
            ? await a.requesterLabel(approval.workspace_id, a.userId, approval.requested_by_user_id)
            : undefined;
      } catch {
        requester = undefined; // a lookup never costs the card
      }
      a.send(a.userId, {
        type: "approval_request",
        approvalId: approval.id,
        conversationId: approval.conversation_id,
        toolName: mayView ? approval.tool_name : "redacted",
        view: mayView ? renderApprovalView(action) : null,
        status: approval.status,
        expiresAt: approval.expires_at,
        requestCount,
        viewerRole,
        // True only when this process still holds the agent's live wait for the request (the session is on this host).
        agentWaiting: hasWaiter(approval.id),
        ...(requester !== undefined ? { requester } : {}),
      });
      sent += 1;
    }
  } catch (err) {
    reportApprovalOp("reattachFailed", err, { conversationId: a.conversationId, userId: a.userId });
  }
  return sent;
}

/**
 * The approval flow of the gated branch (#4672), called from `createCanUseTool` for a slice-1 tool when
 * `deps.approval` is present. Everything here is fail-closed: every error, timeout, abort and unknown outcome is a
 * deny with a STATIC message (never tool input or database text), and the only way out with an allow is a database
 * `consumed: true` for the hash of the exact snapshot that is handed to `allow()`.
 *
 * Built ON the shared `holdForUser` lifecycle (ADR-305), not beside it: the caller passes `hold`, which is that
 * helper with the approval wait as the verdict source, so the pending-gate counter, the compare-and-set status hold
 * and restore, and the "an answer that lands after an abort is not honoured" rule are the same code as the Bash and
 * review-card lanes.
 *
 * Sequence (plan "Gated branch"):
 *   snapshot (deep clone, before the first await) -> flag (once) -> server-derived fields -> canonical + hash ->
 *   submit (create-or-find; an already-approved live row is consumed there, no card, no wait) -> card -> wait ->
 *   approved: consume(id, hash, conversation) -> allow(snapshot).
 *
 * Returns `null` ONLY when the flag is off (or unreadable): the caller then runs the in-memory review gate exactly as
 * it did before this module existed.
 */

import type { PermissionResult } from "@anthropic-ai/claude-agent-sdk";
import type { WSMessage } from "@/lib/types";
import {
  ApprovalCanonicalError,
  canonicalizeAction,
  computeActionHash,
  type CanonicalAction,
  type CanonicalValue,
} from "./canonical";
import type { ApprovalGateDeps } from "./gate-types";
import { logApprovalMarker, reportApprovalOp, type ApprovalOpContext } from "./ops";
import { renderApprovalView } from "./render";
import { registerWaiter, unregisterWaiter, waitForDecision } from "./waiters";

// Static deny texts: no tool input, no database text. The agent reads these.
export const APPROVAL_PENDING_DENY =
  "This action needs the workspace Owner's approval. The request is saved for the Owner. Do not retry now. Once the user says it is approved, call this tool again with byte-identical arguments (a regenerated or reworded body is a different action and needs a new approval). Tell the user the action was not performed yet.";
export const APPROVAL_REJECTED_DENY =
  "The workspace Owner denied this action, so it was not performed. Do not retry or rephrase it. Tell the user and ask how they want to proceed.";
export const APPROVAL_EXPIRED_DENY =
  "The approval request expired before it was used, so the action was not performed. Do not retry unless the user asks. Tell the user the action was not performed and ask how they want to proceed.";
export const APPROVAL_CONSUME_REJECTED_DENY =
  "The approval could not be applied to this call (the arguments changed, or it was already used), so the action was not performed. Do not retry with different arguments. Tell the user the exact action needs a new approval.";
export const APPROVAL_ABORTED_DENY =
  "The session ended before the approval was applied, so the action was not performed. The request stays saved for the workspace Owner. Do not retry unless the user asks.";
export const APPROVAL_UNAVAILABLE_DENY =
  "Approval is unavailable right now, so the action was not performed. Do not retry. Tell the user the action was not performed.";
export const APPROVAL_INVALID_INPUT_DENY =
  "The arguments for this action cannot be approved as given (a field is missing, invalid or not part of the action), so it was not performed. Correct the arguments and ask again.";

export interface RunApprovalGateArgs {
  toolName: string;
  toolInput: Record<string, unknown>;
  /** The per-call signal from the SDK (may be undefined in a degenerate caller; treated as never aborted). */
  callSignal: AbortSignal | undefined;
  controllerSignal: AbortSignal;
  userId: string;
  conversationId: string;
  approval: ApprovalGateDeps;
  sendToClient: (userId: string, payload: WSMessage) => boolean;
  /** `holdForUser` with the approval wait as the verdict source: null = aborted or failed. */
  hold: (approvalId: string, signal: AbortSignal, wait: () => Promise<string>) => Promise<string | null>;
  allow: (input: Record<string, unknown>) => PermissionResult;
  logDecision: (toolName: string, decision: "allow" | "deny", reason: string) => void;
}

const deny = (message: string): PermissionResult => ({ behavior: "deny" as const, message });

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/**
 * Every DEFINED value in the snapshot must appear, equal, in the canonical fields: an argument the canonical object
 * does not carry is an argument the Owner was never shown and the hash does not bind. (Zod strips unknown keys when
 * building the canonical action, so without this check an extra key would ride along on `allow(snapshot)`.)
 */
export function isCoveredByCanonical(snapshot: unknown, canonical: CanonicalValue | undefined): boolean {
  if (snapshot === undefined) return true;
  if (Array.isArray(snapshot)) {
    return (
      Array.isArray(canonical) &&
      canonical.length === snapshot.length &&
      snapshot.every((v, i) => isCoveredByCanonical(v, canonical[i]))
    );
  }
  if (isObj(snapshot)) {
    if (!isObj(canonical)) return false;
    return Object.entries(snapshot).every(([k, v]) => v === undefined || (k in canonical && isCoveredByCanonical(v, canonical[k] as CanonicalValue)));
  }
  return snapshot === canonical;
}

function combineSignals(a: AbortSignal | undefined, b: AbortSignal): AbortSignal {
  return a ? AbortSignal.any([a, b]) : b;
}

export async function runApprovalGate(a: RunApprovalGateArgs): Promise<PermissionResult | null> {
  // The snapshot is taken BEFORE the first await so nothing the agent does while the gate is waiting can reach the
  // object that is hashed and later handed to allow(). A value that cannot be cloned is not approvable (decided below,
  // after the flag, so a flag-off call is never affected).
  let snapshot: Record<string, unknown> | null;
  try {
    snapshot = structuredClone(a.toolInput);
  } catch {
    snapshot = null;
  }

  // Evaluated once per gate. An error is OFF: an unreadable flag can never turn the approval path on.
  let enabled = false;
  try {
    enabled = (await a.approval.isEnabled()) === true;
  } catch {
    enabled = false;
  }
  if (!enabled) return null;

  const op: ApprovalOpContext = {
    toolName: a.toolName,
    conversationId: a.conversationId,
    workspaceId: a.approval.workspaceId,
    userId: a.userId,
  };
  const aborted = () => a.callSignal?.aborted === true || a.controllerSignal.aborted;
  const denyAborted = (): PermissionResult => {
    a.logDecision(a.toolName, "deny", "approval wait aborted");
    return deny(APPROVAL_ABORTED_DENY);
  };

  try {
    if (snapshot === null) {
      reportApprovalOp("gateFailed", null, { ...op, extra: { stage: "snapshot" } });
      return deny(APPROVAL_UNAVAILABLE_DENY);
    }
    if (aborted()) return denyAborted();

    // 1. The fields the model cannot supply but the executed action depends on.
    let derived: Awaited<ReturnType<ApprovalGateDeps["resolveServerDerived"]>>;
    try {
      derived = await a.approval.resolveServerDerived(a.toolName, snapshot);
    } catch (err) {
      reportApprovalOp("bindFailed", err, op);
      a.logDecision(a.toolName, "deny", "approval bind failed");
      return deny(APPROVAL_UNAVAILABLE_DENY);
    }

    // 2. Canonical action + hash, from the snapshot only.
    let action: CanonicalAction;
    let hash: string;
    try {
      action = canonicalizeAction(a.toolName, snapshot, derived);
      if (!isCoveredByCanonical(snapshot, action.fields)) {
        a.logDecision(a.toolName, "deny", "input not covered by the canonical action");
        return deny(APPROVAL_INVALID_INPUT_DENY);
      }
      hash = computeActionHash({
        toolName: a.toolName,
        workspaceId: a.approval.workspaceId,
        conversationId: a.conversationId,
        action,
      });
    } catch (err) {
      const code = err instanceof ApprovalCanonicalError ? err.code : "unknown";
      if (code === "invalid_input") {
        a.logDecision(a.toolName, "deny", "invalid input");
        return deny(APPROVAL_INVALID_INPUT_DENY);
      }
      reportApprovalOp(code === "invalid_server_derived" ? "bindFailed" : "gateFailed", err, { ...op, extra: { code } });
      a.logDecision(a.toolName, "deny", "approval bind failed");
      return deny(APPROVAL_UNAVAILABLE_DENY);
    }
    if (aborted()) return denyAborted();

    // 3. Create-or-find the live request. An already-approved live row is consumed inside submit (no card, no wait).
    let submitted: Awaited<ReturnType<ApprovalGateDeps["submit"]>>;
    try {
      submitted = await a.approval.submit({
        workspaceId: a.approval.workspaceId,
        conversationId: a.conversationId,
        requestedByUserId: a.userId,
        toolName: a.toolName,
        actionSha256: hash,
        canonicalAction: action,
      });
    } catch (err) {
      reportApprovalOp("createFailed", err, op);
      a.logDecision(a.toolName, "deny", "approval request not created");
      return deny(APPROVAL_UNAVAILABLE_DENY);
    }

    switch (submitted.kind) {
      case "released": {
        const ctx = { ...op, approvalId: submitted.approvalId };
        // An approved live row that exists BEFORE this call means the agent is asking again after its wait ended.
        reportApprovalOp("reproposed", null, { ...ctx, extra: { requestCount: submitted.requestCount, released: true } });
        if (aborted()) return denyAborted();
        logApprovalMarker("SOLEUR_APPROVAL_CONSUMED", {
          approval_id: submitted.approvalId,
          tool: a.toolName,
          conversation_id: a.conversationId,
          path: "reproposal",
        });
        a.logDecision(a.toolName, "allow", "approved request consumed on re-proposal");
        return a.allow(snapshot);
      }
      case "consume_rejected": {
        reportApprovalOp("consumeRejected", null, { ...op, approvalId: submitted.approvalId, extra: { reason: submitted.reason } });
        a.logDecision(a.toolName, "deny", "approval consume rejected");
        return deny(APPROVAL_CONSUME_REJECTED_DENY);
      }
      case "not_waitable": {
        const ctx = { ...op, approvalId: submitted.approval.id };
        reportApprovalOp(submitted.approval.status === "expired" ? "expired" : "gateFailed", null, {
          ...ctx,
          extra: { status: submitted.approval.status },
        });
        a.logDecision(a.toolName, "deny", "approval request not waitable");
        return deny(APPROVAL_UNAVAILABLE_DENY);
      }
      case "wait":
        break;
      default:
        reportApprovalOp("gateFailed", null, { ...op, extra: { stage: "submit-kind" } });
        return deny(APPROVAL_UNAVAILABLE_DENY);
    }

    // 4. Wait for the Owner. Register the in-process waiter before the card goes out so a fast decide is never missed
    //    (the poll covers a decide on another host regardless).
    const approvalId = submitted.approval.id;
    const ctx: ApprovalOpContext = { ...op, approvalId };
    const reg = registerWaiter(approvalId);
    try {
      if (!submitted.created || submitted.requestCount > 1) {
        reportApprovalOp("reproposed", null, { ...ctx, extra: { requestCount: submitted.requestCount, created: submitted.created } });
      }
      logApprovalMarker("SOLEUR_APPROVAL_REQUESTED", {
        approval_id: approvalId,
        tool: a.toolName,
        conversation_id: a.conversationId,
        created: submitted.created,
        request_count: submitted.requestCount,
      });

      let viewerRole: "owner" | "member" = "member";
      try {
        viewerRole = await a.approval.viewerRole();
      } catch {
        viewerRole = "member"; // read-only card is the safe default
      }
      try {
        a.sendToClient(a.userId, {
          type: "approval_request",
          approvalId,
          conversationId: a.conversationId,
          toolName: a.toolName,
          view: renderApprovalView(action),
          status: "pending",
          expiresAt: submitted.approval.expires_at,
          requestCount: submitted.requestCount,
          viewerRole,
        });
      } catch (err) {
        reportApprovalOp("notifyFailed", err, { ...ctx, extra: { channel: "ws-card" } });
      }
      if (a.approval.onRequested) {
        try {
          await a.approval.onRequested({ approvalId, created: submitted.created });
        } catch (err) {
          reportApprovalOp("notifyFailed", err, { ...ctx, extra: { channel: "onRequested" } });
        }
      }

      const signal = combineSignals(a.callSignal, a.controllerSignal);
      const wait = async (): Promise<string> => {
        const outcome = await waitForDecision({
          approvalId,
          read: () => a.approval.readStatus(approvalId),
          signal,
          woken: reg.woken,
          ...a.approval.waitOptions,
        });
        if (outcome.kind === "decided") return outcome.status;
        return outcome.kind; // "timeout" | "aborted"
      };
      const selection = await a.hold(approvalId, a.callSignal ?? a.controllerSignal, wait);

      // null = the wait threw or the session aborted (holdForUser re-checks the abort AFTER its restore write).
      if (selection === null || selection === "aborted" || aborted()) return denyAborted();

      switch (selection) {
        case "approved": {
          let consumed: boolean;
          let reason = "unknown";
          try {
            const c = await a.approval.consume({ id: approvalId, hash, conversationId: a.conversationId });
            consumed = c.consumed === true;
            if (!c.consumed) reason = c.reason;
          } catch {
            consumed = false;
            reason = "rpc_error";
          }
          if (!consumed) {
            reportApprovalOp("consumeRejected", null, { ...ctx, extra: { reason } });
            a.logDecision(a.toolName, "deny", "approval consume rejected");
            return deny(APPROVAL_CONSUME_REJECTED_DENY);
          }
          // The approval is spent. If the session died while the consume was in flight it is spent for nothing: deny.
          if (aborted()) return denyAborted();
          logApprovalMarker("SOLEUR_APPROVAL_CONSUMED", {
            approval_id: approvalId,
            tool: a.toolName,
            conversation_id: a.conversationId,
            path: "live",
          });
          a.logDecision(a.toolName, "allow", "approval consumed");
          return a.allow(snapshot);
        }
        case "rejected":
          a.logDecision(a.toolName, "deny", "approval rejected by the owner");
          return deny(APPROVAL_REJECTED_DENY);
        case "timeout":
          reportApprovalOp("waitTimeout", null, ctx);
          a.logDecision(a.toolName, "deny", "approval wait ended undecided");
          return deny(APPROVAL_PENDING_DENY);
        case "expired":
          reportApprovalOp("expired", null, ctx);
          logApprovalMarker("SOLEUR_APPROVAL_EXPIRED", { approval_id: approvalId, tool: a.toolName, conversation_id: a.conversationId, seen_by: "gate" });
          a.logDecision(a.toolName, "deny", "approval expired");
          return deny(APPROVAL_EXPIRED_DENY);
        case "consumed":
          // Another identical call spent the single use first.
          reportApprovalOp("consumeRejected", null, { ...ctx, extra: { reason: "already_consumed" } });
          a.logDecision(a.toolName, "deny", "approval already consumed");
          return deny(APPROVAL_CONSUME_REJECTED_DENY);
        default:
          reportApprovalOp("gateFailed", null, { ...ctx, extra: { stage: "unknown-outcome" } });
          a.logDecision(a.toolName, "deny", "approval outcome unknown");
          return deny(APPROVAL_UNAVAILABLE_DENY);
      }
    } finally {
      unregisterWaiter(approvalId);
    }
  } catch (err) {
    reportApprovalOp("gateFailed", err, op);
    a.logDecision(a.toolName, "deny", "approval flow failed");
    return deny(APPROVAL_UNAVAILABLE_DENY);
  }
}

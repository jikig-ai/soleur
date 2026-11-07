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
 *   approved: consume(id, hash, conversation) -> execution grant -> allow(snapshot).
 *
 * Returns `null` ONLY when the flag is off (or unreadable): the caller then runs the in-memory review gate exactly as
 * it did before this module existed.
 */

import type { PermissionResult } from "@anthropic-ai/claude-agent-sdk";
import type { WSMessage } from "@/lib/types";
import type { ApprovalWireStatus } from "@/lib/approval-wire";
import {
  ApprovalCanonicalError,
  canonicalizeAction,
  computeActionHash,
  type CanonicalAction,
  type CanonicalValue,
} from "./canonical";
import type { ApprovalGateDeps } from "./gate-types";
import { putGrant } from "./grants";
import { logApprovalMarker, reportApprovalOp, type ApprovalOpContext } from "./ops";
import { renderApprovalView } from "./render";
import { registerWaiter, unregisterWaiter, waitForDecision, type WaitStatus } from "./waiters";

// Static deny texts: no tool input, no database text. The agent reads these.
export const APPROVAL_PENDING_DENY =
  "This action needs the workspace Owner's approval. The request is saved for the Owner. Do not retry now. Once the user says it is approved, call this tool again with byte-identical arguments (a regenerated or reworded body is a different action and needs a new approval). Tell the user the action was not performed yet.";
export const APPROVAL_REJECTED_DENY =
  "The workspace Owner denied this action, so it was not performed. Do not retry or rephrase it. Tell the user and ask how they want to proceed.";
export const APPROVAL_EXPIRED_DENY =
  "The approval request expired before it was used, so the action was not performed. Do not retry unless the user asks. Tell the user the action was not performed and ask how they want to proceed.";
export const APPROVAL_CONSUME_REJECTED_DENY =
  "The approval could not be applied to this call (the arguments changed, or it was already used), so the action was not performed. An approval covers byte-identical arguments, and for a push also the commit the server derives from the workspace HEAD. Do not retry with different arguments. Tell the user the exact action needs a new approval.";
export const APPROVAL_PRINCIPAL_CHANGED_DENY =
  "The approval can no longer be applied because workspace membership or roles changed after it was granted, so the action was not performed. Do not retry. Tell the user the action needs a new approval from a current workspace Owner.";
export const APPROVAL_TOO_MANY_PENDING_DENY =
  "Too many approval requests are already waiting for the workspace Owner, so this one was not saved. Do not retry. Tell the user to answer or decline the pending requests first.";
export const APPROVAL_ABORTED_DENY =
  "The session ended before the approval was applied, so the action was not performed. The request stays saved for the workspace Owner. Do not retry unless the user asks.";
/** The abort landed AFTER the approval was consumed: the request is no longer saved, it is spent. */
export const APPROVAL_ABORTED_SPENT_DENY =
  "The session ended after the approval was used but before the action ran, so the action was not performed and that approval is spent. Do not retry unless the user asks; the action needs a new approval.";
export const APPROVAL_UNAVAILABLE_DENY =
  "Approval is unavailable right now, so the action was not performed. Do not retry in this conversation. Tell the user the action was not performed.";
export const APPROVAL_INVALID_INPUT_DENY =
  "The arguments for this action cannot be approved as given (a field is missing, invalid or not part of the action), so it was not performed. Correct the arguments and ask again.";

/** What the wait resolves to: a decided status (never `pending`), or the wait's own end. */
type WaitSelection = Exclude<WaitStatus, "pending"> | "timeout" | "aborted";

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

/** The static agent text for a consume that did not release. Only the reasons that mean something else get their own text. */
export function consumeRejectedDeny(reason: string): string {
  switch (reason) {
    case "expired":
      return APPROVAL_EXPIRED_DENY;
    case "rpc_error":
      return APPROVAL_UNAVAILABLE_DENY;
    case "decider_not_owner":
    case "requester_not_member":
      return APPROVAL_PRINCIPAL_CHANGED_DENY;
    case "not_approved":
      // The consume lost to a revoke: the Owner denied it, so the honest text is the denial, not "arguments changed".
      return APPROVAL_REJECTED_DENY;
    default:
      return APPROVAL_CONSUME_REJECTED_DENY;
  }
}

/** What the card should show after a consume that did not release (the row's real state, so no "your agent is continuing"). */
function consumeRejectedCardStatus(reason: string): "approved" | "rejected" | "expired" | "consumed" {
  switch (reason) {
    case "expired":
      return "expired";
    case "not_approved":
      return "rejected";
    case "already_consumed":
      return "consumed";
    default:
      return "approved";
  }
}

/**
 * The row stays `approved` but can never be consumed (the decider is no longer an Owner, or the requester left the
 * workspace): the card must not tell the Owner that asking again is allowed.
 */
export function consumeRejectedIsUnusable(reason: string): boolean {
  return reason === "decider_not_owner" || reason === "requester_not_member";
}

/** The `onRequested` dispatch (a push/email) is best effort: the gate never waits on it longer than this. */
export const ON_REQUESTED_DEADLINE_MS = 10_000;

/** Run `fn`, but stop waiting for it when the signal aborts or the deadline passes. Resolves "ok" | "aborted" | "timeout"; a throw of `fn` rejects. */
async function boundedByAbort(fn: () => Promise<void>, signal: AbortSignal, deadlineMs: number): Promise<"ok" | "aborted" | "timeout"> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let onAbort: (() => void) | undefined;
  const limit = new Promise<"aborted" | "timeout">((resolve) => {
    timer = setTimeout(() => resolve("timeout"), deadlineMs);
    onAbort = () => resolve("aborted");
    if (signal.aborted) resolve("aborted");
    else signal.addEventListener("abort", onAbort, { once: true });
  });
  try {
    return await Promise.race([fn().then(() => "ok" as const), limit]);
  } finally {
    if (timer) clearTimeout(timer);
    if (onAbort) signal.removeEventListener("abort", onAbort);
  }
}

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
  if (!enabled) {
    // A session that already ran the approval flow never falls back to the legacy requester-answerable card for the other
    // tools after a mid-session flag-off or flag read error: only the grant-checked tools are protected by the sticky
    // `enforcing`, so every approval-required tool denies for the rest of the session (ADR-309 rollback).
    if (a.approval.grants.enforcing) {
      a.logDecision(a.toolName, "deny", "approval flow unavailable after it ran in this session");
      return deny(APPROVAL_UNAVAILABLE_DENY);
    }
    return null;
  }
  // From here the session is on the approval flow for good (sticky): a tool handler that finds no execution grant refuses
  // instead of falling back to the legacy path, even if the flag is turned off mid-session.
  a.approval.grants.enforcing = true;

  const op: ApprovalOpContext = {
    toolName: a.toolName,
    conversationId: a.conversationId,
    workspaceId: a.approval.workspaceId,
    userId: a.userId,
  };
  const aborted = () => a.callSignal?.aborted === true || a.controllerSignal.aborted;
  const denyAborted = (spent = false): PermissionResult => {
    a.logDecision(a.toolName, "deny", "approval wait aborted");
    return deny(spent ? APPROVAL_ABORTED_SPENT_DENY : APPROVAL_ABORTED_DENY);
  };

  // Tell the card what the agent is doing now, so it never claims "your agent is continuing" or "stopped waiting" from a
  // guess (wireframe 04C vs 04D). Best effort: a failed frame is one op and the card keeps its last state.
  const emitStatus = (approvalId: string, status: ApprovalWireStatus, agentWaiting: boolean, unusable = false): void => {
    try {
      a.sendToClient(a.userId, {
        type: "approval_status",
        approvalId,
        conversationId: a.conversationId,
        status,
        agentWaiting,
        ...(unusable ? { unusable: true } : {}),
      });
    } catch (err) {
      reportApprovalOp("notifyFailed", err, { ...op, approvalId, extra: { channel: "ws-status" } });
    }
  };

  // `not_approved` means the row is no longer approved: a revoke (rejected) or the sweep (expired). One best-effort read
  // tells them apart so an expired request is not reported to the agent and the card as "Owner denied". A failed read
  // keeps the safe default (the denial text).
  const refineConsumeReason = async (approvalId: string, reason: string): Promise<string> => {
    if (reason !== "not_approved") return reason;
    try {
      return (await a.approval.readStatus(approvalId)) === "expired" ? "expired" : reason;
    } catch {
      return reason;
    }
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
        reportApprovalOp("invalidInput", null, { ...op, extra: { stage: "not-covered" } });
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
        reportApprovalOp("invalidInput", null, { ...op, extra: { stage: "canonical" } });
        a.logDecision(a.toolName, "deny", "invalid input");
        return deny(APPROVAL_INVALID_INPUT_DENY);
      }
      if (code === "key_unavailable") {
        // The hash key (SENTRY_USERID_PEPPER) is unset: every gated call denies. Its own error-level op, so one alert
        // covers a mis-deployed container instead of sharing the generic gate-failure group.
        reportApprovalOp("keyUnavailable", null, { ...op, extra: { code } });
      } else {
        reportApprovalOp(code === "invalid_server_derived" ? "bindFailed" : "gateFailed", err, { ...op, extra: { code } });
      }
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

    // The grant carries what was approved to the handler that executes it (ADR-309, execution grants). Written immediately before allow(), on
    // both allow paths, keyed by the zod-parsed handler args; a throw here is a deny (the outer catch).
    const allowWithGrant = (): PermissionResult => {
      putGrant(a.approval.grants, a.toolName, snapshot, { workspaceId: a.approval.workspaceId, headSha: derived?.headSha });
      return a.allow(snapshot);
    };

    switch (submitted.kind) {
      case "released": {
        const ctx = { ...op, approvalId: submitted.approvalId };
        // An approved live row that exists BEFORE this call means the agent is asking again after its wait ended.
        reportApprovalOp("reproposed", null, { ...ctx, extra: { requestCount: submitted.requestCount, released: true } });
        // The approval is spent (consumed inside submit). Log it whether or not the session is still alive, and tell the
        // open card, so it never stays "approved" for an action that already ran (duplicate-approval risk).
        const wasAborted = aborted();
        logApprovalMarker("SOLEUR_APPROVAL_CONSUMED", {
          approval_id: submitted.approvalId,
          tool: a.toolName,
          conversation_id: a.conversationId,
          path: "reproposal",
          aborted: wasAborted,
        });
        emitStatus(submitted.approvalId, "consumed", false);
        if (wasAborted) {
          reportApprovalOp("consumedAborted", null, { ...ctx, extra: { path: "reproposal" } });
          return denyAborted(true);
        }
        a.logDecision(a.toolName, "allow", "approved request consumed on re-proposal");
        return allowWithGrant();
      }
      case "consume_rejected": {
        reportApprovalOp("consumeRejected", null, {
          ...op,
          approvalId: submitted.approvalId,
          extra: { reason: submitted.reason, ...(submitted.code ? { code: submitted.code } : {}) },
        });
        const shown = await refineConsumeReason(submitted.approvalId, submitted.reason);
        emitStatus(submitted.approvalId, consumeRejectedCardStatus(shown), false, consumeRejectedIsUnusable(shown));
        a.logDecision(a.toolName, "deny", "approval consume rejected");
        return deny(consumeRejectedDeny(shown));
      }
      case "cap_reached": {
        reportApprovalOp("capReached", null, { ...op, extra: { scope: submitted.scope } });
        a.logDecision(a.toolName, "deny", "too many pending approval requests");
        return deny(APPROVAL_TOO_MANY_PENDING_DENY);
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

      let viewerRole: "owner" | "member";
      try {
        viewerRole = await a.approval.viewerRole();
      } catch (err) {
        reportApprovalOp("viewerRoleFailed", err, ctx);
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
          agentWaiting: true,
        });
      } catch (err) {
        reportApprovalOp("notifyFailed", err, { ...ctx, extra: { channel: "ws-card" } });
      }

      const signal = combineSignals(a.callSignal, a.controllerSignal);
      if (a.approval.onRequested) {
        // Bounded: a slow push provider can neither hold the agent's turn open nor outlive an abort.
        try {
          const dispatched = await boundedByAbort(
            () =>
              a.approval.onRequested!({
                approvalId,
                created: submitted.created,
                notify: submitted.notify,
                expiresAt: submitted.expiresAt,
              }),
            signal,
            a.approval.onRequestedDeadlineMs ?? ON_REQUESTED_DEADLINE_MS,
          );
          if (dispatched === "timeout") reportApprovalOp("notifyFailed", null, { ...ctx, extra: { channel: "onRequested", cause: "timeout" } });
        } catch (err) {
          reportApprovalOp("notifyFailed", err, { ...ctx, extra: { channel: "onRequested" } });
        }
      }

      let readErrors = 0;
      let lastReadError: unknown;
      const wait = async (): Promise<WaitSelection> => {
        const outcome = await waitForDecision({
          approvalId,
          read: () => a.approval.readStatus(approvalId),
          signal,
          woken: reg.woken,
          ...a.approval.waitOptions,
        });
        if (outcome.kind === "decided") return outcome.status;
        readErrors = outcome.readErrors;
        lastReadError = outcome.lastReadError;
        return outcome.kind; // "timeout" | "aborted"
      };
      const selection = (await a.hold(approvalId, a.callSignal ?? a.controllerSignal, wait)) as WaitSelection | null;
      // ONE event per wait with the count, never one per poll.
      if (readErrors > 0) reportApprovalOp("waitReadFailed", lastReadError, { ...ctx, extra: { readErrors } });

      // null = the wait threw or the session aborted (holdForUser re-checks the abort AFTER its restore write).
      if (selection === null || selection === "aborted" || aborted()) return denyAborted();

      switch (selection) {
        case "approved": {
          let consumed: boolean;
          let reason = "unknown";
          let consumeError: unknown = null;
          try {
            const c = await a.approval.consume({ id: approvalId, hash, conversationId: a.conversationId });
            consumed = c.consumed === true;
            if (!c.consumed) {
              reason = c.reason;
              if (c.code) consumeError = { code: c.code };
            }
          } catch (err) {
            consumed = false;
            reason = "rpc_error";
            consumeError = err;
          }
          if (!consumed) {
            reportApprovalOp("consumeRejected", consumeError, { ...ctx, extra: { reason } });
            // The card said "released, your agent is continuing": it must stop saying so.
            const shown = await refineConsumeReason(approvalId, reason);
            emitStatus(approvalId, consumeRejectedCardStatus(shown), false, consumeRejectedIsUnusable(shown));
            a.logDecision(a.toolName, "deny", "approval consume rejected");
            return deny(consumeRejectedDeny(shown));
          }
          // The approval is spent. Log it before the abort check, so a spent-then-aborted approval is visible; if the
          // session died while the consume was in flight it is spent for nothing: deny.
          const wasAborted = aborted();
          logApprovalMarker("SOLEUR_APPROVAL_CONSUMED", {
            approval_id: approvalId,
            tool: a.toolName,
            conversation_id: a.conversationId,
            path: "live",
            aborted: wasAborted,
          });
          emitStatus(approvalId, "consumed", false);
          if (wasAborted) {
            reportApprovalOp("consumedAborted", null, { ...ctx, extra: { path: "live" } });
            return denyAborted(true);
          }
          a.logDecision(a.toolName, "allow", "approval consumed");
          return allowWithGrant();
        }
        case "rejected":
          a.logDecision(a.toolName, "deny", "approval rejected by the owner");
          return deny(APPROVAL_REJECTED_DENY);
        case "timeout":
          emitStatus(approvalId, "pending", false);
          reportApprovalOp("waitTimeout", null, { ...ctx, extra: readErrors > 0 ? { readErrors } : undefined });
          a.logDecision(a.toolName, "deny", "approval wait ended undecided");
          return deny(APPROVAL_PENDING_DENY);
        case "expired":
          emitStatus(approvalId, "expired", false);
          reportApprovalOp("expired", null, ctx);
          logApprovalMarker("SOLEUR_APPROVAL_EXPIRED", { approval_id: approvalId, tool: a.toolName, conversation_id: a.conversationId, seen_by: "gate" });
          a.logDecision(a.toolName, "deny", "approval expired");
          return deny(APPROVAL_EXPIRED_DENY);
        case "consumed":
          // Another identical call spent the single use first.
          reportApprovalOp("consumeRejected", null, { ...ctx, extra: { reason: "already_consumed" } });
          a.logDecision(a.toolName, "deny", "approval already consumed");
          return deny(APPROVAL_CONSUME_REJECTED_DENY);
        default: {
          // Exhaustive over WaitSelection: a new wait outcome is a compile error here. The runtime deny is the fail-closed
          // backstop for the untyped `hold` seam (it returns a bare string), never a reachable branch.
          const unreachable: never = selection;
          void unreachable;
          reportApprovalOp("gateFailed", null, { ...ctx, extra: { stage: "unknown-outcome" } });
          a.logDecision(a.toolName, "deny", "approval outcome unknown");
          return deny(APPROVAL_UNAVAILABLE_DENY);
        }
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

/**
 * Pure state derivation for the durable approval card (#4672, wireframes 04, 05, 07). One function maps what the
 * server told the client (status, whether the agent is still inside its wait, the reply to this viewer's own decide,
 * the viewer's role) to exactly one of ten card states. Kept free of React so the whole matrix is unit-testable and so
 * the chat card and the away-user landing page cannot disagree about what a status means.
 *
 * Honesty rules baked in (single-user-incident class):
 *   - `released` ("Released, your agent is continuing") is reachable only from `consumed`, or from `approved` while the
 *     server says the agent is still waiting. A late approval (the agent stopped waiting) is `approved_late`: the card
 *     tells the Owner to ask again and never claims the agent is continuing.
 *   - No state claims an outcome (sent, ran, executed, delivered): slice 1 records only a release.
 *   - Details removed wins over every status: with no stored text there is nothing to approve.
 */

import type { ApprovalDecideOutcomeWire, ApprovalWireStatus } from "@/lib/types";

export type ApprovalCardState =
  | "pending_owner"
  | "pending_member"
  | "released"
  | "approved_late"
  | "denied"
  | "expired"
  | "expired_after_approval"
  | "already_decided"
  | "conversation_closed"
  | "details_removed";

export interface ApprovalCardStateInput {
  status: ApprovalWireStatus;
  viewerRole: "owner" | "member";
  /** True while the agent is inside its in-session wait. */
  agentWaiting: boolean;
  /** The server's reply to THIS viewer's own decide, when there was one. */
  decideOutcome?: ApprovalDecideOutcomeWire;
  /** The stored action text was removed by the retention scrub (or never verifiable): no details, no buttons. */
  detailsRemoved?: boolean;
  /** Expired after the Owner approved it and the agent never asked again (landing/inbox only; the wire cannot tell). */
  expiredAfterApproval?: boolean;
}

export function deriveApprovalCardState(i: ApprovalCardStateInput): ApprovalCardState {
  if (i.detailsRemoved) return "details_removed";
  if (i.decideOutcome === "closed") return "conversation_closed";
  if (i.decideOutcome === "conflict") return "already_decided";
  switch (i.status) {
    case "rejected":
      return "denied";
    case "consumed":
      return "released";
    case "approved":
      return i.agentWaiting ? "released" : "approved_late";
    case "expired":
      return i.expiredAfterApproval ? "expired_after_approval" : "expired";
    case "pending":
      return i.viewerRole === "owner" ? "pending_owner" : "pending_member";
  }
}

/** States in which the Owner can still decide (the only states that render Approve and Deny). */
export function isDecidable(state: ApprovalCardState, viewerRole: "owner" | "member"): boolean {
  return state === "pending_owner" && viewerRole === "owner";
}

const SINGLE_USE_PREFIX = "One-time · this exact ";

/** "email", "commits", ... from the server-built single-use line; "request" when the shape is unexpected. */
export function nounFromSingleUse(singleUse: string): string {
  return singleUse.startsWith(SINGLE_USE_PREFIX) && singleUse.length > SINGLE_USE_PREFIX.length
    ? singleUse.slice(SINGLE_USE_PREFIX.length)
    : "request";
}

/**
 * The pending request older than a newer pending request for the same conversation and tool shows a render-time banner
 * (wireframe 04L): parallel same-tool calls are legitimate, so nothing is superseded, the older card stays decidable and
 * always shows its own exact action.
 */
export function hasNewerPendingRequest(
  messages: ReadonlyArray<{ type?: string; approvalId?: string; toolName?: string; conversationId?: string; status?: string }>,
  index: number,
): boolean {
  const me = messages[index];
  if (!me || me.type !== "approval_request" || me.status !== "pending") return false;
  for (let j = index + 1; j < messages.length; j++) {
    const m = messages[j];
    if (
      m.type === "approval_request" &&
      m.status === "pending" &&
      m.toolName === me.toolName &&
      m.conversationId === me.conversationId &&
      m.approvalId !== me.approvalId
    ) {
      return true;
    }
  }
  return false;
}

/** Minutes the agent waits in-session for a decision. Lockstep with `DEFAULT_WAIT_MS` in server/approval/waiters.ts (pinned by a test). */
export const AGENT_WAIT_MINUTES = 5;

// Bidi embedding/override/isolate controls, Arabic letter mark, zero-width characters and the BOM: invisible, and a
// right-to-left override inside a recipient or a branch name can make a different value LOOK like the one the Owner
// expects. The card never hides or drops them (the bound value is shown exactly); it makes them visible instead.
const INVISIBLE_RE = /[‪-‮⁦-⁩؜​-‍﻿]/g;

/** Replace invisible direction/zero-width controls with a visible `<U+XXXX>` marker; everything else is untouched. */
export function revealInvisibleChars(s: string): string {
  return s.replace(INVISIBLE_RE, (c) => `<U+${c.codePointAt(0)!.toString(16).toUpperCase().padStart(4, "0")}>`);
}

/** Past this many lines a long block scrolls inside the card with a visible "N more lines" marker (wireframe note 2). */
export const BLOCK_VISIBLE_LINES = 14;

/**
 * The away-user landing page (HTTP, no live socket) cannot see the agent's wait, so it infers it from the row: the agent
 * waits one `AGENT_WAIT_MINUTES` window from the request's creation. A pending request is "still waited on" inside the
 * window; an approved one counts as released when the decision landed inside it. This is a heuristic with one failure
 * mode (the agent session ended inside the window), documented here so nobody mistakes it for server truth: the chat
 * card uses the server-sent `agentWaiting` instead.
 */
export function inferAgentWaiting(row: { created_at: string; decided_at: string | null }, nowMs: number): boolean {
  const created = Date.parse(row.created_at);
  if (Number.isNaN(created)) return false;
  const reference = row.decided_at ? Date.parse(row.decided_at) : nowMs;
  if (Number.isNaN(reference)) return false;
  return reference < created + AGENT_WAIT_MINUTES * 60_000;
}

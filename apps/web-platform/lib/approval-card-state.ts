/**
 * Pure state derivation for the durable approval card (#4672, wireframes 04, 05, 07). One function maps what the
 * server told the client (status, whether the agent is still inside its wait, the reply to this viewer's own decide,
 * the viewer's role) to exactly one of eleven card states. Kept free of React so the whole matrix is unit-testable and so
 * the chat card and the away-user landing page share one definition of what a status means. They differ in ONE input
 * only: the chat card gets `agentWaiting` from the server (a live waiter exists in the agent process); the landing page
 * has no live socket and always passes `false`, so it can never claim the agent is continuing.
 *
 * Honesty rules baked in (single-user-incident class):
 *   - `released` is reachable only from `consumed` (server truth: the agent's repeat was let through), or from
 *     `approved` while the server says the agent is still waiting. An approved request nobody is waiting on is
 *     `approved_late`: the card tells the Owner to ask again and never claims the agent is continuing.
 *   - No state claims an outcome (sent, ran, executed, delivered): slice 1 records only a release.
 *   - Details removed wins over every status: with no stored text there is nothing to approve.
 *   - An approved, unconsumed request can be revoked by its Owner (`deny` on an approved row): the result is `revoked`.
 */

import { AGENT_WAIT_MINUTES } from "@/lib/approval-copy";
import type { ApprovalDecideOutcomeWire, ApprovalWireStatus } from "@/lib/types";

export { AGENT_WAIT_MINUTES };

export type ApprovalCardState =
  | "pending_owner"
  | "pending_member"
  | "released"
  | "approved_late"
  | "denied"
  | "revoked"
  | "expired"
  | "expired_after_approval"
  | "already_decided"
  | "conversation_closed"
  | "details_removed";

export interface ApprovalCardStateInput {
  status: ApprovalWireStatus;
  viewerRole: "owner" | "member";
  /** True while the agent is inside its in-session wait. Server truth on the chat card; always false on the landing page. */
  agentWaiting: boolean;
  /** The server's reply to THIS viewer's own decide, when there was one. */
  decideOutcome?: ApprovalDecideOutcomeWire;
  /** The stored action text was removed by the retention scrub (or never verifiable): no details, no buttons. */
  detailsRemoved?: boolean;
  /** Expired after the Owner approved it and the agent never asked again (landing/inbox only; the wire cannot tell). */
  expiredAfterApproval?: boolean;
  /** A rejected request that was an approval an Owner took back (landing/inbox only; the live wire says `revoked` as an outcome). */
  revoked?: boolean;
}

export function deriveApprovalCardState(i: ApprovalCardStateInput): ApprovalCardState {
  if (i.detailsRemoved) return "details_removed";
  if (i.decideOutcome === "closed") return "conversation_closed";
  // A conflict on a request that was meanwhile used is not a lost race the Owner needs explained: it was released.
  if (i.decideOutcome === "conflict" && i.status !== "consumed") return "already_decided";
  if (i.decideOutcome === "already_decided") return "already_decided";
  if (i.decideOutcome === "revoked" && i.status === "rejected") return "revoked";
  switch (i.status) {
    case "rejected":
      return i.revoked ? "revoked" : "denied";
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

/**
 * States in which the Owner can take an approval back: the request is approved and the agent has not used it yet.
 * `released` also covers a consumed row, so the status is checked as well: a used approval cannot be revoked.
 */
export function isRevocable(state: ApprovalCardState, status: ApprovalWireStatus, viewerRole: "owner" | "member"): boolean {
  return viewerRole === "owner" && status === "approved" && (state === "released" || state === "approved_late");
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

// Characters that render as nothing (or reorder what is around them): bidi embedding/override/isolate controls
// (U+202A-202E, U+2066-2069), the Arabic letter mark (U+061C), zero-width and directional marks (U+200B-200F), the word
// joiner and invisible operators (U+2060-2064), the soft hyphen (U+00AD), the Mongolian vowel separator (U+180E), the
// BOM (U+FEFF) and the tag characters (U+E0000-E007F). A right-to-left override inside a recipient or a branch name can
// make a different value LOOK like the one the Owner expects. Written with escapes only, so the source never contains
// the characters themselves (cq-regex-unicode-separators-escape-only). The `u` flag is required for the astral range.
const INVISIBLE_RE = /[\u202A-\u202E\u2066-\u2069\u061C\u200B-\u200F\u2060-\u2064\u00AD\u180E\uFEFF\u{E0000}-\u{E007F}]/gu;

/**
 * Replace invisible direction/zero-width controls with a visible `<U+XXXX>` marker; everything else is untouched. The
 * card never hides or drops them (the bound value is shown exactly); it makes them visible instead. The same helper
 * renders the inbox row title.
 */
export function revealInvisible(text: string): string {
  return text.replace(INVISIBLE_RE, (c) => `<U+${c.codePointAt(0)!.toString(16).toUpperCase().padStart(4, "0")}>`);
}

/** Past this many lines a long block scrolls inside the card with a visible "N more lines" marker (wireframe note 2). */
export const BLOCK_VISIBLE_LINES = 14;

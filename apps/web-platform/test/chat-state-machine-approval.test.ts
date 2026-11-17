/**
 * #4672 — the reducer arms for durable approval cards. Upsert by approval id (reattach re-sends are idempotent), a new
 * card settles mid-turn bubbles like a review gate, a status frame folds into the card, and a stale re-send never walks a
 * terminal status back. Also pins the wire card view to the server's `ApprovalView` in both directions.
 */
import { describe, expect, test } from "vitest";
import { applyStreamEvent, type ChatMessage } from "../lib/chat-state-machine";
import type { ApprovalCardView, ApprovalDecideOutcomeWire, WSMessage } from "../lib/types";
import type { ApprovalView } from "../server/approval/render";
import type { DomainLeaderId } from "../server/domain-leaders";

const APPROVAL_ID = "00000000-0000-4000-8000-000000000006";
const CONV = "00000000-0000-4000-8000-000000000003";

// Type pin: the structural wire view and the server view are assignable both ways, so neither can drift.
const _serverToWire = (v: ApprovalView): ApprovalCardView => v;
const _wireToServer = (v: ApprovalCardView): Omit<ApprovalView, "tool"> => v;
void _serverToWire;
void _wireToServer;

const view: ApprovalCardView = {
  tool: "mcp__soleur_platform__email_send",
  title: "Your agent wants to send an email",
  verbPhrase: "send an email",
  fields: [{ label: "To", value: "maria@example.test", kind: "text" }],
  consequence: "Your agent can send an email once, if you ask it to try again. Valid in this conversation only.",
  singleUse: "One-time · this exact email",
  noun: "email",
  approveLabel: "Approve",
  denyLabel: "Deny",
  danger: false,
};

type Req = Extract<WSMessage, { type: "approval_request" }>;
const req = (over: Partial<Req> = {}): Req => ({
  type: "approval_request",
  approvalId: APPROVAL_ID,
  conversationId: CONV,
  toolName: view.tool,
  view,
  status: "pending",
  expiresAt: "2030-01-01T00:00:00.000Z",
  requestCount: 1,
  viewerRole: "owner",
  ...over,
});
const status = (s: "pending" | "approved" | "rejected" | "expired" | "consumed", outcome?: ApprovalDecideOutcomeWire): Extract<WSMessage, { type: "approval_status" }> => ({
  type: "approval_status",
  approvalId: APPROVAL_ID,
  conversationId: CONV,
  status: s,
  ...(outcome ? { outcome } : {}),
});

const streams = (e: [string, string][] = []) => new Map(e as [DomainLeaderId, string][]);
const thinking: ChatMessage = { id: "stream-cpo-1", role: "assistant", content: "", type: "text", leaderId: "cpo" as DomainLeaderId, state: "thinking" };

describe("approval_request", () => {
  test("appends a card keyed by approval id and settles a mid-turn bubble (no stuck Working badge)", () => {
    const r = applyStreamEvent([thinking], streams([["cpo", "stream-cpo-1"]]), req());
    expect(r.messages).toHaveLength(2);
    expect(r.messages[0]).toMatchObject({ type: "text", state: "done" });
    expect(r.messages[1]).toMatchObject({
      id: `approval-${APPROVAL_ID}`,
      type: "approval_request",
      approvalId: APPROVAL_ID,
      status: "pending",
      viewerRole: "owner",
      requestCount: 1,
    });
    expect(r.activeStreams.size).toBe(0);
    expect(r.timerAction).toEqual({ type: "clear_all" });
  });

  test("a re-send for the same request updates the card in place and never stacks a duplicate", () => {
    const first = applyStreamEvent([], streams(), req());
    const second = applyStreamEvent(first.messages, first.activeStreams, req({ requestCount: 3, status: "approved" }));
    expect(second.messages.filter((m) => m.type === "approval_request")).toHaveLength(1);
    expect(second.messages[0]).toMatchObject({ requestCount: 3, status: "approved" });
  });

  test("a stale re-send never walks a terminal status back to pending", () => {
    const r1 = applyStreamEvent([], streams(), req());
    const r2 = applyStreamEvent(r1.messages, r1.activeStreams, status("rejected"));
    const r3 = applyStreamEvent(r2.messages, r2.activeStreams, req());
    expect(r3.messages[0]).toMatchObject({ status: "rejected" });
  });

  test("two different requests make two cards", () => {
    const a = applyStreamEvent([], streams(), req());
    const b = applyStreamEvent(a.messages, a.activeStreams, req({ approvalId: "00000000-0000-4000-8000-0000000000cc" }));
    expect(b.messages.filter((m) => m.type === "approval_request")).toHaveLength(2);
  });
});

describe("approval_status", () => {
  test("folds the status and the outcome of this socket's own decide into the card", () => {
    const a = applyStreamEvent([], streams(), req());
    const b = applyStreamEvent(a.messages, a.activeStreams, status("approved", "decided"));
    expect(b.messages[0]).toMatchObject({ type: "approval_request", status: "approved", decideOutcome: "decided" });
  });

  test("a later status without an outcome keeps the outcome the card already holds", () => {
    const a = applyStreamEvent([], streams(), req());
    const b = applyStreamEvent(a.messages, a.activeStreams, status("rejected", "conflict"));
    const c = applyStreamEvent(b.messages, b.activeStreams, status("rejected"));
    expect(c.messages[0]).toMatchObject({ decideOutcome: "conflict" });
  });

  test("a revoke folds into the card as rejected + revoked, and a stale approved re-send does not walk it back", () => {
    const a = applyStreamEvent([], streams(), req({ status: "approved" }));
    const b = applyStreamEvent(a.messages, a.activeStreams, status("rejected", "revoked"));
    expect(b.messages[0]).toMatchObject({ type: "approval_request", status: "rejected", decideOutcome: "revoked" });
    const c = applyStreamEvent(b.messages, b.activeStreams, req({ status: "approved", agentWaiting: true }));
    expect(c.messages[0]).toMatchObject({ status: "rejected", decideOutcome: "revoked", agentWaiting: false });
  });

  test("an unusable flag on a status frame is folded into the card and survives a later frame that omits it", () => {
    const a = applyStreamEvent([], streams(), req({ status: "approved" }));
    const b = applyStreamEvent(a.messages, a.activeStreams, { ...status("approved"), agentWaiting: false, unusable: true });
    expect(b.messages[0]).toMatchObject({ status: "approved", approvalUnusable: true });
    const c = applyStreamEvent(b.messages, b.activeStreams, status("approved"));
    expect(c.messages[0]).toMatchObject({ approvalUnusable: true });
  });

  test("a status for an unknown approval is a no-op", () => {
    const base: ChatMessage[] = [thinking];
    const r = applyStreamEvent(base, streams(), status("approved"));
    expect(r.messages).toBe(base);
  });

  test("a status frame never touches a review gate card that happens to carry the same id", () => {
    const gate: ChatMessage = { id: `gate-${APPROVAL_ID}`, role: "assistant", content: "q", type: "review_gate", gateId: APPROVAL_ID, question: "q", options: ["Approve", "Reject"] };
    const r = applyStreamEvent([gate], streams(), status("approved"));
    expect(r.messages[0]).toBe(gate);
  });
});

describe("agentWaiting (honest approved states, wireframes 04C vs 04D)", () => {
  test("a card carries the server's wait flag; absent means the agent is NOT waiting (the safe reading)", () => {
    const waiting = applyStreamEvent([], streams(), req({ agentWaiting: true }));
    expect(waiting.messages[0]).toMatchObject({ agentWaiting: true });
    const absent = applyStreamEvent([], streams(), req());
    expect(absent.messages[0]).toMatchObject({ agentWaiting: false });
  });

  test("a status frame updates the wait flag when it carries one and keeps it when it does not", () => {
    const a = applyStreamEvent([], streams(), req({ agentWaiting: true }));
    const b = applyStreamEvent(a.messages, a.activeStreams, { ...status("pending"), agentWaiting: false });
    expect(b.messages[0]).toMatchObject({ agentWaiting: false, status: "pending" });
    const c = applyStreamEvent(a.messages, a.activeStreams, status("approved"));
    expect(c.messages[0]).toMatchObject({ agentWaiting: true, status: "approved" });
  });

  test("a stale re-send of a card whose request already reached a terminal status is not 'waiting'", () => {
    const a = applyStreamEvent([], streams(), req({ agentWaiting: true }));
    const b = applyStreamEvent(a.messages, a.activeStreams, status("rejected"));
    const c = applyStreamEvent(b.messages, b.activeStreams, req({ agentWaiting: true }));
    expect(c.messages[0]).toMatchObject({ status: "rejected", agentWaiting: false });
  });

  test("a re-send keeps the outcome of this socket's own decide (a conflict does not vanish on reattach)", () => {
    const a = applyStreamEvent([], streams(), req());
    const b = applyStreamEvent(a.messages, a.activeStreams, status("approved", "conflict"));
    const c = applyStreamEvent(b.messages, b.activeStreams, req({ status: "approved" }));
    expect(c.messages[0]).toMatchObject({ decideOutcome: "conflict" });
  });
});

describe("approval_request: withheld view and requester label (#9601)", () => {
  const WAITING = "An action in this conversation is waiting for an Owner's approval.";
  const redacted = (over: Partial<Req> = {}): Req => req({ view: null, toolName: "redacted", viewerRole: "member", ...over });
  const cardOf = (r: { messages: ChatMessage[] }) => r.messages.find((m) => m.type === "approval_request") as Extract<ChatMessage, { type: "approval_request" }>;

  test("a null view builds a card whose content is the fixed waiting copy (no action text)", () => {
    const r = applyStreamEvent([], streams(), redacted());
    const c = cardOf(r);
    expect(c.view).toBeNull();
    expect(c.content).toBe(WAITING);
    expect(c.toolName).toBe("redacted");
    expect(c.viewerRole).toBe("member");
    expect(JSON.stringify(c)).not.toContain("maria@example.test");
  });

  test("a full frame still uses the view title as content", () => {
    expect(cardOf(applyStreamEvent([], streams(), req())).content).toBe(view.title);
  });

  test("the requester label survives the reducer into the message (fresh card)", () => {
    expect(cardOf(applyStreamEvent([], streams(), req({ requester: "jane@example.com" }))).requester).toBe("jane@example.com");
    expect(cardOf(applyStreamEvent([], streams(), req({ requester: "you" }))).requester).toBe("you");
  });

  test("a frame without a requester carries no requester key", () => {
    expect(Object.hasOwn(cardOf(applyStreamEvent([], streams(), req())), "requester")).toBe(false);
  });

  test("the requester label survives an upsert, and a later frame without one clears the stale label", () => {
    const first = applyStreamEvent([], streams(), req({ requester: "jane@example.com" }));
    const second = applyStreamEvent(first.messages, first.activeStreams, req({ requester: "a workspace member" }));
    expect(cardOf(second).requester).toBe("a workspace member");
    const third = applyStreamEvent(second.messages, second.activeStreams, req());
    expect(cardOf(third).requester).toBeUndefined();
    expect(Object.hasOwn(cardOf(third), "requester")).toBe(false);
  });

  test("a redacted card is upgraded in place by a later full frame (one card, Approve-able Owner state)", () => {
    const first = applyStreamEvent([], streams(), redacted());
    const upgraded = applyStreamEvent(first.messages, first.activeStreams, req({ requester: "jane@example.com" }));
    expect(upgraded.messages.filter((m) => m.type === "approval_request")).toHaveLength(1);
    const c = cardOf(upgraded);
    expect(c.view).toEqual(view);
    expect(c.viewerRole).toBe("owner");
    expect(c.toolName).toBe(view.tool);
    expect(c.content).toBe(view.title);
    expect(c.requester).toBe("jane@example.com");
  });

  test("a full card replaced by a later redacted frame equals a freshly built redacted card (server's latest word wins; no leftover view, content or requester)", () => {
    const first = applyStreamEvent([], streams(), req({ requester: "jane@example.com" }));
    const replaced = applyStreamEvent(first.messages, first.activeStreams, redacted());
    const fresh = applyStreamEvent([], streams(), redacted());
    expect(cardOf(replaced)).toEqual(cardOf(fresh));
    expect(JSON.stringify(cardOf(replaced))).not.toContain("maria@example.test");
    expect(JSON.stringify(cardOf(replaced))).not.toContain("jane@example.com");
  });

  test("a redacted card stays pending after a decided request until expiry: no status frame reaches it, and a re-send of a redacted frame keeps it pending", () => {
    const first = applyStreamEvent([], streams(), redacted());
    const again = applyStreamEvent(first.messages, first.activeStreams, redacted());
    expect(cardOf(again).status).toBe("pending");
    expect(cardOf(again).content).toBe(WAITING);
  });

  test("two redacted cards share the toolName 'redacted', so the newer-request match is true; the banner itself renders only in pending_owner (card test)", async () => {
    const { hasNewerPendingRequest } = await import("../lib/approval-card-state");
    const a = applyStreamEvent([], streams(), redacted({ approvalId: "00000000-0000-4000-8000-0000000000b1" }));
    const b = applyStreamEvent(a.messages, a.activeStreams, redacted({ approvalId: "00000000-0000-4000-8000-0000000000b2" }));
    expect(hasNewerPendingRequest(b.messages, 0)).toBe(true);
  });
});

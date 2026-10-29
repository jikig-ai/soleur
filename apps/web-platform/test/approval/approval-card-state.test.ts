import { describe, expect, it } from "vitest";
import {
  deriveApprovalCardState,
  hasNewerPendingRequest,
  inferAgentWaiting,
  isDecidable,
  nounFromSingleUse,
  revealInvisibleChars,
  type ApprovalCardStateInput,
} from "@/lib/approval-card-state";

const base: ApprovalCardStateInput = { status: "pending", viewerRole: "owner", agentWaiting: false };
const d = (o: Partial<ApprovalCardStateInput>) => deriveApprovalCardState({ ...base, ...o });

describe("deriveApprovalCardState (wireframes 04, 05)", () => {
  it("pending: the Owner decides, a member waits read-only", () => {
    expect(d({})).toBe("pending_owner");
    expect(d({ viewerRole: "member" })).toBe("pending_member");
  });

  it("approved splits in two: released only while the agent still waits, otherwise ask again (04C vs 04D)", () => {
    expect(d({ status: "approved", agentWaiting: true })).toBe("released");
    expect(d({ status: "approved", agentWaiting: false })).toBe("approved_late");
  });

  it("consumed is released regardless of the wait flag", () => {
    expect(d({ status: "consumed", agentWaiting: false })).toBe("released");
  });

  it("rejected is denied; expired splits on whether it was approved first (04F vs 04H)", () => {
    expect(d({ status: "rejected" })).toBe("denied");
    expect(d({ status: "expired" })).toBe("expired");
    expect(d({ status: "expired", expiredAfterApproval: true })).toBe("expired_after_approval");
  });

  it("the reply to this viewer's own decide wins over the status (loser state, closed conversation)", () => {
    expect(d({ status: "approved", decideOutcome: "conflict" })).toBe("already_decided");
    expect(d({ status: "pending", decideOutcome: "closed" })).toBe("conversation_closed");
    expect(d({ status: "approved", decideOutcome: "decided", agentWaiting: false })).toBe("approved_late");
  });

  it("removed details win over every status (nothing to approve)", () => {
    for (const status of ["pending", "approved", "rejected", "expired", "consumed"] as const) {
      expect(d({ status, detailsRemoved: true })).toBe("details_removed");
    }
  });

  it("only the Owner's pending state is decidable", () => {
    expect(isDecidable("pending_owner", "owner")).toBe(true);
    expect(isDecidable("pending_member", "member")).toBe(false);
    expect(isDecidable("pending_owner", "member")).toBe(false);
    expect(isDecidable("approved_late", "owner")).toBe(false);
  });
});

describe("helpers", () => {
  it("extracts the noun from the server-built single-use line, with a safe fallback", () => {
    expect(nounFromSingleUse("One-time · this exact email")).toBe("email");
    expect(nounFromSingleUse("One-time · this exact pull request")).toBe("pull request");
    expect(nounFromSingleUse("something else")).toBe("request");
    expect(nounFromSingleUse("One-time · this exact ")).toBe("request");
  });

  it("makes direction and zero-width controls visible instead of dropping them", () => {
    expect(revealInvisibleChars("a‮b")).toBe("a<U+202E>b");
    expect(revealInvisibleChars("x​y﻿z")).toBe("x<U+200B>y<U+FEFF>z");
    expect(revealInvisibleChars("plain text, é, 日本")).toBe("plain text, é, 日本");
  });

  it("infers the agent's wait on the landing page from the row, as a documented heuristic", () => {
    const created = "2026-10-28T10:00:00Z";
    const at = (iso: string) => Date.parse(iso);
    expect(inferAgentWaiting({ created_at: created, decided_at: null }, at("2026-10-28T10:04:59Z"))).toBe(true);
    expect(inferAgentWaiting({ created_at: created, decided_at: null }, at("2026-10-28T10:05:01Z"))).toBe(false);
    // an approval that landed inside the window counts as released even when read much later
    expect(inferAgentWaiting({ created_at: created, decided_at: "2026-10-28T10:02:00Z" }, at("2026-10-29T10:00:00Z"))).toBe(true);
    expect(inferAgentWaiting({ created_at: created, decided_at: "2026-10-28T10:09:00Z" }, at("2026-10-29T10:00:00Z"))).toBe(false);
    expect(inferAgentWaiting({ created_at: "nope", decided_at: null }, 0)).toBe(false);
  });
});

describe("newer-request banner (04L): parallel same-tool requests are legitimate, nothing is superseded", () => {
  const card = (id: string, status: string, tool = "t1", conv = "c1") => ({ type: "approval_request", approvalId: id, toolName: tool, conversationId: conv, status });
  it("an older pending card sees a later pending card for the same tool and conversation", () => {
    const msgs = [card("a", "pending"), { type: "text" }, card("b", "pending")];
    expect(hasNewerPendingRequest(msgs, 0)).toBe(true);
    expect(hasNewerPendingRequest(msgs, 2)).toBe(false);
  });
  it("a different tool, a different conversation or a non-pending newer card does not trigger it", () => {
    expect(hasNewerPendingRequest([card("a", "pending"), card("b", "pending", "t2")], 0)).toBe(false);
    expect(hasNewerPendingRequest([card("a", "pending"), card("b", "pending", "t1", "c2")], 0)).toBe(false);
    expect(hasNewerPendingRequest([card("a", "pending"), card("b", "rejected")], 0)).toBe(false);
  });
  it("a resolved older card never shows the banner", () => {
    expect(hasNewerPendingRequest([card("a", "approved"), card("b", "pending")], 0)).toBe(false);
  });
});

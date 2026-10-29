import { describe, expect, it } from "vitest";
import {
  deriveApprovalCardState,
  hasNewerPendingRequest,
  isDecidable,
  isRevocable,
  revealInvisible,
  type ApprovalCardStateInput,
} from "@/lib/approval-card-state";

const base: ApprovalCardStateInput = { status: "pending", viewerRole: "owner", agentWaiting: false };
const d = (o: Partial<ApprovalCardStateInput>) => deriveApprovalCardState({ ...base, ...o });

describe("deriveApprovalCardState (wireframes 04, 05)", () => {
  it("pending: the Owner decides, a member waits read-only", () => {
    expect(d({})).toBe("pending_owner");
    expect(d({ viewerRole: "member" })).toBe("pending_member");
  });

  it("the landing page (agentWaiting always false) never reaches released from an approved row", () => {
    expect(d({ status: "approved", agentWaiting: false })).toBe("approved_late");
    expect(d({ status: "approved", agentWaiting: false, decideOutcome: "decided" })).toBe("approved_late");
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

describe("revoke and the loser states", () => {
  it("a revoked request is its own state, from the live outcome or from the row", () => {
    expect(d({ status: "rejected", decideOutcome: "revoked" })).toBe("revoked");
    expect(d({ status: "rejected", revoked: true })).toBe("revoked");
    expect(d({ status: "rejected" })).toBe("denied");
  });

  it("revoke is offered only to an Owner on an approved, unconsumed request", () => {
    expect(isRevocable("approved_late", "approved", "owner")).toBe(true);
    expect(isRevocable("released", "approved", "owner")).toBe(true);
    expect(isRevocable("released", "consumed", "owner")).toBe(false);
    expect(isRevocable("approved_late", "approved", "member")).toBe(false);
    for (const st of ["pending", "rejected", "expired"] as const) expect(isRevocable("denied", st, "owner")).toBe(false);
  });

  it("a conflict on a request that was meanwhile used is released; any other conflict is the loser state", () => {
    expect(d({ status: "consumed", decideOutcome: "conflict" })).toBe("released");
    expect(d({ status: "rejected", decideOutcome: "conflict" })).toBe("already_decided");
    expect(d({ status: "approved", decideOutcome: "already_decided" })).toBe("already_decided");
  });
});

describe("revealInvisible (cq-regex-unicode-separators-escape-only)", () => {
  const ch = (...cps: number[]) => String.fromCodePoint(...cps);

  it("makes direction and zero-width controls visible instead of dropping them", () => {
    expect(revealInvisible(`a${ch(0x202e)}b`)).toBe("a<U+202E>b");
    expect(revealInvisible(`x${ch(0x200b)}y${ch(0xfeff)}z`)).toBe("x<U+200B>y<U+FEFF>z");
    expect(revealInvisible("plain text, \u00e9, \u65e5\u672c")).toBe("plain text, \u00e9, \u65e5\u672c");
  });

  it("covers every range the review named: bidi embeddings and isolates, marks, invisible operators, soft hyphen, tags", () => {
    const cps = [
      0x202a, 0x202b, 0x202c, 0x202d, 0x202e, // embeddings and overrides
      0x2066, 0x2067, 0x2068, 0x2069, // isolates
      0x061c, // Arabic letter mark
      0x200b, 0x200c, 0x200d, 0x200e, 0x200f, // zero-width and directional marks
      0x2060, 0x2061, 0x2062, 0x2063, 0x2064, // word joiner and invisible operators
      0x00ad, 0x180e, 0xfeff, // soft hyphen, Mongolian vowel separator, BOM
      0xe0000, 0xe0041, 0xe007f, // tag characters (astral)
    ];
    for (const cp of cps) {
      const hex = cp.toString(16).toUpperCase().padStart(4, "0");
      expect(revealInvisible(`a${ch(cp)}b`), `U+${hex}`).toBe(`a<U+${hex}>b`);
    }
  });

  it("leaves neighbours of the ranges alone, and never touches visible text (emoji, CJK, accents)", () => {
    for (const cp of [0x2029, 0x202f, 0x2065, 0x206a, 0x061b, 0x061d, 0x00ac, 0x00ae, 0x180d, 0x180f, 0xfefe, 0xe007f + 1, 0xdfff + 1]) {
      expect(revealInvisible(`a${ch(cp)}b`), `U+${cp.toString(16)}`).toBe(`a${ch(cp)}b`);
    }
    expect(revealInvisible(ch(0x1f600) + "caf\u00e9")).toBe(ch(0x1f600) + "caf\u00e9");
  });

  it("the source of this module holds no raw invisible character (escapes only)", async () => {
    const { readFileSync } = await import("node:fs");
    const src = readFileSync(new URL("../../lib/approval-card-state.ts", import.meta.url), "utf8");
    // eslint-disable-next-line no-misleading-character-class
    expect(src).not.toMatch(new RegExp("[\\u202A-\\u202E\\u2066-\\u2069\\u061C\\u200B-\\u200F\\u2060-\\u2064\\u00AD\\u180E\\uFEFF]|[\\u{E0000}-\\u{E007F}]", "u"));
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

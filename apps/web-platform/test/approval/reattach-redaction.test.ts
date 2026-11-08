/**
 * #9601 (ADR-309 flip item 1, limbs i and ii): `reemitLiveApprovals` sends the full card only to a verified Owner or the
 * row's verified requester; every other attaching member gets a redacted waiting frame with NO field value; an Owner's card
 * names the requester.
 *
 * Drives the REAL `reemitLiveApprovals` and the real canonical/hash code, injecting only the DB client, the role read, the
 * flag, `send` and the labeler seam (never a redactor). The assertions run on the SERIALIZED frame the client receives.
 * Synthesized @example.com data only.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({ report: vi.fn() }));
vi.mock("@/server/approval/ops", async (orig) => ({
  ...(await orig<typeof import("@/server/approval/ops")>()),
  reportApprovalOp: (...a: unknown[]) => h.report(...a),
}));

import { canonicalizeAction, computeActionHash } from "@/server/approval/canonical";
import { reemitLiveApprovals, type ReemitArgs } from "@/server/approval/reattach";
import { createRequesterLabeler, type RequesterQueryClient } from "@/server/approval/requester-label";
import type { ApprovalRpcClient } from "@/server/approval/service";
import type { WSMessage } from "@/lib/types";
import {
  CANARIES,
  CONVERSATION_ID,
  EMAIL_TOOL,
  MEMBER_ID,
  OTHER_MEMBER_ID,
  OTHER_WORKSPACE_ID,
  OWNER_ID,
  REQUESTER_EMAIL,
  REQUESTER_ID,
  SHA40,
  TOOLS,
  WORKSPACE_ID,
  expectNoLeak,
  makeLabelerClient,
  type FakeLabelerWorld,
} from "./fixtures";

type ApprovalFrame = Extract<WSMessage, { type: "approval_request" }>;
const FALLBACK = "a workspace member";
const ROW_A = "00000000-0000-4000-8000-0000000000b1";
const ROW_B = "00000000-0000-4000-8000-0000000000b2";
const ROW_C = "00000000-0000-4000-8000-0000000000b3";

const emailInput = {
  to: `${CANARIES.to}@example.com`,
  subject: `Subject ${CANARIES.subject}`,
  body: `Hello, ${CANARIES.body}`,
  replyTo: `${CANARIES.replyTo}@example.com`,
  jurisdiction: "us",
  postalAddress: `1 ${CANARIES.postalAddress} Street`,
};
const ALL_CANARIES = [CANARIES.to, CANARIES.subject, CANARIES.body, CANARIES.replyTo, CANARIES.postalAddress];

interface RowSpec {
  id?: string;
  tool?: string;
  requestedBy?: string | null | undefined;
  status?: "pending" | "approved";
  workspaceId?: string;
  /** The live-request count for the conversation and action (default 1: one live request, so a label may be shown). */
  requestCount?: number;
}

function buildRow(spec: RowSpec = {}) {
  const tool = spec.tool ?? EMAIL_TOOL;
  const workspaceId = spec.workspaceId ?? WORKSPACE_ID;
  const action =
    tool === TOOLS.pushBranch
      ? canonicalizeAction(tool, { branch: CANARIES.branch, force: false }, { repo: `example-org/${CANARIES.repo}`, headSha: SHA40 })
      : canonicalizeAction(tool, emailInput, undefined);
  const row: Record<string, unknown> = {
    id: spec.id ?? ROW_A,
    workspace_id: workspaceId,
    conversation_id: CONVERSATION_ID,
    requested_by_user_id: "requestedBy" in spec ? spec.requestedBy : REQUESTER_ID,
    tool_name: tool,
    action_sha256: computeActionHash({ toolName: tool, workspaceId, conversationId: CONVERSATION_ID, action }),
    status: spec.status ?? "pending",
    expires_at: "2099-01-01T00:00:00.000Z",
    decided_at: null,
    decided_by: null,
    consumed_at: null,
    expired_at: null,
    revoked_at: null,
    revoked_by: null,
    unanswered_flagged_at: null,
    created_at: "2026-11-07T10:00:00.000Z",
    canonical_action: action,
  };
  if (spec.requestedBy === undefined && "requestedBy" in spec) delete row.requested_by_user_id;
  return { approval: row, request_count: spec.requestCount ?? 1 };
}

interface RunOpts {
  viewer: string;
  role: "owner" | "member" | "reject" | "garbage";
  rows: RowSpec[];
  /** The labeler seam; defaults to a spy returning the requester email. */
  label?: ReemitArgs["requesterLabel"];
  sessionWorkspaceId?: string;
  /** Overrides `role` per workspace id (the role read must be asked about the ROW's workspace). */
  roleByWorkspace?: Record<string, "owner" | "member">;
}

async function run(o: RunOpts) {
  const frames: WSMessage[] = [];
  const raw = o.rows.map(buildRow);
  const client: ApprovalRpcClient = { rpc: async () => ({ data: raw, error: null }) };
  const label = vi.fn(o.label ?? (async () => REQUESTER_EMAIL));
  const viewerRole = vi.fn(async (workspaceId: string) => {
    if (o.role === "reject") throw Object.assign(new Error("role read failed"), { code: "PGRST000" });
    if (o.roleByWorkspace) return o.roleByWorkspace[workspaceId] ?? "member";
    return o.role as "owner" | "member";
  });
  const sent = await reemitLiveApprovals({
    userId: o.viewer,
    conversationId: CONVERSATION_ID,
    workspaceId: o.sessionWorkspaceId ?? WORKSPACE_ID,
    send: (_u, p) => {
      frames.push(p);
      return true;
    },
    client: () => client,
    viewerRole,
    requesterLabel: label,
    isEnabled: async () => true,
  });
  const cards = frames.filter((f): f is ApprovalFrame => f.type === "approval_request");
  return { sent, frames, cards, label, viewerRole };
}

const reportKeys = () => h.report.mock.calls.map((c) => c[0] as string);
// The ops registry is mocked here, so the thrown value is handed over raw; the REAL helper reduces it to {code, fn, errName}
// (asserted against the real registry in requester-label.test.ts). What this file pins is what the call SITES put in the
// context: the key and the context object, serialized.
const reportContexts = () => JSON.stringify(h.report.mock.calls.map((c) => [c[0], c[2]]));

beforeEach(() => {
  h.report.mockReset();
});

describe("fixture and detector preconditions", () => {
  it("every canary is at least 12 ASCII-alphanumeric characters, distinct, and equal to no key name", () => {
    const values = Object.values(CANARIES);
    expect(new Set(values).size).toBe(values.length);
    for (const c of values) {
      expect(c).toMatch(/^[A-Za-z0-9]{12,}$/);
    }
    const keyNames = ["type", "approvalId", "conversationId", "toolName", "view", "status", "expiresAt", "requestCount", "viewerRole", "agentWaiting", "requester"];
    for (const c of values) expect(keyNames).not.toContain(c);
  });

  it("the detector is sensitive: it throws on a deliberately leaky frame and on an empty fixture", () => {
    expect(() => expectNoLeak({ type: "approval_request", note: `contains ${CANARIES.body} text` }, ALL_CANARIES)).toThrow(/leak/);
    expect(() => expectNoLeak({}, ALL_CANARIES)).toThrow(/vacuous/);
    expect(() => expectNoLeak({ type: "approval_request", view: null, padding: "x".repeat(40) }, [])).toThrow(/vacuous/);
    expect(() => expectNoLeak({ type: "approval_request", view: null, padding: "x".repeat(40) }, ALL_CANARIES)).not.toThrow();
  });
});

describe("an Owner attaching (positive controls)", () => {
  it("canary is present in the Owner frame", async () => {
    const { cards } = await run({ viewer: OWNER_ID, role: "owner", rows: [{}] });
    expect(cards).toHaveLength(1);
    const text = JSON.stringify(cards[0]);
    for (const c of ALL_CANARIES) expect(text, c).toContain(c);
    expect(cards[0].toolName).toBe(EMAIL_TOOL);
  });

  it("an Owner who is not the requester gets the full view, viewerRole owner and the requester's email", async () => {
    const { cards, label } = await run({ viewer: OWNER_ID, role: "owner", rows: [{}] });
    expect(cards[0].view).not.toBeNull();
    expect(cards[0].viewerRole).toBe("owner");
    expect(cards[0].requester).toBe(REQUESTER_EMAIL);
    expect(label).toHaveBeenCalledWith(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
  });

  it("an Owner who is the requester gets the full view and the literal you, with no lookup", async () => {
    const { cards, label } = await run({ viewer: OWNER_ID, role: "owner", rows: [{ requestedBy: OWNER_ID }] });
    expect(cards[0].view).not.toBeNull();
    expect(cards[0].requester).toBe("you");
    expect(label).not.toHaveBeenCalled();
  });

  it("an Owner and a NULL requester (erased account): the fixed fallback label, full view", async () => {
    const { cards } = await run({ viewer: OWNER_ID, role: "owner", rows: [{ requestedBy: null }], label: async () => FALLBACK });
    expect(cards[0].view).not.toBeNull();
    expect(cards[0].requester).toBe(FALLBACK);
  });

  it("the labeler is given the ROW's workspace, not the attaching session's", async () => {
    const { cards, label } = await run({
      viewer: OWNER_ID,
      role: "owner",
      sessionWorkspaceId: WORKSPACE_ID,
      rows: [{ workspaceId: OTHER_WORKSPACE_ID }],
    });
    expect(cards).toHaveLength(1);
    expect(label).toHaveBeenCalledTimes(1);
    expect(label.mock.calls[0][0]).toBe(OTHER_WORKSPACE_ID);
  });
});

describe("a member who is the requester (non-canonical input that must still pass)", () => {
  it("gets the full view, viewerRole member and the literal you; the labeler is never called", async () => {
    const { cards, label } = await run({ viewer: MEMBER_ID, role: "member", rows: [{ requestedBy: MEMBER_ID }] });
    expect(cards).toHaveLength(1);
    expect(cards[0].view).not.toBeNull();
    expect(cards[0].viewerRole).toBe("member");
    expect(cards[0].requester).toBe("you");
    expect(label).not.toHaveBeenCalled();
    expect(JSON.stringify(cards[0])).toContain(CANARIES.subject);
  });
});

describe("a member who is not the requester gets a redacted waiting frame", () => {
  it("view null, toolName redacted, no requester key, status/time/count/waiting fields present", async () => {
    const { cards, label } = await run({ viewer: MEMBER_ID, role: "member", rows: [{ requestCount: 2 }] });
    expect(cards).toHaveLength(1);
    const f = cards[0];
    expect(f.view).toBeNull();
    expect(f.toolName).toBe("redacted");
    expect(Object.hasOwn(f, "requester")).toBe(false);
    expect(f.status).toBe("pending");
    expect(f.expiresAt).toBe("2099-01-01T00:00:00.000Z");
    expect(f.requestCount).toBe(2);
    expect(f.viewerRole).toBe("member");
    expect(typeof f.agentWaiting).toBe("boolean");
    expect(label).not.toHaveBeenCalled();
  });

  it("the exact key set of the redacted frame", async () => {
    const { cards } = await run({ viewer: MEMBER_ID, role: "member", rows: [{}] });
    expect(Object.keys(cards[0]).sort()).toEqual(
      ["agentWaiting", "approvalId", "conversationId", "expiresAt", "requestCount", "status", "toolName", "type", "view", "viewerRole"].sort(),
    );
  });

  it.each(ALL_CANARIES)("the serialized frame does not contain the canary %s", async (canary) => {
    const { cards } = await run({ viewer: MEMBER_ID, role: "member", rows: [{}] });
    expect(JSON.stringify(cards[0])).not.toContain(canary);
  });

  it("no canonical field value, requester uuid, requester email or real tool name appears in the frame (email send)", async () => {
    const { cards } = await run({ viewer: MEMBER_ID, role: "member", rows: [{}] });
    const text = JSON.stringify(cards[0]);
    expect(() => expectNoLeak(cards[0], [...ALL_CANARIES, REQUESTER_ID, REQUESTER_EMAIL, EMAIL_TOOL, "example.com"])).not.toThrow();
    expect(text).not.toContain("email_send");
  });

  it("a push-branch row carries no repository, branch or tool name either", async () => {
    const { cards } = await run({ viewer: MEMBER_ID, role: "member", rows: [{ tool: TOOLS.pushBranch }] });
    expect(cards).toHaveLength(1);
    expect(() => expectNoLeak(cards[0], [CANARIES.branch, CANARIES.repo, "github_push_branch", SHA40])).not.toThrow();
    // Positive control for the same fixture: the Owner frame DOES contain them.
    const owner = await run({ viewer: OWNER_ID, role: "owner", rows: [{ tool: TOOLS.pushBranch }] });
    expect(JSON.stringify(owner.cards[0])).toContain(CANARIES.branch);
    expect(JSON.stringify(owner.cards[0])).toContain(CANARIES.repo);
  });

  it("a NULL requested_by_user_id: redacted for a member", async () => {
    const { cards } = await run({ viewer: MEMBER_ID, role: "member", rows: [{ requestedBy: null }] });
    expect(cards[0].view).toBeNull();
    expect(cards[0].toolName).toBe("redacted");
  });

  it("a row without the requested_by_user_id key at all (undefined): redacted for a member", async () => {
    const { cards } = await run({ viewer: MEMBER_ID, role: "member", rows: [{ requestedBy: undefined }] });
    expect(cards[0].view).toBeNull();
  });

  it("an empty-string requester with an empty-string attaching id: redacted (empty never equals empty)", async () => {
    const { cards } = await run({ viewer: "", role: "member", rows: [{ requestedBy: "" }] });
    expect(cards).toHaveLength(1);
    expect(cards[0].view).toBeNull();
    expect(cards[0].toolName).toBe("redacted");
    // RA5: the redacted frame carries no requester key at all (an empty string is not a verified requester).
    expect(Object.hasOwn(cards[0], "requester")).toBe(false);
  });

  it("a runtime-garbage role is a FAILED read, not a member: no frame for a non-requester, reported once", async () => {
    const { cards, sent } = await run({ viewer: MEMBER_ID, role: "garbage", rows: [{}, { id: ROW_B }] });
    expect(cards).toHaveLength(0);
    expect(sent).toBe(0);
    expect(reportKeys().filter((k) => k === "viewerRoleFailed")).toHaveLength(1);
  });

  it("a runtime-garbage role and the verified requester: the full read-only card as a member, the failure reported", async () => {
    const { cards, label } = await run({ viewer: MEMBER_ID, role: "garbage", rows: [{ requestedBy: MEMBER_ID }] });
    expect(cards).toHaveLength(1);
    expect(cards[0].view).not.toBeNull();
    expect(cards[0].viewerRole).toBe("member");
    expect(cards[0].requester).toBe("you");
    expect(label).not.toHaveBeenCalled();
    expect(reportKeys()).toContain("viewerRoleFailed");
  });
});

describe("a failed role read", () => {
  it("the verified requester keeps the full view as a member, and the failure is reported", async () => {
    const { cards } = await run({ viewer: MEMBER_ID, role: "reject", rows: [{ requestedBy: MEMBER_ID }] });
    expect(cards).toHaveLength(1);
    expect(cards[0].view).not.toBeNull();
    expect(cards[0].viewerRole).toBe("member");
    expect(reportKeys()).toContain("viewerRoleFailed");
  });

  it("a viewer who is not the verified requester gets NO frame at all (unequal ids), and the failure is reported", async () => {
    const { cards, sent } = await run({ viewer: OWNER_ID, role: "reject", rows: [{}] });
    expect(cards).toHaveLength(0);
    expect(sent).toBe(0);
    expect(reportKeys()).toContain("viewerRoleFailed");
  });

  it("a NULL requester and a failed role read: no frame", async () => {
    const { cards } = await run({ viewer: OWNER_ID, role: "reject", rows: [{ requestedBy: null }] });
    expect(cards).toHaveLength(0);
    expect(reportKeys()).toContain("viewerRoleFailed");
  });

  it("the report carries ids only", async () => {
    await run({ viewer: OWNER_ID, role: "reject", rows: [{}] });
    expect(reportContexts()).not.toContain(REQUESTER_EMAIL);
    for (const c of ALL_CANARIES) expect(reportContexts()).not.toContain(c);
  });
});

describe("several rows in one attach", () => {
  it("own row first, another member's row second: the first is full, the second is redacted", async () => {
    const { cards } = await run({
      viewer: MEMBER_ID,
      role: "member",
      rows: [
        { id: ROW_A, requestedBy: MEMBER_ID },
        { id: ROW_B, requestedBy: OTHER_MEMBER_ID },
      ],
    });
    expect(cards.map((c) => c.approvalId)).toEqual([ROW_A, ROW_B]);
    expect(cards[0].view).not.toBeNull();
    expect(cards[1].view).toBeNull();
    expect(cards[1].toolName).toBe("redacted");
    expect(() => expectNoLeak(cards[1], ALL_CANARIES)).not.toThrow();
  });

  it("a redacted first row does not redact a later row the viewer owns", async () => {
    const { cards } = await run({
      viewer: MEMBER_ID,
      role: "member",
      rows: [
        { id: ROW_A, requestedBy: OTHER_MEMBER_ID },
        { id: ROW_B, requestedBy: MEMBER_ID },
      ],
    });
    expect(cards[0].view).toBeNull();
    expect(cards[1].view).not.toBeNull();
  });

  it("an approved row the viewer cannot see is skipped; a pending row for the same viewer is the redacted frame", async () => {
    const { cards, sent } = await run({
      viewer: MEMBER_ID,
      role: "member",
      rows: [
        { id: ROW_A, status: "approved", requestedBy: OTHER_MEMBER_ID },
        { id: ROW_B, status: "pending", requestedBy: OTHER_MEMBER_ID },
      ],
    });
    expect(cards.map((c) => c.approvalId)).toEqual([ROW_B]);
    expect(cards[0].view).toBeNull();
    expect(sent).toBe(1);
  });

  it("an approved row IS re-sent in full to an Owner and to the requester", async () => {
    const owner = await run({ viewer: OWNER_ID, role: "owner", rows: [{ status: "approved" }] });
    expect(owner.cards[0].status).toBe("approved");
    expect(owner.cards[0].view).not.toBeNull();
    const own = await run({ viewer: MEMBER_ID, role: "member", rows: [{ status: "approved", requestedBy: MEMBER_ID }] });
    expect(own.cards[0].status).toBe("approved");
    expect(own.cards[0].view).not.toBeNull();
  });
});

describe("the labeler is called only for an Owner viewer", () => {
  it("zero labeler calls for every member viewer shape", async () => {
    const a = await run({ viewer: MEMBER_ID, role: "member", rows: [{}, { id: ROW_B, requestedBy: null }, { id: ROW_C, requestedBy: MEMBER_ID }] });
    expect(a.label).not.toHaveBeenCalled();
    const b = await run({ viewer: MEMBER_ID, role: "reject", rows: [{ requestedBy: MEMBER_ID }] });
    expect(b.label).not.toHaveBeenCalled();
  });

  it("a labeler that throws: the frame is still sent, without a requester key", async () => {
    const { cards } = await run({
      viewer: OWNER_ID,
      role: "owner",
      rows: [{}],
      label: async () => {
        throw new Error("lookup exploded");
      },
    });
    expect(cards).toHaveLength(1);
    expect(cards[0].view).not.toBeNull();
    expect(Object.hasOwn(cards[0], "requester")).toBe(false);
  });

  it("a labeler that returns undefined: no requester key", async () => {
    const { cards } = await run({ viewer: OWNER_ID, role: "owner", rows: [{}], label: async () => undefined });
    expect(Object.hasOwn(cards[0], "requester")).toBe(false);
  });
});

describe("with the real labeler over the strict fake", () => {
  const world = (over: Partial<FakeLabelerWorld> = {}): FakeLabelerWorld => ({
    members: [
      { workspace_id: WORKSPACE_ID, user_id: OWNER_ID, role: "owner" },
      { workspace_id: WORKSPACE_ID, user_id: REQUESTER_ID, role: "member" },
      { workspace_id: WORKSPACE_ID, user_id: OTHER_MEMBER_ID, role: "member" },
    ],
    authEmails: { [REQUESTER_ID]: REQUESTER_EMAIL, [OTHER_MEMBER_ID]: "other.member@example.com" },
    ...over,
  });

  it("two rows with the same workspace and requester are one lookup", async () => {
    const fake = makeLabelerClient(world());
    const label = createRequesterLabeler(() => fake.client as unknown as RequesterQueryClient);
    const { cards } = await run({ viewer: OWNER_ID, role: "owner", rows: [{ id: ROW_A }, { id: ROW_B }], label });
    expect(cards.map((c) => c.requester)).toEqual([REQUESTER_EMAIL, REQUESTER_EMAIL]);
    expect(fake.queries).toHaveLength(1);
    expect(fake.authCalls).toEqual([REQUESTER_ID]);
  });

  it("the same requester in two workspaces (a member of one): the email for one row, the fallback for the other, no cross-workspace leak", async () => {
    const fake = makeLabelerClient(
      world({
        members: [
          { workspace_id: WORKSPACE_ID, user_id: OWNER_ID, role: "owner" },
          { workspace_id: WORKSPACE_ID, user_id: REQUESTER_ID, role: "member" },
          { workspace_id: OTHER_WORKSPACE_ID, user_id: OWNER_ID, role: "owner" },
        ],
      }),
    );
    const label = createRequesterLabeler(() => fake.client as unknown as RequesterQueryClient);
    const { cards } = await run({ viewer: OWNER_ID, role: "owner", rows: [{ id: ROW_A }, { id: ROW_B, workspaceId: OTHER_WORKSPACE_ID }], label });
    expect(cards.map((c) => c.requester)).toEqual([REQUESTER_EMAIL, FALLBACK]);
  });

  it("a labeler failure: the frame is sent without the key, one report, and no email in any report argument", async () => {
    const fake = makeLabelerClient(world({ authError: { code: "user_not_found", message: `no user ${REQUESTER_EMAIL}` } }));
    const label = createRequesterLabeler(() => fake.client as unknown as RequesterQueryClient);
    const { cards } = await run({ viewer: OWNER_ID, role: "owner", rows: [{ id: ROW_A }, { id: ROW_B }], label });
    expect(cards).toHaveLength(2);
    expect(cards.every((c) => !Object.hasOwn(c, "requester"))).toBe(true);
    expect(h.report.mock.calls.filter((c) => c[0] === "requesterLabelFailed")).toHaveLength(1);
    expect(reportContexts()).not.toContain(REQUESTER_EMAIL);
  });

  it("three distinct requesters under one hung lookup cost one deadline in total (the first timeout trips the instance)", async () => {
    const ctl = new AbortController();
    let hungReads = 0;
    const hung = {
      from: () => {
        hungReads += 1;
        return { select: () => ({ eq: () => ({ in: () => ({ abortSignal: () => new Promise(() => {}) }) }) }) };
      },
      auth: { admin: { getUserById: () => new Promise(() => {}) } },
    };
    const label = createRequesterLabeler(() => hung as unknown as RequesterQueryClient, { signal: () => ctl.signal });
    const p = run({
      viewer: OWNER_ID,
      role: "owner",
      label,
      rows: [
        { id: ROW_A, requestedBy: REQUESTER_ID },
        { id: ROW_B, requestedBy: OTHER_MEMBER_ID },
        { id: ROW_C, requestedBy: MEMBER_ID },
      ],
    });
    await vi.waitFor(() => expect(hungReads).toBe(1));
    ctl.abort();
    const { cards } = await p;
    expect(hungReads).toBe(1);
    expect(cards).toHaveLength(3);
    expect(cards.every((c) => !Object.hasOwn(c, "requester"))).toBe(true);
    expect(h.report.mock.calls.filter((c) => c[0] === "requesterLabelFailed")).toHaveLength(1);
  });
});

describe("request_count plays no part in the label (it counts rows of any status; requested_by_user_id is immutable per row)", () => {
  it("an Owner viewer and another member's request with count 2: the label is still asked and sent", async () => {
    const { cards, label } = await run({ viewer: OWNER_ID, role: "owner", rows: [{ requestCount: 2 }] });
    expect(cards).toHaveLength(1);
    expect(cards[0].view).not.toBeNull();
    expect(cards[0].requester).toBe(REQUESTER_EMAIL);
    expect(cards[0].requestCount).toBe(2);
    expect(label).toHaveBeenCalledTimes(1);
  });

  it("count 2 because of a prior DENIED row: the Owner still gets the label of THIS row's requester", async () => {
    // The row list holds one live (pending) row; its request_count is 2 because an earlier row was denied.
    const { cards, label } = await run({ viewer: OWNER_ID, role: "owner", rows: [{ requestCount: 2, requestedBy: REQUESTER_ID }] });
    expect(cards[0].requester).toBe(REQUESTER_EMAIL);
    expect(label).toHaveBeenCalledWith(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
  });

  it("a NULL requester with count 2 gets the labeler's value too (the fixed fallback from the real labeler)", async () => {
    const { cards, label } = await run({ viewer: OWNER_ID, role: "owner", rows: [{ requestCount: 2, requestedBy: null }], label: async () => FALLBACK });
    expect(cards[0].requester).toBe(FALLBACK);
    expect(label).toHaveBeenCalledTimes(1);
  });

  it("the verified requester with count 2 still gets the literal you, with no lookup", async () => {
    const own = await run({ viewer: OWNER_ID, role: "owner", rows: [{ requestCount: 2, requestedBy: OWNER_ID }] });
    expect(own.cards[0].requester).toBe("you");
    expect(own.label).not.toHaveBeenCalled();
    const member = await run({ viewer: MEMBER_ID, role: "member", rows: [{ requestCount: 3, requestedBy: MEMBER_ID }] });
    expect(member.cards[0].requester).toBe("you");
    expect(member.label).not.toHaveBeenCalled();
  });

  it("a member viewer who is not the requester never triggers a lookup, whatever the count", async () => {
    const { cards, label } = await run({ viewer: MEMBER_ID, role: "member", rows: [{ requestCount: 1 }, { id: ROW_B, requestCount: 2 }] });
    expect(cards.every((c) => !Object.hasOwn(c, "requester"))).toBe(true);
    expect(label).not.toHaveBeenCalled();
  });
});

describe("the viewer role read: asked about the ROW's workspace, once per workspace per attach", () => {
  it("a role that differs by workspace is read for each row's own workspace (owner here, member there)", async () => {
    const { cards, viewerRole } = await run({
      viewer: OWNER_ID,
      role: "owner",
      roleByWorkspace: { [WORKSPACE_ID]: "owner", [OTHER_WORKSPACE_ID]: "member" },
      sessionWorkspaceId: WORKSPACE_ID,
      rows: [
        { id: ROW_A, workspaceId: WORKSPACE_ID },
        { id: ROW_B, workspaceId: OTHER_WORKSPACE_ID },
      ],
    });
    expect(viewerRole.mock.calls.map((c) => c[0]).sort()).toEqual([OTHER_WORKSPACE_ID, WORKSPACE_ID].sort());
    expect(cards.map((c) => [c.approvalId, c.viewerRole, c.view === null])).toEqual([
      [ROW_A, "owner", false],
      [ROW_B, "member", true],
    ]);
  });

  it("many rows in one workspace read the role once", async () => {
    const { viewerRole, cards } = await run({ viewer: OWNER_ID, role: "owner", rows: [{ id: ROW_A }, { id: ROW_B }, { id: ROW_C }] });
    expect(cards).toHaveLength(3);
    expect(viewerRole).toHaveBeenCalledTimes(1);
    expect(viewerRole).toHaveBeenCalledWith(WORKSPACE_ID);
  });

  it("a failed read is memoised: ONE viewerRoleFailed per workspace, and every row stays fail-closed for a non-requester", async () => {
    const { viewerRole, cards } = await run({ viewer: OWNER_ID, role: "reject", rows: [{ id: ROW_A }, { id: ROW_B }, { id: ROW_C }] });
    expect(cards).toHaveLength(0);
    expect(viewerRole).toHaveBeenCalledTimes(1);
    expect(reportKeys().filter((k) => k === "viewerRoleFailed")).toHaveLength(1);
  });

  it("the memo does not outlive the attach (a second attach reads again)", async () => {
    const a = await run({ viewer: OWNER_ID, role: "owner", rows: [{}] });
    const b = await run({ viewer: OWNER_ID, role: "owner", rows: [{}] });
    expect(a.viewerRole).toHaveBeenCalledTimes(1);
    expect(b.viewerRole).toHaveBeenCalledTimes(1);
  });
});

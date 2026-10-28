import { describe, expect, it, vi } from "vitest";
import {
  APPROVAL_STATUSES,
  APPROVAL_TRANSITIONS,
  ApprovalServiceError,
  anonymiseApprovalRequests,
  canTransition,
  consumeApproval,
  createApprovalRequest,
  getApprovalStatus,
  listLiveApprovals,
  submitApprovalRequest,
  sweepApprovals,
  type ApprovalRpcClient,
  type ApprovalStatus,
} from "@/server/approval/service";
import { decideApproval } from "@/server/approval/decide";
import { APPROVAL_ID, CONVERSATION_ID, OTHER_CONVERSATION_ID, USER_ID, WORKSPACE_ID } from "./fixtures";

const HASH = "a".repeat(64);
const row = (over: Record<string, unknown> = {}) => ({
  id: APPROVAL_ID,
  workspace_id: WORKSPACE_ID,
  conversation_id: CONVERSATION_ID,
  requested_by_user_id: USER_ID,
  tool_name: "mcp__soleur_platform__email_send",
  action_sha256: HASH,
  status: "pending",
  expires_at: "2026-10-29T10:00:00.000Z",
  decided_at: null,
  decided_by: null,
  consumed_at: null,
  expired_at: null,
  unanswered_flagged_at: null,
  created_at: "2026-10-28T10:00:00.000Z",
  canonical_action: { v: 1 },
  ...over,
});

function client(handler: (fn: string, args: Record<string, unknown>) => { data?: unknown; error?: { message: string; code?: string } | null }) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const c: ApprovalRpcClient = {
    rpc: vi.fn(async (fn: string, args: Record<string, unknown> = {}) => {
      calls.push({ fn, args });
      const r = handler(fn, args);
      return { data: r.data ?? null, error: r.error ?? null };
    }),
  };
  return { c, calls };
}

const createParams = {
  workspaceId: WORKSPACE_ID,
  conversationId: CONVERSATION_ID,
  requestedByUserId: USER_ID,
  toolName: "mcp__soleur_platform__email_send",
  actionSha256: HASH,
  canonicalAction: { v: 1, tool: "mcp__soleur_platform__email_send", fields: {} },
};

describe("status machine (mirrors the write-once trigger in migration 180)", () => {
  const edges = new Set(APPROVAL_TRANSITIONS.map(([a, b]) => `${a}>${b}`));

  it("allows exactly pending->approved|rejected|expired and approved->consumed|expired", () => {
    expect([...edges].sort()).toEqual(
      ["approved>consumed", "approved>expired", "pending>approved", "pending>expired", "pending>rejected"].sort(),
    );
  });

  it("every other ordered pair, including every move out of a terminal state, is refused", () => {
    for (const from of APPROVAL_STATUSES) {
      for (const to of APPROVAL_STATUSES) {
        const expected = edges.has(`${from}>${to}`);
        expect(canTransition(from as ApprovalStatus, to as ApprovalStatus), `${from}->${to}`).toBe(expected);
      }
    }
    for (const terminal of ["rejected", "expired", "consumed"] as const) {
      for (const to of APPROVAL_STATUSES) expect(canTransition(terminal, to)).toBe(false);
    }
  });
});

describe("createApprovalRequest", () => {
  it("passes the bound hash and canonical action and returns the row, created flag and request count", async () => {
    const { c, calls } = client(() => ({ data: { approval: row(), created: true, request_count: 1 } }));
    const r = await createApprovalRequest(c, createParams);
    expect(calls[0].fn).toBe("create_approval_request");
    expect(calls[0].args).toMatchObject({
      p_workspace_id: WORKSPACE_ID,
      p_conversation_id: CONVERSATION_ID,
      p_requested_by: USER_ID,
      p_tool_name: createParams.toolName,
      p_action_sha256: HASH,
      p_canonical_action: createParams.canonicalAction,
    });
    expect(r.approval.status).toBe("pending");
    expect(r.created).toBe(true);
    expect(r.requestCount).toBe(1);
  });

  it("throws a static-message error (no database text) when the rpc fails", async () => {
    const { c } = client(() => ({ error: { message: "secret detail from postgres", code: "42501" } }));
    await expect(createApprovalRequest(c, createParams)).rejects.toSatisfy((e: unknown) => {
      return e instanceof ApprovalServiceError && !e.message.includes("secret detail") && e.code === "42501";
    });
  });

  it("rejects a malformed rpc payload instead of trusting it", async () => {
    const { c } = client(() => ({ data: { approval: { status: "weird" }, created: true, request_count: 1 } }));
    await expect(createApprovalRequest(c, createParams)).rejects.toBeInstanceOf(ApprovalServiceError);
  });
});

describe("consumeApproval: the consume contract (one atomic rpc, hash and conversation passed)", () => {
  it("passes id, hash and conversation and reports consumed once", async () => {
    const { c, calls } = client(() => ({ data: { consumed: true, reason: "ok" } }));
    const r = await consumeApproval(c, { id: APPROVAL_ID, hash: HASH, conversationId: CONVERSATION_ID });
    expect(calls[0]).toEqual({
      fn: "consume_approval",
      args: { p_id: APPROVAL_ID, p_hash: HASH, p_conversation: CONVERSATION_ID },
    });
    expect(r).toEqual({ consumed: true });
  });

  it("each rejection reason is surfaced and never reported as consumed", async () => {
    for (const reason of ["not_found", "hash_mismatch", "wrong_conversation", "expired", "not_approved", "already_consumed"]) {
      const { c } = client(() => ({ data: { consumed: false, reason } }));
      expect(await consumeApproval(c, { id: APPROVAL_ID, hash: HASH, conversationId: OTHER_CONVERSATION_ID })).toEqual({
        consumed: false,
        reason,
      });
    }
  });

  it("fails closed: an rpc error, a null payload or an unknown shape is a rejection, never a consume", async () => {
    const err = client(() => ({ error: { message: "boom" } }));
    expect(await consumeApproval(err.c, { id: APPROVAL_ID, hash: HASH, conversationId: CONVERSATION_ID })).toEqual({
      consumed: false,
      reason: "rpc_error",
    });
    for (const data of [null, undefined, {}, { consumed: "true" }, { consumed: 1 }, "ok", []]) {
      const { c } = client(() => ({ data }));
      const r = await consumeApproval(c, { id: APPROVAL_ID, hash: HASH, conversationId: CONVERSATION_ID });
      expect(r.consumed).toBe(false);
    }
  });

  it("refuses to call the rpc with a hash that is not 64 lowercase hex (never consume on a malformed bind)", async () => {
    const { c, calls } = client(() => ({ data: { consumed: true, reason: "ok" } }));
    expect(await consumeApproval(c, { id: APPROVAL_ID, hash: "short", conversationId: CONVERSATION_ID })).toEqual({
      consumed: false,
      reason: "bad_request",
    });
    expect(calls).toHaveLength(0);
  });
});

describe("submitApprovalRequest: re-proposal on an already approved row consumes at once (Guard 1 row 11)", () => {
  it("an approved live row is consumed immediately, with no card and no wait", async () => {
    const { c, calls } = client((fn) =>
      fn === "create_approval_request"
        ? { data: { approval: row({ status: "approved", decided_at: "2026-10-28T10:05:00.000Z" }), created: false, request_count: 2 } }
        : { data: { consumed: true, reason: "ok" } },
    );
    const r = await submitApprovalRequest(c, createParams);
    expect(r).toEqual({ kind: "released", approvalId: APPROVAL_ID, requestCount: 2 });
    expect(calls.map((x) => x.fn)).toEqual(["create_approval_request", "consume_approval"]);
    expect(calls[1].args).toEqual({ p_id: APPROVAL_ID, p_hash: HASH, p_conversation: CONVERSATION_ID });
  });

  it("an approved row whose consume is rejected is reported, never released", async () => {
    const { c } = client((fn) =>
      fn === "create_approval_request"
        ? { data: { approval: row({ status: "approved" }), created: false, request_count: 2 } }
        : { data: { consumed: false, reason: "expired" } },
    );
    expect(await submitApprovalRequest(c, createParams)).toEqual({ kind: "consume_rejected", approvalId: APPROVAL_ID, reason: "expired" });
  });

  it("a pending row goes to the wait loop and does NOT call consume", async () => {
    const { c, calls } = client(() => ({ data: { approval: row(), created: true, request_count: 1 } }));
    const r = await submitApprovalRequest(c, createParams);
    expect(r.kind).toBe("wait");
    expect(calls.map((x) => x.fn)).toEqual(["create_approval_request"]);
  });

  it("any other live status is never treated as released", async () => {
    for (const status of ["rejected", "expired", "consumed"]) {
      const { c, calls } = client(() => ({ data: { approval: row({ status }), created: false, request_count: 3 } }));
      const r = await submitApprovalRequest(c, createParams);
      expect(r.kind).not.toBe("released");
      expect(calls.map((x) => x.fn)).not.toContain("consume_approval");
    }
  });
});

describe("get / list / sweep / anonymise", () => {
  it("getApprovalStatus returns null for an unknown id", async () => {
    const { c, calls } = client(() => ({ data: null }));
    expect(await getApprovalStatus(c, APPROVAL_ID)).toBeNull();
    expect(calls[0]).toEqual({ fn: "get_approval_status", args: { p_id: APPROVAL_ID } });
  });

  it("listLiveApprovals scopes by conversation", async () => {
    const { c, calls } = client(() => ({ data: [{ approval: row(), request_count: 1 }] }));
    const r = await listLiveApprovals(c, CONVERSATION_ID);
    expect(calls[0]).toEqual({ fn: "list_live_approvals", args: { p_conversation: CONVERSATION_ID } });
    expect(r[0].approval.id).toBe(APPROVAL_ID);
    expect(r[0].requestCount).toBe(1);
  });

  it("sweepApprovals maps the counts and per-row lists the cron needs", async () => {
    const { c, calls } = client(() => ({
      data: {
        expired: [{ id: APPROVAL_ID, workspace_id: WORKSPACE_ID, tool_name: "t", reason: "unanswered" }],
        flagged: [{ id: APPROVAL_ID, workspace_id: WORKSPACE_ID, tool_name: "t" }],
        scrubbed: 2,
      },
    }));
    const r = await sweepApprovals(c);
    expect(calls[0].fn).toBe("sweep_approvals");
    expect(r.expired[0]).toMatchObject({ id: APPROVAL_ID, workspaceId: WORKSPACE_ID, reason: "unanswered" });
    expect(r.flagged).toHaveLength(1);
    expect(r.scrubbed).toBe(2);
  });

  it("anonymiseApprovalRequests passes the user and returns the affected count", async () => {
    const { c, calls } = client(() => ({ data: 3 }));
    expect(await anonymiseApprovalRequests(c, USER_ID)).toBe(3);
    expect(calls[0]).toEqual({ fn: "anonymise_approval_request", args: { p_user_id: USER_ID } });
  });
});

describe("decideApproval (user-JWT client only; the actor is auth.uid() inside the rpc, never a parameter)", () => {
  it("sends only the id and the decision: no actor or user id can be supplied", async () => {
    const { c, calls } = client(() => ({ data: { outcome: "decided", approval: row({ status: "approved" }) } }));
    const r = await decideApproval(c, { id: APPROVAL_ID, decision: "approve" });
    expect(calls[0]).toEqual({ fn: "decide_approval", args: { p_id: APPROVAL_ID, p_decision: "approve" } });
    expect(r.outcome).toBe("decided");
  });

  it("rejects an unknown decision before calling the database (no 'approve all', no free text)", async () => {
    const { c, calls } = client(() => ({ data: {} }));
    for (const decision of ["approve_all", "APPROVE", "yes", "", "Approve"]) {
      await expect(decideApproval(c, { id: APPROVAL_ID, decision: decision as never })).rejects.toBeInstanceOf(ApprovalServiceError);
    }
    expect(calls).toHaveLength(0);
  });

  it("maps every outcome and keeps the not-authorised error distinct", async () => {
    for (const outcome of ["decided", "unchanged", "conflict", "expired", "closed"]) {
      const { c } = client(() => ({ data: { outcome, approval: row() } }));
      expect((await decideApproval(c, { id: APPROVAL_ID, decision: "deny" })).outcome).toBe(outcome);
    }
    const { c } = client(() => ({ error: { message: "approval: not authorized", code: "42501" } }));
    await expect(decideApproval(c, { id: APPROVAL_ID, decision: "deny" })).rejects.toMatchObject({ code: "42501" });
  });

  it("an unknown outcome string is an error, never a silent success", async () => {
    const { c } = client(() => ({ data: { outcome: "approved_for_all", approval: row() } }));
    await expect(decideApproval(c, { id: APPROVAL_ID, decision: "approve" })).rejects.toBeInstanceOf(ApprovalServiceError);
  });
});

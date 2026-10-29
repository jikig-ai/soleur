import { describe, expect, it, vi } from "vitest";
import {
  APPROVAL_STATUSES,
  APPROVAL_TRANSITIONS,
  ApprovalServiceError,
  ApprovalCapReachedError,
  consumeApproval,
  createApprovalRequest,
  getApprovalStatus,
  listLiveApprovals,
  submitApprovalRequest,
  sweepApprovals,
  type ApprovalRpcClient,
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
  revoked_at: null,
  revoked_by: null,
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

const CREATE_OK = { approval: row(), created: true, request_count: 1, notify: true, expires_at: row().expires_at };

const createParams = {
  workspaceId: WORKSPACE_ID,
  conversationId: CONVERSATION_ID,
  requestedByUserId: USER_ID,
  toolName: "mcp__soleur_platform__email_send",
  actionSha256: HASH,
  canonicalAction: { v: 1, tool: "mcp__soleur_platform__email_send", fields: {} },
};

describe("status machine (mirrors the write-once trigger in migration 180; SQL parity is in migration-180-approval-request.test.ts)", () => {
  const edges = new Set(APPROVAL_TRANSITIONS.map(([a, b]) => `${a}>${b}`));

  it("allows exactly pending->approved|rejected|expired, approved->consumed|expired and the Owner revoke approved->rejected", () => {
    expect([...edges].sort()).toEqual(
      [
        "approved>consumed",
        "approved>expired",
        "approved>rejected",
        "pending>approved",
        "pending>expired",
        "pending>rejected",
      ].sort(),
    );
  });

  it("every move out of a terminal state is refused, and nothing moves back to pending", () => {
    for (const terminal of ["rejected", "expired", "consumed"] as const) {
      for (const to of APPROVAL_STATUSES) expect(edges.has(`${terminal}>${to}`), `${terminal}->${to}`).toBe(false);
    }
    for (const from of APPROVAL_STATUSES) expect(edges.has(`${from}>pending`), `${from}->pending`).toBe(false);
  });
});

describe("createApprovalRequest", () => {
  it("passes the bound hash and canonical action and returns the row, created flag and request count", async () => {
    const { c, calls } = client(() => ({ data: CREATE_OK }));
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
    expect(r.notify).toBe(true);
    expect(r.expiresAt).toBe(row().expires_at);
  });

  it("maps the pending-cap SQLSTATEs to a typed ApprovalCapReachedError (AP429 conversation, AP430 workspace)", async () => {
    for (const [code, scope] of [["AP429", "conversation"], ["AP430", "workspace"]] as const) {
      const { c } = client(() => ({ error: { message: "approval: too many pending requests", code } }));
      await expect(createApprovalRequest(c, createParams)).rejects.toSatisfy(
        (e: unknown) => e instanceof ApprovalCapReachedError && e instanceof ApprovalServiceError && e.code === code && e.scope === scope,
      );
    }
    // Any other SQLSTATE stays a plain service error.
    const { c } = client(() => ({ error: { message: "x", code: "40001" } }));
    await expect(createApprovalRequest(c, createParams)).rejects.toSatisfy((e: unknown) => e instanceof ApprovalServiceError && !(e instanceof ApprovalCapReachedError));
  });

  it("defaults an absent notify (true) and expires_at (the row's) but rejects a present field of the wrong type", async () => {
    const bare: Record<string, unknown> = { ...CREATE_OK };
    delete bare.notify;
    delete bare.expires_at;
    const ok = client(() => ({ data: bare }));
    expect(await createApprovalRequest(ok.c, createParams)).toMatchObject({ notify: true, expiresAt: row().expires_at });
    for (const bad of [{ notify: "yes" }, { expires_at: 5 }]) {
      const { c } = client(() => ({ data: { ...CREATE_OK, ...bad } }));
      await expect(createApprovalRequest(c, createParams)).rejects.toMatchObject({ code: "bad_payload" });
    }
  });

  it("throws a static-message error (no database text) when the rpc fails", async () => {
    const { c } = client(() => ({ error: { message: "secret detail from postgres", code: "42501" } }));
    await expect(createApprovalRequest(c, createParams)).rejects.toSatisfy((e: unknown) => {
      return e instanceof ApprovalServiceError && !e.message.includes("secret detail") && e.code === "42501";
    });
  });

  it("rejects a malformed rpc payload instead of trusting it", async () => {
    const { c } = client(() => ({ data: { ...CREATE_OK, approval: { status: "weird" } } }));
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
    for (const reason of [
      "not_found",
      "hash_mismatch",
      "wrong_conversation",
      "expired",
      "decider_not_owner",
      "requester_not_member",
      "not_approved",
      "already_consumed",
    ]) {
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
        ? { data: { ...CREATE_OK, approval: row({ status: "approved", decided_at: "2026-10-28T10:05:00.000Z" }), created: false, request_count: 2, notify: false } }
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
        ? { data: { ...CREATE_OK, approval: row({ status: "approved" }), created: false, request_count: 2, notify: false } }
        : { data: { consumed: false, reason: "expired" } },
    );
    expect(await submitApprovalRequest(c, createParams)).toEqual({ kind: "consume_rejected", approvalId: APPROVAL_ID, reason: "expired" });
  });

  it("a pending row goes to the wait loop and does NOT call consume", async () => {
    const { c, calls } = client(() => ({ data: CREATE_OK }));
    const r = await submitApprovalRequest(c, createParams);
    expect(r.kind).toBe("wait");
    expect(calls.map((x) => x.fn)).toEqual(["create_approval_request"]);
  });

  it("the wait result exposes notify and expiresAt from the create result (no table read needed downstream)", async () => {
    const { c } = client(() => ({ data: { ...CREATE_OK, notify: false, expires_at: "2026-10-30T00:00:00.000Z" } }));
    const r = await submitApprovalRequest(c, createParams);
    expect(r).toMatchObject({ kind: "wait", created: true, notify: false, expiresAt: "2026-10-30T00:00:00.000Z" });
  });

  it("a pending cap is a typed cap_reached outcome with its scope, nothing is created or consumed", async () => {
    for (const [code, scope] of [["AP429", "conversation"], ["AP430", "workspace"]] as const) {
      const { c, calls } = client(() => ({ error: { message: "x", code } }));
      expect(await submitApprovalRequest(c, createParams)).toEqual({ kind: "cap_reached", scope });
      expect(calls.map((x) => x.fn)).toEqual(["create_approval_request"]);
    }
  });

  it("any other create failure still throws (the gate fails closed)", async () => {
    const { c } = client(() => ({ error: { message: "x", code: "42501" } }));
    await expect(submitApprovalRequest(c, createParams)).rejects.toBeInstanceOf(ApprovalServiceError);
  });

  it("any other live status is never treated as released", async () => {
    for (const status of ["rejected", "expired", "consumed"]) {
      const { c, calls } = client(() => ({ data: { ...CREATE_OK, approval: row({ status }), created: false, request_count: 3, notify: false } }));
      const r = await submitApprovalRequest(c, createParams);
      expect(r.kind).not.toBe("released");
      expect(calls.map((x) => x.fn)).not.toContain("consume_approval");
    }
  });
});

describe("get / list / sweep", () => {
  it("getApprovalStatus never exposes the action text or user ids, even if the payload carried them", async () => {
    const { c } = client(() => ({ data: row({ status: "approved", revoked_at: null }) }));
    const st = await getApprovalStatus(c, APPROVAL_ID);
    expect(st).toMatchObject({ id: APPROVAL_ID, status: "approved", revoked_at: null });
    for (const k of ["canonical_action", "requested_by_user_id", "decided_by", "revoked_by"]) expect(st).not.toHaveProperty(k);
  });

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
    for (const outcome of ["decided", "unchanged", "already_decided", "conflict", "revoked", "expired", "closed"]) {
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

/**
 * #4672 — the WebSocket half of the durable approval flow: the Owner's decision (`approval_decide`), the waiter wake,
 * the cross-kind guard (a review-gate answer can never resolve an approval, an approval frame can never resolve a review
 * gate) and the reattach re-send of live cards.
 *
 * Drives the REAL `handleMessage`. Synthesized ids only.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { TC_VERSION } from "@/lib/legal/tc-version";
import { canonicalizeAction, computeActionHash } from "@/server/approval/canonical";
import {
  APPROVAL_ID,
  CONVERSATION_ID,
  OTHER_CONVERSATION_ID,
  OTHER_WORKSPACE_ID,
  SAMPLES,
  TOOLS,
  USER_ID,
  WORKSPACE_ID,
} from "../approval/fixtures";

const OTHER_USER = "00000000-0000-4000-8000-0000000000aa";
const GATE_ID = "00000000-0000-4000-8000-0000000000bb";

const h = vi.hoisted(() => ({
  tenantRpc: vi.fn(),
  serviceRpc: vi.fn(),
  getFreshTenantClient: vi.fn(),
  resolveReviewGate: vi.fn(),
  flagOn: { value: false },
  /** When set, the flag is on only for this workspace id (a workspace-scoped cohort). */
  flagWorkspace: { value: null as string | null },
  flagCalls: [] as Array<{ userId: string; workspaceId: string | null }>,
  /** When set, the attaching session's workspace resolution rejects with this error. */
  resolveWorkspaceError: { value: null as Error | null },
  report: vi.fn(),
  warn: vi.fn(),
  logWarn: vi.fn(),
}));

vi.mock("@/server/current-repo-url", () => ({ getCurrentRepoUrl: vi.fn(async () => "https://github.com/acme/repo.git") }));

vi.mock("@/lib/supabase/tenant", () => {
  class RuntimeAuthError extends Error {
    cause: string;
    constructor(message: string, cause = "unknown") {
      super(message);
      this.cause = cause;
    }
  }
  const conv = {
    id: "00000000-0000-4000-8000-000000000003",
    repo_url: "https://github.com/acme/repo.git",
    workspace_id: "00000000-0000-4000-8000-000000000001",
    status: "active",
    current_workspace_id: "00000000-0000-4000-8000-000000000001",
    last_active: "2026-10-29T10:00:00Z",
  };
  const single = async () => ({ data: conv, error: null });
  // Any query chain: `single`/`maybeSingle` resolve the conversation row, awaiting the chain itself resolves an empty list.
  const chain = (): unknown =>
    new Proxy(() => {}, {
      get: (_t, p) => {
        if (p === "single" || p === "maybeSingle") return single;
        if (p === "then") return (ok: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null, count: 0 }).then(ok);
        return () => chain();
      },
    });
  const tenantClient = {
    from: () => chain(),
    rpc: (...a: unknown[]) => h.tenantRpc(...a),
  };
  h.getFreshTenantClient.mockImplementation(async () => tenantClient);
  return { getFreshTenantClient: h.getFreshTenantClient, getMyRevocationStatus: vi.fn(async () => null), RuntimeAuthError };
});

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ rpc: (...a: unknown[]) => h.serviceRpc(...a), from: vi.fn(), auth: { getUser: vi.fn() } }),
  serverUrl: "https://test.supabase.co",
}));

vi.mock("@/server/workspace-resolver", async (importActual) => {
  const actual = await importActual<typeof import("@/server/workspace-resolver")>();
  return {
    ...actual,
    resolveCurrentWorkspaceId: (...a: Parameters<typeof actual.resolveCurrentWorkspaceId>) => {
      if (h.resolveWorkspaceError.value) return Promise.reject(h.resolveWorkspaceError.value);
      return actual.resolveCurrentWorkspaceId(...a);
    },
  };
});

vi.mock("@/server/approval/flag", () => ({
  isApprovalQueueEnabled: async (id: { userId: string; workspaceId: string | null }) => {
    h.flagCalls.push(id);
    return h.flagOn.value && (h.flagWorkspace.value === null || id.workspaceId === h.flagWorkspace.value);
  },
}));

// The resume paths' unrelated collaborators: engine binding guard and in-flight checkpoint restore.
vi.mock("@/server/agent-engine-route-guard", () => ({
  assertLegacyConversationEngineBinding: vi.fn(async () => {}),
  assertLegacyEngineBinding: vi.fn(),
}));
vi.mock("@/server/inflight-checkpoint", () => ({
  restoreInflightCheckpoint: vi.fn(async () => ({ restored: true })),
  CHECKPOINT_REFUSED_MESSAGE: "refused",
}));

vi.mock("../../server/agent-runner", () => ({
  startAgentSession: vi.fn(),
  sendUserMessage: vi.fn(),
  resolveReviewGate: (...a: unknown[]) => h.resolveReviewGate(...a),
  abortSession: vi.fn(),
}));

vi.mock("@/server/observability", async (importActual) => {
  const actual = await importActual<typeof import("@/server/observability")>();
  return { ...actual, reportSilentFallback: h.report, warnSilentFallback: h.warn };
});

vi.mock("@/server/logger", async (importActual) => {
  const actual = await importActual<typeof import("@/server/logger")>();
  const wrap = (l: any) => new Proxy(l, { get: (t, p) => (p === "warn" ? h.logWarn : t[p]) });
  return {
    ...actual,
    default: wrap(actual.default),
    createChildLogger: (ctxName: any) => wrap(actual.createChildLogger(ctxName)),
  };
});

import { handleMessage, sessions, type ClientSession } from "@/server/ws-handler";
import { clearAllWaiters, registerWaiter, waiterCount } from "@/server/approval/waiters";
import { parseWSMessage } from "@/lib/ws-zod-schemas";
import type { WSMessage } from "@/lib/types";

function makeSession(conversationId?: string): ClientSession {
  const ws = { readyState: 1, send: vi.fn(), close: vi.fn() } as unknown as ClientSession["ws"];
  return { ws, lastActivity: Date.now(), tcVersionAtHandshake: TC_VERSION, tcRecheckCacheUntil: Date.now() + 1_000_000, conversationId };
}
const frames = (s: ClientSession): WSMessage[] =>
  (s.ws.send as unknown as { mock: { calls: unknown[][] } }).mock.calls.map((c) => JSON.parse(c[0] as string) as WSMessage);

const row = (over: Record<string, unknown> = {}) => ({
  id: APPROVAL_ID,
  workspace_id: WORKSPACE_ID,
  conversation_id: CONVERSATION_ID,
  requested_by_user_id: USER_ID,
  tool_name: TOOLS.emailSend,
  action_sha256: "a".repeat(64),
  status: "approved",
  expires_at: new Date(Date.now() + 3600_000).toISOString(),
  decided_at: new Date().toISOString(),
  decided_by: USER_ID,
  consumed_at: null,
  expired_at: null,
  revoked_at: null,
  revoked_by: null,
  unanswered_flagged_at: null,
  created_at: new Date().toISOString(),
  canonical_action: null,
  ...over,
});

const send = (userId: string, msg: Record<string, unknown>) => handleMessage(userId, JSON.stringify(msg));
const decideFrame = (over: Record<string, unknown> = {}) => ({ type: "approval_decide", approvalId: APPROVAL_ID, decision: "approve", ...over });

beforeEach(() => {
  vi.clearAllMocks();
  h.flagOn.value = false;
  h.flagWorkspace.value = null;
  h.flagCalls.length = 0;
  h.resolveWorkspaceError.value = null;
  h.tenantRpc.mockImplementation(async (fn: string) => {
    if (fn === "decide_approval") return { data: { outcome: "decided", approval: row() }, error: null };
    if (fn === "is_workspace_owner") return { data: true, error: null };
    return { data: null, error: null };
  });
  clearAllWaiters();
});
afterEach(() => {
  sessions.delete(USER_ID);
  sessions.delete(OTHER_USER);
  clearAllWaiters();
});

describe("approval_decide", () => {
  it("decides through the tenant client of the SOCKET user, with no actor parameter, and reports the outcome", async () => {
    const s = makeSession(CONVERSATION_ID);
    sessions.set(USER_ID, s);
    await send(USER_ID, decideFrame());

    expect(h.getFreshTenantClient).toHaveBeenCalledWith(USER_ID);
    expect(h.tenantRpc).toHaveBeenCalledWith("decide_approval", { p_id: APPROVAL_ID, p_decision: "approve" });
    const args = h.tenantRpc.mock.calls.find((c) => c[0] === "decide_approval")![1] as Record<string, unknown>;
    expect(Object.keys(args).sort()).toEqual(["p_decision", "p_id"]);
    expect(frames(s)).toContainEqual({
      type: "approval_status",
      approvalId: APPROVAL_ID,
      conversationId: CONVERSATION_ID,
      status: "approved",
      outcome: "decided",
    });
    expect(h.logWarn.mock.calls.some((c) => String(c[1]).startsWith(`SOLEUR_APPROVAL_DECIDED approval_id=${APPROVAL_ID}`))).toBe(true);
  });

  it("a forged user id in the payload cannot change the actor (and the wire schema refuses it outright)", async () => {
    const s = makeSession(CONVERSATION_ID);
    sessions.set(USER_ID, s);
    await send(USER_ID, decideFrame({ userId: OTHER_USER, decidedBy: OTHER_USER }));
    expect(h.getFreshTenantClient).toHaveBeenCalledWith(USER_ID);
    expect(h.getFreshTenantClient).not.toHaveBeenCalledWith(OTHER_USER);
    expect(h.tenantRpc.mock.calls.find((c) => c[0] === "decide_approval")![1]).toEqual({ p_id: APPROVAL_ID, p_decision: "approve" });
    expect(parseWSMessage({ ...decideFrame(), userId: OTHER_USER }).ok).toBe(false);
  });

  it("the wire schema admits only the closed decision enum and a UUID id (no 'approve all', no free text)", () => {
    expect(parseWSMessage(decideFrame()).ok).toBe(true);
    expect(parseWSMessage(decideFrame({ decision: "deny" })).ok).toBe(true);
    expect(parseWSMessage(decideFrame({ decision: "approve_all" })).ok).toBe(false);
    expect(parseWSMessage(decideFrame({ decision: "Approve" })).ok).toBe(false);
    expect(parseWSMessage(decideFrame({ approvalId: "not-a-uuid" })).ok).toBe(false);
    expect(parseWSMessage({ type: "approval_decide", approvalId: APPROVAL_ID }).ok).toBe(false);
    expect(parseWSMessage(decideFrame({ options: ["Approve"] })).ok).toBe(false);
  });

  it("wakes the in-process waiter with the status the database holds", async () => {
    const reg = registerWaiter(APPROVAL_ID);
    sessions.set(USER_ID, makeSession(CONVERSATION_ID));
    await send(USER_ID, decideFrame());
    await expect(reg.woken).resolves.toBe("approved");
  });

  it("a refused decision (non-owner, unknown id, RPC error) wakes nothing, reports one op and tells the client in static text", async () => {
    const reg = registerWaiter(APPROVAL_ID);
    h.tenantRpc.mockImplementation(async () => ({ data: null, error: { message: "row echo: secret body", code: "42501" } }));
    const s = makeSession(CONVERSATION_ID);
    sessions.set(USER_ID, s);
    await send(USER_ID, decideFrame());

    const woken = await Promise.race([reg.woken, new Promise((r) => setTimeout(() => r("not woken"), 20))]);
    expect(woken).toBe("not woken");
    expect(h.report.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-decide-failed")).toBe(true);
    const out = frames(s);
    expect(out.some((f) => f.type === "approval_status")).toBe(false);
    expect(JSON.stringify(out)).not.toContain("secret body");
    expect(out).toContainEqual({ type: "error", message: "Could not record your decision. Please try again." });
  });

  it("the loser of a two-Owner race gets the final row (conflict) and the waiter is woken with the final status", async () => {
    const reg = registerWaiter(APPROVAL_ID);
    h.tenantRpc.mockImplementation(async () => ({ data: { outcome: "conflict", approval: row({ status: "rejected" }) }, error: null }));
    const s = makeSession(CONVERSATION_ID);
    sessions.set(USER_ID, s);
    await send(USER_ID, decideFrame());
    expect(frames(s)).toContainEqual(expect.objectContaining({ type: "approval_status", status: "rejected", outcome: "conflict" }));
    await expect(reg.woken).resolves.toBe("rejected");
  });

  it("a DENY decision sends p_decision 'deny' to the RPC, reports the rejected row and wakes the waiter with 'rejected'", async () => {
    const reg = registerWaiter(APPROVAL_ID);
    h.tenantRpc.mockImplementation(async (fn: string) =>
      fn === "decide_approval" ? { data: { outcome: "decided", approval: row({ status: "rejected" }) }, error: null } : { data: null, error: null },
    );
    const s = makeSession(CONVERSATION_ID);
    sessions.set(USER_ID, s);
    await send(USER_ID, decideFrame({ decision: "deny" }));
    expect(h.tenantRpc).toHaveBeenCalledWith("decide_approval", { p_id: APPROVAL_ID, p_decision: "deny" });
    expect(frames(s)).toContainEqual({
      type: "approval_status",
      approvalId: APPROVAL_ID,
      conversationId: CONVERSATION_ID,
      status: "rejected",
      outcome: "decided",
    });
    await expect(reg.woken).resolves.toBe("rejected");
  });

  it("a revoke (deny on an APPROVED row) reports status 'rejected' with outcome 'revoked', and the requester sees the card settle", async () => {
    const reg = registerWaiter(APPROVAL_ID);
    h.tenantRpc.mockImplementation(async () => ({
      data: { outcome: "revoked", approval: row({ status: "rejected", requested_by_user_id: OTHER_USER, revoked_at: new Date().toISOString(), revoked_by: USER_ID }) },
      error: null,
    }));
    const owner = makeSession(CONVERSATION_ID);
    const requester = makeSession(CONVERSATION_ID);
    sessions.set(USER_ID, owner);
    sessions.set(OTHER_USER, requester);
    await send(USER_ID, decideFrame({ decision: "deny" }));
    expect(frames(owner)).toContainEqual(expect.objectContaining({ type: "approval_status", status: "rejected", outcome: "revoked" }));
    expect(frames(requester)).toContainEqual({ type: "approval_status", approvalId: APPROVAL_ID, conversationId: CONVERSATION_ID, status: "rejected" });
    await expect(reg.woken).resolves.toBe("rejected");
  });

  it("a second Owner repeating the recorded decision gets outcome 'already_decided' with the current status", async () => {
    h.tenantRpc.mockImplementation(async () => ({ data: { outcome: "already_decided", approval: row({ status: "approved" }) }, error: null }));
    const s = makeSession(CONVERSATION_ID);
    sessions.set(USER_ID, s);
    await send(USER_ID, decideFrame());
    expect(frames(s)).toContainEqual(expect.objectContaining({ type: "approval_status", status: "approved", outcome: "already_decided" }));
  });

  it("a closed conversation (still pending) does not wake the waiter", async () => {
    const reg = registerWaiter(APPROVAL_ID);
    h.tenantRpc.mockImplementation(async () => ({ data: { outcome: "closed", approval: row({ status: "pending" }) }, error: null }));
    const s = makeSession(CONVERSATION_ID);
    sessions.set(USER_ID, s);
    await send(USER_ID, decideFrame());
    expect(frames(s)).toContainEqual(expect.objectContaining({ status: "pending", outcome: "closed" }));
    const woken = await Promise.race([reg.woken, new Promise((r) => setTimeout(() => r("not woken"), 20))]);
    expect(woken).toBe("not woken");
  });

  it("the requester (a different user than the deciding Owner) sees the card settle without an outcome", async () => {
    h.tenantRpc.mockImplementation(async () => ({ data: { outcome: "decided", approval: row({ requested_by_user_id: OTHER_USER }) }, error: null }));
    const owner = makeSession(CONVERSATION_ID);
    const requester = makeSession(CONVERSATION_ID);
    sessions.set(USER_ID, owner);
    sessions.set(OTHER_USER, requester);
    await send(USER_ID, decideFrame());
    expect(frames(requester)).toContainEqual({ type: "approval_status", approvalId: APPROVAL_ID, conversationId: CONVERSATION_ID, status: "approved" });
  });

  it("with no bound conversation there is nothing to decide against", async () => {
    const s = makeSession(undefined);
    sessions.set(USER_ID, s);
    await send(USER_ID, decideFrame());
    expect(h.tenantRpc).not.toHaveBeenCalled();
    expect(frames(s)).toContainEqual({ type: "error", message: "No active session." });
  });
});

describe("cross-kind resolution bypass: a review gate and an approval can never resolve each other", () => {
  it("review_gate_response carrying an approval's id does not wake the waiter, does not decide, and is refused", async () => {
    const reg = registerWaiter(APPROVAL_ID);
    const s = makeSession(CONVERSATION_ID);
    sessions.set(USER_ID, s);
    await send(USER_ID, { type: "review_gate_response", gateId: APPROVAL_ID, selection: "Approve" });

    expect(h.tenantRpc).not.toHaveBeenCalled(); // no decide_approval
    expect(h.resolveReviewGate).not.toHaveBeenCalled(); // not even consulted as a gate
    const woken = await Promise.race([reg.woken, new Promise((r) => setTimeout(() => r("not woken"), 20))]);
    expect(woken).toBe("not woken");
    expect(waiterCount()).toBe(1);
    expect(frames(s)).toContainEqual(expect.objectContaining({ type: "error", gateId: APPROVAL_ID }));
  });

  it("every selection string, including the approval wording, is refused the same way", async () => {
    registerWaiter(APPROVAL_ID);
    sessions.set(USER_ID, makeSession(CONVERSATION_ID));
    for (const selection of ["Approve", "approve", "Approved", "Reject", "approved", ""]) {
      await send(USER_ID, { type: "review_gate_response", gateId: APPROVAL_ID, selection });
    }
    expect(h.resolveReviewGate).not.toHaveBeenCalled();
    expect(h.tenantRpc).not.toHaveBeenCalled();
  });

  it("an ordinary review gate is still resolved by review_gate_response (the guard is narrow)", async () => {
    sessions.set(USER_ID, makeSession(CONVERSATION_ID));
    await send(USER_ID, { type: "review_gate_response", gateId: GATE_ID, selection: "Approve" });
    expect(h.resolveReviewGate).toHaveBeenCalledWith(USER_ID, CONVERSATION_ID, GATE_ID, "Approve");
  });

  it("approval_decide carrying a review gate's id goes to the decide path only and never resolves a gate", async () => {
    h.tenantRpc.mockImplementation(async () => ({ data: null, error: { message: "not found", code: "P0002" } }));
    sessions.set(USER_ID, makeSession(CONVERSATION_ID));
    await send(USER_ID, decideFrame({ approvalId: GATE_ID }));
    expect(h.tenantRpc).toHaveBeenCalledWith("decide_approval", { p_id: GATE_ID, p_decision: "approve" });
    expect(h.resolveReviewGate).not.toHaveBeenCalled();
  });

  it("the decide frame is not routable as any review/disclosure answer: no other handler is invoked", async () => {
    sessions.set(USER_ID, makeSession(CONVERSATION_ID));
    await send(USER_ID, decideFrame());
    expect(h.resolveReviewGate).not.toHaveBeenCalled();
  });
});

describe("reattach re-send", () => {
  const liveRow = (over: Record<string, unknown> = {}, mutateHash = false) => {
    const sample = SAMPLES[TOOLS.emailSend];
    const action = canonicalizeAction(TOOLS.emailSend, sample.input, sample.server);
    // The hash is bound to the ROW's workspace, so a row of another workspace still verifies (only the flag can hide it).
    const rowWorkspace = (over.workspace_id as string | undefined) ?? WORKSPACE_ID;
    const hash = computeActionHash({ toolName: TOOLS.emailSend, workspaceId: rowWorkspace, conversationId: CONVERSATION_ID, action });
    return {
      approval: row({ status: "pending", decided_at: null, decided_by: null, canonical_action: action, action_sha256: mutateHash ? "b".repeat(64) : hash, ...over }),
      request_count: 2,
    };
  };

  const resume = (s: ClientSession) => {
    sessions.set(USER_ID, s);
    return send(USER_ID, { type: "resume_stream", conversationId: CONVERSATION_ID, ackSeq: 0 });
  };
  const settle = () => new Promise((r) => setTimeout(r, 30));

  // The three places a client attaches to a conversation. Each must re-send the live cards.
  const ATTACH_SITES: Array<[string, (s: ClientSession) => Promise<void>]> = [
    ["resume_stream", resume],
    [
      "resume_session",
      (s) => {
        sessions.set(USER_ID, s);
        return send(USER_ID, { type: "resume_session", conversationId: CONVERSATION_ID });
      },
    ],
    [
      "start_session with resumeByContextPath (context_path)",
      (s) => {
        sessions.set(USER_ID, s);
        return send(USER_ID, { type: "start_session", resumeByContextPath: "knowledge-base/overview/doc.md" });
      },
    ],
  ];

  describe.each(ATTACH_SITES)("attach site: %s", (_name, attach) => {
    it("flag on: the live card is re-sent", async () => {
      h.flagOn.value = true;
      h.serviceRpc.mockResolvedValue({ data: [liveRow()], error: null });
      const s = makeSession(undefined);
      await attach(s);
      await settle();
      expect(h.serviceRpc).toHaveBeenCalledWith("list_live_approvals", { p_conversation: CONVERSATION_ID });
      expect(frames(s).find((f) => f.type === "approval_request")).toMatchObject({ approvalId: APPROVAL_ID, status: "pending", viewerRole: "owner" });
    });

    it("flag off: dormant, zero reads, no card", async () => {
      h.flagOn.value = false;
      h.serviceRpc.mockResolvedValue({ data: [liveRow()], error: null });
      const s = makeSession(undefined);
      await attach(s);
      await settle();
      expect(h.serviceRpc).not.toHaveBeenCalled();
      expect(frames(s).some((f) => f.type === "approval_request")).toBe(false);
    });

    it("a workspace-scoped cohort: the card is re-sent for the cohort's workspace and the flag was read WITH a workspace", async () => {
      h.flagOn.value = true;
      h.flagWorkspace.value = WORKSPACE_ID;
      h.serviceRpc.mockResolvedValue({ data: [liveRow()], error: null });
      const s = makeSession(undefined);
      await attach(s);
      await settle();
      expect(frames(s).find((f) => f.type === "approval_request")).toMatchObject({ approvalId: APPROVAL_ID });
      expect(h.flagCalls.length).toBeGreaterThan(0);
      expect(h.flagCalls.every((c) => c.workspaceId !== null)).toBe(true);
      expect(h.flagCalls.some((c) => c.workspaceId === WORKSPACE_ID)).toBe(true);
    });
  });

  // The attaching session's workspace is WORKSPACE_ID (the mocked conversation's current workspace). The early return
  // covers a flag that is off THERE; the PER-ROW check is what hides a row of a different workspace, so these two
  // tests put the flag on for the attaching workspace and vary it for the row's own workspace. Deleting the per-row
  // check in reattach.ts turns the first one red.
  it("per-row flag check: a row of ANOTHER workspace is not shown when the flag is on for the attaching session's workspace only", async () => {
    h.flagOn.value = true;
    h.flagWorkspace.value = WORKSPACE_ID;
    h.serviceRpc.mockResolvedValue({ data: [liveRow({ workspace_id: OTHER_WORKSPACE_ID })], error: null });
    const s = makeSession(CONVERSATION_ID);
    await resume(s);
    await settle();
    expect(h.serviceRpc).toHaveBeenCalledWith("list_live_approvals", { p_conversation: CONVERSATION_ID }); // the early return did NOT fire
    expect(h.flagCalls.map((c) => c.workspaceId)).toEqual(expect.arrayContaining([WORKSPACE_ID, OTHER_WORKSPACE_ID]));
    expect(frames(s).some((f) => f.type === "approval_request")).toBe(false);
    // Hidden by the flag, not by a failed hash check: no reattach-failed op.
    expect(h.warn.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-reattach-failed")).toBe(false);
  });

  it("per-row flag check, converse: the same row IS shown when the flag is on for its workspace too", async () => {
    h.flagOn.value = true;
    h.serviceRpc.mockResolvedValue({ data: [liveRow({ workspace_id: OTHER_WORKSPACE_ID })], error: null });
    const s = makeSession(CONVERSATION_ID);
    await resume(s);
    await settle();
    expect(frames(s).find((f) => f.type === "approval_request")).toMatchObject({ approvalId: APPROVAL_ID });
  });

  it("flag off for the attaching session's workspace: the early return reads no row (even if a row's workspace would be on)", async () => {
    h.flagOn.value = true;
    h.flagWorkspace.value = OTHER_WORKSPACE_ID;
    h.serviceRpc.mockResolvedValue({ data: [liveRow({ workspace_id: OTHER_WORKSPACE_ID })], error: null });
    const s = makeSession(CONVERSATION_ID);
    await resume(s);
    await settle();
    expect(h.serviceRpc).not.toHaveBeenCalled();
    expect(frames(s).some((f) => f.type === "approval_request")).toBe(false);
  });

  it("a failure to resolve the attaching session's workspace is REPORTED (approval-reattach-failed, stage), never swallowed, and does not break the attach", async () => {
    h.flagOn.value = true;
    h.resolveWorkspaceError.value = Object.assign(new Error("tenant client down"), { code: "PGRST000" });
    h.serviceRpc.mockResolvedValue({ data: [liveRow()], error: null });
    const s = makeSession(CONVERSATION_ID);
    await resume(s);
    await settle();
    const op = h.warn.mock.calls.find((c) => (c[1] as { op?: string }).op === "approval-reattach-failed");
    expect(op).toBeDefined();
    expect((op![1] as { extra: Record<string, unknown> }).extra).toMatchObject({ stage: "resolve-workspace", code: "PGRST000" });
    expect(JSON.stringify(op)).not.toContain("tenant client down");
    expect(h.serviceRpc).not.toHaveBeenCalled();
    expect(frames(s).some((f) => f.type === "error")).toBe(false);
  });

  it("flag on: live cards are re-sent from the table, built from the stored canonical action", async () => {
    h.flagOn.value = true;
    h.serviceRpc.mockResolvedValue({ data: [liveRow()], error: null });
    const s = makeSession(CONVERSATION_ID);
    await resume(s);
    await settle();
    expect(h.serviceRpc).toHaveBeenCalledWith("list_live_approvals", { p_conversation: CONVERSATION_ID });
    const card = frames(s).find((f) => f.type === "approval_request") as Extract<WSMessage, { type: "approval_request" }>;
    expect(card).toMatchObject({ approvalId: APPROVAL_ID, conversationId: CONVERSATION_ID, status: "pending", requestCount: 2, viewerRole: "owner" });
    expect(card.view.fields.map((f) => f.value).join("|")).toContain("Updated pricing");
  });

  it("flag on: agentWaiting reflects whether THIS process still holds the agent's wait for the request", async () => {
    h.flagOn.value = true;
    h.serviceRpc.mockResolvedValue({ data: [liveRow()], error: null });
    const s1 = makeSession(CONVERSATION_ID);
    await resume(s1);
    await settle();
    const idle = frames(s1).find((f) => f.type === "approval_request") as Extract<WSMessage, { type: "approval_request" }>;
    expect(idle.agentWaiting).toBe(false);

    const { registerWaiter, clearAllWaiters } = await import("@/server/approval/waiters");
    registerWaiter(APPROVAL_ID);
    try {
      const s2 = makeSession(CONVERSATION_ID);
      await resume(s2);
      await settle();
      const live = frames(s2).find((f) => f.type === "approval_request") as Extract<WSMessage, { type: "approval_request" }>;
      expect(live.agentWaiting).toBe(true);
    } finally {
      clearAllWaiters();
    }
  });

  it("flag off: zero database reads and no card (dormant)", async () => {
    h.flagOn.value = false;
    h.serviceRpc.mockResolvedValue({ data: [liveRow()], error: null });
    const s = makeSession(CONVERSATION_ID);
    await resume(s);
    await settle();
    expect(h.serviceRpc).not.toHaveBeenCalled();
    expect(frames(s).some((f) => f.type === "approval_request")).toBe(false);
  });

  it("a row whose stored action does not hash to the bound value is never rendered (the card cannot disagree with the hash)", async () => {
    h.flagOn.value = true;
    h.serviceRpc.mockResolvedValue({ data: [liveRow({}, true)], error: null });
    const s = makeSession(CONVERSATION_ID);
    await resume(s);
    await settle();
    expect(frames(s).some((f) => f.type === "approval_request")).toBe(false);
    expect(h.warn.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-reattach-failed")).toBe(true);
  });

  it("an approved-but-unconsumed row is re-sent as approved", async () => {
    h.flagOn.value = true;
    h.serviceRpc.mockResolvedValue({ data: [liveRow({ status: "approved" })], error: null });
    const s = makeSession(CONVERSATION_ID);
    await resume(s);
    await settle();
    expect(frames(s).find((f) => f.type === "approval_request")).toMatchObject({ status: "approved" });
  });

  it("a failing read never breaks the attach: one op, stream replay unaffected", async () => {
    h.flagOn.value = true;
    h.serviceRpc.mockResolvedValue({ data: null, error: { message: "boom", code: "XX000" } });
    const s = makeSession(CONVERSATION_ID);
    await resume(s);
    await settle();
    expect(h.warn.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-reattach-failed")).toBe(true);
    expect(frames(s).some((f) => f.type === "error")).toBe(false);
  });

  it("the cards are scoped to the attached conversation id", async () => {
    h.flagOn.value = true;
    h.serviceRpc.mockResolvedValue({ data: [], error: null });
    await resume(makeSession(CONVERSATION_ID));
    await settle();
    expect(h.serviceRpc).not.toHaveBeenCalledWith("list_live_approvals", { p_conversation: OTHER_CONVERSATION_ID });
  });
});

/**
 * #4672: the approval flow in the gated branch of `createCanUseTool`.
 *
 * Guard 1 (approval consume gate): a slice-1 tool call is allowed only if it consumes, exactly once, an approved and
 * unexpired request whose hash equals the hash of the full input about to run, in the same conversation. The consume
 * predicate itself lives in SQL (migration 180, proven in migration-180-approval-request.test.ts); this file proves
 * the GATE half: what it hashes, what it asks the database to consume, that only `consumed: true` is an allow, and
 * that every error, timeout, abort and unknown outcome is a deny.
 *
 * The services under test are the REAL `submitApprovalRequest`, `getApprovalStatus` and `consumeApproval` wrappers
 * over an in-memory RPC fake that implements the same predicate as the SQL (status, hash, conversation, expiry,
 * single use), so a wrong bind in the gate turns into a database-shaped rejection, not a mock agreement.
 *
 * Synthesized data only (UUID-shaped ids, reserved example domains).
 */
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const { log, mockWarn, mockReport, mockLogDecision } = vi.hoisted(() => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  mockWarn: vi.fn(),
  mockReport: vi.fn(),
  mockLogDecision: vi.fn(),
}));
vi.mock("@/server/logger", () => ({ createChildLogger: () => log, default: log }));
vi.mock("@/server/permission-log", () => ({ logPermissionDecision: mockLogDecision }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: mockWarn, reportSilentFallback: mockReport }));

import { createCanUseTool, type CanUseToolContext, type StatusGuard } from "@/server/permission-callback";
import { canonicalizeAction, computeActionHash, handlerArgsKey } from "@/server/approval/canonical";
import { ExecutionGrants } from "@/server/approval/grants";
import { clearAllWaiters, wakeWaiter, waiterCount } from "@/server/approval/waiters";
import {
  consumeApproval,
  getApprovalStatus,
  submitApprovalRequest,
  type ApprovalRpcClient,
  type RpcResult,
} from "@/server/approval/service";
import { APPROVAL_REQUIRED_TOOLS } from "@/server/approval/tools";
import {
  APPROVAL_ABORTED_DENY,
  APPROVAL_ABORTED_SPENT_DENY,
  APPROVAL_CONSUME_REJECTED_DENY,
  APPROVAL_EXPIRED_DENY,
  APPROVAL_INVALID_INPUT_DENY,
  APPROVAL_PENDING_DENY,
  APPROVAL_PRINCIPAL_CHANGED_DENY,
  APPROVAL_REJECTED_DENY,
  APPROVAL_TOO_MANY_PENDING_DENY,
  APPROVAL_UNAVAILABLE_DENY,
  consumeRejectedDeny,
  consumeRejectedIsUnusable,
} from "@/server/approval/gate-flow";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { CONVERSATION_ID, OTHER_CONVERSATION_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

// ---------------------------------------------------------------------------
// An in-memory database with the migration-180 semantics the gate depends on.
// ---------------------------------------------------------------------------

interface Row {
  id: string;
  workspace_id: string;
  conversation_id: string;
  tool_name: string;
  action_sha256: string;
  status: "pending" | "approved" | "rejected" | "expired" | "consumed";
  expires_at: number;
  requested_by_user_id: string;
}

class FakeDb {
  rows: Row[] = [];
  seq = 0;
  now = () => Date.now();
  rpcLog: Array<{ fn: string; args: Record<string, unknown> }> = [];
  /** Test switches. */
  failCreate = false;
  failRead = false;
  failConsume: "throw" | "garbage" | null = null;
  /** The pending cap the fake database reports (SQLSTATE AP429 conversation / AP430 workspace). */
  cap: "AP429" | "AP430" | null = null;
  /** Coalescing verdict returned by create. */
  notify = true;

  private id() {
    this.seq += 1;
    return `00000000-0000-4000-8000-${String(100 + this.seq).padStart(12, "0")}`;
  }

  decide(id: string, status: "approved" | "rejected") {
    const r = this.rows.find((x) => x.id === id)!;
    expect(r.status).toBe("pending");
    r.status = status;
    return r;
  }

  client: ApprovalRpcClient = {
    rpc: async (fn, args = {}): Promise<RpcResult> => {
      this.rpcLog.push({ fn, args });
      if (fn === "create_approval_request") {
        if (this.failCreate) return { data: null, error: { message: "db text that must never surface", code: "XX000" } };
        if (this.cap) return { data: null, error: { message: "approval: too many pending requests", code: this.cap } };
        const conv = args.p_conversation_id as string;
        const hash = args.p_action_sha256 as string;
        let row = this.rows.find((r) => r.conversation_id === conv && r.action_sha256 === hash && ["pending", "approved"].includes(r.status));
        const created = !row;
        if (!row) {
          row = {
            id: this.id(),
            workspace_id: args.p_workspace_id as string,
            conversation_id: conv,
            tool_name: args.p_tool_name as string,
            action_sha256: hash,
            status: "pending",
            expires_at: this.now() + 24 * 3600_000,
            requested_by_user_id: args.p_requested_by as string,
          };
          this.rows.push(row);
        }
        const count = this.rows.filter((r) => r.conversation_id === conv && r.action_sha256 === hash).length;
        return {
          data: { approval: this.view(row), created, request_count: count, notify: created && this.notify, expires_at: new Date(row.expires_at).toISOString() },
          error: null,
        };
      }
      if (fn === "consume_approval") {
        if (this.failConsume === "throw") throw new Error("socket hang up");
        if (this.failConsume === "garbage") return { data: { consumed: "true" }, error: null };
        const row = this.rows.find((r) => r.id === args.p_id);
        if (!row) return { data: { consumed: false, reason: "not_found" }, error: null };
        // The SQL predicate, conjunct by conjunct.
        if (row.status === "consumed") return { data: { consumed: false, reason: "already_consumed" }, error: null };
        if (row.status !== "approved") return { data: { consumed: false, reason: "not_approved" }, error: null };
        if (row.expires_at <= this.now()) return { data: { consumed: false, reason: "expired" }, error: null };
        if (row.action_sha256 !== args.p_hash) return { data: { consumed: false, reason: "hash_mismatch" }, error: null };
        if (row.conversation_id !== args.p_conversation) return { data: { consumed: false, reason: "wrong_conversation" }, error: null };
        row.status = "consumed";
        return { data: { consumed: true }, error: null };
      }
      if (fn === "get_approval_status") {
        if (this.failRead) return { data: null, error: { message: "boom", code: "XX000" } };
        const row = this.rows.find((r) => r.id === args.p_id);
        return { data: row ? this.view(row) : null, error: null };
      }
      throw new Error(`unexpected rpc ${fn}`);
    },
  };

  private view(r: Row) {
    return {
      id: r.id,
      workspace_id: r.workspace_id,
      conversation_id: r.conversation_id,
      requested_by_user_id: r.requested_by_user_id,
      tool_name: r.tool_name,
      action_sha256: r.action_sha256,
      status: r.status,
      expires_at: new Date(r.expires_at).toISOString(),
      decided_at: null,
      decided_by: null,
      consumed_at: null,
      expired_at: null,
      revoked_at: null,
      revoked_by: null,
      unanswered_flagged_at: null,
      created_at: new Date().toISOString(),
      canonical_action: null,
    };
  }
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const P = "mcp__soleur_platform__";
const TOOL_NAMES: string[] = [...APPROVAL_REQUIRED_TOOLS];

type Frame = Record<string, unknown> & { type: string };

function makeHarness(
  opts: {
    db?: FakeDb;
    enabled?: boolean | (() => Promise<boolean>);
    deadlineMs?: number;
    serverDerived?: ApprovalGateDeps["resolveServerDerived"];
    withApproval?: boolean;
    conversationId?: string;
    gate?: (...a: unknown[]) => Promise<string>;
    nonInteractive?: boolean;
    onRequested?: ApprovalGateDeps["onRequested"];
    onRequestedDeadlineMs?: number;
    viewerRole?: ApprovalGateDeps["viewerRole"];
    sendDelivered?: boolean;
  } = {},
) {
  const db = opts.db ?? new FakeDb();
  const controller = new AbortController();
  const row = { status: "active" };
  const updateConversationStatus = vi.fn(async (_id: string, status: string, guard?: StatusGuard) => {
    if (guard && !(guard.onlyIfStatusIn as readonly string[]).includes(row.status)) return;
    row.status = status;
  });
  const frames: Frame[] = [];
  const sendToClient = vi.fn((_u: string, m: Frame) => {
    frames.push(m);
    return opts.sendDelivered ?? true;
  });
  const isEnabled = vi.fn(async () => {
    if (typeof opts.enabled === "function") return opts.enabled();
    return opts.enabled ?? true;
  });
  const defaultDerived: ApprovalGateDeps["resolveServerDerived"] = async (tool) => {
    const s = SAMPLES[tool];
    return s && Object.keys(s.server).length ? (s.server as Record<string, string>) : undefined;
  };
  const grants = new ExecutionGrants();
  const approval: ApprovalGateDeps = {
    isEnabled,
    workspaceId: WORKSPACE_ID,
    grants,
    resolveServerDerived: vi.fn(opts.serverDerived ?? defaultDerived),
    submit: vi.fn((p) => submitApprovalRequest(db.client, p)),
    readStatus: vi.fn(async (id: string) => (await getApprovalStatus(db.client, id))?.status ?? null),
    consume: vi.fn((p) => consumeApproval(db.client, p)),
    viewerRole: vi.fn(opts.viewerRole ?? (async () => "owner" as const)),
    onRequested: opts.onRequested,
    onRequestedDeadlineMs: opts.onRequestedDeadlineMs,
    waitOptions: { deadlineMs: opts.deadlineMs ?? 60, sleep: (ms) => new Promise((r) => setTimeout(r, Math.min(ms, 15))) },
  };
  const deps = {
    abortableReviewGate: vi.fn(opts.gate ?? (() => Promise.resolve("Approve"))),
    sendToClient,
    notifyOfflineUser: vi.fn().mockResolvedValue(true),
    updateConversationStatus,
    ...(opts.withApproval === false ? {} : { approval }),
  };
  const ctx = {
    userId: USER_ID,
    conversationId: opts.conversationId ?? CONVERSATION_ID,
    leaderId: "cto",
    workspacePath: "/tmp/ws",
    platformToolNames: TOOL_NAMES.concat([`${P}create_issue`]),
    pluginMcpServerNames: [],
    repoOwner: "example-org",
    repoName: "example-repo",
    session: { abort: controller, reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: controller.signal,
    nonInteractive: opts.nonInteractive,
    deps,
  } as unknown as CanUseToolContext;
  const call = (tool: string, input: Record<string, unknown>, signal: AbortSignal = new AbortController().signal) =>
    createCanUseTool(ctx)(tool, input, { signal, toolUseID: "t", requestId: "r" } as never) as Promise<{
      behavior: string;
      message?: string;
      updatedInput?: Record<string, unknown>;
    }>;
  return { db, ctx, deps, approval, grants, controller, row, frames, call, sendToClient, isEnabled, updateConversationStatus };
}

const sampleInput = (tool: string) => structuredClone(SAMPLES[tool].input);
const expectedHash = (tool: string, input: Record<string, unknown>, conv = CONVERSATION_ID) =>
  computeActionHash({
    toolName: tool,
    workspaceId: WORKSPACE_ID,
    conversationId: conv,
    action: canonicalizeAction(tool, input, SAMPLES[tool].server),
  });
const tick = (ms = 5) => new Promise((r) => setTimeout(r, ms));
const requestFrame = (frames: Frame[]) => frames.find((f) => f.type === "approval_request")!;

/** Wait until the gate has emitted its card, then decide it and wake the in-process waiter like ws-handler does. */
async function decideWhenCardArrives(h: ReturnType<typeof makeHarness>, status: "approved" | "rejected", wake = true) {
  for (let i = 0; i < 200 && !h.frames.some((f) => f.type === "approval_request"); i++) await tick(1);
  const id = requestFrame(h.frames).approvalId as string;
  h.db.decide(id, status);
  if (wake) wakeWaiter(id, status);
  return id;
}

beforeEach(() => {
  vi.clearAllMocks();
  clearAllWaiters();
});
afterEach(() => clearAllWaiters());

// ---------------------------------------------------------------------------
// Dormancy: flag off / dependency absent => today's gated branch, byte for byte.
// ---------------------------------------------------------------------------

describe("dormant when the approval dependency is absent or the flag is off", () => {
  const transcript = async (h: ReturnType<typeof makeHarness>, tool: string) => {
    const res = await h.call(tool, sampleInput(tool));
    return {
      res,
      gateCalls: h.deps.abortableReviewGate.mock.calls.map((c) => [c[1] !== undefined, c[3], c[4]]),
      frames: h.frames.map((f) => f.type),
      statuses: h.updateConversationStatus.mock.calls.map((c) => [c[1], c[2]]),
      notified: h.deps.notifyOfflineUser.mock.calls.length,
      warn: log.warn.mock.calls.length,
      decisions: mockLogDecision.mock.calls.map((c) => c.slice(0, 4)),
    };
  };

  test.each(TOOL_NAMES)("%s: absent, disabled and a throwing flag read behave identically", async (tool) => {
    const absent = makeHarness({ withApproval: false });
    const base = await transcript(absent, tool);
    vi.clearAllMocks();
    const off = makeHarness({ enabled: false });
    const offT = await transcript(off, tool);
    vi.clearAllMocks();
    const boom = makeHarness({ enabled: () => Promise.reject(new Error("flagsmith down")) });
    const boomT = await transcript(boom, tool);

    // The review card is what a user sees today.
    expect(base.frames).toEqual(["review_gate"]);
    expect(base.gateCalls.length).toBe(1);
    expect(offT).toEqual(base);
    expect(boomT).toEqual(base);
    // Nothing of the approval path ran.
    for (const h of [off, boom]) {
      expect(h.approval.submit).not.toHaveBeenCalled();
      expect(h.approval.resolveServerDerived).not.toHaveBeenCalled();
      expect(h.db.rpcLog).toEqual([]);
      expect(waiterCount()).toBe(0);
    }
  });

  test("the flag is read once per gate and only for an approval-required tool", async () => {
    const h = makeHarness({ enabled: false });
    await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(h.isEnabled).toHaveBeenCalledTimes(1);
    const other = makeHarness();
    await other.call(`${P}create_issue`, { title: "t", body: "b" });
    expect(other.isEnabled).not.toHaveBeenCalled();
    expect(other.approval.submit).not.toHaveBeenCalled();
    expect(other.deps.abortableReviewGate).toHaveBeenCalledTimes(1);
  });

  test("a throwing flag read emits no approval op", async () => {
    const h = makeHarness({ enabled: () => Promise.reject(new Error("flagsmith down")) });
    await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(mockReport).not.toHaveBeenCalled();
    expect(mockWarn.mock.calls.filter((c) => (c[1] as { feature?: string }).feature === "approval-queue")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Pre-conditions that stay in front of the approval flow.
// ---------------------------------------------------------------------------

describe("the existing pre-checks still run first", () => {
  test("a non-interactive session denies at once, before the flag is even read", async () => {
    const h = makeHarness({ nonInteractive: true });
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res.behavior).toBe("deny");
    expect(h.isEnabled).not.toHaveBeenCalled();
    expect(h.approval.submit).not.toHaveBeenCalled();
  });

  test("an input the old card refuses to show in full is still denied, with no request created", async () => {
    const h = makeHarness();
    const input = { ...sampleInput(TOOLS.emailSend), to: "maria@exämple.test" };
    const res = await h.call(TOOLS.emailSend, input);
    expect(res.behavior).toBe("deny");
    expect(h.approval.submit).not.toHaveBeenCalled();
    expect(h.db.rpcLog).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// The live path.
// ---------------------------------------------------------------------------

describe("flag on: decision inside the wait window", () => {
  test.each(TOOL_NAMES)("%s: approve in window -> exactly one consume with the independently computed hash -> allow", async (tool) => {
    const h = makeHarness({ deadlineMs: 2000 });
    const input = sampleInput(tool);
    const pending = h.call(tool, input);
    await decideWhenCardArrives(h, "approved");
    const res = await pending;

    expect(res.behavior).toBe("allow");
    expect(h.approval.consume).toHaveBeenCalledTimes(1);
    expect(h.approval.consume).toHaveBeenCalledWith({
      id: expect.any(String),
      hash: expectedHash(tool, input),
      conversationId: CONVERSATION_ID,
    });
    expect(h.db.rows.map((r) => r.status)).toEqual(["consumed"]);
    // The old in-memory gate is not used for an approval-required tool when the flow is on.
    expect(h.deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(waiterCount()).toBe(0);
  });

  test("the card frame is built from the canonical object and carries no option strings", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const input = sampleInput(TOOLS.pushBranch);
    const pending = h.call(TOOLS.pushBranch, input);
    await decideWhenCardArrives(h, "approved");
    await pending;
    const f = requestFrame(h.frames);
    expect(f).toMatchObject({
      type: "approval_request",
      conversationId: CONVERSATION_ID,
      toolName: TOOLS.pushBranch,
      status: "pending",
      requestCount: 1,
      viewerRole: "owner",
    });
    expect(f).not.toHaveProperty("options");
    // `force` and the server-derived HEAD are on the card: the preview and the hash are the same object.
    const labels = (f.view as { fields: Array<{ label: string; value: string }> }).fields.map((r) => r.value).join("|");
    expect(labels).toContain("feat/pricing");
    expect(labels).toContain(SAMPLES[TOOLS.pushBranch].server.headSha as string);
  });

  test("the allowed input is a deep clone of what was hashed, never the live object (mutation row 8)", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const input = sampleInput(TOOLS.emailSend);
    const original = structuredClone(input);
    const pending = h.call(TOOLS.emailSend, input);
    // The agent (or a hook) mutates the live object while the gate is waiting.
    await decideWhenCardArrives(h, "approved", false);
    input.body = "SOMETHING ELSE ENTIRELY";
    (input as Record<string, unknown>).to = "attacker@example.test";
    wakeWaiter(requestFrame(h.frames).approvalId as string, "approved");
    const res = await pending;

    // The consume used the hash of the ORIGINAL; what the SDK runs is the snapshot, not the mutated object.
    expect(h.approval.consume).toHaveBeenCalledWith(expect.objectContaining({ hash: expectedHash(TOOLS.emailSend, original) }));
    expect(res.behavior).toBe("allow");
    expect(res.updatedInput).toEqual(original);
    expect(res.updatedInput).not.toBe(input);
    expect(res.updatedInput).not.toEqual(input);
  });

  test("a mutation made between the snapshot and the hash (while server-derived fields resolve) cannot reach the hash", async () => {
    const input = sampleInput(TOOLS.emailReply);
    const original = structuredClone(input);
    const h = makeHarness({
      deadlineMs: 2000,
      serverDerived: async () => {
        input.body = "swapped while the platform was resolving the recipient";
        return SAMPLES[TOOLS.emailReply].server as Record<string, string>;
      },
    });
    const pending = h.call(TOOLS.emailReply, input);
    await decideWhenCardArrives(h, "approved");
    const res = await pending;
    expect(h.approval.consume).toHaveBeenCalledWith(expect.objectContaining({ hash: expectedHash(TOOLS.emailReply, original) }));
    expect(res.updatedInput).toEqual(original);
  });

  test("only a boolean true from consume is an allow (a truthy string is not)", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    h.approval.consume = vi.fn(async () => ({ consumed: "true" }) as never);
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    expect((await pending).behavior).toBe("deny");
  });

  test("an input with a field the canonical action does not cover is denied (unbound input), nothing is requested", async () => {
    const h = makeHarness();
    const res = await h.call(TOOLS.emailSend, { ...sampleInput(TOOLS.emailSend), bcc: "attacker@example.test" });
    expect(res.behavior).toBe("deny");
    expect(res.message).toBe(APPROVAL_INVALID_INPUT_DENY);
    expect(h.approval.submit).not.toHaveBeenCalled();
    expect(h.db.rpcLog).toEqual([]);
  });

  test("harness row b: the same arguments in a different key order hash equal and consume", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const input = sampleInput(TOOLS.emailSend);
    const reordered = Object.fromEntries(Object.entries(input).reverse());
    const first = h.call(TOOLS.emailSend, input);
    const id = await decideWhenCardArrives(h, "approved");
    expect((await first).behavior).toBe("allow");
    // Same conversation, same arguments, reordered, after the first was consumed: a NEW request (single use), same hash.
    const second = h.call(TOOLS.emailSend, reordered);
    for (let i = 0; i < 200 && h.db.rows.length < 2; i++) await tick(1);
    expect(h.db.rows).toHaveLength(2);
    expect(h.db.rows[1].action_sha256).toBe(h.db.rows[0].action_sha256);
    expect(h.db.rows[1].id).not.toBe(id);
    h.controller.abort();
    await second;
  });

  test("a rejected request denies with the static text and never consumes", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.createPr, sampleInput(TOOLS.createPr));
    await decideWhenCardArrives(h, "rejected");
    const res = await pending;
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_REJECTED_DENY });
    expect(h.approval.consume).not.toHaveBeenCalled();
  });

  test("a decision made on ANOTHER host (no in-process wake) is picked up by the poll", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.kbShareCreate, sampleInput(TOOLS.kbShareCreate));
    await decideWhenCardArrives(h, "approved", false);
    const res = await pending;
    expect(res.behavior).toBe("allow");
    expect(h.approval.consume).toHaveBeenCalledTimes(1);
  });

  test("a wake that the row does not confirm is not an allow", async () => {
    const h = makeHarness({ deadlineMs: 120 });
    const pending = h.call(TOOLS.setAutonomous, sampleInput(TOOLS.setAutonomous));
    for (let i = 0; i < 200 && !h.frames.some((f) => f.type === "approval_request"); i++) await tick(1);
    wakeWaiter(requestFrame(h.frames).approvalId as string, "approved"); // the row is still pending
    const res = await pending;
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_PENDING_DENY });
    expect(h.approval.consume).not.toHaveBeenCalled();
  });

  test("the conversation is held in waiting_for_user during the wait and restored to active", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    await pending;
    expect(h.updateConversationStatus.mock.calls.map((c) => c[1])).toEqual(["waiting_for_user", "active"]);
    expect(h.row.status).toBe("active");
  });
});

// ---------------------------------------------------------------------------
// Timeout, abort: fail closed, the durable row stays pending.
// ---------------------------------------------------------------------------

describe("flag on: nothing decided in time, or the session ends", () => {
  test("timeout denies with the 'saved, do not retry now' text, leaves the row pending and mirrors one op with the approval id", async () => {
    const h = makeHarness({ deadlineMs: 40 });
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_PENDING_DENY });
    expect(APPROVAL_PENDING_DENY).toMatch(/byte-identical/);
    expect(h.db.rows.map((r) => r.status)).toEqual(["pending"]);
    expect(h.approval.consume).not.toHaveBeenCalled();
    expect(h.row.status).toBe("active");
    const timeoutOps = mockWarn.mock.calls.filter((c) => (c[1] as { op?: string }).op === "approval-wait-timeout");
    expect(timeoutOps).toHaveLength(1);
    expect((timeoutOps[0][1] as { tags: Record<string, string> }).tags.approval_id).toBe(h.db.rows[0].id);
    expect(waiterCount()).toBe(0);
  });

  test("abort during the wait denies, leaves the row pending, and an approval that arrives afterwards is never honoured", async () => {
    const h = makeHarness({ deadlineMs: 5000 });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    for (let i = 0; i < 200 && !h.frames.some((f) => f.type === "approval_request"); i++) await tick(1);
    h.controller.abort();
    const res = await pending;
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_ABORTED_DENY });
    expect(h.db.rows.map((r) => r.status)).toEqual(["pending"]);

    // The Owner approves after the abort: the row becomes approved, nobody consumes it for this dead call.
    h.db.decide(h.db.rows[0].id, "approved");
    wakeWaiter(h.db.rows[0].id, "approved");
    await tick(20);
    expect(h.approval.consume).not.toHaveBeenCalled();
    expect(h.db.rows[0].status).toBe("approved");
  });

  test("an approval and an abort landing together: the abort wins, nothing is consumed (mutation row 5)", async () => {
    const h = makeHarness({ deadlineMs: 5000 });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    for (let i = 0; i < 200 && !h.frames.some((f) => f.type === "approval_request"); i++) await tick(1);
    const id = requestFrame(h.frames).approvalId as string;
    h.db.decide(id, "approved");
    h.controller.abort();
    wakeWaiter(id, "approved");
    const res = await pending;
    expect(res.behavior).toBe("deny");
    expect(h.approval.consume).not.toHaveBeenCalled();
  });

  test("an already-aborted call performs no database read and cannot allow", async () => {
    const h = makeHarness({ deadlineMs: 5000 });
    const signal = AbortSignal.abort();
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend), signal);
    expect(res.behavior).toBe("deny");
    expect(h.approval.consume).not.toHaveBeenCalled();
    expect(h.db.rpcLog).toEqual([]); // no create, no read, no consume
    expect(h.approval.resolveServerDerived).not.toHaveBeenCalled();
    expect(h.approval.submit).not.toHaveBeenCalled();
  });

  test("the per-call signal alone also aborts the wait", async () => {
    const h = makeHarness({ deadlineMs: 5000 });
    const ac = new AbortController();
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend), ac.signal);
    for (let i = 0; i < 200 && !h.frames.some((f) => f.type === "approval_request"); i++) await tick(1);
    ac.abort();
    expect((await pending).behavior).toBe("deny");
    expect(h.approval.consume).not.toHaveBeenCalled();
  });

  test("transient read errors never allow; the wait ends at the deadline", async () => {
    const db = new FakeDb();
    db.failRead = true;
    const h = makeHarness({ db, deadlineMs: 50 });
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_PENDING_DENY });
    expect(h.approval.consume).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// Guard 1: the consume gate.
// ---------------------------------------------------------------------------

describe("Guard 1: the consume gate is fail-closed and bound to hash, conversation and single use", () => {
  test("rows 1-3: each rejected consume reason denies, emits approval-consume-rejected with the approval id, and never allows", async () => {
    for (const reason of ["hash_mismatch", "wrong_conversation", "expired", "already_consumed", "not_approved", "not_found"]) {
      vi.clearAllMocks();
      clearAllWaiters();
      const h = makeHarness({ deadlineMs: 2000 });
      h.approval.consume = vi.fn(async () => ({ consumed: false as const, reason }));
      const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
      const id = await decideWhenCardArrives(h, "approved");
      const res = await pending;
      expect(res, reason).toEqual({
        behavior: "deny",
        message: reason === "expired" ? APPROVAL_EXPIRED_DENY : reason === "not_approved" ? APPROVAL_REJECTED_DENY : APPROVAL_CONSUME_REJECTED_DENY,
      });
      const ops = mockWarn.mock.calls.filter((c) => (c[1] as { op?: string }).op === "approval-consume-rejected");
      expect(ops, reason).toHaveLength(1);
      expect((ops[0][1] as { tags: Record<string, string> }).tags.approval_id).toBe(id);
      expect((ops[0][1] as { extra: Record<string, unknown> }).extra.reason).toBe(reason);
    }
  });

  test("a consume that throws, or answers with anything but boolean true, is a deny", async () => {
    for (const mode of ["throw", "garbage"] as const) {
      vi.clearAllMocks();
      clearAllWaiters();
      const db = new FakeDb();
      db.failConsume = mode;
      const h = makeHarness({ db, deadlineMs: 2000 });
      const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
      await decideWhenCardArrives(h, "approved");
      expect((await pending).behavior, mode).toBe("deny");
    }
  });

  test("a single approval is consumed once: two identical parallel calls share the request, only one is allowed", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const input = sampleInput(TOOLS.emailSend);
    const a = h.call(TOOLS.emailSend, structuredClone(input));
    const b = h.call(TOOLS.emailSend, structuredClone(input));
    for (let i = 0; i < 200 && h.frames.filter((f) => f.type === "approval_request").length < 2; i++) await tick(1);
    expect(h.db.rows).toHaveLength(1);
    const id = h.db.rows[0].id;
    h.db.decide(id, "approved");
    wakeWaiter(id, "approved");
    const results = await Promise.all([a, b]);
    expect(results.map((r) => r.behavior).sort()).toEqual(["allow", "deny"]);
    expect(h.db.rows[0].status).toBe("consumed");
  });

  test("row 10: an approval for one action cannot be spent on a different action", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const a = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    const idA = await decideWhenCardArrives(h, "approved");
    expect((await a).behavior).toBe("allow");

    // Approve A in advance on a fresh request, then propose a DIFFERENT body: it must open its own request.
    const a2 = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    for (let i = 0; i < 200 && h.db.rows.length < 2; i++) await tick(1);
    const idA2 = h.db.rows[1].id;
    h.db.decide(idA2, "approved");
    wakeWaiter(idA2, "approved");
    expect((await a2).behavior).toBe("allow");

    const changed = { ...sampleInput(TOOLS.emailSend), body: "A different body." };
    const b = h.call(TOOLS.emailSend, changed);
    for (let i = 0; i < 200 && h.db.rows.length < 3; i++) await tick(1);
    expect(h.db.rows).toHaveLength(3);
    expect(h.db.rows[2].action_sha256).not.toBe(h.db.rows[0].action_sha256);
    expect(h.db.rows[2].status).toBe("pending");
    expect(idA).not.toBe(h.db.rows[2].id);
    h.controller.abort();
    expect((await b).behavior).toBe("deny");
  });

  test("an approval is bound to the conversation: the same arguments in another conversation open a new request", async () => {
    const db = new FakeDb();
    const h1 = makeHarness({ db, deadlineMs: 2000 });
    const a = h1.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h1, "approved");
    await a;

    const h2 = makeHarness({ db, deadlineMs: 40, conversationId: OTHER_CONVERSATION_ID });
    const res = await h2.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_PENDING_DENY });
    expect(db.rows).toHaveLength(2);
    expect(db.rows[1].conversation_id).toBe(OTHER_CONVERSATION_ID);
    expect(h2.approval.consume).not.toHaveBeenCalled();
  });

  test("row 11: a live row that is already approved is consumed at once, with no card and no wait", async () => {
    const db = new FakeDb();
    const h1 = makeHarness({ db, deadlineMs: 40 });
    await h1.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend)); // times out, row stays pending
    db.decide(db.rows[0].id, "approved"); // the Owner approves after the agent stopped waiting

    const h2 = makeHarness({ db, deadlineMs: 5000 });
    const res = await h2.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res.behavior).toBe("allow");
    expect(h2.frames.filter((f) => f.type === "approval_request")).toEqual([]);
    expect(h2.updateConversationStatus).not.toHaveBeenCalled();
    expect(db.rows).toHaveLength(1);
    expect(db.rows[0].status).toBe("consumed");
    expect(h2.approval.consume).not.toHaveBeenCalled(); // consumed inside submit, once
    expect(db.rpcLog.filter((r) => r.fn === "consume_approval")).toHaveLength(1);
    // Asking again is observable.
    expect(mockWarn.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-reproposed")).toBe(true);
  });

  test("a late approval whose consume is rejected on re-proposal denies and reports the rejection", async () => {
    const h = makeHarness({ deadlineMs: 5000 });
    h.approval.submit = vi.fn(async () => ({ kind: "consume_rejected" as const, approvalId: "x", reason: "hash_mismatch" }));
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_CONSUME_REJECTED_DENY });
    expect(mockWarn.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-consume-rejected")).toBe(true);
  });

  test("a request that is neither pending nor approved is not waitable: deny", async () => {
    const h = makeHarness({ deadlineMs: 5000 });
    h.approval.submit = vi.fn(async () => ({
      kind: "not_waitable" as const,
      requestCount: 1,
      approval: { id: "x", status: "expired" } as never,
    }));
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res.behavior).toBe("deny");
    expect(res.message).toBe(APPROVAL_UNAVAILABLE_DENY);
  });
});

// ---------------------------------------------------------------------------
// Fail closed on every other failure.
// ---------------------------------------------------------------------------

describe("every other failure is a deny with its own op", () => {
  test("the request cannot be created: deny, approval-create-failed, no card, no hold, static text only", async () => {
    const db = new FakeDb();
    db.failCreate = true;
    const h = makeHarness({ db });
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(res.message).not.toContain("db text");
    expect(h.frames).toEqual([]);
    expect(h.updateConversationStatus).not.toHaveBeenCalled();
    expect(mockReport.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-create-failed")).toBe(true);
  });

  test("server-derived fields that cannot be resolved: deny, approval-bind-failed, nothing requested", async () => {
    const h = makeHarness({ serverDerived: async () => Promise.reject(new Error("lookup failed")) });
    const res = await h.call(TOOLS.emailReply, sampleInput(TOOLS.emailReply));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.approval.submit).not.toHaveBeenCalled();
    expect(mockReport.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-bind-failed")).toBe(true);
  });

  test("a missing server-derived field fails the canonical step: deny", async () => {
    const h = makeHarness({ serverDerived: async () => undefined });
    const res = await h.call(TOOLS.pushBranch, sampleInput(TOOLS.pushBranch));
    expect(res.behavior).toBe("deny");
    expect(h.approval.submit).not.toHaveBeenCalled();
  });

  test("an input that does not satisfy the tool schema is a deny, not a throw", async () => {
    const h = makeHarness();
    const res = await h.call(TOOLS.emailSend, { to: "x@example.test" });
    expect(res.behavior).toBe("deny");
    expect(h.approval.submit).not.toHaveBeenCalled();
  });

  test("an unexpected throw inside the flow becomes a deny with approval-gate-failed", async () => {
    const h = makeHarness();
    h.approval.submit = vi.fn(async () => {
      throw new TypeError("boom");
    });
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(mockReport.mock.calls.some((c) => ["approval-gate-failed", "approval-create-failed"].includes((c[1] as { op?: string }).op ?? ""))).toBe(true);
  });

  test("a consume that rejects at the dependency boundary (not just inside the service) is a deny", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    h.approval.consume = vi.fn(async () => {
      throw new Error("pool exhausted");
    });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    // An rpc failure is "approval unavailable", not "the arguments changed".
    expect(await pending).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
  });

  test("a fault anywhere else in the flow (here: the decision logger, after the consume) denies and reports, never allows", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    mockLogDecision.mockImplementation((_k: string, _t: string, decision: string) => {
      if (decision === "allow") throw new Error("logger fault");
    });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    const res = await pending;
    mockLogDecision.mockReset();
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(mockReport.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-gate-failed")).toBe(true);
  });

  test("a delivery failure of the card or the notify hook is reported and does not decide anything", async () => {
    const onRequested = vi.fn(async () => {
      throw new Error("push provider down");
    });
    const h = makeHarness({ deadlineMs: 2000, onRequested });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    expect((await pending).behavior).toBe("allow");
    expect(onRequested).toHaveBeenCalledTimes(1);
    expect(mockWarn.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-notify-failed")).toBe(true);
  });

  test("a card that was not delivered (user offline) does not fail the request: the row and inbox item remain", async () => {
    const h = makeHarness({ deadlineMs: 40, sendDelivered: false });
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_PENDING_DENY });
    expect(h.db.rows).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// Wait-state frames: the card must know what the agent is doing, never guess (wireframes 04C vs 04D).
// ---------------------------------------------------------------------------

describe("the card is told whether the agent is still waiting (honest approved states)", () => {
  const statusFrames = (frames: Array<Record<string, unknown>>) => frames.filter((f) => f.type === "approval_status");

  test("the card is sent with agentWaiting=true: the agent is inside its wait", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    await pending;
    expect(requestFrame(h.frames)).toMatchObject({ type: "approval_request", agentWaiting: true });
  });

  test("a consumed approval is announced as consumed with the wait over", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    expect((await pending).behavior).toBe("allow");
    expect(statusFrames(h.frames)).toEqual([expect.objectContaining({ status: "consumed", agentWaiting: false, approvalId: h.db.rows[0].id })]);
  });

  test("a wait that ends undecided tells the card the agent stopped waiting while the request stays pending", async () => {
    const h = makeHarness({ deadlineMs: 40 });
    await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(statusFrames(h.frames)).toEqual([expect.objectContaining({ status: "pending", agentWaiting: false })]);
    expect(h.db.rows[0].status).toBe("pending");
  });

  test("a rejected request sends no wait-state frame of its own (the decide path settles the card)", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.createPr, sampleInput(TOOLS.createPr));
    await decideWhenCardArrives(h, "rejected");
    await pending;
    expect(statusFrames(h.frames)).toEqual([]);
  });

  test("a consume that is rejected announces nothing as consumed", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    h.db.failConsume = "garbage";
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    expect((await pending).behavior).toBe("deny");
    expect(statusFrames(h.frames).some((f) => f.status === "consumed")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Observability.
// ---------------------------------------------------------------------------

describe("markers and ops", () => {
  test("REQUESTED and CONSUMED markers reach pino at warn with ids and the tool, never the action text", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    const id = await decideWhenCardArrives(h, "approved");
    await pending;
    const lines = log.warn.mock.calls.map((c) => String(c[1]));
    const requested = lines.find((l) => l.startsWith("SOLEUR_APPROVAL_REQUESTED"));
    const consumed = lines.find((l) => l.startsWith("SOLEUR_APPROVAL_CONSUMED"));
    expect(requested).toContain(`approval_id=${id}`);
    expect(consumed).toContain(`approval_id=${id}`);
    for (const l of [requested!, consumed!]) {
      expect(l).not.toContain("Updated pricing");
      expect(l).not.toContain("maria@example.test");
    }
  });
});

// ---------------------------------------------------------------------------
// Guard 1 gaps closed by the mutation battery (test/approval-guard1-mutation.test.sh).
// ---------------------------------------------------------------------------

describe("Guard 1: terminal outcomes and abort edges are denies, and the release hands allow() the snapshot", () => {
  async function waitForCard(h: ReturnType<typeof makeHarness>) {
    for (let i = 0; i < 200 && !h.frames.some((f) => f.type === "approval_request"); i++) await tick(1);
    return requestFrame(h.frames).approvalId as string;
  }

  test("a request that expires while the agent waits denies with the expiry text and never consumes", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    const id = await waitForCard(h);
    h.db.rows[0].status = "expired";
    wakeWaiter(id, "expired");
    expect(await pending).toEqual({ behavior: "deny", message: APPROVAL_EXPIRED_DENY });
    expect(h.approval.consume).not.toHaveBeenCalled();
  });

  test("a request that another identical call already consumed denies and never consumes again", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    const id = await waitForCard(h);
    h.db.rows[0].status = "consumed";
    wakeWaiter(id, "consumed");
    expect(await pending).toEqual({ behavior: "deny", message: APPROVAL_CONSUME_REJECTED_DENY });
    expect(h.approval.consume).not.toHaveBeenCalled();
  });

  test("the re-proposal release also hands allow() the snapshot, never the live object", async () => {
    const db = new FakeDb();
    const h1 = makeHarness({ db, deadlineMs: 40 });
    await h1.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend)); // times out, row stays pending
    db.decide(db.rows[0].id, "approved");

    const input = sampleInput(TOOLS.emailSend);
    const original = structuredClone(input);
    const h2 = makeHarness({ db, deadlineMs: 5000 });
    h2.approval.submit = vi.fn(async (p) => {
      input.body = "SOMETHING ELSE ENTIRELY"; // the live object changes after the hash was taken
      return submitApprovalRequest(db.client, p);
    });
    const res = await h2.call(TOOLS.emailSend, input);
    expect(res.behavior).toBe("allow");
    expect(res.updatedInput).toEqual(original);
    expect(res.updatedInput).not.toBe(input);
  });

  test("a session that dies while the consume is in flight is a deny (the approval is spent for nothing)", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const real = h.approval.consume;
    h.approval.consume = vi.fn(async (p) => {
      const r = await real(p);
      h.controller.abort();
      return r;
    });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    // The approval is spent: the text must not claim the request is still saved.
    expect(await pending).toEqual({ behavior: "deny", message: APPROVAL_ABORTED_SPENT_DENY });
    expect(APPROVAL_ABORTED_SPENT_DENY).not.toMatch(/saved/);
    expect(h.db.rows[0].status).toBe("consumed");
  });

  test("an abort that lands while the server-derived fields resolve creates no request", async () => {
    let abort: () => void = () => {};
    const h = makeHarness({
      serverDerived: async () => {
        abort();
        return undefined;
      },
    });
    abort = () => h.controller.abort();
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_ABORTED_DENY });
    expect(h.approval.submit).not.toHaveBeenCalled();
    expect(h.db.rows).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// ADR-307 (grants, denies, caps, notification): grants, reason texts, caps, notification, honest frames, observability.
// ---------------------------------------------------------------------------

describe("consume reasons map to their own static text", () => {
  test.each([
    ["expired", APPROVAL_EXPIRED_DENY],
    ["rpc_error", APPROVAL_UNAVAILABLE_DENY],
    ["decider_not_owner", APPROVAL_PRINCIPAL_CHANGED_DENY],
    ["requester_not_member", APPROVAL_PRINCIPAL_CHANGED_DENY],
    ["hash_mismatch", APPROVAL_CONSUME_REJECTED_DENY],
    ["wrong_conversation", APPROVAL_CONSUME_REJECTED_DENY],
    // The consume lost to a revoke: the honest text is the denial, not "arguments changed / already used".
    ["not_approved", APPROVAL_REJECTED_DENY],
    ["already_consumed", APPROVAL_CONSUME_REJECTED_DENY],
    ["not_found", APPROVAL_CONSUME_REJECTED_DENY],
    ["bad_request", APPROVAL_CONSUME_REJECTED_DENY],
    ["unknown", APPROVAL_CONSUME_REJECTED_DENY],
    ["something_new", APPROVAL_CONSUME_REJECTED_DENY],
  ])("%s", (reason, text) => {
    expect(consumeRejectedDeny(reason)).toBe(text);
  });

  test("the principal-changed text says what happened and that a new Owner approval is needed, with no database text", () => {
    expect(APPROVAL_PRINCIPAL_CHANGED_DENY).toMatch(/membership or roles changed/);
    expect(APPROVAL_PRINCIPAL_CHANGED_DENY).toMatch(/new approval from a current workspace Owner/);
    expect(APPROVAL_EXPIRED_DENY).not.toMatch(/arguments changed/);
    expect(APPROVAL_UNAVAILABLE_DENY).not.toMatch(/arguments changed/);
  });

  test("a live consume rejected because the decider is no longer an Owner denies with the principal-changed text", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    h.approval.consume = vi.fn(async () => ({ consumed: false as const, reason: "decider_not_owner" }));
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    expect(await pending).toEqual({ behavior: "deny", message: APPROVAL_PRINCIPAL_CHANGED_DENY });
  });

  test("the same reason on the re-proposal path (consumed inside submit) maps the same way", async () => {
    const h = makeHarness();
    h.approval.submit = vi.fn(async () => ({ kind: "consume_rejected" as const, approvalId: "x", reason: "requester_not_member" }));
    expect(await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend))).toEqual({ behavior: "deny", message: APPROVAL_PRINCIPAL_CHANGED_DENY });
  });
});

describe("the hash key is a fail-closed dependency", () => {
  test("an unset pepper denies with the unavailable text, reports its OWN approval-key-unavailable op with the code, and creates nothing", async () => {
    const h = makeHarness();
    const saved = process.env.SENTRY_USERID_PEPPER;
    delete process.env.SENTRY_USERID_PEPPER;
    try {
      const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
      expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    } finally {
      if (saved !== undefined) process.env.SENTRY_USERID_PEPPER = saved;
    }
    expect(h.approval.submit).not.toHaveBeenCalled();
    expect(h.db.rpcLog).toEqual([]);
    const ops = mockReport.mock.calls.filter((c) => (c[1] as { op?: string }).op === "approval-key-unavailable");
    expect(ops).toHaveLength(1);
    expect((ops[0][1] as { extra: Record<string, unknown> }).extra.code).toBe("key_unavailable");
    // It no longer shares the generic gate-failure group.
    expect(mockReport.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-gate-failed")).toBe(false);
  });
});

describe("pending caps", () => {
  test.each([
    ["AP429", "conversation"],
    ["AP430", "workspace"],
  ] as const)("%s -> static too-many-pending deny, a capReached op with the scope, no card, no wait, no hold", async (code, scope) => {
    const db = new FakeDb();
    db.cap = code;
    const h = makeHarness({ db });
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_TOO_MANY_PENDING_DENY });
    expect(h.frames).toEqual([]);
    expect(h.updateConversationStatus).not.toHaveBeenCalled();
    expect(waiterCount()).toBe(0);
    const ops = mockWarn.mock.calls.filter((c) => (c[1] as { op?: string }).op === "approval-cap-reached");
    expect(ops).toHaveLength(1);
    expect((ops[0][1] as { extra: Record<string, unknown> }).extra.scope).toBe(scope);
    // Not the generic create failure.
    expect(mockReport.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-create-failed")).toBe(false);
    expect(APPROVAL_TOO_MANY_PENDING_DENY).toMatch(/answer or decline the pending requests first/);
  });
});

describe("the request notification", () => {
  test("onRequested receives the database's coalescing verdict and the expiry from the create result", async () => {
    const onRequested = vi.fn(async () => {});
    const h = makeHarness({ deadlineMs: 2000, onRequested });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    await pending;
    expect(onRequested).toHaveBeenCalledWith({
      approvalId: h.db.rows[0].id,
      created: true,
      notify: true,
      expiresAt: new Date(h.db.rows[0].expires_at).toISOString(),
    });
    const db = new FakeDb();
    db.notify = false;
    const onRequested2 = vi.fn(async () => {});
    const h2 = makeHarness({ db, deadlineMs: 40, onRequested: onRequested2 });
    await h2.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(onRequested2).toHaveBeenCalledWith(expect.objectContaining({ created: true, notify: false }));
  });

  test("a push that never settles does not hold the agent: the deadline reports notify-failed and the wait proceeds", async () => {
    const onRequested = vi.fn(() => new Promise<void>(() => {}));
    const h = makeHarness({ deadlineMs: 40, onRequested, onRequestedDeadlineMs: 20 });
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_PENDING_DENY });
    const ops = mockWarn.mock.calls.filter((c) => (c[1] as { op?: string }).op === "approval-notify-failed");
    expect(ops.some((c) => (c[1] as { extra: Record<string, unknown> }).extra.cause === "timeout")).toBe(true);
  });

  test("an abort while the push is in flight ends the gate without waiting for the push", async () => {
    const onRequested = vi.fn(() => new Promise<void>(() => {}));
    const h = makeHarness({ deadlineMs: 5000, onRequested, onRequestedDeadlineMs: 5000 });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    for (let i = 0; i < 200 && !h.frames.some((f) => f.type === "approval_request"); i++) await tick(1);
    h.controller.abort();
    expect(await pending).toEqual({ behavior: "deny", message: APPROVAL_ABORTED_DENY });
  });
});

describe("the released (re-proposal) path tells the open card it was consumed", () => {
  test("approval_status{consumed, agentWaiting:false} is emitted before allow()", async () => {
    const db = new FakeDb();
    const h1 = makeHarness({ db, deadlineMs: 40 });
    await h1.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    db.decide(db.rows[0].id, "approved");
    const h2 = makeHarness({ db, deadlineMs: 5000 });
    const res = await h2.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res.behavior).toBe("allow");
    expect(h2.frames.filter((f) => f.type === "approval_status")).toEqual([
      expect.objectContaining({ status: "consumed", agentWaiting: false, approvalId: db.rows[0].id }),
    ]);
  });

  test("a spent approval for a session that already ended is logged (aborted=true), reported and denied", async () => {
    const db = new FakeDb();
    const h1 = makeHarness({ db, deadlineMs: 40 });
    await h1.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    db.decide(db.rows[0].id, "approved");
    const h2 = makeHarness({ db, deadlineMs: 5000 });
    const real = h2.approval.submit;
    h2.approval.submit = vi.fn(async (p) => {
      const r = await real(p);
      h2.controller.abort();
      return r;
    });
    log.warn.mockClear();
    const res = await h2.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_ABORTED_SPENT_DENY });
    const consumed = log.warn.mock.calls.map((c) => String(c[1])).find((l) => l.startsWith("SOLEUR_APPROVAL_CONSUMED"));
    expect(consumed).toContain("path=reproposal");
    expect(consumed).toContain("aborted=true");
    expect(mockWarn.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-consumed-aborted")).toBe(true);
    expect(h2.grants.size()).toBe(0);
  });

  test("the live path logs CONSUMED with aborted=true BEFORE denying a session that died during the consume", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const real = h.approval.consume;
    h.approval.consume = vi.fn(async (p) => {
      const r = await real(p);
      h.controller.abort();
      return r;
    });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    await pending;
    const consumed = log.warn.mock.calls.map((c) => String(c[1])).find((l) => l.startsWith("SOLEUR_APPROVAL_CONSUMED"));
    expect(consumed).toContain("path=live");
    expect(consumed).toContain("aborted=true");
    expect(mockWarn.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-consumed-aborted")).toBe(true);
    expect(h.grants.size()).toBe(0);
  });
});

describe("silent paths are now observable", () => {
  test("an invalid-input deny and a not-covered deny each leave a warn op with the stage", async () => {
    const h = makeHarness();
    await h.call(TOOLS.pushBranch, { branch: "" });
    await h.call(TOOLS.emailSend, { ...sampleInput(TOOLS.emailSend), bcc: "attacker@example.test" });
    const stages = mockWarn.mock.calls
      .filter((c) => (c[1] as { op?: string }).op === "approval-invalid-input")
      .map((c) => (c[1] as { extra: Record<string, unknown> }).extra.stage);
    expect(stages).toEqual(["canonical", "not-covered"]);
  });

  test("a viewer-role read failure is reported once and the card falls back to the read-only member view", async () => {
    const h = makeHarness({
      deadlineMs: 40,
      viewerRole: async () => {
        throw new Error("rpc down");
      },
    });
    await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(requestFrame(h.frames)).toMatchObject({ viewerRole: "member" });
    expect(mockWarn.mock.calls.filter((c) => (c[1] as { op?: string }).op === "approval-viewer-role-failed")).toHaveLength(1);
  });

  test("poll read errors are counted and reported ONCE per wait with the count, also on the timeout op", async () => {
    const db = new FakeDb();
    db.failRead = true;
    const h = makeHarness({ db, deadlineMs: 80 });
    const res = await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_PENDING_DENY });
    const ops = mockWarn.mock.calls.filter((c) => (c[1] as { op?: string }).op === "approval-wait-read-failed");
    expect(ops).toHaveLength(1);
    const n = (ops[0][1] as { extra: { readErrors: number } }).extra.readErrors;
    expect(n).toBeGreaterThan(1);
    const timeout = mockWarn.mock.calls.find((c) => (c[1] as { op?: string }).op === "approval-wait-timeout");
    expect((timeout![1] as { extra: { readErrors: number } }).extra.readErrors).toBe(n);
  });

  test("a clean wait reports no read-failure op", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    await decideWhenCardArrives(h, "approved");
    await pending;
    expect(mockWarn.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-wait-read-failed")).toBe(false);
  });
});

describe("R1: the execution grant is written right before allow(), on both allow paths, and never on a deny", () => {
  const input = () => sampleInput(TOOLS.pushBranch);
  const key = () => handlerArgsKey(TOOLS.pushBranch, input());
  const headSha = SAMPLES[TOOLS.pushBranch].server.headSha as string;

  test("the flag turning on marks the session enforcing; a flag-off call leaves it untouched", async () => {
    const off = makeHarness({ enabled: false });
    await off.call(TOOLS.pushBranch, input());
    expect(off.grants.enforcing).toBe(false);
    expect(off.grants.size()).toBe(0);

    const on = makeHarness({ deadlineMs: 30 });
    await on.call(TOOLS.pushBranch, input());
    expect(on.grants.enforcing).toBe(true);
  });

  test("live approved path: the grant carries the approved headSha and workspace, keyed by the handler args, and is in place when allow() runs", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.pushBranch, input());
    await decideWhenCardArrives(h, "approved");
    const res = await pending;
    expect(res.behavior).toBe("allow");
    expect(h.grants.take(TOOLS.pushBranch, key())).toEqual({ workspaceId: WORKSPACE_ID, headSha });
    expect(h.grants.take(TOOLS.pushBranch, key())).toBeNull(); // one-shot
  });

  test("released (re-proposal) path: the same grant is written", async () => {
    const db = new FakeDb();
    const h1 = makeHarness({ db, deadlineMs: 40 });
    await h1.call(TOOLS.pushBranch, input());
    db.decide(db.rows[0].id, "approved");
    const h2 = makeHarness({ db, deadlineMs: 5000 });
    expect((await h2.call(TOOLS.pushBranch, input())).behavior).toBe("allow");
    expect(h2.grants.take(TOOLS.pushBranch, key())).toEqual({ workspaceId: WORKSPACE_ID, headSha });
  });

  test("a tool without a server-derived commit gets a grant with only the workspace", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.setAutonomous, sampleInput(TOOLS.setAutonomous));
    await decideWhenCardArrives(h, "approved");
    expect((await pending).behavior).toBe("allow");
    expect(h.grants.take(TOOLS.setAutonomous, handlerArgsKey(TOOLS.setAutonomous, sampleInput(TOOLS.setAutonomous)))).toEqual({
      workspaceId: WORKSPACE_ID,
      headSha: undefined,
    });
  });

  test("the grant is written BEFORE allow(): if writing it fails the call is a deny, never an allow without a grant", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    h.grants.put = () => {
      throw new Error("grant store fault");
    };
    const pending = h.call(TOOLS.pushBranch, input());
    await decideWhenCardArrives(h, "approved");
    expect(await pending).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(mockReport.mock.calls.some((c) => (c[1] as { op?: string }).op === "approval-gate-failed")).toBe(true);
  });

  test.each([
    ["rejected", async (h: ReturnType<typeof makeHarness>) => void (await decideWhenCardArrives(h, "rejected"))],
    ["timeout", async () => {}],
  ])("a %s outcome never writes a grant", async (_name, act) => {
    const h = makeHarness({ deadlineMs: 40 });
    const pending = h.call(TOOLS.pushBranch, input());
    await act(h);
    expect((await pending).behavior).toBe("deny");
    expect(h.grants.size()).toBe(0);
  });

  test("a consume rejection, a cap and an aborted call never write a grant", async () => {
    const rej = makeHarness({ deadlineMs: 2000 });
    rej.approval.consume = vi.fn(async () => ({ consumed: false as const, reason: "hash_mismatch" }));
    const p = rej.call(TOOLS.pushBranch, input());
    await decideWhenCardArrives(rej, "approved");
    expect((await p).behavior).toBe("deny");
    expect(rej.grants.size()).toBe(0);

    const db = new FakeDb();
    db.cap = "AP429";
    const capped = makeHarness({ db });
    await capped.call(TOOLS.pushBranch, input());
    expect(capped.grants.size()).toBe(0);

    const ab = makeHarness();
    await ab.call(TOOLS.pushBranch, input(), AbortSignal.abort());
    expect(ab.grants.size()).toBe(0);
  });

  test("a grant keyed for one set of arguments is not returned for another", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const pending = h.call(TOOLS.pushBranch, input());
    await decideWhenCardArrives(h, "approved");
    await pending;
    expect(h.grants.take(TOOLS.pushBranch, handlerArgsKey(TOOLS.pushBranch, { branch: "other-branch" }))).toBeNull();
  });
});

describe("concurrent gates for the same approval share one waiter (refcounted)", () => {
  test("the first gate finishing does not drop the waiter the second still waits on", async () => {
    const h = makeHarness({ deadlineMs: 2000 });
    const input = sampleInput(TOOLS.emailSend);
    const a = h.call(TOOLS.emailSend, structuredClone(input));
    const b = h.call(TOOLS.emailSend, structuredClone(input));
    for (let i = 0; i < 200 && h.frames.filter((f) => f.type === "approval_request").length < 2; i++) await tick(1);
    expect(waiterCount()).toBe(1);
    const id = h.db.rows[0].id;
    h.db.decide(id, "approved");
    wakeWaiter(id, "approved");
    await Promise.all([a, b]);
    expect(waiterCount()).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Round 2 (ADR-307 rollback / observability): sticky enforcing denies EVERY approval-required tool, the card never keeps
// claiming "your agent is continuing" after a failed consume, and the failing RPC's code is not dropped.
// ---------------------------------------------------------------------------

describe("a flag that goes off (or fails to read) after the flow ran in this session denies every approval-required tool", () => {
  test.each(TOOL_NAMES)("%s: flag on, then off, on ONE ExecutionGrants object -> terminal unavailable deny, no review card, no request", async (tool) => {
    const on = makeHarness({ deadlineMs: 20 });
    await on.call(tool, sampleInput(tool)); // the flow runs: grants.enforcing becomes true (the wait ends undecided)
    expect(on.grants.enforcing).toBe(true);

    for (const enabled of [false, () => Promise.reject(new Error("flagsmith down"))] as const) {
      const off = makeHarness({ enabled });
      off.approval.grants = on.grants; // the SAME per-session object, as agent-runner shares it
      const res = await off.call(tool, sampleInput(tool));
      expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
      // The legacy requester-answerable card must not come back.
      expect(off.deps.abortableReviewGate).not.toHaveBeenCalled();
      expect(off.frames.map((f) => f.type)).toEqual([]);
      expect(off.approval.submit).not.toHaveBeenCalled();
      expect(off.db.rpcLog).toEqual([]);
    }
  });

  test("a session the flow NEVER ran in still falls back to the legacy gate when the flag is off", async () => {
    const off = makeHarness({ enabled: false });
    expect(off.grants.enforcing).toBe(false);
    await off.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(off.deps.abortableReviewGate).toHaveBeenCalledTimes(1);
  });

  test("the terminal texts tell the agent not to retry in this conversation", () => {
    expect(APPROVAL_UNAVAILABLE_DENY).toMatch(/Do not retry in this conversation/);
    expect(APPROVAL_UNAVAILABLE_DENY).toMatch(/not performed/);
  });
});

describe("a consume that does not release stops the card claiming the agent is continuing", () => {
  test.each([
    ["hash_mismatch", "approved"],
    ["rpc_error", "approved"],
    ["decider_not_owner", "approved"],
    ["expired", "expired"],
    ["not_approved", "rejected"],
    ["already_consumed", "consumed"],
  ] as const)("live path, reason %s -> approval_status %s with agentWaiting=false", async (reason, status) => {
    const h = makeHarness({ deadlineMs: 2000 });
    h.approval.consume = vi.fn(async () => ({ consumed: false as const, reason }));
    const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    const id = await decideWhenCardArrives(h, "approved");
    expect((await pending).behavior).toBe("deny");
    expect(h.frames.filter((f) => f.type === "approval_status")).toEqual([
      expect.objectContaining({ approvalId: id, status, agentWaiting: false }),
    ]);
  });

  test.each(["decider_not_owner", "requester_not_member"] as const)(
    "reason %s leaves the row approved but flags the status frame unusable (the card must not say 'ask again'); other reasons never do",
    async (reason) => {
      const h = makeHarness({ deadlineMs: 2000 });
      h.approval.consume = vi.fn(async () => ({ consumed: false as const, reason }));
      const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
      await decideWhenCardArrives(h, "approved");
      await pending;
      expect(h.frames.filter((f) => f.type === "approval_status")).toEqual([
        expect.objectContaining({ status: "approved", agentWaiting: false, unusable: true }),
      ]);
      expect(consumeRejectedIsUnusable(reason)).toBe(true);
    },
  );

  test("hash_mismatch / rpc_error / not_approved / expired / already_consumed are not flagged unusable", () => {
    for (const r of ["hash_mismatch", "rpc_error", "not_approved", "expired", "already_consumed", "not_found"]) {
      expect(consumeRejectedIsUnusable(r)).toBe(false);
    }
  });

  test("the re-proposal path flags an unusable approval the same way", async () => {
    const h = makeHarness();
    h.approval.submit = vi.fn(async () => ({ kind: "consume_rejected" as const, approvalId: "x", reason: "decider_not_owner" }));
    await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(h.frames.filter((f) => f.type === "approval_status")).toEqual([
      expect.objectContaining({ approvalId: "x", status: "approved", unusable: true }),
    ]);
  });

  describe("not_approved: one best-effort status read tells a revoke from the sweep", () => {
    const run = async (read: (real: () => Promise<string | null>) => Promise<string | null>) => {
      const h = makeHarness({ deadlineMs: 2000 });
      let consumed = false;
      h.approval.consume = vi.fn(async () => {
        consumed = true;
        return { consumed: false as const, reason: "not_approved" };
      });
      const real = h.approval.readStatus;
      h.approval.readStatus = vi.fn(async (id: string) => (consumed ? read(() => real(id)) : real(id))) as typeof h.approval.readStatus;
      const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
      await decideWhenCardArrives(h, "approved");
      return { res: await pending, h };
    };

    test("a row that expired meanwhile maps to the expired deny text and the expired card status, not 'Owner denied'", async () => {
      const { res, h } = await run(async () => "expired");
      expect(res).toEqual({ behavior: "deny", message: APPROVAL_EXPIRED_DENY });
      expect(h.frames.filter((f) => f.type === "approval_status")).toEqual([expect.objectContaining({ status: "expired", agentWaiting: false })]);
    });

    test("a row that was rejected (a revoke) keeps the denial text and the rejected card status", async () => {
      const { res, h } = await run(async () => "rejected");
      expect(res).toEqual({ behavior: "deny", message: APPROVAL_REJECTED_DENY });
      expect(h.frames.filter((f) => f.type === "approval_status")).toEqual([expect.objectContaining({ status: "rejected" })]);
    });

    test("a failed or empty read keeps the safe default (the denial), and the deny stays static", async () => {
      for (const read of [async () => Promise.reject(new Error("db text that must never surface")), async () => null]) {
        const { res } = await run(read as never);
        expect(res).toEqual({ behavior: "deny", message: APPROVAL_REJECTED_DENY });
      }
    });
  });

  test("re-proposal path (consume rejected inside submit) emits the same settle frame", async () => {
    const h = makeHarness();
    h.approval.submit = vi.fn(async () => ({ kind: "consume_rejected" as const, approvalId: "x", reason: "hash_mismatch" }));
    await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    expect(h.frames.filter((f) => f.type === "approval_status")).toEqual([
      expect.objectContaining({ approvalId: "x", status: "approved", agentWaiting: false }),
    ]);
  });

  test("the byte-identical-arguments text names the server-derived commit for a push", () => {
    expect(APPROVAL_CONSUME_REJECTED_DENY).toMatch(/commit the server derives from the workspace HEAD/);
  });
});

describe("the failing RPC's code is kept (never its message)", () => {
  test("a consume that throws with a code reports it in extra.code, and a coded rpc_error result does too", async () => {
    const boom = Object.assign(new Error("db text that must never surface"), { code: "57014" });
    for (const consume of [
      async () => {
        throw boom;
      },
      async () => ({ consumed: false as const, reason: "rpc_error", code: "57014" }),
    ]) {
      vi.clearAllMocks();
      clearAllWaiters();
      const h = makeHarness({ deadlineMs: 2000 });
      h.approval.consume = vi.fn(consume);
      const pending = h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
      await decideWhenCardArrives(h, "approved");
      expect(await pending).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
      const op = mockWarn.mock.calls.find((c) => (c[1] as { op?: string }).op === "approval-consume-rejected");
      expect((op![1] as { extra: Record<string, unknown> }).extra).toMatchObject({ reason: "rpc_error", code: "57014" });
      expect(JSON.stringify(op)).not.toContain("db text that must never surface");
    }
  });

  test("the real consumeApproval keeps the RPC error code on an rpc_error result", async () => {
    const client = { rpc: async () => ({ data: null, error: { message: "x", code: "57014" } }) } as unknown as ApprovalRpcClient;
    expect(await consumeApproval(client, { id: "a", hash: "a".repeat(64), conversationId: CONVERSATION_ID })).toEqual({
      consumed: false,
      reason: "rpc_error",
      code: "57014",
    });
  });

  test("poll read errors keep the last error's code on the one wait-read-failed op", async () => {
    const db = new FakeDb();
    db.failRead = true; // the fake answers { code: "XX000" }
    const h = makeHarness({ db, deadlineMs: 80 });
    await h.call(TOOLS.emailSend, sampleInput(TOOLS.emailSend));
    const op = mockWarn.mock.calls.find((c) => (c[1] as { op?: string }).op === "approval-wait-read-failed");
    expect((op![1] as { extra: Record<string, unknown> }).extra).toMatchObject({ code: "XX000" });
  });
});

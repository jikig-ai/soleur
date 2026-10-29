/**
 * #4672 (ADR-307): the PRODUCTION gate-deps factory `createApprovalGateDeps` (server/approval/gate.ts), pinned.
 *
 * Every other gate test hand-builds an `ApprovalGateDeps`, so the one place that wires the flag seam, the service-role RPC
 * wrappers, the tenant client reads and the per-session grants was unpinned: a factory that built its own
 * `ExecutionGrants`, consumed unconditionally, always answered "owner", or ignored the connected repository still passed
 * every gate test. This file builds the REAL factory over injected RPC and tenant clients and asserts what leaves it, and
 * then composes the gate with the REAL `kb_share_create` handler over ONE grants object (the wiring agent-runner does).
 *
 * Synthesized data only.
 */
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";

const m = vi.hoisted(() => ({
  getRuntimeFlag: vi.fn(),
  createShare: vi.fn(),
  currentWorkspace: { value: "00000000-0000-4000-8000-000000000001" },
}));

vi.mock("@/lib/supabase/service", () => ({ createServiceClient: () => ({}) }));
vi.mock("@/lib/supabase/tenant", () => ({ getFreshTenantClient: vi.fn(async () => ({})) }));
vi.mock("@/server/approval/notify", () => ({ notifyApprovalRequested: vi.fn(async () => true) }));
vi.mock("@/lib/feature-flags/server", () => ({ getRuntimeFlag: (...a: unknown[]) => m.getRuntimeFlag(...a) }));
vi.mock("@/server/logger", () => {
  const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() };
  return { default: log, createChildLogger: () => log };
});
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));
vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: (name: string, description: string, _schema: unknown, handler: Function) => ({ name, description, handler }),
}));
vi.mock("@/server/kb-share", () => ({
  createShare: (...a: unknown[]) => m.createShare(...a),
  listShares: vi.fn(),
  revokeShare: vi.fn(),
  previewShare: vi.fn(),
}));
vi.mock("@/server/workspace-resolver", () => ({ resolveCurrentWorkspaceId: vi.fn(async () => m.currentWorkspace.value) }));

import { createApprovalGateDeps } from "@/server/approval/gate";
import { runApprovalGate, APPROVAL_UNAVAILABLE_DENY } from "@/server/approval/gate-flow";
import { ExecutionGrants } from "@/server/approval/grants";
import { canonicalizeAction, computeActionHash } from "@/server/approval/canonical";
import { buildKbShareTools } from "@/server/kb-share-tools";
import type { ApprovalRpcClient, RpcResult } from "@/server/approval/service";
import { clearAllWaiters } from "@/server/approval/waiters";
import { CONVERSATION_ID, MESSAGE_ID, OTHER_WORKSPACE_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

const HEAD = "d".repeat(40);
const REPO = "example-org/example-repo";
const HASH = "a".repeat(64);

beforeEach(() => {
  vi.clearAllMocks();
  clearAllWaiters();
  m.currentWorkspace.value = WORKSPACE_ID;
  process.env.SENTRY_USERID_PEPPER = "gate-deps-test-pepper";
});

function rpcRecorder(answer: (fn: string, args: Record<string, unknown>) => RpcResult) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const client: ApprovalRpcClient = {
    rpc: async (fn, args = {}) => {
      calls.push({ fn, args });
      return answer(fn, args);
    },
  };
  return { client, calls };
}

interface TenantFake {
  rpcAnswer: { data: unknown; error: unknown };
  senderRow: { data: unknown; error: unknown };
  rpcCalls: Array<{ fn: string; args?: Record<string, unknown> }>;
  fromCalls: Array<{ table: string; cols: string; col: string; val: string }>;
  client: () => Promise<never>;
}
function tenantFake(): TenantFake {
  const t: TenantFake = {
    rpcAnswer: { data: true, error: null },
    senderRow: { data: { sender: "sender@example.test" }, error: null },
    rpcCalls: [],
    fromCalls: [],
    client: async () =>
      ({
        rpc: async (fn: string, args?: Record<string, unknown>) => {
          t.rpcCalls.push({ fn, args });
          return t.rpcAnswer;
        },
        from: (table: string) => ({
          select: (cols: string) => ({
            eq: (col: string, val: string) => ({
              maybeSingle: async () => {
                t.fromCalls.push({ table, cols, col, val });
                return t.senderRow;
              },
            }),
          }),
        }),
      }) as never,
  };
  return t;
}

function makeDeps(over: Partial<Parameters<typeof createApprovalGateDeps>[0]> = {}) {
  const grants = new ExecutionGrants();
  const rpc = rpcRecorder(() => ({ data: null, error: null }));
  const tenant = tenantFake();
  const headSha = vi.fn(async (_p: string) => HEAD);
  const deps = createApprovalGateDeps({
    userId: USER_ID,
    workspaceId: WORKSPACE_ID,
    repoSlug: REPO,
    workspacePath: "/tmp/ws-gate-deps",
    grants,
    serviceClient: () => rpc.client,
    tenantClient: tenant.client,
    headSha,
    ...over,
  });
  return { deps, grants, rpc, tenant, headSha };
}

describe("createApprovalGateDeps: the grants object", () => {
  it("exposes the SAME ExecutionGrants object it was given (not a copy, not a fresh instance)", () => {
    const { deps, grants } = makeDeps();
    expect(deps.grants).toBe(grants);
    expect(deps.workspaceId).toBe(WORKSPACE_ID);
  });

  it("a gate run through the factory's deps turns THAT object enforcing", async () => {
    const { deps, grants } = makeDeps({ isEnabled: async () => true });
    expect(grants.enforcing).toBe(false);
    await runApprovalGate({
      toolName: TOOLS.emailSuppress,
      toolInput: { recipient: "r@example.test", reason: "manual" },
      callSignal: undefined,
      controllerSignal: new AbortController().signal,
      userId: USER_ID,
      conversationId: CONVERSATION_ID,
      approval: deps,
      sendToClient: () => true,
      hold: async (_id, _s, wait) => wait(),
      allow: (input) => ({ behavior: "allow", updatedInput: input }),
      logDecision: () => {},
    });
    expect(grants.enforcing).toBe(true);
  });
});

describe("createApprovalGateDeps: RPC forwarding", () => {
  it("consume forwards consume_approval with the id, the hash and the conversation, and returns the database verdict", async () => {
    const rpc = rpcRecorder(() => ({ data: { consumed: false, reason: "hash_mismatch" }, error: null }));
    const { deps } = makeDeps({ serviceClient: () => rpc.client });
    const res = await deps.consume({ id: "x-id", hash: HASH, conversationId: CONVERSATION_ID });
    expect(rpc.calls).toEqual([{ fn: "consume_approval", args: { p_id: "x-id", p_hash: HASH, p_conversation: CONVERSATION_ID } }]);
    // Never an unconditional release: only the database's `consumed: true` is one.
    expect(res).toEqual({ consumed: false, reason: "hash_mismatch" });
    const ok = rpcRecorder(() => ({ data: { consumed: true }, error: null }));
    const { deps: deps2 } = makeDeps({ serviceClient: () => ok.client });
    expect(await deps2.consume({ id: "x-id", hash: HASH, conversationId: CONVERSATION_ID })).toEqual({ consumed: true });
  });

  it("readStatus forwards get_approval_status with the id and returns the row's own status (null for no row)", async () => {
    const statusRow = (status: string) => ({
      id: "x-id",
      status,
      conversation_id: CONVERSATION_ID,
      action_sha256: HASH,
      workspace_id: WORKSPACE_ID,
      tool_name: TOOLS.emailSend,
      expires_at: new Date().toISOString(),
      created_at: new Date().toISOString(),
    });
    for (const status of ["pending", "approved", "rejected", "expired", "consumed"]) {
      const rpc = rpcRecorder(() => ({ data: statusRow(status), error: null }));
      const { deps } = makeDeps({ serviceClient: () => rpc.client });
      expect(await deps.readStatus("x-id")).toBe(status);
      expect(rpc.calls).toEqual([{ fn: "get_approval_status", args: { p_id: "x-id" } }]);
    }
    const none = rpcRecorder(() => ({ data: null, error: null }));
    expect(await makeDeps({ serviceClient: () => none.client }).deps.readStatus("x-id")).toBeNull();
  });

  it("submit forwards create_approval_request with the workspace, conversation, requester, tool, hash and canonical action", async () => {
    const pendingRow = {
      id: "x-id",
      workspace_id: WORKSPACE_ID,
      conversation_id: CONVERSATION_ID,
      requested_by_user_id: USER_ID,
      tool_name: TOOLS.emailSend,
      action_sha256: HASH,
      status: "pending",
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
      created_at: new Date().toISOString(),
    };
    const rpc = rpcRecorder(() => ({ data: { approval: pendingRow, created: true, request_count: 1, notify: true }, error: null }));
    const { deps } = makeDeps({ serviceClient: () => rpc.client });
    const action = canonicalizeAction(TOOLS.emailSend, SAMPLES[TOOLS.emailSend].input, undefined);
    const res = await deps.submit({
      workspaceId: WORKSPACE_ID,
      conversationId: CONVERSATION_ID,
      requestedByUserId: USER_ID,
      toolName: TOOLS.emailSend,
      actionSha256: HASH,
      canonicalAction: action,
    });
    expect(rpc.calls).toEqual([
      {
        fn: "create_approval_request",
        args: {
          p_workspace_id: WORKSPACE_ID,
          p_conversation_id: CONVERSATION_ID,
          p_requested_by: USER_ID,
          p_tool_name: TOOLS.emailSend,
          p_action_sha256: HASH,
          p_canonical_action: action,
        },
      },
    ]);
    expect(res).toMatchObject({ kind: "wait", created: true });
  });

  it("the service client is created once and reused across calls", async () => {
    const make = vi.fn(() => rpcRecorder(() => ({ data: null, error: null })).client);
    const { deps } = makeDeps({ serviceClient: make });
    await deps.readStatus("a");
    await deps.readStatus("b");
    expect(make).toHaveBeenCalledTimes(1);
  });
});

describe("createApprovalGateDeps: resolveServerDerived", () => {
  it("email_reply: the STORED sender of the owner-scoped inbound item, read by the message id the model named", async () => {
    const { deps, tenant } = makeDeps();
    const out = await deps.resolveServerDerived(TOOLS.emailReply, { messageId: MESSAGE_ID });
    expect(out).toEqual({ recipient: "sender@example.test" });
    expect(tenant.fromCalls).toEqual([{ table: "email_triage_items", cols: "id, sender", col: "id", val: MESSAGE_ID }]);
  });

  it("email_reply: no message id, a read error, or an empty / non-string sender throws (the action is not approvable)", async () => {
    const { deps, tenant } = makeDeps();
    await expect(deps.resolveServerDerived(TOOLS.emailReply, {})).rejects.toThrow();
    await expect(deps.resolveServerDerived(TOOLS.emailReply, { messageId: 7 })).rejects.toThrow();
    tenant.senderRow = { data: { sender: "ok@example.test" }, error: { code: "XX000" } };
    await expect(deps.resolveServerDerived(TOOLS.emailReply, { messageId: MESSAGE_ID })).rejects.toThrow();
    for (const data of [null, { sender: "" }, { sender: null }, { sender: 5 }]) {
      tenant.senderRow = { data, error: null };
      await expect(deps.resolveServerDerived(TOOLS.emailReply, { messageId: MESSAGE_ID })).rejects.toThrow();
    }
  });

  it("push: the connected repository and the workspace HEAD resolved FROM THE WORKSPACE PATH", async () => {
    const { deps, headSha } = makeDeps();
    const out = await deps.resolveServerDerived(TOOLS.pushBranch, { branch: "feat-x", force: false });
    expect(out).toEqual({ repo: REPO, headSha: HEAD });
    expect(headSha).toHaveBeenCalledWith("/tmp/ws-gate-deps");
  });

  it("PR and workflow trigger: the connected repository only", async () => {
    const { deps, headSha } = makeDeps();
    expect(await deps.resolveServerDerived(TOOLS.createPr, {})).toEqual({ repo: REPO });
    expect(await deps.resolveServerDerived(TOOLS.triggerWorkflow, {})).toEqual({ repo: REPO });
    expect(headSha).not.toHaveBeenCalled();
  });

  it("push / PR / trigger with NO connected repository throw (nothing to bind)", async () => {
    const { deps } = makeDeps({ repoSlug: "" });
    for (const tool of [TOOLS.pushBranch, TOOLS.createPr, TOOLS.triggerWorkflow]) {
      await expect(deps.resolveServerDerived(tool, {}), tool).rejects.toThrow();
    }
  });

  it("push: a HEAD that cannot be read throws; tools with no server-derived field resolve to undefined", async () => {
    const { deps } = makeDeps({
      headSha: async () => {
        throw new Error("not a git repository");
      },
    });
    await expect(deps.resolveServerDerived(TOOLS.pushBranch, {})).rejects.toThrow();
    for (const tool of [TOOLS.emailSend, TOOLS.emailSuppress, TOOLS.kbShareCreate, TOOLS.setAutonomous]) {
      expect(await deps.resolveServerDerived(tool, {}), tool).toBeUndefined();
    }
  });
});

describe("createApprovalGateDeps: the DEFAULT workspace HEAD reader (real git, no injected headSha)", () => {
  const roots: string[] = [];
  afterAll(() => {
    for (const r of roots) rmSync(r, { recursive: true, force: true });
  });
  const git = (cwd: string, ...args: string[]) =>
    execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.test", ...args], { cwd, stdio: "pipe", encoding: "utf8" }).trim();
  function repo(files: number): { dir: string; head: string } {
    const dir = mkdtempSync(join(tmpdir(), "gate-deps-head-"));
    roots.push(dir);
    git(dir, "init", "-q", "-b", "main");
    for (let i = 0; i < files; i++) {
      writeFileSync(join(dir, `f${i}.txt`), `content ${i}`);
      git(dir, "add", ".");
      git(dir, "commit", "-q", "-m", `c${i}`);
    }
    return { dir, head: git(dir, "rev-parse", "HEAD") };
  }

  it("push binds the HEAD of THE WORKSPACE PATH (not the process cwd's repository), as a bare commit sha", async () => {
    const a = repo(1);
    const b = repo(2);
    expect(a.head).not.toBe(b.head);
    const deps = (dir: string) =>
      createApprovalGateDeps({ userId: USER_ID, workspaceId: WORKSPACE_ID, repoSlug: REPO, workspacePath: dir, grants: new ExecutionGrants(), tenantClient: tenantFake().client });
    expect(await deps(a.dir).resolveServerDerived(TOOLS.pushBranch, { branch: "feat-x" })).toEqual({ repo: REPO, headSha: a.head });
    expect(await deps(b.dir).resolveServerDerived(TOOLS.pushBranch, { branch: "feat-x" })).toEqual({ repo: REPO, headSha: b.head });
  });

  it("a workspace that is not a git repository (or has no commit) is not approvable: the resolver throws", async () => {
    const empty = mkdtempSync(join(tmpdir(), "gate-deps-nogit-"));
    roots.push(empty);
    const d = createApprovalGateDeps({ userId: USER_ID, workspaceId: WORKSPACE_ID, repoSlug: REPO, workspacePath: empty, grants: new ExecutionGrants(), tenantClient: tenantFake().client });
    await expect(d.resolveServerDerived(TOOLS.pushBranch, {})).rejects.toThrow();
  });
});

describe("createApprovalGateDeps: viewerRole", () => {
  it("is 'owner' only for a clean `true`, asked of is_workspace_owner for THIS workspace and user", async () => {
    const { deps, tenant } = makeDeps();
    tenant.rpcAnswer = { data: true, error: null };
    expect(await deps.viewerRole()).toBe("owner");
    expect(tenant.rpcCalls).toEqual([{ fn: "is_workspace_owner", args: { p_workspace_id: WORKSPACE_ID, p_user_id: USER_ID } }]);
  });

  it("is 'member' for false, null and any non-true answer", async () => {
    const { deps, tenant } = makeDeps();
    for (const data of [false, null, undefined, "true", 1, { owner: true }]) {
      tenant.rpcAnswer = { data, error: null };
      expect(await deps.viewerRole(), String(data)).toBe("member");
    }
  });

  it("a read error is thrown (the gate reports it and shows the read-only card); it is never an owner", async () => {
    const { deps, tenant } = makeDeps();
    tenant.rpcAnswer = { data: true, error: { code: "XX000" } };
    await expect(deps.viewerRole()).rejects.toThrow();
  });
});

describe("createApprovalGateDeps: the flag seam", () => {
  it("the default isEnabled reads the REAL approval-queue flag with the user and the workspace", async () => {
    m.getRuntimeFlag.mockResolvedValue(true);
    const { deps } = makeDeps();
    expect(await deps.isEnabled()).toBe(true);
    expect(m.getRuntimeFlag).toHaveBeenCalledWith("approval-queue", expect.objectContaining({ userId: USER_ID, orgId: WORKSPACE_ID }));
  });

  it("the default is OFF when the flag is off or unreadable (never on by default)", async () => {
    m.getRuntimeFlag.mockResolvedValue(false);
    expect(await makeDeps().deps.isEnabled()).toBe(false);
    m.getRuntimeFlag.mockRejectedValue(new Error("flagsmith down"));
    expect(await makeDeps().deps.isEnabled()).toBe(false);
  });

  it("an injected isEnabled replaces the flag read", async () => {
    const { deps } = makeDeps({ isEnabled: async () => true });
    expect(await deps.isEnabled()).toBe(true);
    expect(m.getRuntimeFlag).not.toHaveBeenCalled();
  });
});

describe("createApprovalGateDeps: onRequested", () => {
  it("pushes only for a NEW request the database said to notify about, with the workspace and the expiry", async () => {
    const notifyRequested = vi.fn(async () => true);
    const { deps } = makeDeps({ notifyRequested });
    await deps.onRequested!({ approvalId: "ap", created: true, notify: true, expiresAt: "2026-11-01T00:00:00Z" });
    expect(notifyRequested).toHaveBeenCalledWith("ap", WORKSPACE_ID, "2026-11-01T00:00:00Z");
    await deps.onRequested!({ approvalId: "ap", created: false, notify: true, expiresAt: "x" });
    await deps.onRequested!({ approvalId: "ap", created: true, notify: false, expiresAt: "x" });
    expect(notifyRequested).toHaveBeenCalledTimes(1);
  });

  it("a dispatch that reaches nobody throws, so the gate reports approval-notify-failed", async () => {
    const { deps } = makeDeps({ notifyRequested: async () => false });
    await expect(deps.onRequested!({ approvalId: "ap", created: true, notify: true, expiresAt: "x" })).rejects.toThrow();
  });
});

// ---------------------------------------------------------------------------
// The gate composed with the REAL kb_share_create handler over ONE grants object (what agent-runner wires).
// ---------------------------------------------------------------------------

describe("composed: factory deps -> gate -> the real kb_share_create handler, over one shared grants object", () => {
  const input = { documentPath: "knowledge-base/pricing/q4.md" };

  /** A database that already holds an APPROVED live row for this exact action: the gate consumes it in submit and releases. */
  function approvedDb(workspaceId: string) {
    const action = canonicalizeAction(TOOLS.kbShareCreate, input, undefined);
    const hash = computeActionHash({ toolName: TOOLS.kbShareCreate, workspaceId, conversationId: CONVERSATION_ID, action });
    return rpcRecorder((fn) => {
      if (fn === "create_approval_request") {
        return {
          data: {
            approval: {
              id: "ap-1",
              workspace_id: workspaceId,
              conversation_id: CONVERSATION_ID,
              requested_by_user_id: USER_ID,
              tool_name: TOOLS.kbShareCreate,
              action_sha256: hash,
              status: "approved",
              expires_at: new Date(Date.now() + 3600_000).toISOString(),
              created_at: new Date().toISOString(),
            },
            created: false,
            request_count: 2,
            notify: false,
          },
          error: null,
        };
      }
      if (fn === "consume_approval") return { data: { consumed: true }, error: null };
      throw new Error(`unexpected rpc ${fn}`);
    });
  }

  const run = (deps: ReturnType<typeof makeDeps>["deps"]) =>
    runApprovalGate({
      toolName: TOOLS.kbShareCreate,
      toolInput: { ...input },
      callSignal: undefined,
      controllerSignal: new AbortController().signal,
      userId: USER_ID,
      conversationId: CONVERSATION_ID,
      approval: deps,
      sendToClient: () => true,
      hold: async (_id, _s, wait) => wait(),
      allow: (i) => ({ behavior: "allow", updatedInput: i }),
      logDecision: () => {},
    });

  const kbCreate = (grants: ExecutionGrants) =>
    (buildKbShareTools({ serviceClient: {} as never, userId: USER_ID, kbRoot: "/k", baseUrl: "https://app.test", grants }) as unknown as Array<{
      name: string;
      handler: (a: Record<string, unknown>) => Promise<{ content: Array<{ text: string }>; isError?: boolean }>;
    }>).find((t) => t.name === "kb_share_create")!.handler;

  beforeEach(() => {
    m.createShare.mockReset().mockResolvedValue({ ok: true, token: "t", url: "/shared/t", documentPath: input.documentPath, size: 1 });
  });

  it("approved in W1 and still in W1: the gate allows, the handler (same object) runs once, and a second identical call is refused", async () => {
    const db = approvedDb(WORKSPACE_ID);
    const { deps, grants } = makeDeps({ serviceClient: () => db.client, isEnabled: async () => true });
    const verdict = await run(deps);
    expect(verdict).toMatchObject({ behavior: "allow" });
    expect(db.calls.map((c) => c.fn)).toEqual(["create_approval_request", "consume_approval"]);

    const handler = kbCreate(grants);
    const first = await handler({ ...input });
    expect(first.isError).toBeUndefined();
    expect(m.createShare).toHaveBeenCalledTimes(1);
    expect(m.createShare.mock.calls[0][2]).toBe(WORKSPACE_ID);
    expect((await handler({ ...input })).isError).toBe(true);
    expect(m.createShare).toHaveBeenCalledTimes(1);
  });

  it("approved in W1 but the active workspace moved to W2: the handler refuses (this fails if the factory built its own grants object)", async () => {
    const db = approvedDb(WORKSPACE_ID);
    const { deps, grants } = makeDeps({ serviceClient: () => db.client, isEnabled: async () => true });
    expect(await run(deps)).toMatchObject({ behavior: "allow" });
    m.currentWorkspace.value = OTHER_WORKSPACE_ID;
    const res = await kbCreate(grants)({ ...input });
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text)).toMatchObject({ code: "workspace_changed", status: 409 });
    expect(m.createShare).not.toHaveBeenCalled();
    // The handler's object IS the one the gate turned enforcing.
    expect(grants.enforcing).toBe(true);
  });

  it("the consume verdict decides: a database that refuses the consume yields a deny and writes no grant", async () => {
    const base = approvedDb(WORKSPACE_ID);
    const client: ApprovalRpcClient = {
      rpc: async (fn, args) => (fn === "consume_approval" ? { data: { consumed: false, reason: "hash_mismatch" }, error: null } : base.client.rpc(fn, args)),
    };
    const { deps, grants } = makeDeps({ serviceClient: () => client, isEnabled: async () => true });
    const verdict = await run(deps);
    expect(verdict).toMatchObject({ behavior: "deny" });
    expect(verdict).not.toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(grants.size()).toBe(0);
    expect(m.createShare).not.toHaveBeenCalled();
  });
});

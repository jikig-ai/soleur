/**
 * FR1 (#5240) — verified deterministic workspace rebind on resume.
 *
 * On `resume_session`, the agent cwd is resolved by
 * `resolveActiveWorkspacePath` → `resolveCurrentWorkspaceId`, which reads
 * `user_session_state.current_workspace_id` (falling back to the solo
 * userId). Nobody re-aligns that field with the conversation on resume, so
 * a reconnect resolves the stale (solo) workspace. FR1 writes
 * `current_workspace_id = conversations.workspace_id` via the existing
 * `set_current_workspace_id` switch (mirrors `accept-invite/route.ts:78`).
 *
 * This is a deterministic unit test: it spies the tenant client's `.rpc`
 * call and asserts the switch fires with the conversation's workspace_id.
 * It does NOT assert via the in-memory `userWorkspaces` map (R1) — the cwd
 * resolver never reads it.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import { TC_VERSION } from "@/lib/legal/tc-version";

const REPO_URL = "https://github.com/acme/repo.git";
const CONV_ID = "conv-resume-1";
// Valid UUID: production `conversations.workspace_id` is a NOT-NULL UUID FK
// (migration 059). `workspacePathForWorkspaceId` (called by the #5275 restore
// hook on resume) validates the format, so the fixture must be a real UUID —
// a `team` workspace whose id differs from USER_ID (cross-user shared tree).
const WORKSPACE_ID = "a1b2c3d4-0000-4000-8000-000000000123";
const USER_ID = "user-resume-A";

const { rpcSpy, singleSpy } = vi.hoisted(() => ({
  rpcSpy: vi.fn(
    async (): Promise<{
      error: { code: string; message: string } | null;
    }> => ({ error: null }),
  ),
  singleSpy: vi.fn(async () => ({
    data: {
      id: "conv-resume-1",
      status: "active",
      repo_url: "https://github.com/acme/repo.git",
      workspace_id: "a1b2c3d4-0000-4000-8000-000000000123",
    },
    error: null,
  })),
}));

vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: vi.fn(async () => REPO_URL),
}));

// #5275 — this suite covers the FR1 rebind, not the in-flight restore. Stub the
// restore helper so no real `git` subprocess runs against a synthetic workspace
// path; the restore-refused / restored branches have their own unit coverage in
// test/inflight-checkpoint.test.ts.
vi.mock("@/server/inflight-checkpoint", () => ({
  restoreInflightCheckpoint: vi.fn(async () => ({
    restored: false,
    reason: "no-checkpoint" as const,
  })),
  CHECKPOINT_REFUSED_MESSAGE: "stubbed-refused-message",
}));

vi.mock("@/lib/supabase/tenant", () => {
  class RuntimeAuthError extends Error {
    cause: string;
    constructor(message: string, cause = "unknown") {
      super(message);
      this.cause = cause;
    }
  }
  // Recursive-by-default chain: every builder method returns the same chain, so
  // both the conversation read (`.select().eq().eq().single()`) AND the #5275
  // sibling-slot probe (`.select().eq().neq().gte()`, awaited directly) resolve.
  // `.single()` yields the conversation row; awaiting the chain yields an empty
  // slot set (no live sibling).
  const makeChain = () => {
    const chain: Record<string, unknown> = {};
    for (const m of ["select", "eq", "neq", "gte", "lte", "order", "limit"]) {
      chain[m] = () => chain;
    }
    chain.single = singleSpy;
    // Thenable so `await tenantClient.from(...).select().eq().neq().gte()`
    // resolves to an empty (no live sibling slot) result.
    chain.then = (resolve: (v: { data: unknown[]; error: null }) => unknown) =>
      resolve({ data: [], error: null });
    return chain;
  };
  const tenantClient = {
    from: () => makeChain(),
    rpc: rpcSpy,
  };
  return {
    getFreshTenantClient: vi.fn(async () => tenantClient),
    getMyRevocationStatus: vi.fn(async () => null),
    RuntimeAuthError,
  };
});

import { handleMessage, sessions, type ClientSession } from "@/server/ws-handler";

function makeSession(): ClientSession {
  const ws = {
    readyState: 1, // WebSocket.OPEN
    send: vi.fn(),
    close: vi.fn(),
    // biome-ignore lint/suspicious/noExplicitAny: minimal WS test double
  } as any;
  return {
    ws,
    lastActivity: Date.now(),
    // Bypass the mid-session TC recheck DB round-trip: baseline matches the
    // current constant and the recheck cache is fresh.
    tcVersionAtHandshake: TC_VERSION,
    tcRecheckCacheUntil: Date.now() + 1_000_000,
  };
}

describe("ws-handler resume_session — FR1 workspace rebind", () => {
  beforeEach(() => {
    rpcSpy.mockClear();
    singleSpy.mockClear();
  });

  afterEach(() => {
    sessions.delete(USER_ID);
  });

  it("aligns current_workspace_id to conversations.workspace_id via set_current_workspace_id", async () => {
    sessions.set(USER_ID, makeSession());

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_session", conversationId: CONV_ID }),
    );

    // The resume path bound the conversation...
    expect(sessions.get(USER_ID)?.conversationId).toBe(CONV_ID);
    // ...and re-aligned the resolver's field (the load-bearing fix).
    expect(rpcSpy).toHaveBeenCalledWith("set_current_workspace_id", {
      p_workspace_id: WORKSPACE_ID,
    });
  });

  it("fails loud (honest client error, no binding) when the switch errors", async () => {
    rpcSpy.mockResolvedValueOnce({
      error: { code: "PGRST", message: "boom" },
    });
    const session = makeSession();
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_session", conversationId: CONV_ID }),
    );

    // No silent solo-fallback: the session must NOT be left bound...
    expect(sessions.get(USER_ID)?.conversationId).toBeUndefined();
    // ...and the client receives an honest error frame (terminal catch).
    const sendMock = session.ws.send as unknown as {
      mock: { calls: unknown[][] };
    };
    const frames = sendMock.mock.calls.map(
      (c: unknown[]) => JSON.parse(c[0] as string).type,
    );
    expect(frames).toContain("error");
    expect(frames).not.toContain("session_started");
  });

  it("does NOT rebind when the conversation's repo is out of scope (gate precedes the switch)", async () => {
    // Repo-scope mismatch: the conversation belongs to a different repo than
    // the session's current repo. The resume path must return "Conversation
    // not found" BEFORE the rebind fires — the switch must never run for a
    // conversation that fails the ownership/repo-scope gate.
    singleSpy.mockResolvedValueOnce({
      data: {
        id: CONV_ID,
        status: "active",
        repo_url: "https://github.com/other/repo.git",
        workspace_id: WORKSPACE_ID,
      },
      error: null,
    });
    const session = makeSession();
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_session", conversationId: CONV_ID }),
    );

    expect(rpcSpy).not.toHaveBeenCalled();
    expect(sessions.get(USER_ID)?.conversationId).toBeUndefined();
    const sendMock = session.ws.send as unknown as {
      mock: { calls: unknown[][] };
    };
    const frames = sendMock.mock.calls.map(
      (c: unknown[]) => JSON.parse(c[0] as string).type,
    );
    expect(frames).toContain("error");
    expect(frames).not.toContain("session_started");
  });
});

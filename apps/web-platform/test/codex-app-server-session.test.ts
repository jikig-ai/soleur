import { describe, expect, it, vi } from "vitest";
import { createCodexAppServerSession } from "@/server/codex-app-server-session";

describe("Codex App Server session coordinator", () => {
  it("initializes once, starts a thread, and starts a turn", async () => {
    const client = {
      request: vi.fn()
        .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
        .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: "session-1" } })
        .mockResolvedValueOnce({ turn: { id: "turn-1" } })
        .mockResolvedValueOnce({ turn: { id: "turn-2" } }),
      notify: vi.fn(async () => undefined),
      respond: vi.fn(async () => undefined),
    };
    const session = createCodexAppServerSession(client, {
      nextRequestId: (() => {
        let sequence = 0;
        return () => `rpc-${++sequence}`;
      })(),
      cwd: "/workspaces/ws-1",
    });

    await expect(session.start("Inspect the repository")).resolves.toEqual({
      thread: { resumeHandle: "thread-1", sessionId: "session-1" },
      turnId: "turn-1",
    });
    await expect(session.start("Continue")).resolves.toEqual({
      thread: { resumeHandle: "thread-1", sessionId: "session-1" },
      turnId: "turn-2",
    });
    expect(client.request).toHaveBeenCalledTimes(4);
    expect(client.notify).toHaveBeenCalledOnce();
    expect(client.request.mock.calls.map(([request]) => request.method)).toEqual([
      "initialize", "thread/start", "turn/start", "turn/start",
    ]);
  });

  it("resumes a bound thread without creating a new one", async () => {
    const client = {
      request: vi.fn()
        .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
        .mockResolvedValueOnce({ thread: { id: "thread-2", sessionId: null } })
        .mockResolvedValueOnce({ turn: { id: "turn-2" } }),
      notify: vi.fn(async () => undefined),
      respond: vi.fn(async () => undefined),
    };
    const session = createCodexAppServerSession(client, { nextRequestId: () => "rpc" });
    await expect(session.resume("thread-2", "Continue the existing work")).resolves.toEqual({
      thread: { resumeHandle: "thread-2", sessionId: null },
      turnId: "turn-2",
    });
    expect(client.request.mock.calls.map(([request]) => request.method)).toEqual([
      "initialize", "thread/resume", "turn/start",
    ]);
  });

  it("maps approval decisions and rejects malformed provider thread results", async () => {
    const client = {
      request: vi.fn().mockResolvedValueOnce({ serverInfo: { name: "codex" } }).mockResolvedValueOnce({ thread: {} }),
      notify: vi.fn(async () => undefined),
      respond: vi.fn(async () => undefined),
    };
    const session = createCodexAppServerSession(client, { nextRequestId: () => "rpc" });
    await expect(session.start("Do work")).rejects.toMatchObject({ code: "codex_thread_invalid" });
    await expect(session.respondToApproval("approval-1", "deny")).resolves.toBeUndefined();
    expect(client.respond).toHaveBeenCalledWith("approval-1", { decision: "decline" });
  });

  it("lists persisted turns through the negotiated server-owned session", async () => {
    const client = {
      request: vi.fn()
        .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
        .mockResolvedValueOnce({ turns: [], nextCursor: null }),
      notify: vi.fn(async () => undefined),
      respond: vi.fn(async () => undefined),
    };
    const session = createCodexAppServerSession(client, { nextRequestId: () => "rpc" });
    await expect(session.listTurns("thread-1", { cursor: null, limit: 10 })).resolves.toEqual({
      turns: [],
      nextCursor: null,
    });
    expect(client.request.mock.calls.map(([request]) => request.method)).toEqual([
      "initialize", "thread/turns/list",
    ]);
    expect(client.request.mock.calls[1][0]).toMatchObject({
      params: { threadId: "thread-1", limit: 10, sortDirection: "asc", itemsView: "full" },
    });
  });
});

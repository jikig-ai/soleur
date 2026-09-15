import { describe, expect, it, vi } from "vitest";
import { createCodexAppServerEventBridge } from "@/server/codex-app-server-event-bridge";
import { createCodexAppServerLifecycleSource } from "@/server/codex-app-server-lifecycle-source";

const context = { runId: "run-1" } as never;
const lease = { accessToken: "opaque", expiresAt: Date.now() + 60_000 };

describe("Codex App Server lifecycle source", () => {
  it("starts and resumes through one server-owned connection", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: "session-1" } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: "session-1" } })
      .mockResolvedValueOnce({ turn: { id: "turn-2" } });
    const notify = vi.fn(async () => undefined);
    const connection = {
      client: {
        request,
        notify,
        respond: vi.fn(async () => undefined),
        receiveLine: vi.fn(), receive: vi.fn(), close: vi.fn(), pendingCount: () => 0,
      },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({
      open: vi.fn(async () => connection),
      nextRequestId: (() => { let n = 0; return () => `rpc-${++n}`; })(),
    });

    const first = await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    const second = await source.continue(context, { resumeHandle: "thread-1", sessionId: "session-1" }, { text: "Continue", attachmentIds: [] }, lease);
    expect(first).toEqual(expect.any(Object));
    expect(second).toEqual(expect.any(Object));
    expect(request.mock.calls.map(([rpcRequest]) => rpcRequest.method)).toEqual([
      "initialize", "thread/start", "turn/start", "thread/resume", "turn/start",
    ]);
    expect(notify).toHaveBeenCalledOnce();
  });

  it("routes approval responses and rejects unsupported lifecycle operations", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn();
    const notify = vi.fn();
    const respond = vi.fn(async () => undefined);
    const connection = {
      client: { request, notify, respond, receiveLine: vi.fn(), receive: vi.fn(), close: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({ open: vi.fn(async () => connection), nextRequestId: () => "rpc" });
    await expect(source.respondToApproval(context, "approval-1", "deny", lease)).resolves.toBeUndefined();
    expect(respond).toHaveBeenCalledWith("approval-1", { decision: "decline" });
    await expect(source.cancel(context, { resumeHandle: "thread-1", sessionId: null }, lease)).rejects.toMatchObject({ code: "codex_operation_unsupported" });
    await expect(source.erase(context, { resumeHandle: "thread-1", sessionId: null }, lease)).resolves.toBe("unsupported");
  });
});

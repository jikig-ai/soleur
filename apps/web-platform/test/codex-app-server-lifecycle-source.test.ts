import { describe, expect, it, vi } from "vitest";
import { createCodexAppServerEventBridge } from "@/server/codex-app-server-event-bridge";
import { createCodexAppServerTransport } from "@/server/codex-code-adapter";
import { createCodexAppServerLifecycleSource } from "@/server/codex-app-server-lifecycle-source";
import { createEngineObservability } from "@/server/agent-engine-observability";

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

  it("interrupts an active turn and conservatively reconciles its status", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({})
      .mockResolvedValueOnce({ thread: { id: "thread-1", status: { type: "active" }, turns: [{ status: "inProgress" }] } });
    const notify = vi.fn();
    const respond = vi.fn(async () => undefined);
    const connection = {
      client: { request, notify, respond, receiveLine: vi.fn(), receive: vi.fn(), close: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({ open: vi.fn(async () => connection), nextRequestId: () => "rpc" });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    await expect(source.cancel(context, { resumeHandle: "thread-1", sessionId: null }, lease)).resolves.toBe("requested");
    await expect(source.reconcile(context, { resumeHandle: "thread-1", sessionId: null }, lease)).resolves.toBe("running");
    expect(request.mock.calls.map(([rpcRequest]) => rpcRequest.method)).toEqual([
      "initialize", "thread/start", "turn/start", "turn/interrupt", "thread/read",
    ]);
  });

  it("routes approval responses, requires a replay thread, and confirms remote erasure", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({});
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
    await expect(source.resumeFromCursor(context, null, lease)).rejects.toMatchObject({ code: "codex_thread_missing" });
    await expect(source.erase(context, { resumeHandle: "thread-1", sessionId: null }, lease)).resolves.toBe("confirmed");
    expect(request.mock.calls.map(([rpcRequest]) => rpcRequest.method)).toEqual(["initialize", "thread/delete"]);
  });

  it("replays bounded persisted turns through the neutral transport", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({
        data: [{
          id: "turn-1",
          status: "completed",
          usage: { inputTokens: 2, outputTokens: 1 },
          items: [{ type: "agentMessage", id: "item-1", text: "replayed answer" }],
        }],
        nextCursor: null,
      });
    const connection = {
      client: { request, notify: vi.fn(), respond: vi.fn(), receiveLine: vi.fn(), receive: vi.fn(), close: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({ open: vi.fn(async () => connection), nextRequestId: () => "rpc" });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    const transport = createCodexAppServerTransport(source);
    const replayed = [];
    for await (const event of transport.resumeFromCursor(context, "cursor-1", lease)) replayed.push(event);
    expect(replayed).toEqual([
      { runId: "run-1", eventId: "codex:item:item-1:message", sequence: 1, payload: { type: "text", text: "replayed answer" } },
      { runId: "run-1", eventId: "codex:turn:turn-1:usage", sequence: 2, payload: { type: "usage", usage: { native: [{ unit: "input_tokens", value: 2 }, { unit: "output_tokens", value: 1 }], cost: { provenance: "unavailable" } } } },
      { runId: "run-1", eventId: "codex:turn:turn-1:status", sequence: 3, payload: { type: "status", status: "completed" } },
    ]);
    expect(request.mock.calls.map(([rpcRequest]) => rpcRequest.method)).toEqual([
      "initialize", "thread/start", "turn/start", "thread/turns/list",
    ]);
  });

  it("fails closed when persisted replay contains a malformed recognized item", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({
        data: [{
          id: "turn-1",
          status: "completed",
          items: [{ type: "agentMessage", id: "bad\nitem", text: "must fail" }],
        }],
      });
    const connection = {
      client: { request, notify: vi.fn(), respond: vi.fn(), receiveLine: vi.fn(), receive: vi.fn(), close: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({ open: vi.fn(async () => connection), nextRequestId: () => "rpc" });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    const transport = createCodexAppServerTransport(source);
    await expect((async () => {
      for await (const _event of transport.resumeFromCursor(context, "cursor-1", lease)) { /* no-op */ }
    })()).rejects.toMatchObject({ code: "codex_replay_invalid" });
  });

  it("fails closed when persisted replay contains malformed context compaction", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({
        data: [{
          id: "turn-1",
          status: "completed",
          items: [{ type: "contextCompaction", id: "bad\ncompaction" }],
        }],
      });
    const connection = {
      client: { request, notify: vi.fn(), respond: vi.fn(), receiveLine: vi.fn(), receive: vi.fn(), close: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({ open: vi.fn(async () => connection), nextRequestId: () => "rpc" });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    const transport = createCodexAppServerTransport(source);
    await expect((async () => {
      for await (const _event of transport.resumeFromCursor(context, "cursor-1", lease)) { /* no-op */ }
    })()).rejects.toMatchObject({ code: "codex_replay_invalid" });
  });

  it("fails closed when persisted replay contains malformed web-search activity", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({
        data: [{
          id: "turn-1",
          status: "completed",
          items: [{ type: "webSearch", id: "bad\nsearch", query: "must fail" }],
        }],
      });
    const connection = {
      client: { request, notify: vi.fn(), respond: vi.fn(), receiveLine: vi.fn(), receive: vi.fn(), close: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({ open: vi.fn(async () => connection), nextRequestId: () => "rpc" });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    const transport = createCodexAppServerTransport(source);
    await expect((async () => {
      for await (const _event of transport.resumeFromCursor(context, "cursor-1", lease)) { /* no-op */ }
    })()).rejects.toMatchObject({ code: "codex_replay_invalid" });
  });

  it("fails closed when persisted replay contains malformed image-view activity", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({
        data: [{
          id: "turn-1",
          status: "completed",
          items: [{ type: "imageView", id: "bad\nimage", path: "/private.png" }],
        }],
      });
    const connection = {
      client: { request, notify: vi.fn(), respond: vi.fn(), receiveLine: vi.fn(), close: vi.fn(), receive: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({ open: vi.fn(async () => connection), nextRequestId: () => "rpc" });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    const transport = createCodexAppServerTransport(source);
    await expect((async () => {
      for await (const _event of transport.resumeFromCursor(context, "cursor-1", lease)) { /* no-op */ }
    })()).rejects.toMatchObject({ code: "codex_replay_invalid" });
  });

  it("fails closed when persisted replay contains malformed function output", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({
        data: [{
          id: "turn-1",
          status: "completed",
          items: [{ type: "functionCallOutput", id: "bad\noutput", output: "must fail" }],
        }],
      });
    const connection = {
      client: { request, notify: vi.fn(), respond: vi.fn(), receiveLine: vi.fn(), close: vi.fn(), receive: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({ open: vi.fn(async () => connection), nextRequestId: () => "rpc" });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    const transport = createCodexAppServerTransport(source);
    await expect((async () => {
      for await (const _event of transport.resumeFromCursor(context, "cursor-1", lease)) { /* no-op */ }
    })()).rejects.toMatchObject({ code: "codex_replay_invalid" });
  });

  it("fails closed when persisted replay contains malformed user input", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({
        data: [{
          id: "turn-1",
          status: "completed",
          items: [{ type: "userMessage", id: "bad\nuser", content: [] }],
        }],
      });
    const connection = {
      client: { request, notify: vi.fn(), respond: vi.fn(), receiveLine: vi.fn(), close: vi.fn(), receive: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({ open: vi.fn(async () => connection), nextRequestId: () => "rpc" });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    const transport = createCodexAppServerTransport(source);
    await expect((async () => {
      for await (const _event of transport.resumeFromCursor(context, "cursor-1", lease)) { /* no-op */ }
    })()).rejects.toMatchObject({ code: "codex_replay_invalid" });
  });

  it("emits safe telemetry when replay drops unsupported provider items", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({
        data: [{
          id: "turn-1",
          status: "completed",
          items: [{ type: "reasoning", id: "reason-1", summary: ["private"], content: ["private"] }],
        }],
      });
    const connection = {
      client: { request, notify: vi.fn(), respond: vi.fn(), receiveLine: vi.fn(), close: vi.fn(), receive: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const sink = vi.fn();
    const source = createCodexAppServerLifecycleSource({
      open: vi.fn(async () => connection),
      nextRequestId: () => "rpc",
      observability: createEngineObservability(sink),
    });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    const transport = createCodexAppServerTransport(source);
    const replayed = [];
    for await (const event of transport.resumeFromCursor(context, "cursor-1", lease)) replayed.push(event);
    expect(replayed).toEqual([
      { runId: "run-1", eventId: "codex:turn:turn-1:status", sequence: 1, payload: { type: "status", status: "completed" } },
    ]);
    expect(sink).toHaveBeenCalledWith("engine_replay_item_dropped", {
      engineId: "codex",
      itemType: "reasoning",
      reason: "unsupported_item",
    });
  });

  it("emits safe telemetry before failing on malformed replay pages", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({ data: "malformed", nextCursor: null });
    const connection = {
      client: { request, notify: vi.fn(), respond: vi.fn(), receiveLine: vi.fn(), close: vi.fn(), receive: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const sink = vi.fn();
    const source = createCodexAppServerLifecycleSource({
      open: vi.fn(async () => connection),
      nextRequestId: () => "rpc",
      observability: createEngineObservability(sink),
    });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    const transport = createCodexAppServerTransport(source);
    await expect((async () => {
      for await (const _event of transport.resumeFromCursor(context, "cursor-1", lease)) { /* no-op */ }
    })()).rejects.toMatchObject({ code: "codex_replay_invalid" });
    expect(sink).toHaveBeenCalledWith("engine_replay_failed", {
      engineId: "codex",
      failureClass: "page_invalid",
    });
  });

  it("fails closed on malformed interrupt and reconciliation responses", async () => {
    const events = createCodexAppServerEventBridge();
    const request = vi.fn()
      .mockResolvedValueOnce({ serverInfo: { name: "codex" } })
      .mockResolvedValueOnce({ thread: { id: "thread-1", sessionId: null } })
      .mockResolvedValueOnce({ turn: { id: "turn-1" } })
      .mockResolvedValueOnce({ accepted: true })
      .mockResolvedValueOnce({ thread: { id: "other-thread", turns: [] } })
      .mockResolvedValueOnce({ accepted: true });
    const connection = {
      client: { request, notify: vi.fn(), respond: vi.fn(), receiveLine: vi.fn(), receive: vi.fn(), close: vi.fn(), pendingCount: () => 0 },
      events,
      dispose: vi.fn(async () => undefined),
    };
    const source = createCodexAppServerLifecycleSource({ open: vi.fn(async () => connection), nextRequestId: () => "rpc" });
    await source.start(context, { text: "Inspect", attachmentIds: [] }, lease);
    await expect(source.cancel(context, { resumeHandle: "thread-1", sessionId: null }, lease)).rejects.toMatchObject({ code: "codex_cancel_ack_invalid" });
    await expect(source.reconcile(context, { resumeHandle: "thread-1", sessionId: null }, lease)).rejects.toMatchObject({ code: "codex_reconcile_invalid" });
    await expect(source.erase(context, { resumeHandle: "thread-1", sessionId: null }, lease)).rejects.toMatchObject({ code: "codex_erase_ack_invalid" });
  });
});

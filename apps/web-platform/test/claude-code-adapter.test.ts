import { describe, expect, it, vi } from "vitest";
import {
  CLAUDE_CODE_ENGINE_ID,
  createClaudeCodeAdapter,
  createClaudeCodeSdkTransport,
} from "@/server/claude-code-adapter";

describe("Claude Code neutral adapter boundary", () => {
  it("delegates lifecycle operations without exposing SDK-shaped types", async () => {
    expect(CLAUDE_CODE_ENGINE_ID).toBe("claude-code");
    const transport = {
      start: vi.fn(async function* () { yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const }; }),
      continue: vi.fn(async function* () { yield* []; }),
      cancel: vi.fn().mockResolvedValue("requested" as const),
      reconcile: vi.fn().mockResolvedValue("running" as const),
      resumeFromCursor: vi.fn(async function* () { yield* []; }),
      respondToApproval: vi.fn().mockResolvedValue(undefined),
      erase: vi.fn().mockResolvedValue("confirmed" as const),
      dispose: vi.fn().mockResolvedValue(undefined),
    };
    const adapter = createClaudeCodeAdapter(transport);
    const context = { runId: "run-1", binding: { engineId: "claude-code" } } as never;
    const events = [];
    for await (const event of adapter.start(context, { text: "hi", attachmentIds: [] })) events.push(event);
    await expect(adapter.cancel(context, { resumeHandle: "opaque", sessionId: null })).resolves.toBe("requested");
    await expect(adapter.reconcile(context, { resumeHandle: "opaque", sessionId: null })).resolves.toBe("running");
    await expect(adapter.erase(context, { resumeHandle: "opaque", sessionId: null })).resolves.toBe("confirmed");
    await adapter.respondToApproval(context, "approval-1", "deny");
    await adapter.dispose();
    expect(transport.start).toHaveBeenCalledOnce();
    expect(transport.cancel).toHaveBeenCalledOnce();
    expect(transport.reconcile).toHaveBeenCalledOnce();
    expect(transport.erase).toHaveBeenCalledOnce();
    expect(transport.respondToApproval).toHaveBeenCalledWith(context, "approval-1", "deny");
    expect(transport.dispose).toHaveBeenCalledOnce();
    expect(events).toHaveLength(1);
  });

  it("rejects malformed or stale events before they cross the neutral boundary", async () => {
    const transport = {
      start: vi.fn(async function* () {
        yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const };
        yield { runId: "run-1", eventId: "evt-2", sequence: 1, payload: { type: "text", text: "duplicate" } as const };
      }),
      continue: vi.fn(async function* () { yield* []; }),
      cancel: vi.fn().mockResolvedValue("requested" as const),
      reconcile: vi.fn().mockResolvedValue("running" as const),
      resumeFromCursor: vi.fn(async function* () { yield* []; }),
      respondToApproval: vi.fn().mockResolvedValue(undefined),
      erase: vi.fn().mockResolvedValue("confirmed" as const),
      dispose: vi.fn().mockResolvedValue(undefined),
    };
    const adapter = createClaudeCodeAdapter(transport);
    const events = adapter.start({ runId: "run-1" } as never, { text: "hi", attachmentIds: [] });
    await expect((async () => {
      const collected = [];
      for await (const event of events) collected.push(event);
      return collected;
    })()).rejects.toMatchObject({ code: "claude_event_sequence_invalid" });
  });

  it("sanitizes provider errors while retaining a stable failure code", async () => {
    const transport = {
      start: vi.fn(async function* () { yield* []; }),
      continue: vi.fn(async function* () { yield* []; }),
      cancel: vi.fn().mockRejectedValue(Object.assign(new Error("token=secret"), { code: "provider_timeout" })),
      reconcile: vi.fn().mockResolvedValue("running" as const),
      resumeFromCursor: vi.fn(async function* () { yield* []; }),
      respondToApproval: vi.fn().mockResolvedValue(undefined),
      erase: vi.fn().mockResolvedValue("confirmed" as const),
      dispose: vi.fn().mockResolvedValue(undefined),
    };
    const adapter = createClaudeCodeAdapter(transport);
    await expect(adapter.cancel({ runId: "run-1" } as never, { resumeHandle: "opaque", sessionId: null }))
      .rejects.toMatchObject({ code: "provider_timeout", message: "Claude provider request failed" });
  });

  it("bridges SDK-shaped message streams through the neutral adapter", async () => {
    const source = {
      start: vi.fn(async function* () {
        yield { type: "assistant", uuid: "sdk-1", message: { content: [{ type: "text", text: "hello" }] } };
        yield { type: "result", subtype: "success", uuid: "sdk-2", is_error: false, usage: {} };
      }),
      continue: vi.fn(async function* () { yield* []; }),
      cancel: vi.fn().mockResolvedValue("requested" as const),
      reconcile: vi.fn().mockResolvedValue("running" as const),
      resumeFromCursor: vi.fn(async function* () { yield* []; }),
      respondToApproval: vi.fn().mockResolvedValue(undefined),
      erase: vi.fn().mockResolvedValue("confirmed" as const),
      dispose: vi.fn().mockResolvedValue(undefined),
    };
    const adapter = createClaudeCodeAdapter(createClaudeCodeSdkTransport(source));
    const events = [];
    for await (const event of adapter.start({ runId: "run-1" } as never, { text: "hi", attachmentIds: [] })) {
      events.push(event);
    }
    expect(events).toEqual([
      { runId: "run-1", eventId: "claude:sdk-1:text:0", sequence: 1, payload: { type: "text", text: "hello" } },
      { runId: "run-1", eventId: "claude:sdk-2:usage", sequence: 2, payload: { type: "usage", usage: { native: [], cost: { provenance: "unavailable" } } } },
      { runId: "run-1", eventId: "claude:sdk-2:status", sequence: 3, payload: { type: "status", status: "completed" } },
    ]);
    await expect(adapter.cancel({ runId: "run-1" } as never, { resumeHandle: "opaque", sessionId: null })).resolves.toBe("requested");
    expect(source.start).toHaveBeenCalledOnce();
    expect(source.cancel).toHaveBeenCalledOnce();
  });
});

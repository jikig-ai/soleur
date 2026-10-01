import { describe, expect, it, vi } from "vitest";
import { dispatchBoundEngineRun } from "@/server/agent-engine-dispatch";
import { createDeterministicRemoteAdapter } from "@/server/agent-engine-deterministic-remote-adapter";

const context = {
  runId: "remote-run-1",
  binding: {
    workspaceId: "ws-1",
    execution: { kind: "conversation" as const, conversationId: "conv-1" },
    engineId: "deterministic-remote",
    authMode: "managed",
    adapterVersion: "remote-test-v1",
    boundAt: "2026-09-14T22:00:00Z",
  },
  idempotencyKey: "idem-1",
  signal: new AbortController().signal,
};

describe("deterministic remote adapter", () => {
  it("models queued, running, waiting, and terminal states with unavailable cost", async () => {
    const adapter = createDeterministicRemoteAdapter({ approval: true });
    const events = [];
    for await (const event of adapter.start(context, { text: "synthetic", attachmentIds: [] })) {
      events.push(event);
    }
    expect(events.map((event) => event.payload.type === "status" ? event.payload.status : event.payload.type)).toEqual([
      "queued", "running", "waiting", "approval", "usage", "completed",
    ]);
    expect(events.find((event) => event.payload.type === "usage")?.payload).toEqual({
      type: "usage",
      usage: {
        native: [{ unit: "remote_steps", value: 1 }],
        cost: { provenance: "unavailable" },
      },
    });
  });

  it("delays cancellation confirmation until reconciliation observes termination", async () => {
    const adapter = createDeterministicRemoteAdapter({ cancellationConfirmAfter: 2 });
    await expect(adapter.cancel(context, { resumeHandle: "remote-job", sessionId: null })).resolves.toBe("requested");
    await expect(adapter.reconcile(context, { resumeHandle: "remote-job", sessionId: null })).resolves.toBe("running");
    await expect(adapter.reconcile(context, { resumeHandle: "remote-job", sessionId: null })).resolves.toBe("cancelled");
  });

  it("lets the neutral dispatch boundary reject a duplicated remote sequence", async () => {
    const adapter = createDeterministicRemoteAdapter({ duplicateSequence: true });
    const repository = { getRun: vi.fn().mockResolvedValue({ id: context.runId, binding: context.binding }) };
    const eventSink = { appendEvent: vi.fn().mockResolvedValue(undefined) };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRun({
        repository,
        adapter,
        runId: context.runId,
        eventSink,
        input: { text: "synthetic", attachmentIds: [] },
        context,
      })) { /* no-op */ }
    })()).rejects.toThrow("event sequence is stale or duplicated");
    expect(eventSink.appendEvent).toHaveBeenCalledTimes(3);
  });
});

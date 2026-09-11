import { describe, expect, it, vi } from "vitest";
import { dispatchBoundEngineRun } from "@/server/agent-engine-dispatch";

describe("dispatchBoundEngineRun", () => {
  it("loads the persisted binding before invoking the adapter", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({
      id: "run-1", binding: { engineId: "claude-code" },
    }) };
    const events = [];
    for await (const event of dispatchBoundEngineRun({ repository, adapter, runId: "run-1", input: { text: "hi", attachmentIds: [] }, context: {} as never })) {
      events.push(event);
    }
    expect(repository.getRun).toHaveBeenCalledWith("run-1");
    expect(adapter.start).toHaveBeenCalledOnce();
    expect(events).toHaveLength(1);
  });

  it("fails closed when persistence has no binding", async () => {
    const adapter = { start: vi.fn() };
    const repository = { getRun: vi.fn().mockResolvedValue(null) };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRun({ repository, adapter, runId: "missing", input: { text: "hi", attachmentIds: [] }, context: {} as never })) { /* no-op */ }
    })()).rejects.toThrow("persisted engine binding not found");
    expect(adapter.start).not.toHaveBeenCalled();
  });
});

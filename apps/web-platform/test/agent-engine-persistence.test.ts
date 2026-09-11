import { describe, expect, it, vi } from "vitest";
import { AgentEnginePersistenceRepository } from "@/server/agent-engine-persistence";

function client() {
  const rpc = vi.fn().mockResolvedValue({ data: { id: "run-1" }, error: null });
  const insert = vi.fn().mockResolvedValue({ data: [{ id: "evt-row" }], error: null });
  const select = vi.fn().mockReturnValue({
    eq: vi.fn().mockReturnValue({
      maybeSingle: vi.fn().mockResolvedValue({ data: { id: "run-1", engine_id: "claude-code" }, error: null }),
    }),
  });
  return { rpc, from: vi.fn().mockReturnValue({ insert, select, upsert: insert }), insert };
}

describe("AgentEnginePersistenceRepository", () => {
  it("uses the atomic bind RPC and never derives the engine from client input", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.bind({ workspaceId: "ws-1", executionKind: "conversation", conversationId: "conv-1", createdBy: "user-1" });
    expect(supabase.rpc).toHaveBeenCalledWith("bind_agent_engine_run", expect.objectContaining({ p_workspace_id: "ws-1" }));
    expect(supabase.rpc.mock.calls[0][1]).not.toHaveProperty("p_engine_id");
  });

  it("appends events idempotently through the unique event key", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.appendEvent({ runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "hi" } });
    expect(supabase.from).toHaveBeenCalledWith("agent_engine_events");
    expect(supabase.insert).toHaveBeenCalledWith(
      expect.objectContaining({ event_id: "evt-1", run_id: "run-1" }),
      { onConflict: "run_id,event_id", ignoreDuplicates: true },
    );
  });
});

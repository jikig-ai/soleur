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
  it("updates the workspace default only through the owner RPC", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.setDefaultEngine("ws-1", "codex");
    expect(supabase.rpc).toHaveBeenCalledWith("set_workspace_default_engine", {
      p_workspace_id: "ws-1",
      p_engine_id: "codex",
    });
  });

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

  it("surfaces bind failures instead of silently creating an unbound run", async () => {
    const supabase = client();
    supabase.rpc.mockResolvedValueOnce({ data: null, error: { message: "permission denied" } });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.bind({
      workspaceId: "ws-1",
      executionKind: "routine",
      routineId: "daily-triage",
      routineRunId: "run-1",
      createdBy: "user-1",
    })).rejects.toThrow("engine run bind failed: permission denied");
  });

  it("surfaces event persistence failures for retry/reconciliation", async () => {
    const supabase = client();
    supabase.insert.mockResolvedValueOnce({ data: null, error: { message: "unique violation" } });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.appendEvent({
      runId: "run-1",
      eventId: "evt-2",
      sequence: 2,
      payload: { type: "status", status: "running" },
    })).rejects.toThrow("engine event append failed: unique violation");
  });

  it("normalizes persisted snake_case rows into the neutral binding contract", async () => {
    const supabase = client();
    supabase.from.mockReturnValueOnce({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          maybeSingle: vi.fn().mockResolvedValue({
            data: {
              id: "run-1",
              workspace_id: "ws-1",
              execution_kind: "routine",
              routine_id: "daily-triage",
              routine_run_id: "2026-09-12T01:00:00Z",
              engine_id: "claude-code",
              auth_mode: "managed",
              adapter_version: "claude-v1",
              created_at: "2026-09-12T01:00:01Z",
            },
            error: null,
          }),
        }),
      }),
    });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.getRun("run-1")).resolves.toEqual({
      id: "run-1",
      binding: {
        workspaceId: "ws-1",
        execution: { kind: "routine", routineId: "daily-triage", routineRunId: "2026-09-12T01:00:00Z" },
        engineId: "claude-code",
        authMode: "managed",
        adapterVersion: "claude-v1",
        boundAt: "2026-09-12T01:00:01Z",
      },
    });
  });
});

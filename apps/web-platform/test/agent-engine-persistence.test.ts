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

  it("persists an explicit auth mode with the workspace default", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.setDefaultEngine("ws-1", "claude-code", "managed");
    expect(supabase.rpc).toHaveBeenCalledWith("set_workspace_default_engine", {
      p_workspace_id: "ws-1",
      p_engine_id: "claude-code",
      p_auth_mode: "managed",
    });
  });

  it("persists explicit intent to apply a Codex auth-mode change to existing conversations", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.setDefaultEngine("ws-1", "codex", "api-key", true, 3);
    expect(supabase.rpc).toHaveBeenCalledWith("set_workspace_default_engine", {
      p_workspace_id: "ws-1",
      p_engine_id: "codex",
      p_auth_mode: "api-key",
      p_apply_to_existing_codex_conversations: true,
      p_expected_affected_count: 3,
    });
  });

  it("previews the number of Codex conversations that will change for a mode", async () => {
    const supabase = client();
    supabase.rpc.mockResolvedValueOnce({ data: 3, error: null });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.countCodexConversationRebinds("ws-1", "api-key")).resolves.toBe(3);
    expect(supabase.rpc).toHaveBeenCalledWith("count_codex_conversation_rebinds", {
      p_workspace_id: "ws-1", p_auth_mode: "api-key",
    });
  });

  it("preserves the owner authorization code from the settings RPC", async () => {
    const supabase = client();
    supabase.rpc.mockResolvedValueOnce({
      data: null,
      error: { message: "workspace default engine requires owner", code: "42501" },
    });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.setDefaultEngine("ws-1", "codex"))
      .rejects.toMatchObject({ code: "workspace_owner_required" });
  });

  it("reads the persisted auth mode through the tenant-scoped settings table", async () => {
    const supabase = client();
    supabase.from.mockReturnValueOnce({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          maybeSingle: vi.fn().mockResolvedValue({ data: { default_auth_mode: "api-key" }, error: null }),
        }),
      }),
    });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.getDefaultAuthMode("ws-1")).resolves.toBe("api-key");
  });

  it("reads a workspace default through the tenant-scoped settings table", async () => {
    const supabase = client();
    supabase.from.mockReturnValueOnce({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          maybeSingle: vi.fn().mockResolvedValue({ data: { default_engine_id: "codex" }, error: null }),
        }),
      }),
    });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.getDefaultEngine("ws-1")).resolves.toBe("codex");
  });

  it("reads the saved Codex authentication mode independently of the workspace default", async () => {
    const supabase = client();
    supabase.from.mockReturnValueOnce({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          maybeSingle: vi.fn().mockResolvedValue({ data: { codex_auth_mode: "api-key" }, error: null }),
        }),
      }),
    });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.getCodexAuthMode("ws-1")).resolves.toBe("api-key");
  });

  it("uses the atomic bind RPC and never derives the engine from client input", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.bind({ workspaceId: "ws-1", executionKind: "conversation", conversationId: "conv-1", createdBy: "user-1" });
    expect(supabase.rpc).toHaveBeenCalledWith("bind_agent_engine_run", expect.objectContaining({ p_workspace_id: "ws-1" }));
    expect(supabase.rpc.mock.calls[0][1]).not.toHaveProperty("p_engine_id");
  });

  it("stores bounded lifecycle metadata instead of text payloads or provider event IDs", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.appendEvent({
      runId: "run-1",
      eventId: "codex:item:native-42",
      sequence: 1,
      payload: { type: "text", text: "private repository contents" },
    });
    expect(supabase.rpc).toHaveBeenCalledWith("append_agent_engine_event", {
      p_run_id: "run-1",
      p_event_id: "engine-event-1",
      p_sequence: 1,
      p_payload: { type: "lifecycle", source_type: "text" },
    });
    expect(JSON.stringify(supabase.rpc.mock.calls[0][1])).not.toContain("private repository contents");
    expect(JSON.stringify(supabase.rpc.mock.calls[0][1])).not.toContain("native-42");
  });

  it("retains only the allowlisted status value in lifecycle metadata", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.appendEvent({
      runId: "run-1",
      eventId: "provider-status-id",
      sequence: 2,
      payload: { type: "status", status: "running" },
    });
    expect(supabase.rpc).toHaveBeenCalledWith("append_agent_engine_event", {
      p_run_id: "run-1",
      p_event_id: "engine-event-2",
      p_sequence: 2,
      p_payload: { type: "lifecycle", source_type: "status", status: "running" },
    });
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
    supabase.rpc.mockResolvedValueOnce({ data: null, error: { message: "event key conflict" } });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.appendEvent({
      runId: "run-1",
      eventId: "evt-2",
      sequence: 2,
      payload: { type: "status", status: "running" },
    })).rejects.toThrow("engine event append failed: event key conflict");
  });

  it("starts and transitions a turn attempt without rebinding the conversation", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.startAttempt("binding-1", "turn-42", "api-key", 3);
    await repo.transitionAttempt("attempt-1", "completed");
    expect(supabase.rpc).toHaveBeenNthCalledWith(1, "start_agent_engine_attempt", {
      p_run_id: "binding-1", p_attempt_key: "turn-42",
      p_expected_auth_mode: "api-key", p_expected_generation: 3,
    });
    expect(supabase.rpc).toHaveBeenNthCalledWith(2, "transition_agent_engine_attempt", {
      p_attempt_id: "attempt-1", p_status: "completed",
    });
  });

  it("validates the attempt generation before it can cross the provider boundary", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.assertAttemptGeneration("attempt-1");
    expect(supabase.rpc).toHaveBeenCalledWith("assert_agent_engine_attempt_generation", {
      p_attempt_id: "attempt-1",
    });
  });

  it("skips text deltas and lets the database allocate lifecycle sequences", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    await repo.appendLifecycleEvent("binding-1", "attempt-1", {
      type: "text", text: "private repository contents",
    });
    expect(supabase.rpc).not.toHaveBeenCalled();
    await repo.appendLifecycleEvent("binding-1", "attempt-1", {
      type: "status", status: "running",
    });
    expect(supabase.rpc).toHaveBeenCalledWith("append_agent_engine_lifecycle_event", {
      p_run_id: "binding-1", p_attempt_id: "attempt-1",
      p_payload: { type: "lifecycle", source_type: "status", status: "running" },
    });
    expect(JSON.stringify(supabase.rpc.mock.calls[0][1])).not.toContain("private repository contents");
  });

  it("reads and writes protected native recovery checkpoints through service RPCs", async () => {
    const supabase = client();
    const repo = new AgentEnginePersistenceRepository(supabase);
    const checkpoint = { resumeHandle: "thread-secret", sessionId: "session-secret", cursor: "cursor-secret" };
    await repo.saveRecoveryCheckpoint("binding-1", "attempt-1", checkpoint);
    await repo.getRecoveryCheckpoint("binding-1");
    expect(supabase.rpc).toHaveBeenNthCalledWith(1, "save_agent_engine_recovery_checkpoint", {
      p_run_id: "binding-1", p_attempt_id: "attempt-1", p_checkpoint: checkpoint,
    });
    expect(supabase.rpc).toHaveBeenNthCalledWith(2, "get_agent_engine_recovery_checkpoint", {
      p_run_id: "binding-1",
    });
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

  it("loads the unique conversation binding by conversation id", async () => {
    const maybeSingle = vi.fn().mockResolvedValue({
      data: {
        id: "run-conv-1",
        workspace_id: "ws-1",
        execution_kind: "conversation",
        conversation_id: "conv-1",
        engine_id: "claude-code",
        auth_mode: "managed",
        adapter_version: "claude-v1",
        created_at: "2026-09-14T20:00:00Z",
      },
      error: null,
    });
    const secondEq = vi.fn().mockReturnValue({ maybeSingle });
    const eq = vi.fn().mockReturnValue({ eq: secondEq });
    const supabase = client();
    supabase.from.mockReturnValueOnce({
      select: vi.fn().mockReturnValue({ eq }),
    });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.getConversationRun("conv-1")).resolves.toEqual({
      id: "run-conv-1",
      binding: {
        workspaceId: "ws-1",
        execution: { kind: "conversation", conversationId: "conv-1" },
        engineId: "claude-code",
        authMode: "managed",
        adapterVersion: "claude-v1",
        boundAt: "2026-09-14T20:00:00Z",
      },
    });
    expect(eq).toHaveBeenCalledWith("execution_kind", "conversation");
    expect(secondEq).toHaveBeenCalledWith("conversation_id", "conv-1");
    expect(maybeSingle).toHaveBeenCalledOnce();
  });

  it("loads the unique routine binding by routine and application run id", async () => {
    const maybeSingle = vi.fn().mockResolvedValue({
      data: {
        id: "run-routine-1",
        workspace_id: "ws-1",
        execution_kind: "routine",
        routine_id: "cron-daily-triage",
        routine_run_id: "routine-run-1",
        engine_id: "claude-code",
        auth_mode: "managed",
        adapter_version: "claude-v1",
        created_at: "2026-09-14T20:00:00Z",
      },
      error: null,
    });
    const routineRunEq = vi.fn().mockReturnValue({ maybeSingle });
    const eq = vi.fn().mockReturnValueOnce({ eq: routineRunEq });
    const supabase = client();
    supabase.from.mockReturnValueOnce({
      select: vi.fn().mockReturnValue({ eq }),
    });
    const repo = new AgentEnginePersistenceRepository(supabase);
    await expect(repo.getRoutineRun("cron-daily-triage", "routine-run-1")).resolves.toEqual({
      id: "run-routine-1",
      binding: {
        workspaceId: "ws-1",
        execution: { kind: "routine", routineId: "cron-daily-triage", routineRunId: "routine-run-1" },
        engineId: "claude-code",
        authMode: "managed",
        adapterVersion: "claude-v1",
        boundAt: "2026-09-14T20:00:00Z",
      },
    });
    expect(eq).toHaveBeenCalledWith("routine_id", "cron-daily-triage");
    expect(routineRunEq).toHaveBeenCalledWith("routine_run_id", "routine-run-1");
  });
});

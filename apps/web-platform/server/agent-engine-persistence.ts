import type { EngineEvent } from "./agent-engine-contract";

// Supabase PostgREST builders are thenable but are not typed as native
// Promises. PromiseLike keeps this repository compatible with both builders
// and the small promise based test doubles used by the server tests.
type QueryResult<T> = PromiseLike<{ data: T; error: { message: string } | null }>;
type SelectBuilder = {
  eq(column: string, value: unknown): SelectBuilder;
  maybeSingle(): QueryResult<unknown>;
};
export type PersistenceClient = {
  rpc(name: string, args: Record<string, unknown>): QueryResult<unknown>;
  from(table: string): {
    insert(row: Record<string, unknown>, options?: Record<string, unknown>): QueryResult<unknown>;
    select(columns?: string): SelectBuilder;
  };
};

function normalizeRun(data: unknown): unknown {
  if (!data || typeof data !== "object") return null;
  const row = data as Record<string, unknown>;
  const execution = row.execution_kind === "conversation"
    ? { kind: "conversation" as const, conversationId: String(row.conversation_id) }
    : { kind: "routine" as const, routineId: String(row.routine_id), routineRunId: String(row.routine_run_id) };
  return {
    id: String(row.id),
    binding: {
      workspaceId: String(row.workspace_id),
      execution,
      engineId: String(row.engine_id),
      authMode: String(row.auth_mode),
      adapterVersion: String(row.adapter_version),
      boundAt: String(row.created_at),
    },
  };
}

export interface BindRunInput {
  workspaceId: string;
  executionKind: "conversation" | "routine";
  conversationId?: string;
  routineId?: string;
  routineRunId?: string;
  createdBy: string;
}

function lifecycleMetadata(event: EngineEvent): Record<string, string> {
  if (event.payload.type === "status") {
    return {
      type: "lifecycle",
      source_type: "status",
      status: event.payload.status,
    };
  }
  return { type: "lifecycle", source_type: event.payload.type };
}

export class AgentEnginePersistenceRepository {
  constructor(private readonly client: PersistenceClient) {}

  async setDefaultEngine(workspaceId: string, engineId: string, authMode?: string): Promise<unknown> {
    const args: Record<string, unknown> = {
      p_workspace_id: workspaceId,
      p_engine_id: engineId,
    };
    if (authMode !== undefined) args.p_auth_mode = authMode;
    const result = await this.client.rpc("set_workspace_default_engine", {
      ...args,
    });
    if (result.error) {
      const error = result.error as { message: string; code?: string };
      if (error.code === "42501" || error.message.includes("requires owner")) {
        throw Object.assign(new Error("workspace default engine requires owner"), {
          code: "workspace_owner_required",
        });
      }
      throw new Error(`workspace default engine update failed: ${error.message}`);
    }
    return result.data;
  }

  async getDefaultAuthMode(workspaceId: string): Promise<string | null> {
    const result = await this.client.from("workspace_engine_settings")
      .select("default_auth_mode")
      .eq("workspace_id", workspaceId)
      .maybeSingle();
    if (result.error) throw new Error(`workspace default auth mode lookup failed: ${result.error.message}`);
    if (!result.data || typeof result.data !== "object") return null;
    const value = (result.data as { default_auth_mode?: unknown }).default_auth_mode;
    return typeof value === "string" ? value : null;
  }

  async getDefaultEngine(workspaceId: string): Promise<string | null> {
    const result = await this.client.from("workspace_engine_settings")
      .select("default_engine_id")
      .eq("workspace_id", workspaceId)
      .maybeSingle();
    if (result.error) throw new Error(`workspace default engine lookup failed: ${result.error.message}`);
    if (!result.data || typeof result.data !== "object") return null;
    const value = (result.data as { default_engine_id?: unknown }).default_engine_id;
    return typeof value === "string" ? value : null;
  }

  async bind(input: BindRunInput): Promise<unknown> {
    const result = await this.client.rpc("bind_agent_engine_run", {
      p_workspace_id: input.workspaceId,
      p_execution_kind: input.executionKind,
      p_conversation_id: input.conversationId ?? null,
      p_routine_id: input.routineId ?? null,
      p_routine_run_id: input.routineRunId ?? null,
      p_created_by: input.createdBy,
    });
    if (result.error) throw new Error(`engine run bind failed: ${result.error.message}`);
    return result.data;
  }

  async appendEvent(event: EngineEvent): Promise<unknown> {
    const result = await this.client.rpc("append_agent_engine_event", {
      p_run_id: event.runId,
      p_event_id: `engine-event-${event.sequence}`,
      p_sequence: event.sequence,
      p_payload: lifecycleMetadata(event),
    });
    if (result.error) throw new Error(`engine event append failed: ${result.error.message}`);
    return result.data;
  }

  async getRun(runId: string): Promise<unknown> {
    const result = await this.client.from("agent_engine_runs").select("*").eq("id", runId).maybeSingle();
    if (result.error) throw new Error(`engine run lookup failed: ${result.error.message}`);
    return normalizeRun(result.data);
  }

  async getConversationRun(conversationId: string): Promise<unknown> {
    const result = await this.client.from("agent_engine_runs")
      .select("*")
      .eq("execution_kind", "conversation")
      .eq("conversation_id", conversationId)
      .maybeSingle();
    if (result.error) throw new Error(`conversation engine run lookup failed: ${result.error.message}`);
    return normalizeRun(result.data);
  }

  async getRoutineRun(routineId: string, routineRunId: string): Promise<unknown> {
    const result = await this.client.from("agent_engine_runs")
      .select("*")
      .eq("routine_id", routineId)
      .eq("routine_run_id", routineRunId)
      .maybeSingle();
    if (result.error) throw new Error(`routine engine run lookup failed: ${result.error.message}`);
    return normalizeRun(result.data);
  }
}

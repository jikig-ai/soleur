import type { EngineEvent } from "./agent-engine-contract";

// Supabase PostgREST builders are thenable but are not typed as native
// Promises. PromiseLike keeps this repository compatible with both builders
// and the small promise based test doubles used by the server tests.
type QueryResult<T> = PromiseLike<{ data: T; error: { message: string } | null }>;
export type PersistenceClient = {
  rpc(name: string, args: Record<string, unknown>): QueryResult<unknown>;
  from(table: string): {
    insert(row: Record<string, unknown>, options?: Record<string, unknown>): QueryResult<unknown>;
    select(columns?: string): { eq(column: string, value: unknown): { maybeSingle(): QueryResult<unknown> } };
  };
};

export interface BindRunInput {
  workspaceId: string;
  executionKind: "conversation" | "routine";
  conversationId?: string;
  routineId?: string;
  routineRunId?: string;
  createdBy: string;
}

export class AgentEnginePersistenceRepository {
  constructor(private readonly client: PersistenceClient) {}

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
    const result = await this.client.from("agent_engine_events").insert(
      {
        run_id: event.runId,
        event_id: event.eventId,
        sequence: event.sequence,
        payload: event.payload,
      },
      { onConflict: "run_id,event_id", ignoreDuplicates: true },
    );
    if (result.error) throw new Error(`engine event append failed: ${result.error.message}`);
    return result.data;
  }

  async getRun(runId: string): Promise<unknown> {
    const result = await this.client.from("agent_engine_runs").select("*").eq("id", runId).maybeSingle();
    if (result.error) throw new Error(`engine run lookup failed: ${result.error.message}`);
    if (!result.data || typeof result.data !== "object") return null;
    const row = result.data as Record<string, unknown>;
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
}

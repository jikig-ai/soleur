import type { EngineExecution, AgentEngineId } from "./agent-engine-contract";

export interface BindingActor {
  userId: string;
  isWorkspaceOwner: boolean;
}

export interface EngineBindingRecord {
  runId: string;
  execution: EngineExecution;
  engineId: AgentEngineId;
  createdBy: string;
  createdAt: string;
}

export class EngineBindingAuthorizationError extends Error {
  constructor(public readonly code: "workspace_default_owner_required") {
    super(code);
    this.name = "EngineBindingAuthorizationError";
  }
}

type BindingInput = { execution: EngineExecution; actor: BindingActor };

/**
 * Keeps execution binding separate from mutable workspace settings. A database
 * repository can implement the same operations atomically; this class provides
 * the deterministic policy seam and test double for that repository.
 */
export class AgentEngineBindingStore {
  private defaultEngineId: AgentEngineId;
  private readonly bindings = new Map<string, EngineBindingRecord>();
  private sequence = 0;

  constructor(options: { defaultEngineId: AgentEngineId }) {
    this.defaultEngineId = options.defaultEngineId;
  }

  setDefaultEngine(engineId: AgentEngineId, actor: BindingActor): void {
    if (!actor.isWorkspaceOwner) {
      throw new EngineBindingAuthorizationError("workspace_default_owner_required");
    }
    this.defaultEngineId = engineId;
  }

  bind(input: BindingInput): EngineBindingRecord {
    const key = executionKey(input.execution);
    if (this.bindings.has(key)) {
      throw new Error(`execution already bound: ${key}`);
    }

    const record: EngineBindingRecord = {
      runId: `engine-run-${++this.sequence}`,
      execution: input.execution,
      engineId: this.defaultEngineId,
      createdBy: input.actor.userId,
      createdAt: new Date().toISOString(),
    };
    this.bindings.set(key, record);
    return { ...record, execution: { ...record.execution } };
  }

  get(runId: string): EngineBindingRecord | undefined {
    const record = [...this.bindings.values()].find((candidate) => candidate.runId === runId);
    return record && { ...record, execution: { ...record.execution } };
  }

  retry(runId: string): EngineBindingRecord | undefined {
    return this.get(runId);
  }
}

function executionKey(execution: EngineExecution): string {
  return execution.kind === "conversation"
    ? `conversation:${execution.conversationId}`
    : `routine:${execution.routineId}:${execution.routineRunId}`;
}

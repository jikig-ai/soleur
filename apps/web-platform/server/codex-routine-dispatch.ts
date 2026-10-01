import type { EngineEvent, EngineInput, EngineRunContext, EngineSelection } from "./agent-engine-contract";
import { dispatchRoutineEngineRun } from "./agent-engine-dispatch";
import type { ReviewedEngineRegistry } from "./agent-engine-adapter-factory";
import type { EngineDataEgressEvidence } from "./agent-engine-data-egress-policy";
import { createCodexWebEngineFactoriesForBinding, type CodexWebRuntimeOptions } from "./codex-web-runtime";

interface RoutineBindingRepository {
  getRoutineRun(routineId: string, routineRunId: string): Promise<unknown>;
  getRun(runId: string): Promise<unknown>;
  appendEvent?(event: EngineEvent): Promise<unknown>;
}

export interface CodexRoutineDispatchOptions {
  repository: RoutineBindingRepository;
  runtime: Omit<CodexWebRuntimeOptions, "authMode">;
  routineId: string;
  routineRunId: string;
  input: EngineInput;
  context: EngineRunContext;
  selection: EngineSelection;
  evidence: EngineDataEgressEvidence;
  registry?: ReviewedEngineRegistry;
}

/** Dispatch one persisted Codex routine run without falling back to Claude. */
export async function* dispatchCodexRoutineToEvents(options: CodexRoutineDispatchOptions): AsyncGenerator<EngineEvent> {
  const persisted = await options.repository.getRoutineRun(options.routineId, options.routineRunId);
  const binding = persisted && typeof persisted === "object" && "binding" in persisted
    ? (persisted as { binding: { engineId?: unknown; authMode?: unknown } }).binding
    : null;
  if (!binding || binding.engineId !== "codex" || typeof binding.authMode !== "string") {
    throw Object.assign(new Error("persisted routine is not Codex-bound"), { code: "codex_binding_mismatch" });
  }
  const factories = createCodexWebEngineFactoriesForBinding({ ...options.runtime, binding: { engineId: "codex", authMode: binding.authMode } });
  if (!factories.codex) {
    throw Object.assign(new Error("Codex adapter factory is unavailable"), { code: "codex_adapter_unavailable" });
  }
  yield* dispatchRoutineEngineRun({
    repository: options.repository,
    factories: { codex: factories.codex },
    registry: options.registry,
    routineId: options.routineId,
    routineRunId: options.routineRunId,
    input: options.input,
    context: options.context,
    egress: { selection: options.selection, evidence: options.evidence },
    eventSink: options.repository.appendEvent ? { appendEvent: options.repository.appendEvent.bind(options.repository) } : undefined,
  });
}

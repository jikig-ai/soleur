import type { WSMessage } from "@/lib/types";
import type { EngineEvent, EngineInput, EngineRunContext, EngineSelection } from "./agent-engine-contract";
import { dispatchConversationEngineRun } from "./agent-engine-dispatch";
import type { ReviewedEngineRegistry } from "./agent-engine-adapter-factory";
import { createCodexWebEngineFactoriesForBinding, type CodexWebRuntimeOptions } from "./codex-web-runtime";
import { mapCodexEngineEventToWsMessage } from "./codex-ws-events";
import { reviewedEngineRegistry } from "./agent-engine-reviewed-definitions";
import { authorizeEngineDataEgress } from "./agent-engine-data-egress-policy";

interface ConversationBindingRepository {
  getConversationRun(conversationId: string): Promise<unknown>;
  getRun(runId: string): Promise<unknown>;
  appendEvent?(event: unknown): Promise<unknown>;
  startAttempt(runId: string, attemptKey: string, expectedAuthMode: string, expectedGeneration: number): Promise<unknown>;
  assertAttemptGeneration(attemptId: string): Promise<unknown>;
  transitionAttempt?(attemptId: string, status: "running" | "completed" | "failed" | "cancelled"): Promise<unknown>;
  appendLifecycleEvent?(runId: string, attemptId: string, payload: EngineEvent["payload"]): Promise<unknown>;
}

export interface CodexConversationDispatchOptions {
  repository: ConversationBindingRepository;
  runtime: Omit<CodexWebRuntimeOptions, "authMode">;
  conversationId: string;
  input: EngineInput;
  context: EngineRunContext;
  selection: EngineSelection;
  evidence: Parameters<typeof import("./agent-engine-data-egress-policy").authorizeEngineDataEgress>[1];
  leaderId: Parameters<typeof mapCodexEngineEventToWsMessage>[1]["leaderId"];
  workspaceId?: string;
  send: (message: WSMessage) => void;
  registry?: ReviewedEngineRegistry;
}

/** Dispatch one persisted Codex conversation run into the existing WS stream. */
export async function dispatchCodexConversationToWebSocket(options: CodexConversationDispatchOptions): Promise<void> {
  const persisted = await options.repository.getConversationRun(options.conversationId);
  const binding = persisted && typeof persisted === "object" && "binding" in persisted
    ? (persisted as { binding: { engineId?: unknown; authMode?: unknown } }).binding
    : null;
  if (!binding || binding.engineId !== "codex" || typeof binding.authMode !== "string") {
    throw Object.assign(new Error("persisted conversation is not Codex-bound"), { code: "codex_binding_mismatch" });
  }
  const bindingGeneration = "authModeGeneration" in binding ? binding.authModeGeneration : null;
  if (typeof bindingGeneration !== "number" || !Number.isSafeInteger(bindingGeneration) || bindingGeneration < 0) {
    throw Object.assign(new Error("persisted Codex binding generation is invalid"), { code: "codex_binding_generation_invalid" });
  }
  // The production catalog is default-off. Qualification and transfer evidence
  // must be checked before service-role attempt writes or provider invocation.
  const registry = options.registry ?? reviewedEngineRegistry;
  if (!registry.resolve) throw new Error("engine_qualification_unavailable");
  if (options.selection.engineId !== binding.engineId || options.selection.authMode !== binding.authMode) {
    throw new Error("Codex dispatch selection does not match persisted binding");
  }
  registry.resolve(options.selection);
  authorizeEngineDataEgress(options.selection, options.evidence);
  const runId = (persisted as { id?: unknown }).id;
  if (typeof runId !== "string" || !runId) throw new Error("persisted Codex run id is missing");
  const attempt = await options.repository.startAttempt(runId, options.context.idempotencyKey, binding.authMode, bindingGeneration);
  const attemptId = attempt && typeof attempt === "object" && "id" in attempt
    ? (attempt as { id: unknown }).id : null;
  if (typeof attemptId !== "string") {
    throw new Error("Codex attempt start returned no id");
  }
  try {
    let terminalStatus: "completed" | "failed" | "cancelled" | null = null;
    // This RPC is the request's acceptance boundary. A settings switch that
    // committed after the attempt was created makes it stale before transport.
    await options.repository.assertAttemptGeneration(attemptId);
    await options.repository.transitionAttempt?.(attemptId, "running");
    const factories = createCodexWebEngineFactoriesForBinding({ ...options.runtime, binding: { engineId: "codex", authMode: binding.authMode } });
    if (!factories.codex) {
      throw Object.assign(new Error("Codex adapter factory is unavailable"), { code: "codex_adapter_unavailable" });
    }
    for await (const event of dispatchConversationEngineRun({
    repository: options.repository,
    persistedRun: persisted,
    factories: { codex: factories.codex },
    conversationId: options.conversationId,
    input: options.input,
    context: options.context,
    registry: options.registry,
    egress: { selection: options.selection, evidence: options.evidence },
      eventSink: typeof attemptId === "string" && options.repository.appendLifecycleEvent
        ? { appendEvent: (event) => options.repository.appendLifecycleEvent!(runId, attemptId, event.payload) }
        : options.repository.appendEvent ? { appendEvent: options.repository.appendEvent.bind(options.repository) } : undefined,
    })) {
      if (event.payload.type === "status"
        && (event.payload.status === "completed" || event.payload.status === "failed" || event.payload.status === "cancelled")) {
        terminalStatus = event.payload.status;
      }
      options.send(mapCodexEngineEventToWsMessage(event, {
        leaderId: options.leaderId,
        conversationId: options.conversationId,
        workspaceId: options.workspaceId,
      }));
    }
    if (terminalStatus === null) {
      throw Object.assign(new Error("Codex stream ended without a terminal status"), { code: "codex_terminal_missing" });
    }
    if (typeof attemptId === "string") await options.repository.transitionAttempt?.(attemptId, terminalStatus);
  } catch (error) {
    if (typeof attemptId === "string") {
      try { await options.repository.transitionAttempt?.(attemptId, "failed"); } catch { /* preserve dispatch error */ }
    }
    throw error;
  }
}

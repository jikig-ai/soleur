import type { WSMessage } from "@/lib/types";
import type { EngineInput, EngineRunContext, EngineSelection } from "./agent-engine-contract";
import { dispatchConversationEngineRun } from "./agent-engine-dispatch";
import type { ReviewedEngineRegistry } from "./agent-engine-adapter-factory";
import { createCodexWebEngineFactoriesForBinding, type CodexWebRuntimeOptions } from "./codex-web-runtime";
import { mapCodexEngineEventToWsMessage } from "./codex-ws-events";

interface ConversationBindingRepository {
  getConversationRun(conversationId: string): Promise<unknown>;
  getRun(runId: string): Promise<unknown>;
  appendEvent?(event: unknown): Promise<unknown>;
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
  const factories = createCodexWebEngineFactoriesForBinding({ ...options.runtime, binding: { engineId: "codex", authMode: binding.authMode } });
  if (!factories.codex) {
    throw Object.assign(new Error("Codex adapter factory is unavailable"), { code: "codex_adapter_unavailable" });
  }
  for await (const event of dispatchConversationEngineRun({
    repository: options.repository,
    factories: { codex: factories.codex },
    conversationId: options.conversationId,
    input: options.input,
    context: options.context,
    registry: options.registry,
    egress: { selection: options.selection, evidence: options.evidence },
    eventSink: options.repository.appendEvent ? { appendEvent: options.repository.appendEvent.bind(options.repository) } : undefined,
  })) {
    options.send(mapCodexEngineEventToWsMessage(event, {
      leaderId: options.leaderId,
      conversationId: options.conversationId,
      workspaceId: options.workspaceId,
    }));
  }
}

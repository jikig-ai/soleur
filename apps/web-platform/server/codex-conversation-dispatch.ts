import type { WSMessage } from "@/lib/types";
import type { EngineBinding, EngineEvent, EngineInput, EngineRunContext, EngineSelection } from "./agent-engine-contract";
import { dispatchConversationEngineRun } from "./agent-engine-dispatch";
import type { ReviewedEngineRegistry } from "./agent-engine-adapter-factory";
import { createCodexWebEngineFactoriesForBinding, type CodexWebRuntimeOptions } from "./codex-web-runtime";
import { createCodexWebEventMapper, mapCodexEngineEventToWsMessage } from "./codex-ws-events";
import { reviewedEngineRegistry } from "./agent-engine-reviewed-definitions";
import { authorizeEngineDataEgress } from "./agent-engine-data-egress-policy";

interface ConversationBindingRepository {
  getConversationRun(conversationId: string): Promise<unknown>;
  getRun(runId: string): Promise<unknown>;
  startAttempt(runId: string, attemptKey: string, expectedAuthMode: string, expectedGeneration: number): Promise<unknown>;
  assertAttemptGeneration(attemptId: string): Promise<unknown>;
  transitionAttempt(attemptId: string, status: "running" | "completed" | "failed" | "cancelled"): Promise<unknown>;
  appendLifecycleEvent(runId: string, attemptId: string, payload: EngineEvent["payload"]): Promise<unknown>;
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
  /** Called only after the unique attempt claim and generation fence commit. */
  onAccepted?: () => void;
  registry?: ReviewedEngineRegistry;
}

/** Dispatch one persisted Codex conversation run into the existing WS stream. */
export async function dispatchCodexConversationToWebSocket(options: CodexConversationDispatchOptions): Promise<void> {
  assertTurnActive(options.context.signal);
  const persisted = await options.repository.getConversationRun(options.conversationId);
  assertTurnActive(options.context.signal);
  const binding = persisted && typeof persisted === "object" && "binding" in persisted
    ? (persisted as { binding: Partial<EngineBinding> }).binding
    : null;
  if (!binding || binding.engineId !== "codex" || typeof binding.authMode !== "string") {
    throw Object.assign(new Error("persisted conversation is not Codex-bound"), { code: "codex_binding_mismatch" });
  }
  const bindingGeneration = "authModeGeneration" in binding ? binding.authModeGeneration : null;
  if (typeof bindingGeneration !== "number" || !Number.isSafeInteger(bindingGeneration) || bindingGeneration < 0) {
    throw Object.assign(new Error("persisted Codex binding generation is invalid"), { code: "codex_binding_generation_invalid" });
  }
  const runId = (persisted as { id?: unknown }).id;
  const verifiedBinding = options.context.binding;
  const verifiedGeneration = verifiedBinding.authModeGeneration ?? 0;
  // Preserve the identity and generation whose history acknowledgment the
  // WebSocket handler verified. A same-mode ABA switch still invalidates it.
  if (runId !== options.context.runId
    || binding.engineId !== verifiedBinding.engineId
    || binding.authMode !== verifiedBinding.authMode
    || bindingGeneration !== verifiedGeneration
    || binding.workspaceId !== verifiedBinding.workspaceId
    || binding.adapterVersion !== verifiedBinding.adapterVersion
    || binding.execution?.kind !== "conversation"
    || binding.execution.conversationId !== options.conversationId
    || verifiedBinding.execution.kind !== "conversation"
    || verifiedBinding.execution.conversationId !== options.conversationId
    || (options.workspaceId !== undefined && binding.workspaceId !== options.workspaceId)) {
    throw Object.assign(new Error("Codex conversation binding changed after acknowledgment"), { code: "codex_binding_stale" });
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
  if (typeof runId !== "string" || !runId) throw new Error("persisted Codex run id is missing");
  const attempt = await options.repository.startAttempt(runId, options.context.idempotencyKey, verifiedBinding.authMode, verifiedGeneration);
  const attemptId = attempt && typeof attempt === "object" && "id" in attempt
    ? (attempt as { id: unknown }).id : null;
  if (typeof attemptId !== "string") {
    throw new Error("Codex attempt start returned no id");
  }
  let terminalStatus: "completed" | "failed" | "cancelled" | null = null;
  try {
    assertTurnActive(options.context.signal);
    // This RPC is the request's acceptance boundary. A settings switch that
    // committed after the attempt was created makes it stale before transport.
    await options.repository.assertAttemptGeneration(attemptId);
    assertTurnActive(options.context.signal);
    await options.repository.transitionAttempt(attemptId, "running");
    assertTurnActive(options.context.signal);
    options.onAccepted?.();
    const factories = createCodexWebEngineFactoriesForBinding({ ...options.runtime, binding: { engineId: "codex", authMode: binding.authMode } });
    if (!factories.codex) {
      throw Object.assign(new Error("Codex adapter factory is unavailable"), { code: "codex_adapter_unavailable" });
    }
    assertTurnActive(options.context.signal);
    const mapWebEvent = createCodexWebEventMapper({
      leaderId: options.leaderId,
      conversationId: options.conversationId,
      workspaceId: options.workspaceId,
    });
    for await (const event of dispatchConversationEngineRun({
      repository: options.repository,
      persistedRun: persisted,
      factories: { codex: factories.codex },
      conversationId: options.conversationId,
      input: options.input,
      context: options.context,
      registry,
      egress: { selection: options.selection, evidence: options.evidence },
      eventSink: { appendEvent: (event) => options.repository.appendLifecycleEvent(runId, attemptId, event.payload) },
    })) {
      if (event.payload.type === "status"
        && (event.payload.status === "completed" || event.payload.status === "failed" || event.payload.status === "cancelled")) {
        terminalStatus = event.payload.status;
      }
      options.send(mapWebEvent(event));
    }
    if (terminalStatus === null) {
      throw Object.assign(new Error("Codex stream ended without a terminal status"), { code: "codex_terminal_missing" });
    }
    // The lifecycle append RPC commits terminal event and attempt status
    // together. Do not write a second terminal transition after the client
    // frame is sent: socket delivery is outside the database transaction.
  } catch (error) {
    const cancelled = options.context.signal?.aborted || isTurnCancelled(error);
    if (cancelled && terminalStatus === null) terminalStatus = "cancelled";
    if (typeof attemptId === "string" && terminalStatus === null) {
      try {
        await options.repository.appendLifecycleEvent(runId, attemptId, { type: "status", status: "failed" });
      } catch {
        try { await options.repository.transitionAttempt(attemptId, "failed"); } catch { /* preserve dispatch error */ }
      }
    } else if (typeof attemptId === "string" && terminalStatus === "cancelled") {
      try {
        await options.repository.appendLifecycleEvent(runId, attemptId, { type: "status", status: "cancelled" });
      } catch {
        try { await options.repository.transitionAttempt(attemptId, "cancelled"); } catch { /* preserve dispatch error */ }
      }
    }
    throw error;
  }
}

function isTurnCancelled(error: unknown): boolean {
  return !!error && typeof error === "object" && "code" in error
    && (error as { code?: unknown }).code === "codex_turn_cancelled";
}

function assertTurnActive(signal?: AbortSignal): void {
  if (signal?.aborted) {
    throw Object.assign(new Error("Codex turn was cancelled before provider dispatch"), { code: "codex_turn_cancelled" });
  }
}

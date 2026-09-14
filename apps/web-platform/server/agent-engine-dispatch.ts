import type {
  EngineAdapter,
  EngineEvent,
  EngineInput,
  EngineRunContext,
} from "./agent-engine-contract";
import { createReviewedEngineAdapter, type EngineAdapterFactory } from "./agent-engine-adapter-factory";
import {
  authorizeEngineDataEgress,
  type EngineDataEgressEvidence,
} from "./agent-engine-data-egress-policy";
import type { EngineSelection } from "./agent-engine-contract";
import { createEngineObservability, type EngineObservability } from "./agent-engine-observability";

interface BindingRepository {
  getRun(runId: string): Promise<unknown>;
}
interface ConversationBindingRepository extends BindingRepository {
  getConversationRun(conversationId: string): Promise<unknown>;
}
interface RoutineBindingRepository extends BindingRepository {
  getRoutineRun(routineId: string, routineRunId: string): Promise<unknown>;
}
interface EventSink {
  appendEvent(event: EngineEvent): Promise<unknown>;
}

type NewRunRepository = BindingRepository & {
  bind(input: Record<string, unknown>): Promise<unknown>;
};

function validateDispatchedEvent(event: EngineEvent, runId: string, lastSequence: number): void {
  if (
    !event ||
    event.runId !== runId ||
    typeof event.eventId !== "string" ||
    event.eventId.length === 0 ||
    !Number.isInteger(event.sequence) ||
    event.sequence < 1
  ) {
    throw new Error("engine event does not match bound run");
  }
  if (event.sequence <= lastSequence) {
    throw new Error("engine event sequence is stale or duplicated");
  }
}

interface DispatchOptions {
  repository: BindingRepository;
  adapter: Pick<EngineAdapter, "start">;
  adapterEngineId?: string;
  eventSink?: EventSink;
  observability?: EngineObservability;
  runId: string;
  input: EngineInput;
  context: EngineRunContext;
}

export async function* dispatchBoundEngineRunFromRegistry(options: {
  repository: BindingRepository;
  factories: Readonly<Record<string, EngineAdapterFactory>>;
  eventSink?: EventSink;
  observability?: EngineObservability;
  egress?: { selection: EngineSelection; evidence?: EngineDataEgressEvidence };
  runId: string;
  input: EngineInput;
  context: EngineRunContext;
}): AsyncGenerator<EngineEvent> {
  const persisted = await options.repository.getRun(options.runId);
  if (!persisted || typeof persisted !== "object") throw new Error("persisted engine binding not found");
  const binding = (persisted as { binding?: EngineRunContext["binding"] }).binding ??
    (persisted as unknown as EngineRunContext["binding"]);
  if (options.egress) {
    if (options.egress.selection.engineId !== binding.engineId) {
      throw new Error("egress selection does not match persisted engine binding");
    }
    authorizeEngineDataEgress(options.egress.selection, options.egress.evidence);
  }
  const adapter = createReviewedEngineAdapter(binding.engineId, options.factories, "existing-run");
  yield* dispatchBoundEngineRun({
    repository: options.repository,
    adapter,
    adapterEngineId: binding.engineId,
    eventSink: options.eventSink,
    observability: options.observability,
    runId: options.runId,
    input: options.input,
    context: options.context,
  });
}

/** Resolve a conversation's immutable binding before selecting any provider adapter. */
export async function* dispatchConversationEngineRun(options: {
  repository: ConversationBindingRepository;
  factories: Readonly<Record<string, EngineAdapterFactory>>;
  eventSink?: EventSink;
  observability?: EngineObservability;
  egress?: { selection: EngineSelection; evidence?: EngineDataEgressEvidence };
  conversationId: string;
  input: EngineInput;
  context: EngineRunContext;
}): AsyncGenerator<EngineEvent> {
  const persisted = await options.repository.getConversationRun(options.conversationId);
  if (!persisted || typeof persisted !== "object") {
    throw new Error("persisted conversation engine binding not found");
  }
  const binding = (persisted as { binding?: EngineRunContext["binding"] }).binding ??
    (persisted as unknown as EngineRunContext["binding"]);
  if (binding.execution?.kind !== "conversation" || binding.execution.conversationId !== options.conversationId) {
    throw new Error("persisted conversation engine binding does not match conversation");
  }
  const runId = (persisted as { id?: unknown }).id;
  if (typeof runId !== "string" || runId.length === 0) {
    throw new Error("persisted conversation engine binding has no run id");
  }
  yield* dispatchBoundEngineRunFromRegistry({
    repository: options.repository,
    factories: options.factories,
    eventSink: options.eventSink,
    observability: options.observability,
    egress: options.egress,
    runId,
    input: options.input,
    context: options.context,
  });
}

/** Resolve a routine's immutable binding before selecting any provider adapter. */
export async function* dispatchRoutineEngineRun(options: {
  repository: RoutineBindingRepository;
  factories: Readonly<Record<string, EngineAdapterFactory>>;
  eventSink?: EventSink;
  observability?: EngineObservability;
  egress?: { selection: EngineSelection; evidence?: EngineDataEgressEvidence };
  routineId: string;
  routineRunId: string;
  input: EngineInput;
  context: EngineRunContext;
}): AsyncGenerator<EngineEvent> {
  const persisted = await options.repository.getRoutineRun(options.routineId, options.routineRunId);
  if (!persisted || typeof persisted !== "object") {
    throw new Error("persisted routine engine binding not found");
  }
  const binding = (persisted as { binding?: EngineRunContext["binding"] }).binding ??
    (persisted as unknown as EngineRunContext["binding"]);
  if (
    binding.execution?.kind !== "routine" ||
    binding.execution.routineId !== options.routineId ||
    binding.execution.routineRunId !== options.routineRunId
  ) {
    throw new Error("persisted routine engine binding does not match routine");
  }
  const runId = (persisted as { id?: unknown }).id;
  if (typeof runId !== "string" || runId.length === 0) {
    throw new Error("persisted routine engine binding has no run id");
  }
  yield* dispatchBoundEngineRunFromRegistry({
    repository: options.repository,
    factories: options.factories,
    eventSink: options.eventSink,
    observability: options.observability,
    egress: options.egress,
    runId,
    input: options.input,
    context: options.context,
  });
}

/** Dispatch is binding-first: no persisted run means no provider invocation. */
export async function* dispatchBoundEngineRun(
  options: DispatchOptions,
): AsyncGenerator<EngineEvent> {
  const persisted = await options.repository.getRun(options.runId);
  if (!persisted || typeof persisted !== "object") {
    throw new Error("persisted engine binding not found");
  }

  const context = {
    ...options.context,
    runId: options.runId,
    binding: (persisted as { binding?: EngineRunContext["binding"] }).binding ??
      (persisted as unknown as EngineRunContext["binding"]),
  } as EngineRunContext;
  if (options.adapterEngineId && context.binding.engineId !== options.adapterEngineId) {
    throw new Error("persisted engine binding does not match adapter");
  }
  const observability = options.observability ?? createEngineObservability();
  const metadata = {
    engineId: context.binding.engineId,
    workspaceId: context.binding.workspaceId,
    runId: context.runId,
    adapterVersion: context.binding.adapterVersion,
    ...(context.binding.execution?.kind === "conversation"
      ? { conversationId: context.binding.execution.conversationId }
      : context.binding.execution?.kind === "routine"
        ? { routineId: context.binding.execution.routineId, routineRunId: context.binding.execution.routineRunId }
        : {}),
  };
  observability.emit("engine_dispatch_started", metadata);
  try {
    let lastSequence = 0;
    for await (const event of options.adapter.start(context, options.input)) {
      validateDispatchedEvent(event, options.runId, lastSequence);
      lastSequence = event.sequence;
      observability.emit("engine_dispatch_progress", { ...metadata, sequence: event.sequence, status: event.payload.type });
      if (options.eventSink) await options.eventSink.appendEvent(event);
      yield event;
    }
    observability.emit("engine_dispatch_completed", metadata);
  } catch (error) {
    observability.emit("engine_dispatch_failed", {
      ...metadata,
      failureClass: error instanceof Error && "code" in error && typeof error.code === "string" ? error.code : "provider_error",
    });
    throw error;
  }
}

type LifecycleRepository = BindingRepository;

async function loadBoundContext(options: {
  repository: LifecycleRepository;
  runId: string;
  context: EngineRunContext;
  adapterEngineId?: string;
}): Promise<EngineRunContext> {
  const persisted = await options.repository.getRun(options.runId);
  if (!persisted || typeof persisted !== "object") throw new Error("persisted engine binding not found");
  const context = {
    ...options.context,
    runId: options.runId,
    binding: (persisted as { binding?: EngineRunContext["binding"] }).binding ??
      (persisted as unknown as EngineRunContext["binding"]),
  } as EngineRunContext;
  if (options.adapterEngineId && context.binding.engineId !== options.adapterEngineId) {
    throw new Error("persisted engine binding does not match adapter");
  }
  return context;
}

export async function cancelBoundEngineRun(options: {
  repository: LifecycleRepository;
  adapter: Pick<EngineAdapter, "cancel">;
  adapterEngineId?: string;
  runId: string;
  context: EngineRunContext;
  session: Parameters<EngineAdapter["cancel"]>[1];
}): Promise<ReturnType<EngineAdapter["cancel"]>> {
  const context = await loadBoundContext(options);
  return options.adapter.cancel(context, options.session);
}

export async function reconcileBoundEngineRun(options: {
  repository: LifecycleRepository;
  adapter: Pick<EngineAdapter, "reconcile">;
  adapterEngineId?: string;
  observability?: EngineObservability;
  runId: string;
  context: EngineRunContext;
  session: Parameters<EngineAdapter["reconcile"]>[1];
}): Promise<ReturnType<EngineAdapter["reconcile"]>> {
  const context = await loadBoundContext(options);
  const status = await options.adapter.reconcile(context, options.session);
  (options.observability ?? createEngineObservability()).emit("engine_session_reconciled", {
    engineId: context.binding.engineId,
    workspaceId: context.binding.workspaceId,
    runId: context.runId,
    status,
  });
  return status;
}

export async function* continueBoundEngineRun(options: {
  repository: LifecycleRepository;
  adapter: Pick<EngineAdapter, "continue">;
  eventSink?: EventSink;
  adapterEngineId?: string;
  runId: string;
  context: EngineRunContext;
  session: Parameters<EngineAdapter["continue"]>[1];
  input: EngineInput;
}): AsyncGenerator<EngineEvent> {
  const context = await loadBoundContext(options);
  for await (const event of options.adapter.continue(context, options.session, options.input)) {
    if (options.eventSink) await options.eventSink.appendEvent(event);
    yield event;
  }
}

export async function* resumeBoundEngineRun(options: {
  repository: LifecycleRepository;
  adapter: Pick<EngineAdapter, "resumeFromCursor">;
  eventSink?: EventSink;
  adapterEngineId?: string;
  runId: string;
  context: EngineRunContext;
  cursor: string | null;
}): AsyncGenerator<EngineEvent> {
  const context = await loadBoundContext(options);
  for await (const event of options.adapter.resumeFromCursor(context, options.cursor)) {
    if (options.eventSink) await options.eventSink.appendEvent(event);
    yield event;
  }
}

export async function respondToApprovalBoundEngineRun(options: {
  repository: LifecycleRepository;
  adapter: Pick<EngineAdapter, "respondToApproval">;
  adapterEngineId?: string;
  runId: string;
  context: EngineRunContext;
  requestId: string;
  decision: "allow" | "deny";
}): Promise<void> {
  const context = await loadBoundContext(options);
  await options.adapter.respondToApproval(context, options.requestId, options.decision);
}

export async function eraseBoundEngineRun(options: {
  repository: LifecycleRepository;
  adapter: Pick<EngineAdapter, "erase">;
  adapterEngineId?: string;
  runId: string;
  context: EngineRunContext;
  session: Parameters<EngineAdapter["erase"]>[1];
}): Promise<ReturnType<EngineAdapter["erase"]>> {
  const context = await loadBoundContext(options);
  return options.adapter.erase(context, options.session);
}

export async function* dispatchNewEngineRun(options: {
  repository: NewRunRepository;
  adapter: Pick<EngineAdapter, "start">;
  adapterEngineId?: string;
  eventSink?: EventSink;
  binding: Record<string, unknown>;
  input: EngineInput;
  context: EngineRunContext;
}): AsyncGenerator<EngineEvent> {
  const created = await options.repository.bind(options.binding);
  if (!created || typeof created !== "object" || !("id" in created)) {
    throw new Error("engine run binding did not return a run id");
  }
  yield* dispatchBoundEngineRun({
    repository: options.repository,
    adapter: options.adapter,
    adapterEngineId: options.adapterEngineId,
    eventSink: options.eventSink,
    runId: String((created as { id: unknown }).id),
    input: options.input,
    context: options.context,
  });
}

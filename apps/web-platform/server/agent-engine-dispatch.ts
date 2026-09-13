import type {
  EngineAdapter,
  EngineEvent,
  EngineInput,
  EngineRunContext,
} from "./agent-engine-contract";

interface BindingRepository {
  getRun(runId: string): Promise<unknown>;
}
interface EventSink {
  appendEvent(event: EngineEvent): Promise<unknown>;
}

type NewRunRepository = BindingRepository & {
  bind(input: Record<string, unknown>): Promise<unknown>;
};

interface DispatchOptions {
  repository: BindingRepository;
  adapter: Pick<EngineAdapter, "start">;
  adapterEngineId?: string;
  eventSink?: EventSink;
  runId: string;
  input: EngineInput;
  context: EngineRunContext;
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
  for await (const event of options.adapter.start(context, options.input)) {
    if (options.eventSink) await options.eventSink.appendEvent(event);
    yield event;
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
  runId: string;
  context: EngineRunContext;
  session: Parameters<EngineAdapter["reconcile"]>[1];
}): Promise<ReturnType<EngineAdapter["reconcile"]>> {
  const context = await loadBoundContext(options);
  return options.adapter.reconcile(context, options.session);
}

export async function* continueBoundEngineRun(options: {
  repository: LifecycleRepository;
  adapter: Pick<EngineAdapter, "continue">;
  adapterEngineId?: string;
  runId: string;
  context: EngineRunContext;
  session: Parameters<EngineAdapter["continue"]>[1];
  input: EngineInput;
}): AsyncGenerator<EngineEvent> {
  const context = await loadBoundContext(options);
  for await (const event of options.adapter.continue(context, options.session, options.input)) {
    yield event;
  }
}

export async function* resumeBoundEngineRun(options: {
  repository: LifecycleRepository;
  adapter: Pick<EngineAdapter, "resumeFromCursor">;
  adapterEngineId?: string;
  runId: string;
  context: EngineRunContext;
  cursor: string | null;
}): AsyncGenerator<EngineEvent> {
  const context = await loadBoundContext(options);
  for await (const event of options.adapter.resumeFromCursor(context, options.cursor)) {
    yield event;
  }
}

export async function* dispatchNewEngineRun(options: {
  repository: NewRunRepository;
  adapter: Pick<EngineAdapter, "start">;
  adapterEngineId?: string;
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
    runId: String((created as { id: unknown }).id),
    input: options.input,
    context: options.context,
  });
}

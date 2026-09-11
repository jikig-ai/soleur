import type {
  EngineAdapter,
  EngineEvent,
  EngineInput,
  EngineRunContext,
} from "./agent-engine-contract";

interface BindingRepository {
  getRun(runId: string): Promise<unknown>;
}

type NewRunRepository = BindingRepository & {
  bind(input: Record<string, unknown>): Promise<unknown>;
};

interface DispatchOptions {
  repository: BindingRepository;
  adapter: Pick<EngineAdapter, "start">;
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
  for await (const event of options.adapter.start(context, options.input)) {
    yield event;
  }
}

export async function* dispatchNewEngineRun(options: {
  repository: NewRunRepository;
  adapter: Pick<EngineAdapter, "start">;
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
    runId: String((created as { id: unknown }).id),
    input: options.input,
    context: options.context,
  });
}

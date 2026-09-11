import type {
  EngineAdapter,
  EngineEvent,
  EngineInput,
  EngineRunContext,
} from "./agent-engine-contract";

interface BindingRepository {
  getRun(runId: string): Promise<unknown>;
}

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

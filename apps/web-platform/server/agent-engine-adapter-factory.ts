import type { EngineAdapter } from "./agent-engine-contract";
import { reviewedEngineRegistry } from "./agent-engine-reviewed-definitions";

export type EngineAdapterFactory = () => EngineAdapter;

export function createReviewedEngineAdapter(
  engineId: string,
  factories: Readonly<Record<string, EngineAdapterFactory>>,
  operation: "new-run" | "existing-run" = "new-run",
  registry: Pick<typeof reviewedEngineRegistry, "get"> = reviewedEngineRegistry,
): EngineAdapter {
  let definition;
  try {
    definition = registry.get(engineId);
  } catch {
    throw new Error("engine_unknown");
  }
  const enabled = operation === "new-run" ? definition.enabledForNewRuns : definition.enabledForExistingRuns;
  if (!enabled) throw new Error("engine_disabled");
  const factory = factories[definition.id];
  if (!factory) throw new Error("adapter_unavailable");
  return factory();
}

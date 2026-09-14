import type { EngineAdapter, EngineSelection } from "./agent-engine-contract";
import { EngineEligibilityError } from "./agent-engine-registry";
import { reviewedEngineRegistry } from "./agent-engine-reviewed-definitions";

export type EngineAdapterFactory = () => EngineAdapter;
export type ReviewedEngineRegistry = Pick<typeof reviewedEngineRegistry, "get"> &
  Partial<Pick<typeof reviewedEngineRegistry, "resolve">>;

export function createReviewedEngineAdapter(
  engineId: string,
  factories: Readonly<Record<string, EngineAdapterFactory>>,
  operation: "new-run" | "existing-run" = "new-run",
  registry: ReviewedEngineRegistry = reviewedEngineRegistry,
  selection?: EngineSelection,
): EngineAdapter {
  let definition;
  try {
    if (selection) {
      if (selection.engineId !== engineId) throw new Error("engine_selection_mismatch");
      if (!registry.resolve) throw new Error("engine_qualification_unavailable");
      definition = registry.resolve(selection);
    } else {
      definition = registry.get(engineId);
    }
  } catch (error) {
    if (error instanceof EngineEligibilityError) throw error;
    if (error instanceof Error && error.message === "engine_selection_mismatch") throw error;
    if (error instanceof Error && error.message === "engine_qualification_unavailable") throw error;
    throw new Error("engine_unknown");
  }
  const enabled = operation === "new-run" ? definition.enabledForNewRuns : definition.enabledForExistingRuns;
  if (!enabled) throw new Error("engine_disabled");
  const factory = factories[definition.id];
  if (!factory) throw new Error("adapter_unavailable");
  return factory();
}

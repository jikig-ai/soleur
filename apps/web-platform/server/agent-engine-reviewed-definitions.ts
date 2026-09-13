import { DEFAULT_AGENT_ENGINE_ID, type EngineDefinition } from "./agent-engine-contract";
import { createEngineRegistry } from "./agent-engine-registry";

// Deployment catalog. Qualification still gates execution; this catalog only
// defines which reviewed engines may appear in workspace settings.
export const reviewedEngineRegistry = createEngineRegistry([
  {
    id: DEFAULT_AGENT_ENGINE_ID,
    version: "claude-code-v1",
    transport: "local",
    enabledForNewRuns: true,
    enabledForExistingRuns: true,
    authModes: ["managed", "api-key"],
    qualifications: [],
  } satisfies EngineDefinition,
  {
    id: "codex",
    version: "codex-v1",
    transport: "remote",
    enabledForNewRuns: false,
    enabledForExistingRuns: false,
    authModes: ["managed", "api-key"],
    qualifications: [],
  } satisfies EngineDefinition,
]);

export function listReviewedEngineDefinitions(): EngineDefinition[] {
  return [DEFAULT_AGENT_ENGINE_ID, "codex"].map((id) => reviewedEngineRegistry.get(id));
}

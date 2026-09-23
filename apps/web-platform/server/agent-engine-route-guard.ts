import { DEFAULT_AGENT_ENGINE_ID } from "./agent-engine-contract";

/**
 * Legacy handlers may run only the default engine. A persisted binding for a
 * different reviewed engine must be routed through the engine dispatcher;
 * silently executing Claude here would violate engine stickiness.
 */
export function assertLegacyEngineBinding(binding: unknown): void {
  if (!binding || typeof binding !== "object") {
    throw Object.assign(new Error("persisted engine binding is invalid"), {
      code: "engine_binding_invalid",
    });
  }
  const record = binding as { engineId?: unknown; engine_id?: unknown };
  const engineId = record.engineId ?? record.engine_id;
  if (engineId !== DEFAULT_AGENT_ENGINE_ID) {
    throw Object.assign(new Error("persisted engine requires reviewed dispatcher"), {
      code: "engine_dispatch_required",
    });
  }
}

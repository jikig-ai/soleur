import type { EngineDefinition, EngineSelection } from "./agent-engine-contract";

export type EngineEligibilityCode =
  | "engine_unknown" | "engine_duplicate" | "engine_id_invalid"
  | "engine_disabled" | "engine_auth_unsupported" | "engine_unqualified"
  | "engine_capability_missing";

/** Codes only: untrusted engine identifiers and provider details are not echoed. */
export class EngineEligibilityError extends Error {
  constructor(readonly code: EngineEligibilityCode) {
    super(code);
    this.name = "EngineEligibilityError";
  }
}

function validId(id: string): boolean {
  return /^[a-z][a-z0-9-]{0,63}$/.test(id)
    && !["constructor", "prototype", "__proto__"].includes(id)
    && !/[\r\n]/.test(id);
}

/** Reviewed deployment definitions only. No customer adapter registration.
 * A returned definition is an eligibility result, not a credential lease or
 * authorization grant; dispatch must still recheck current shared policy.
 */
export function createEngineRegistry(definitions: readonly EngineDefinition[]) {
  const entries = new Map<string, EngineDefinition>();
  for (const definition of definitions) {
    if (!validId(definition.id)) throw new EngineEligibilityError("engine_id_invalid");
    if (entries.has(definition.id)) throw new EngineEligibilityError("engine_duplicate");
    entries.set(definition.id, structuredClone(definition));
  }

  return {
    get(engineId: string): EngineDefinition {
      const definition = entries.get(engineId);
      if (!definition) throw new EngineEligibilityError("engine_unknown");
      return structuredClone(definition);
    },
    resolve(selection: EngineSelection): EngineDefinition {
      const definition = entries.get(selection.engineId);
      if (!definition) throw new EngineEligibilityError("engine_unknown");
      const enabled = selection.operation === "new-run"
        ? definition.enabledForNewRuns : definition.enabledForExistingRuns;
      if (!enabled) throw new EngineEligibilityError("engine_disabled");
      if (!definition.authModes.includes(selection.authMode)) {
        throw new EngineEligibilityError("engine_auth_unsupported");
      }
      const qualifications = definition.qualifications.filter((q) =>
        q.authMode === selection.authMode
        && q.adapterVersion === definition.version
        && q.workflow === selection.workflow
        && q.dataClass === selection.dataClass
        && Number.isFinite(selection.now)
        && Number.isFinite(q.expiresAt)
        && q.expiresAt > selection.now
        && q.evidenceRef.trim().length > 0,
      );
      if (qualifications.length === 0) throw new EngineEligibilityError("engine_unqualified");
      if (!qualifications.some((q) => selection.requiredCapabilities.every(
        (capability) => q.capabilities[capability] === "verified",
      ))) throw new EngineEligibilityError("engine_capability_missing");
      // Neither the registering caller nor a consumer can mutate registry state.
      return structuredClone(definition);
    },
  };
}

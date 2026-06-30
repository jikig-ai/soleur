// SDK-native phase-surface hint hook for the web Concierge agent (#5772 lever 1,
// ADR-070). The JS port of the CLI `.claude/hooks/phase-surface-hint.sh`: a
// fail-open `PostToolUse(Skill)` hook that maps the called skill → a workflow
// phase and injects that phase's ADDITIVE hint as `additionalContext`. It
// removes nothing and never restricts the tool surface (two-tier fail-open rule,
// ADR-070); the web SDK `disallowedTools`/`canUseTool` floor is untouched.
//
// Security parity with the shell hook: the model-controlled `skill` value is used
// ONLY as a map lookup key and is NEVER echoed into the hint (the hint is composed
// from map-derived constants). `Object.hasOwn` guards the lookup so a crafted
// prototype key (`__proto__`, `constructor`) cannot resolve to a truthy non-string.
//
// Fail-open: any unmapped/disabled/malformed/thrown path returns `{}` (no hint,
// full surface). The callback never throws into the SDK.
import type { HookCallback, PostToolUseHookInput } from "@anthropic-ai/claude-agent-sdk";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";
import { PHASE_SURFACE_MAP } from "./phase-surface-map";

const log = createChildLogger("phase-surface-hook");

// The web Concierge emits BARE workflow names in `tool_input.skill` (`work`),
// while the canonical map is FQN-keyed (`soleur:work`). Normalize bare→FQN.
const SOLEUR_SKILL_PREFIX = "soleur:";

/**
 * Compose the phase hint for a skill, or null on any non-match. Pure + sync.
 * Mirrors the CLI hook's jq pipeline: one own-property gate on the
 * model-controlled key, one null-check on the derived surface.
 */
function buildHint(skill: string): string | null {
  // Kill-switch (strict "1", read per-invocation — mirrors the shell `== "1"`).
  if (process.env.SOLEUR_DISABLE_PHASE_HINT === "1") return null;
  if (typeof skill !== "string") return null;

  const key = skill.includes(":") ? skill : SOLEUR_SKILL_PREFIX + skill;
  // The single security gate: own-property lookup rejects every inherited key
  // (`__proto__`, `constructor`, `toString`) before reading the value.
  if (!Object.hasOwn(PHASE_SURFACE_MAP.skill_to_phase, key)) return null;
  const phase = PHASE_SURFACE_MAP.skill_to_phase[key];

  // Plain null-check on the derived surface (mirrors the CLI hook's `$s == null`).
  const surface = phase ? PHASE_SURFACE_MAP.phase_to_surface[phase] : undefined;
  if (!surface) return null;

  let hint = `[phase-scope] You are in the ${phase} phase. `;
  if (surface.relevant_skills.length > 0) {
    hint += `Phase-relevant skills: ${surface.relevant_skills.join(", ")}. `;
  }
  if (surface.relevant_agents.length > 0) {
    hint += `Phase-relevant agents: ${surface.relevant_agents.join(", ")}. `;
  }
  if (surface.not_live_note !== "") {
    hint += `Not yet live: ${surface.not_live_note} `;
  }
  hint += "(Guidance only — all tools remain available; this never restricts what you can call.)";
  return hint;
}

/**
 * Build the PostToolUse(Skill) hook callback. The factory is side-effect-free
 * (it only closes over the imported map) so a builder-time call inside the
 * `options.hooks` literal can never throw into `query()` startup.
 */
export function createPhaseSurfaceHook(): HookCallback {
  return async (input) => {
    try {
      const i = input as PostToolUseHookInput;
      if (i.tool_name !== "Skill") return {};
      const skill = (i.tool_input as { skill?: unknown } | null | undefined)?.skill;
      if (typeof skill !== "string") return {};
      const hint = buildHint(skill);
      if (hint === null) return {};
      return { hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: hint } };
    } catch (err) {
      // Fail-open: never throw into the SDK turn. Mirror to Sentry with a STATIC
      // message — the model-controlled skill value MUST NOT enter the error path.
      log.warn({ err }, "phase-surface hook failed (fail-open: no hint)");
      reportSilentFallback(err, { feature: "phase-surface-hook", op: "buildHint" });
      return {};
    }
  };
}

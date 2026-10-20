/**
 * /go routing dispatch — maps classified intent labels to registered skills/agents.
 *
 * Mirrors the eval-gate routing table in plugins/soleur/commands/go.md.
 * Golden-path eval (Phase F #6325) asserts Grok slash_command dispatch fidelity.
 * Anti-bypass contract (#6338): routes resolve via workflow-fidelity.ts.
 */

import { invokeSkill, spawnAgent, type SkillInvocation, type AgentSpawn } from "./harness";
import { GO_SKILL_ROUTES, resolveGoSkillRoute } from "./workflow-fidelity";

export { GO_SKILL_ROUTES, resolveGoSkillRoute };

/** Agent routes (spawn_subagent / Task — never improvised workflows). */
export const GO_AGENT_ROUTES: Record<string, string> = {
  "clo-attestation": "clo",
  "legal-threshold": "clo",
};

export type GoRouteTarget =
  | { kind: "skill"; skill: string }
  | { kind: "agent"; agent: string };

/** Resolve a classified routing label to its registered target. */
export function resolveGoRoute(label: string): GoRouteTarget {
  if (label in GO_AGENT_ROUTES) {
    return { kind: "agent", agent: GO_AGENT_ROUTES[label] };
  }
  return { kind: "skill", skill: resolveGoSkillRoute(label) };
}

export type GoDispatch =
  | { kind: "skill"; invocation: SkillInvocation }
  | { kind: "agent"; spawn: AgentSpawn };

/**
 * Dispatch a classified /go route under the active harness.
 * Pass `env` in tests to pin Grok vs Claude without mutating process.env.
 */
export function dispatchGoRoute(
  label: string,
  userInput: string,
  env?: NodeJS.ProcessEnv,
): GoDispatch {
  const target = resolveGoRoute(label);
  const prev = { ...process.env };

  if (env) {
    for (const key of Object.keys(process.env)) {
      if (!(key in env)) delete process.env[key];
    }
    Object.assign(process.env, env);
  }

  try {
    if (target.kind === "agent") {
      return { kind: "agent", spawn: spawnAgent(target.agent, userInput) };
    }
    return { kind: "skill", invocation: invokeSkill(target.skill, userInput) };
  } finally {
    for (const key of Object.keys(process.env)) {
      if (!(key in prev)) delete process.env[key];
    }
    Object.assign(process.env, prev);
  }
}

/** Pin harness for deterministic golden-path tests. */
export function grokTestEnv(): NodeJS.ProcessEnv {
  return { GROK_HOME: "/home/user/.grok" };
}

export function claudeTestEnv(): NodeJS.ProcessEnv {
  return { CLAUDECODE: "1" };
}

/** Expected Grok slash command for a skill route (golden-path assertion). */
export function expectedGrokSlashCommand(skill: string, args?: string): string {
  const trimmed = args?.trim();
  return trimmed ? `/${skill} ${trimmed}` : `/${skill}`;
}
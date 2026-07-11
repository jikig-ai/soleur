/**
 * Harness adapter — maps Soleur workflow invocations to Claude Code or Grok Build surfaces.
 *
 * Claude: Skill tool (`soleur:<skill>`), Task tool (agents), `/soleur:<command>` slash commands.
 * Grok:   slash commands (`/<skill>`, `/go`), spawn_subagent (agents).
 *
 * Skills and go.md must call these helpers (or follow routingInstructions) — never improvise workflows.
 */

import { pathToAgentId } from "./agent-registry";
import { pipelineInvocationSuffix, workflowFidelityInstructions } from "./workflow-fidelity";

export type Harness = "claude" | "grok" | "unknown";

/** Env vars set by Grok Build (see https://docs.x.ai/build/settings/reference). */
const GROK_ENV_MARKERS = [
  "GROK_HOME",
  "GROK_AGENT",
  "GROK_DEFAULT_MODEL",
  "GROK_SUBAGENTS",
] as const;

export interface SkillInvocation {
  harness: Harness;
  tool: "Skill" | "slash_command";
  command: string;
  args?: string;
  instruction: string;
}

export interface AgentSpawn {
  harness: Harness;
  tool: "Task" | "spawn_subagent";
  agent: string;
  prompt: string;
  instruction: string;
}

/** Strip `soleur:` prefix; Grok exposes bare skill names as slash commands. */
export function normalizeSkillName(skill: string): string {
  return skill.replace(/^soleur:/, "");
}

/**
 * Ensure agent ids are plugin-qualified when a bare or path-style name is passed.
 * Path-style: `engineering/review/security-sentinel` → registry-qualified id.
 */
export function normalizeAgentName(agent: string): string {
  if (agent.startsWith("soleur:")) {
    return agent;
  }
  if (agent.includes("/")) {
    return pathToAgentId(`agents/${agent.replace(/\.md$/, "")}.md`);
  }
  if (agent.includes(":")) {
    return `soleur:${agent}`;
  }
  return agent;
}

/**
 * Detect the active harness from environment markers and process metadata.
 * Detection order: CLAUDECODE → GROK_* → process title/argv heuristics.
 */
export function detectHarness(env: NodeJS.ProcessEnv = process.env): Harness {
  if (env.CLAUDECODE) {
    return "claude";
  }

  for (const key of GROK_ENV_MARKERS) {
    if (env[key]) {
      return "grok";
    }
  }

  // Process heuristics apply only when inspecting the live runtime env — not
  // injected test fixtures (Grok Build's argv/title would false-positive "grok").
  if (env === process.env && typeof process !== "undefined") {
    const title = (process.title ?? "").toLowerCase();
    const argv = process.argv.join(" ").toLowerCase();
    if (title.includes("grok") || /\bgrok\b/.test(argv)) {
      return "grok";
    }
  }

  return "unknown";
}

/**
 * Return the harness-specific skill invocation string (display / logging).
 */
export function formatSkillInvocation(skill: string, args?: string): string {
  const harness = detectHarness();
  const name = normalizeSkillName(skill);
  const trimmedArgs = args?.trim();

  if (harness === "grok") {
    return trimmedArgs ? `/${name} ${trimmedArgs}` : `/${name}`;
  }

  const skillId = `soleur:${name}`;
  return trimmedArgs ? `${skillId} (args: ${trimmedArgs})` : skillId;
}

/**
 * Structured skill invocation — use at routing sites instead of improvising steps.
 */
export function invokeSkill(skill: string, args?: string): SkillInvocation {
  const harness = detectHarness();
  const name = normalizeSkillName(skill);
  const trimmedArgs = args?.trim();

  const pipelineSuffix = pipelineInvocationSuffix(name);

  if (harness === "grok") {
    const command = trimmedArgs ? `/${name} ${trimmedArgs}` : `/${name}`;
    return {
      harness,
      tool: "slash_command",
      command,
      args: trimmedArgs,
      instruction:
        `Invoke the registered skill via slash command \`${command}\`. ` +
        "Do NOT improvise workflow steps — run the skill to completion." +
        pipelineSuffix,
    };
  }

  const command = `soleur:${name}`;
  return {
    harness: harness === "claude" ? "claude" : harness,
    tool: "Skill",
    command,
    args: trimmedArgs,
    instruction:
      `Invoke via the **Skill tool** with skill \`${command}\`` +
      (trimmedArgs ? ` and args: \`${trimmedArgs}\`` : "") +
      ". Do NOT improvise workflow steps." +
      pipelineSuffix,
  };
}

/**
 * Return markdown guidance for spawning an agent under the active harness.
 */
export function formatAgentSpawn(agent: string, prompt: string): string {
  const harness = detectHarness();
  const agentId = normalizeAgentName(agent);

  if (harness === "grok") {
    return (
      `Use **spawn_subagent** with agent \`${agentId}\` and this prompt:\n\n${prompt}`
    );
  }

  return (
    `Use the **Task tool** with subagent_type \`${agentId}\` and this prompt:\n\n${prompt}`
  );
}

/**
 * Structured agent spawn — maps Claude Task tool to Grok spawn_subagent.
 */
export function spawnAgent(agent: string, prompt: string): AgentSpawn {
  const harness = detectHarness();
  const agentId = normalizeAgentName(agent);

  if (harness === "grok") {
    return {
      harness,
      tool: "spawn_subagent",
      agent: agentId,
      prompt,
      instruction:
        `Spawn via **spawn_subagent** with agent \`${agentId}\` ` +
        "(enable with `GROK_SUBAGENTS=1` or `[subagents] enabled = true` in config). " +
        "Pass the prompt verbatim — do NOT substitute a manual workflow.",
    };
  }

  return {
    harness: harness === "claude" ? "claude" : harness,
    tool: "Task",
    agent: agentId,
    prompt,
    instruction:
      `Spawn via the **Task tool** with subagent_type \`${agentId}\`. ` +
      "Pass the prompt verbatim.",
  };
}

/**
 * Harness-specific guidance for merge → release → deploy polling loops.
 * Cite in ship Phase 7, postmerge Phase 2, one-shot Step 7–8.
 */
export function pollInstructions(harness: Harness): string {
  switch (harness) {
    case "claude":
      return [
        "**Merge/deploy polling (Claude Code)**",
        "- Use the **Monitor tool** with state-change + heartbeat shell loops.",
        "- NEVER Bash `run_in_background` for PR merge, CI, or release polling.",
        "- After merge: watch release workflows to `completed`, then invoke `soleur:postmerge`.",
        "- FORBIDDEN: asking the operator to watch merge/deploy status.",
      ].join("\n");

    case "grok":
      return [
        "**Merge/deploy polling (Grok Build)**",
        "- Use **Shell** with adequate `block_until_ms` for short `gh` probes.",
        "- Use **AwaitShell** with a `pattern` regex for long poll loops (PR merge Phase 7, release runs, postmerge CI) — match terminal lines like `MERGED`, `completed success`, `postmerge verification complete`.",
        "- NEVER ask the operator to monitor merge, CI, or deploy — you own the wait.",
        "- After `/ship` merge: poll release workflows, invoke `/postmerge <PR>`, then emit `<promise>DONE</promise>`.",
        "- FORBIDDEN: ending the turn after `gh pr merge --auto` without polling through deploy verification.",
      ].join("\n");

    default:
      return [
        "**Merge/deploy polling**",
        "- Poll PR merge and release workflows to completion before ending.",
        "- Invoke postmerge verification before declaring done.",
      ].join("\n");
  }
}

/**
 * Markdown snippet for go.md / eval-harness — embed at routing time.
 */
export function routingInstructions(harness: Harness): string {
  const fidelity = workflowFidelityInstructions(harness);
  const polling = pollInstructions(harness);

  switch (harness) {
    case "claude":
      return [
        "**Harness: Claude Code**",
        "- Skills: **Skill tool** with `soleur:<skill>` namespace.",
        "- Agents: **Task tool** with `subagent_type`.",
        "- Commands: `/soleur:go`, `/soleur:sync`, `/soleur:help`.",
        "- **Never improvise** when a route names a `soleur:<skill>` or agent — invoke it.",
        "",
        fidelity,
        "",
        polling,
      ].join("\n");

    case "grok":
      return [
        "**Harness: Grok Build**",
        "- Skills: **slash commands** — `/brainstorm`, `/one-shot`, `/plan`, etc.",
        "- Agents: **spawn_subagent** (not Task).",
        "- Commands: `/go`, `/sync`, `/help` — **not** `/soleur:go`.",
        "- **Never improvise** — invoke the registered slash command or subagent.",
        "",
        fidelity,
        "",
        polling,
      ].join("\n");

    default:
      return [
        "**Harness: unknown** — default to Claude conventions.",
        "- Skills: Skill tool (`soleur:<skill>`). Agents: Task tool.",
        "- If tools are missing, run `grok inspect` and `grok --trust` from repo root.",
        "",
        fidelity,
        "",
        polling,
      ].join("\n");
  }
}
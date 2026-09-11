/**
 * Harness adapter — maps Soleur workflow invocations to Claude Code, Grok Build, Codex, or Devin CLI.
 *
 * Claude: Skill tool (`soleur:<skill>`), Task tool (agents), `/soleur:<command>` slash commands.
 * Grok:   slash commands (`/<skill>`, `/go`), spawn_subagent (agents).
 * Codex:  $soleur:<skill> skill mentions, spawn_agent (agents).
 * Devin:  Skill tool (`soleur:<skill>`), run_subagent (agents), `/soleur:<command>` slash commands.
 *
 * Skills and go.md must call these helpers (or follow routingInstructions) — never improvise workflows.
 */

import { resolve } from "path";
import {
  agentIdToGrokSubagentType,
  discoverAgentEntries,
  pathToAgentId,
  PLUGIN_ROOT,
} from "./agent-registry";
import { behindSyncInstructions } from "./pr-merge-poll";
import { pipelineInvocationSuffix, workflowFidelityInstructions } from "./workflow-fidelity";

export type Harness = "claude" | "grok" | "codex" | "devin" | "unknown";

/** Env vars set by Grok Build (see https://docs.x.ai/build/settings/reference). */
const GROK_ENV_MARKERS = [
  "GROK_HOME",
  "GROK_AGENT",
  "GROK_DEFAULT_MODEL",
  "GROK_SUBAGENTS",
] as const;

/** Env vars set by Devin CLI. */
const DEVIN_ENV_MARKERS = [
  "DEVIN",
  "DEVIN_HOME",
] as const;

export interface SkillInvocation {
  harness: Harness;
  tool: "Skill" | "slash_command" | "skill";
  command: string;
  args?: string;
  instruction: string;
}

export interface AgentSpawn {
  harness: Harness;
  tool: "Task" | "spawn_subagent" | "spawn_agent" | "run_subagent";
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
 * Detection order: CLAUDECODE → GROK_* → CODEX_THREAD_ID → DEVIN_* → process title/argv heuristics.
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

  if (env.CODEX_THREAD_ID) {
    return "codex";
  }

  for (const key of DEVIN_ENV_MARKERS) {
    if (env[key]) {
      return "devin";
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
    if (title.includes("devin") || /\bdevin\b/.test(argv)) {
      return "devin";
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

  if (harness === "codex") {
    return trimmedArgs ? `$soleur:${name} ${trimmedArgs}` : `$soleur:${name}`;
  }

  if (harness === "grok") {
    return trimmedArgs ? `/${name} ${trimmedArgs}` : `/${name}`;
  }

  if (harness === "devin") {
    const command = trimmedArgs ? `/soleur:${name} ${trimmedArgs}` : `/soleur:${name}`;
    return command;
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

  if (harness === "codex") {
    return {
      harness,
      tool: "skill",
      command: `$soleur:${name}`,
      args: trimmedArgs,
      instruction:
        `Load the registered Soleur skill $soleur:${name}: read its SKILL.md and follow the entire workflow.` +
        (trimmedArgs ? ` Use these arguments as $ARGUMENTS: ${trimmedArgs}` : "") +
        " Use skills.read when available, otherwise read the installed skill file. Do not send a dollar mention to the shell." +
        pipelineSuffix,
    };
  }

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

  if (harness === "devin") {
    const command = trimmedArgs ? `/soleur:${name} ${trimmedArgs}` : `/soleur:${name}`;
    return {
      harness,
      tool: "slash_command",
      command,
      args: trimmedArgs,
      instruction:
        `Invoke the registered skill via the \`${command}\` slash command. ` +
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

  if (harness === "codex") {
    const spawn = spawnAgent(agent, prompt);
    return `${spawn.instruction}\n\n${spawn.prompt}`;
  }

  if (harness === "grok") {
    // Grok validates subagent_type against the .grok/agents filename stem
    // (colons → hyphens), not the colon-qualified Claude id.
    const grokType = agentIdToGrokSubagentType(agentId);
    return (
      `Use **spawn_subagent** with subagent_type \`${grokType}\` ` +
      `(Grok spawn key; canonical id \`${agentId}\`) and this prompt:\n\n${prompt}`
    );
  }

  if (harness === "devin") {
    return (
      `Use the **run_subagent** tool with agent \`${agentId}\` and this prompt:\n\n${prompt}`
    );
  }

  return (
    `Use the **Task tool** with subagent_type \`${agentId}\` and this prompt:\n\n${prompt}`
  );
}

/**
 * Structured agent spawn — maps Claude Task tool to Grok spawn_subagent, Codex spawn_agent, and Devin run_subagent.
 */
export function spawnAgent(agent: string, prompt: string): AgentSpawn {
  const harness = detectHarness();
  const agentId = normalizeAgentName(agent);

  if (harness === "codex") {
    const entries = discoverAgentEntries().filter(
      (entry) => entry.id === agentId || entry.name === agentId,
    );
    if (entries.length !== 1) {
      throw new Error(`Unknown or ambiguous Soleur agent: ${agent}`);
    }
    const entry = entries[0];
    return {
      harness,
      tool: "spawn_agent",
      agent: entry.id,
      prompt: `Read and follow the Soleur agent definition at ${resolve(PLUGIN_ROOT, entry.path)}.\nApply the Codex compatibility instructions at ${resolve(PLUGIN_ROOT, "codex/INSTRUCTIONS.md")}.\n\n${prompt}`,
      instruction:
        "Use the available spawn_agent tool with its default agent type and pass the supplied prompt verbatim as its message. " +
        "Inherit the session model and permissions. Use the tool's actual schema; the Soleur ID identifies the instruction file, not a registered Codex agent type.",
    };
  }

  if (harness === "grok") {
    const grokType = agentIdToGrokSubagentType(agentId);
    return {
      harness,
      tool: "spawn_subagent",
      agent: grokType,
      prompt,
      instruction:
        `Spawn via **spawn_subagent** with subagent_type \`${grokType}\` ` +
        `(not colon form \`${agentId}\` — Grok matches the \`.grok/agents/\` filename stem). ` +
        "Enable with `GROK_SUBAGENTS=1` or `[subagents] enabled = true` in config. " +
        "Pass the prompt verbatim — do NOT substitute a manual workflow.",
    };
  }

  if (harness === "devin") {
    const entries = discoverAgentEntries().filter(
      (entry) => entry.id === agentId || entry.name === agentId,
    );
    if (entries.length !== 1) {
      throw new Error(`Unknown or ambiguous Soleur agent: ${agent}`);
    }
    const entry = entries[0];
    return {
      harness,
      tool: "run_subagent",
      agent: entry.id,
      prompt: `Read and follow the Soleur agent definition at ${resolve(PLUGIN_ROOT, entry.path)}.\nApply the Devin compatibility instructions at ${resolve(PLUGIN_ROOT, "devin/INSTRUCTIONS.md")}.\n\n${prompt}`,
      instruction:
        `Spawn via **run_subagent** with agent \`${entry.id}\`. ` +
        "Inherit the session model and permissions. " +
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
  const behind = behindSyncInstructions(harness);

  switch (harness) {
    case "codex":
      return [
        "**Merge/deploy polling (Codex)**",
        "- Use exec_command for bounded status probes; resume yielded shell sessions with write_stdin.",
        "- Poll PR state and mergeStateStatus, resolve BEHIND in the PR worktree before continuing.",
        "- Keep waiting through merge and release completion; load $soleur:postmerge before declaring completion.",
        behind,
      ].join("\n");

    case "claude":
      return [
        "**Merge/deploy polling (Claude Code)**",
        "- Poll `gh pr view --jq '.state,.mergeStateStatus'` — not checks alone.",
        "- Use the **Monitor tool**, and prefer the canonical loop over hand-rolling one:",
        "  `Monitor({command: \"bash plugins/soleur/scripts/monitor-pr-checks.sh <PR>\",",
        "  persistent: true, description: \"PR #<N> checks\"})`.",
        "  Pass `persistent: true` — the Monitor tool's `timeout_ms` DEFAULTS TO 5 MINUTES and",
        "  caps at 1 hour, while this script's default budget is 60 polls x 120s = 2 hours, so the",
        "  obvious invocation is killed after roughly one line.",
        "  **It emits on every CHANGE, plus a heartbeat every `--heartbeat-every` polls (default 5)",
        "  when nothing changed.** Silence must never be the healthy signal — but emitting every",
        "  poll unconditionally is the opposite failure, since the Monitor tool auto-stops a watch",
        "  that produces too many events. A hand-rolled",
        "  loop whose every `echo` sits behind a terminal-state branch satisfies both monitor",
        "  hard rules and still emits nothing for the entire run — measured on #7778, where the",
        "  operator had to ask why the monitor showed no progress. The Monitor docs warn about",
        "  the inverse case only (\"if this crashed, would my filter emit?\"); the healthy",
        "  still-running path is the one that gets forgotten, and silence there is",
        "  indistinguishable from a dead watch.",
        "- NEVER Bash `run_in_background` for PR merge, CI, or release polling.",
        "- **A monitor is a resource with a lifetime. Re-scoping what you watch means",
        "  `TaskStop` on the old one FIRST — never arming a second beside it.** A monitor",
        "  exits only when the state it polls goes terminal, so a superseded one does not",
        "  wind down on its own: it keeps polling the same endpoint at the same cadence",
        "  for its full timeout. Layering is the default failure because each re-scope",
        "  feels like a new need rather than a replacement.",
        "  In the Soleur repo a hook additionally REPORTS a re-arm on a target you are",
        "  still watching, naming the task ids to stop. It does not block: it reads",
        "  liveness from an undocumented transcript shape, so it fails open by design.",
        "- After merge: watch release workflows to `completed`, then invoke `soleur:postmerge`.",
        "- FORBIDDEN: asking the operator to watch merge/deploy status.",
        "",
        behind,
      ].join("\n");

    case "grok":
      return [
        "**Merge/deploy polling (Grok Build)**",
        "- Poll `gh pr view --json state,mergeStateStatus` on every tick — **pending checks alone miss BEHIND**.",
        "- Use **Shell** with adequate `block_until_ms` for short `gh` probes.",
        "- Use **AwaitShell** with `pattern` for long loops — match `MERGED`, `BEHIND detected`, `auto-sync.*pushed`, `BEHIND resolved`, `postmerge verification complete`.",
        "- NEVER ask the operator to monitor merge, CI, or deploy — you own the wait.",
        "- After `/ship` merge: poll release workflows, invoke `/postmerge <PR>`, then emit `<promise>DONE</promise>`.",
        "- FORBIDDEN: heartbeating on CI while `mergeStateStatus` is `BEHIND`.",
        "",
        behind,
      ].join("\n");

    case "devin":
      return [
        "**Merge/deploy polling (Devin CLI)**",
        "- Poll `gh pr view --json state,mergeStateStatus` on every tick — **pending checks alone miss BEHIND**.",
        "- Use **exec** with adequate timeout for short `gh` probes.",
        "- Use **get_output** with timeout for long loops — match `MERGED`, `BEHIND detected`, `auto-sync.*pushed`, `BEHIND resolved`, `postmerge verification complete`.",
        "- NEVER ask the operator to monitor merge, CI, or deploy — you own the wait.",
        "- After `/soleur:ship` merge: poll release workflows, invoke `/soleur:postmerge <PR>`, then emit `<promise>DONE</promise>`.",
        "- FORBIDDEN: heartbeating on CI while `mergeStateStatus` is `BEHIND`.",
        "",
        behind,
      ].join("\n");

    default:
      return [
        "**Merge/deploy polling**",
        "- Poll PR state + mergeStateStatus; resync on BEHIND before watching checks.",
        "- Invoke postmerge verification before declaring done.",
        "",
        behind,
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
    case "codex":
      return [
        "**Harness: Codex**",
        "- Entry points: $soleur:go, $soleur:sync, $soleur:help.",
        "- Load named skills through skills.read when available, otherwise read their installed SKILL.md and follow every required phase.",
        "- Agents: spawn_agent with a prompt that reads the canonical agent definition; use spawnAgent() to resolve its absolute path.",
        "- Read codex/INSTRUCTIONS.md in the installed plugin for tool and path mappings.",
        fidelity,
        polling,
      ].join("\n");

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
        "- Agents: **spawn_subagent** (not Task). Use `spawnAgent()` so registry colon ids map to hyphen filename stems (`soleur:product:cpo` → `soleur-product-cpo`).",
        "- Commands: `/go`, `/sync`, `/help` — **not** `/soleur:go`.",
        "- **Never improvise** — invoke the registered slash command or subagent.",
        "",
        fidelity,
        "",
        polling,
      ].join("\n");

    case "devin":
      return [
        "**Harness: Devin CLI**",
        "- Skills: **slash commands** — `/soleur:<skill>` (e.g. `/soleur:one-shot`, `/soleur:brainstorm`).",
        "- Agents: **run_subagent** with agent id.",
        "- Commands: `/soleur:go`, `/soleur:sync`, `/soleur:help`.",
        "- **Never improvise** when a route names a `soleur:<skill>` or agent — invoke the slash command or subagent.",
        "- Read devin/INSTRUCTIONS.md in the installed plugin for tool and path mappings.",
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

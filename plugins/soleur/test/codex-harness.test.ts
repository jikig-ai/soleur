import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import {
  detectHarness,
  formatAgentSpawn,
  formatSkillInvocation,
  invokeSkill,
  pollInstructions,
  routingInstructions,
  spawnAgent,
} from "../lib/harness";

const markers = ["CLAUDECODE", "GROK_HOME", "GROK_AGENT", "GROK_DEFAULT_MODEL", "GROK_SUBAGENTS", "CODEX_THREAD_ID", "DEVIN", "DEVIN_HOME"];
let saved: Record<string, string | undefined>;

beforeEach(() => {
  saved = Object.fromEntries(markers.map((key) => [key, process.env[key]]));
  for (const key of markers) delete process.env[key];
  process.env.CODEX_THREAD_ID = "test-codex-thread";
});

afterEach(() => {
  for (const key of markers) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
});

describe("Codex harness", () => {
  test("detects a session, but does not mistake an installed CLI for one", () => {
    expect(detectHarness({ CODEX_THREAD_ID: "test-thread" })).toBe("codex");
    expect(detectHarness({ CODEX_HOME: "/tmp/example" })).toBe("unknown");
    expect(detectHarness({ CLAUDECODE: "1", CODEX_THREAD_ID: "parent" })).toBe("claude");
  });

  test("routes a workflow to its namespaced Codex skill with arguments intact", () => {
    const invocation = invokeSkill("soleur:one-shot", "  fix the checkout  ");
    expect(invocation.harness).toBe("codex");
    expect(invocation.tool).toBe("skill");
    expect(invocation.command).toBe("$soleur:one-shot");
    expect(invocation.args).toBe("fix the checkout");
    expect(invocation.instruction).toContain("SKILL.md");
    expect(invocation.instruction).toContain("Steps 0–8");
    expect(formatSkillInvocation("brainstorm", "new feature")).toBe("$soleur:brainstorm new feature");
  });

  test("supplies canonical agent instructions to a generic Codex subagent", () => {
    const spawned = spawnAgent("engineering/review/security-sentinel", "Review checkout");
    expect(spawned.harness).toBe("codex");
    expect(spawned.tool).toBe("spawn_agent");
    expect(spawned.agent).toBe("soleur:engineering:review:security-sentinel");
    expect(spawned.prompt).toContain("/agents/engineering/review/security-sentinel.md");
    expect(spawned.prompt).toContain("Review checkout");
    expect(spawned.instruction).not.toContain("subagent_type");
    expect(formatAgentSpawn("product/cpo", "Assess")).toContain("spawn_agent");
  });

  test("explains skill loading and owned polling without unavailable tools", () => {
    const routing = routingInstructions("codex");
    expect(routing).toContain("$soleur:go");
    expect(routing).toContain("spawn_agent");
    expect(routing).not.toContain("**Skill tool**");
    expect(pollInstructions("codex")).toContain("write_stdin");
    expect(pollInstructions("codex")).toContain("BEHIND");
  });
});

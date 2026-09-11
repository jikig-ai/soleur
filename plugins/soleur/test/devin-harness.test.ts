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

const markers = [
  "CLAUDECODE",
  "GROK_HOME",
  "GROK_AGENT",
  "GROK_DEFAULT_MODEL",
  "GROK_SUBAGENTS",
  "CODEX_THREAD_ID",
  "DEVIN",
  "DEVIN_HOME",
];
let saved: Record<string, string | undefined>;

beforeEach(() => {
  saved = Object.fromEntries(markers.map((key) => [key, process.env[key]]));
  for (const key of markers) delete process.env[key];
  process.env.DEVIN = "1";
});

afterEach(() => {
  for (const key of markers) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
});

describe("Devin harness", () => {
  test("detects a session, but does not mistake an installed CLI for one", () => {
    expect(detectHarness({ DEVIN: "1" })).toBe("devin");
    expect(detectHarness({ DEVIN_HOME: "/home/user/.devin" })).toBe("devin");
    expect(detectHarness({ CLAUDECODE: "1", DEVIN: "1" })).toBe("claude");
    expect(detectHarness({ GROK_HOME: "/home/user/.grok", DEVIN: "1" })).toBe("grok");
    expect(detectHarness({ CODEX_THREAD_ID: "test-thread", DEVIN: "1" })).toBe("codex");
  });

  test("routes a workflow to its namespaced Devin skill with arguments intact", () => {
    const invocation = invokeSkill("soleur:one-shot", "  fix the checkout  ");
    expect(invocation.harness).toBe("devin");
    expect(invocation.tool).toBe("Skill");
    expect(invocation.command).toBe("soleur:one-shot");
    expect(invocation.args).toBe("fix the checkout");
    expect(invocation.instruction).toContain("Skill tool");
    expect(invocation.instruction).toContain("Steps 0–8");
    expect(formatSkillInvocation("brainstorm", "new feature")).toBe("soleur:brainstorm (args: new feature)");
  });

  test("supplies canonical agent instructions to a Devin subagent", () => {
    const spawned = spawnAgent("engineering/review/security-sentinel", "Review checkout");
    expect(spawned.harness).toBe("devin");
    expect(spawned.tool).toBe("run_subagent");
    expect(spawned.agent).toBe("soleur:engineering:review:security-sentinel");
    expect(spawned.prompt).toContain("/agents/engineering/review/security-sentinel.md");
    expect(spawned.prompt).toContain("Review checkout");
    expect(spawned.prompt).toContain("devin/INSTRUCTIONS.md");
    expect(spawned.instruction).toContain("run_subagent");
    expect(formatAgentSpawn("product/cpo", "Assess")).toContain("run_subagent");
  });

  test("explains skill loading and owned polling without unavailable tools", () => {
    const routing = routingInstructions("devin");
    expect(routing).toContain("/soleur:go");
    expect(routing).toContain("run_subagent");
    expect(routing).toContain("devin/INSTRUCTIONS.md");
    expect(routing).not.toContain("**Monitor tool**");
    expect(pollInstructions("devin")).toContain("get_output");
    expect(pollInstructions("devin")).toContain("BEHIND");
    expect(pollInstructions("devin")).toContain("/soleur:postmerge");
    expect(pollInstructions("devin")).toContain("/soleur:ship");
  });

  test("handles Devin-specific skill invocation format", () => {
    process.env.DEVIN = "1";
    const inv = invokeSkill("plan", "implement feature");
    expect(inv.harness).toBe("devin");
    expect(inv.tool).toBe("Skill");
    expect(inv.command).toBe("soleur:plan");
    expect(inv.args).toBe("implement feature");
    expect(inv.instruction).toContain("Skill tool");
    expect(inv.instruction).toContain("Do NOT improvise");
  });

  test("handles Devin-specific agent spawning format", () => {
    process.env.DEVIN = "1";
    const spawn = spawnAgent("clo", "Legal attestation");
    expect(spawn.harness).toBe("devin");
    expect(spawn.tool).toBe("run_subagent");
    expect(spawn.agent).toBe("soleur:legal:clo");
    expect(spawn.instruction).toContain("run_subagent");
    expect(spawn.instruction).toContain("Inherit the session model");
  });
});

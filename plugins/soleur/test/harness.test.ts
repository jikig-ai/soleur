import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import {
  detectHarness,
  formatSkillInvocation,
  formatAgentSpawn,
  invokeSkill,
  spawnAgent,
  routingInstructions,
  normalizeSkillName,
  normalizeAgentName,
} from "../lib/harness";

function env(overrides: Record<string, string | undefined>): NodeJS.ProcessEnv {
  const base: NodeJS.ProcessEnv = {};
  for (const [key, val] of Object.entries(overrides)) {
    if (val !== undefined) {
      base[key] = val;
    }
  }
  return base;
}

/** Snapshot and restore harness-related env vars between tests. */
let savedEnv: Record<string, string | undefined>;

beforeEach(() => {
  savedEnv = {
    CLAUDECODE: process.env.CLAUDECODE,
    GROK_HOME: process.env.GROK_HOME,
    GROK_AGENT: process.env.GROK_AGENT,
    GROK_DEFAULT_MODEL: process.env.GROK_DEFAULT_MODEL,
    GROK_SUBAGENTS: process.env.GROK_SUBAGENTS,
  };
  delete process.env.CLAUDECODE;
  delete process.env.GROK_HOME;
  delete process.env.GROK_AGENT;
  delete process.env.GROK_DEFAULT_MODEL;
  delete process.env.GROK_SUBAGENTS;
});

afterEach(() => {
  for (const [key, val] of Object.entries(savedEnv)) {
    if (val === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = val;
    }
  }
});

describe("detectHarness", () => {
  test("CLAUDECODE → claude", () => {
    expect(detectHarness(env({ CLAUDECODE: "1" }))).toBe("claude");
  });

  test("GROK_HOME → grok", () => {
    expect(detectHarness(env({ GROK_HOME: "/home/user/.grok" }))).toBe("grok");
  });

  test("GROK_AGENT → grok", () => {
    expect(detectHarness(env({ GROK_AGENT: "grok-build" }))).toBe("grok");
  });

  test("CLAUDECODE wins over GROK_* when both set", () => {
    expect(
      detectHarness(env({ CLAUDECODE: "1", GROK_HOME: "/home/user/.grok" })),
    ).toBe("claude");
  });

  test("empty env → unknown", () => {
    expect(detectHarness(env({}))).toBe("unknown");
  });
});

describe("normalizeSkillName", () => {
  test("strips soleur: prefix", () => {
    expect(normalizeSkillName("soleur:one-shot")).toBe("one-shot");
    expect(normalizeSkillName("brainstorm")).toBe("brainstorm");
  });
});

describe("normalizeAgentName", () => {
  test("bare name passes through", () => {
    expect(normalizeAgentName("clo")).toBe("clo");
  });

  test("namespaced path gets soleur: prefix", () => {
    expect(normalizeAgentName("legal:clo")).toBe("soleur:legal:clo");
  });

  test("already qualified unchanged", () => {
    expect(normalizeAgentName("soleur:legal:clo")).toBe("soleur:legal:clo");
  });

  test("path-style agent resolves via registry", () => {
    expect(normalizeAgentName("engineering/review/security-sentinel")).toBe(
      "soleur:engineering:review:security-sentinel",
    );
  });
});

describe("formatSkillInvocation", () => {
  test("claude formats soleur: skill with args", () => {
    process.env.CLAUDECODE = "1";
    expect(formatSkillInvocation("one-shot", "fix auth")).toBe(
      "soleur:one-shot (args: fix auth)",
    );
  });

  test("grok formats slash command", () => {
    process.env.GROK_HOME = "/home/user/.grok";
    expect(formatSkillInvocation("soleur:brainstorm", "add feature")).toBe(
      "/brainstorm add feature",
    );
    expect(formatSkillInvocation("plan")).toBe("/plan");
  });
});

describe("invokeSkill", () => {
  test("claude returns Skill tool invocation", () => {
    process.env.CLAUDECODE = "1";
    const inv = invokeSkill("one-shot", "fix bug");

    expect(inv.harness).toBe("claude");
    expect(inv.tool).toBe("Skill");
    expect(inv.command).toBe("soleur:one-shot");
    expect(inv.args).toBe("fix bug");
    expect(inv.instruction).toContain("Skill tool");
    expect(inv.instruction).toContain("Do NOT improvise");
  });

  test("grok returns slash_command invocation", () => {
    process.env.GROK_HOME = "/home/user/.grok";
    const inv = invokeSkill("drain-labeled-backlog", "--label security");

    expect(inv.harness).toBe("grok");
    expect(inv.tool).toBe("slash_command");
    expect(inv.command).toBe("/drain-labeled-backlog --label security");
    expect(inv.instruction).toContain("slash command");
  });
});

describe("spawnAgent", () => {
  test("claude uses Task tool", () => {
    process.env.CLAUDECODE = "1";
    const spawn = spawnAgent("clo", "Review issue #123");

    expect(spawn.harness).toBe("claude");
    expect(spawn.tool).toBe("Task");
    expect(spawn.agent).toBe("clo");
    expect(spawn.instruction).toContain("Task tool");
  });

  test("grok uses spawn_subagent", () => {
    process.env.GROK_HOME = "/home/user/.grok";
    const spawn = spawnAgent("legal:clo", "Attestation for #456");

    expect(spawn.harness).toBe("grok");
    expect(spawn.tool).toBe("spawn_subagent");
    expect(spawn.agent).toBe("soleur:legal:clo");
    expect(spawn.instruction).toContain("spawn_subagent");
  });
});

describe("formatAgentSpawn", () => {
  test("claude mentions Task tool", () => {
    process.env.CLAUDECODE = "1";
    const text = formatAgentSpawn("clo", "prompt body");
    expect(text).toContain("Task tool");
    expect(text).toContain("prompt body");
  });

  test("grok mentions spawn_subagent", () => {
    process.env.GROK_HOME = "/home/user/.grok";
    const text = formatAgentSpawn("clo", "prompt body");
    expect(text).toContain("spawn_subagent");
  });
});

describe("routingInstructions", () => {
  test("claude documents soleur: namespace", () => {
    const md = routingInstructions("claude");
    expect(md).toContain("soleur:<skill>");
    expect(md).toContain("/soleur:go");
    expect(md).toContain("Never improvise");
  });

  test("grok documents /go not /soleur:go", () => {
    const md = routingInstructions("grok");
    expect(md).toContain("/go");
    expect(md).toContain("**not** `/soleur:go`");
    expect(md).toContain("spawn_subagent");
  });

  test("unknown suggests grok inspect", () => {
    const md = routingInstructions("unknown");
    expect(md).toContain("grok inspect");
  });
});
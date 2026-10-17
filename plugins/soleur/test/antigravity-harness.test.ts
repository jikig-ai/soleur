import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import {
  detectHarness,
  formatSkillInvocation,
  formatAgentSpawn,
  invokeSkill,
  spawnAgent,
  routingInstructions,
  pollInstructions,
} from "../lib/harness";
import { readToolsTable, ANTIGRAVITY_INSTRUCTIONS, CLAUDE_CODE_TOOLS, usesTool, isEmptyTranslation } from "../lib/harness-tool-map";
import { readPopulation } from "../lib/harness-parity";

function env(overrides: Record<string, string | undefined>): NodeJS.ProcessEnv {
  const base: NodeJS.ProcessEnv = {};
  for (const [key, val] of Object.entries(overrides)) {
    if (val !== undefined) {
      base[key] = val;
    }
  }
  return base;
}

let savedEnv: Record<string, string | undefined>;

beforeEach(() => {
  savedEnv = {
    CLAUDECODE: process.env.CLAUDECODE,
    ANTIGRAVITY_CLI: process.env.ANTIGRAVITY_CLI,
    AGY_VERSION: process.env.AGY_VERSION,
    GEMINI_CLI: process.env.GEMINI_CLI,
    CODEX_THREAD_ID: process.env.CODEX_THREAD_ID,
    GROK_HOME: process.env.GROK_HOME,
    DEVIN: process.env.DEVIN,
  };
  delete process.env.CLAUDECODE;
  delete process.env.ANTIGRAVITY_CLI;
  delete process.env.AGY_VERSION;
  delete process.env.GEMINI_CLI;
  delete process.env.CODEX_THREAD_ID;
  delete process.env.GROK_HOME;
  delete process.env.DEVIN;
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

describe("Antigravity Harness - detectHarness", () => {
  test("ANTIGRAVITY_CLI → antigravity", () => {
    expect(detectHarness(env({ ANTIGRAVITY_CLI: "1" }))).toBe("antigravity");
  });

  test("AGY_VERSION → antigravity", () => {
    expect(detectHarness(env({ AGY_VERSION: "1.0.0" }))).toBe("antigravity");
  });

  test("GEMINI_CLI → antigravity", () => {
    expect(detectHarness(env({ GEMINI_CLI: "1" }))).toBe("antigravity");
  });

  test("CLAUDECODE wins over ANTIGRAVITY_CLI when both set", () => {
    expect(
      detectHarness(env({ CLAUDECODE: "1", ANTIGRAVITY_CLI: "1" })),
    ).toBe("claude");
  });

  test("ANTIGRAVITY_CLI wins over DEVIN when both set", () => {
    expect(
      detectHarness(env({ ANTIGRAVITY_CLI: "1", DEVIN: "1" })),
    ).toBe("antigravity");
  });
});

describe("Antigravity Harness - formatSkillInvocation", () => {
  test("formats slash command with args", () => {
    process.env.ANTIGRAVITY_CLI = "1";
    expect(formatSkillInvocation("one-shot", "fix auth")).toBe("/soleur:one-shot fix auth");
    expect(formatSkillInvocation("plan")).toBe("/soleur:plan");
  });
});

describe("Antigravity Harness - invokeSkill", () => {
  test("returns progressive disclosure instruction for antigravity", () => {
    process.env.ANTIGRAVITY_CLI = "1";
    const inv = invokeSkill("one-shot", "fix bug");

    expect(inv.harness).toBe("antigravity");
    expect(inv.tool).toBe("slash_command");
    expect(inv.command).toBe("/soleur:one-shot fix bug");
    expect(inv.instruction).toContain("SKILL.md");
    expect(inv.instruction).toContain("Do NOT improvise");
  });
});

describe("Antigravity Harness - spawnAgent", () => {
  test("uses invoke_subagent with prompt referencing canonical definition", () => {
    process.env.ANTIGRAVITY_CLI = "1";
    const spawn = spawnAgent("clo", "Review issue #123");

    expect(spawn.harness).toBe("antigravity");
    expect(spawn.tool).toBe("invoke_subagent");
    expect(spawn.agent).toBe("soleur:legal:clo");
    expect(spawn.instruction).toContain("invoke_subagent");
    expect(spawn.prompt).toContain("antigravity/INSTRUCTIONS.md");
  });
});

describe("Antigravity Harness - formatAgentSpawn", () => {
  test("mentions invoke_subagent and define_subagent", () => {
    process.env.ANTIGRAVITY_CLI = "1";
    const text = formatAgentSpawn("clo", "prompt body");
    expect(text).toContain("invoke_subagent");
    expect(text).toContain("prompt body");
  });
});

describe("Antigravity Harness - routingInstructions", () => {
  test("documents /soleur:go, invoke_subagent, and send_message", () => {
    const md = routingInstructions("antigravity");
    expect(md).toContain("/soleur:go");
    expect(md).toContain("invoke_subagent");
    expect(md).toContain("send_message");
    expect(md).toContain("antigravity/INSTRUCTIONS.md");
    expect(md).toContain("Workflow fidelity");
    expect(md).not.toContain("Skill tool");
  });
});

describe("Antigravity Harness - pollInstructions", () => {
  test("documents schedule and background run_command reactive polling", () => {
    const md = pollInstructions("antigravity");
    expect(md).toContain("[ship.phase7.queue_wait]");
    expect(md).toContain("schedule");
    expect(md).toContain("run_command");
    expect(md).toContain("manage_task");
    expect(md).toContain("/soleur:postmerge");
    expect(md).toContain("NEVER ask");
  });
});

describe("Antigravity Harness - Tool Translation Table", () => {
  test("the Antigravity ## Tools table parses to a non-empty vocabulary", () => {
    const table = readToolsTable(ANTIGRAVITY_INSTRUCTIONS);
    expect(table.size).toBeGreaterThanOrEqual(30);
  });

  test("every used Claude tool name is translated by the Antigravity table", () => {
    const table = readToolsTable(ANTIGRAVITY_INSTRUCTIONS);
    const docs = readPopulation().map((d) => ({ path: d.path, text: d.text }));
    const problems: string[] = [];

    for (const tool of CLAUDE_CODE_TOOLS) {
      const user = docs.find((d) => usesTool(d.text, tool));
      if (!user) continue;
      if (!table.has(tool) || isEmptyTranslation(table.get(tool))) {
        problems.push(
          `${tool} used at ${user.path}, missing a translation in antigravity/INSTRUCTIONS.md`,
        );
      }
    }
    expect(problems).toEqual([]);
  });
});

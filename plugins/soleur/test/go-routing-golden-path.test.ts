import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";
import {
  dispatchGoRoute,
  resolveGoRoute,
  expectedGrokSlashCommand,
  grokTestEnv,
  claudeTestEnv,
  GO_SKILL_ROUTES,
} from "../lib/go-routing";
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { extractLabel } = require("../skills/eval-harness/scripts/parse-label.cjs");

const GO_ROUTING_TASKS = resolve(
  import.meta.dir,
  "../skills/eval-harness/tasks/go-routing.jsonl",
);
const GO_ENUM_PATH = resolve(
  import.meta.dir,
  "../skills/eval-harness/enums/go-routes.json",
);

type GoldenRow = { vars: { input: string; golden_label: string } };

function loadGoRoutingGoldenRows(): GoldenRow[] {
  return readFileSync(GO_ROUTING_TASKS, "utf-8")
    .trim()
    .split("\n")
    .filter((line) => line.length > 0)
    .map((line) => JSON.parse(line) as GoldenRow);
}

const GO_ENUM: string[] = JSON.parse(readFileSync(GO_ENUM_PATH, "utf-8"));

describe("go-routing golden-path (Grok harness)", () => {
  test('fix intent routes to /one-shot slash_command', () => {
    const input =
      "The dashboard throws a 500 when I click Export. It worked yesterday — can you fix it?";
    const dispatch = dispatchGoRoute("fix", input, grokTestEnv());

    expect(dispatch.kind).toBe("skill");
    if (dispatch.kind !== "skill") return;

    expect(dispatch.invocation.harness).toBe("grok");
    expect(dispatch.invocation.tool).toBe("slash_command");
    expect(dispatch.invocation.command).toBe(expectedGrokSlashCommand("one-shot", input));
    expect(dispatch.invocation.instruction).toContain("Do NOT improvise");
  });

  test("all skill routes produce Grok slash commands (not soleur: prefix)", () => {
    for (const [label, skill] of Object.entries(GO_SKILL_ROUTES)) {
      const dispatch = dispatchGoRoute(label, "test args", grokTestEnv());
      expect(dispatch.kind).toBe("skill");
      if (dispatch.kind !== "skill") continue;

      expect(dispatch.invocation.command).toBe(expectedGrokSlashCommand(skill, "test args"));
      expect(dispatch.invocation.command).not.toMatch(/^\/soleur:/);
    }
  });

  test("agent routes use spawn_subagent under Grok", () => {
    const dispatch = dispatchGoRoute(
      "legal-threshold",
      "Customer DSAR deletion request",
      grokTestEnv(),
    );
    expect(dispatch.kind).toBe("agent");
    if (dispatch.kind !== "agent") return;

    expect(dispatch.spawn.harness).toBe("grok");
    expect(dispatch.spawn.tool).toBe("spawn_subagent");
    expect(dispatch.spawn.agent).toBe("clo");
  });

  test("Claude harness preserves soleur: Skill tool for fix route", () => {
    const dispatch = dispatchGoRoute("fix", "fix auth", claudeTestEnv());
    expect(dispatch.kind).toBe("skill");
    if (dispatch.kind !== "skill") return;

    expect(dispatch.invocation.harness).toBe("claude");
    expect(dispatch.invocation.tool).toBe("Skill");
    expect(dispatch.invocation.command).toBe("soleur:one-shot");
  });
});

describe("go-routing golden-path (eval-harness corpus)", () => {
  test("fix golden row label resolves to one-shot skill", () => {
    const rows = loadGoRoutingGoldenRows();
    const fixRow = rows.find((r) => r.vars.golden_label === "fix");
    expect(fixRow).toBeDefined();

    const target = resolveGoRoute(fixRow!.vars.golden_label);
    expect(target).toEqual({ kind: "skill", skill: "one-shot" });

    const dispatch = dispatchGoRoute(fixRow!.vars.golden_label, fixRow!.vars.input, grokTestEnv());
    expect(dispatch.kind).toBe("skill");
    if (dispatch.kind === "skill") {
      expect(dispatch.invocation.command).toMatch(/^\/one-shot /);
    }
  });

  test("golden labels are members of go-routes enum", () => {
    for (const row of loadGoRoutingGoldenRows()) {
      expect(GO_ENUM).toContain(row.vars.golden_label);
      // Simulated classifier output for harness dispatch smoke (no LLM).
      const label = extractLabel(row.vars.golden_label, GO_ENUM);
      expect(label).toBe(row.vars.golden_label);
    }
  });
});
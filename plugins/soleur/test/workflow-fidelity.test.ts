import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";
import {
  isPipelineSkill,
  isOneShotRoute,
  resolveGoSkillRoute,
  ONE_SHOT_DONE_MARKER,
  GO_POST_ROUTE_SENTINEL,
  ONE_SHOT_ANTI_BYPASS_SENTINEL,
  workflowFidelityInstructions,
} from "../lib/workflow-fidelity";
import { invokeSkill, routingInstructions } from "../lib/harness";
import { dispatchGoRoute, expectedGrokSlashCommand, grokTestEnv } from "../lib/go-routing";

const PLUGIN_ROOT = resolve(import.meta.dir, "..");

describe("workflow-fidelity contract", () => {
  test("implement routes to one-shot", () => {
    expect(resolveGoSkillRoute("implement")).toBe("one-shot");
    expect(isOneShotRoute("implement")).toBe(true);
    expect(isOneShotRoute("default")).toBe(false);
  });

  test("pipeline skills include one-shot and drain skills", () => {
    expect(isPipelineSkill("one-shot")).toBe(true);
    expect(isPipelineSkill("drain-prs")).toBe(true);
    expect(isPipelineSkill("brainstorm")).toBe(false);
  });

  test("grok routing instructions include anti-bypass fidelity block", () => {
    const md = routingInstructions("grok");
    expect(md).toContain("Workflow fidelity");
    expect(md).toContain(ONE_SHOT_DONE_MARKER);
    expect(md).toContain("never bypass");
  });

  test("one-shot invokeSkill stresses full pipeline on Grok", () => {
    const prev = { ...process.env };
    process.env.GROK_HOME = "/home/user/.grok";
    try {
      const inv = invokeSkill("one-shot", "#6325 implement Phase F");
      expect(inv.tool).toBe("slash_command");
      expect(inv.instruction).toContain(ONE_SHOT_DONE_MARKER);
      expect(inv.instruction).toContain("Steps 0–8");
    } finally {
      Object.assign(process.env, prev);
    }
  });

  test("implement golden path dispatches /one-shot under Grok", () => {
    const input = "#6325 implement Phase F";
    const dispatch = dispatchGoRoute("implement", input, grokTestEnv());
    expect(dispatch.kind).toBe("skill");
    if (dispatch.kind === "skill") {
      expect(dispatch.invocation.command).toBe(expectedGrokSlashCommand("one-shot", input));
    }
  });
});

describe("workflow-fidelity sentinel markers in skills", () => {
  test("go.md contains post-route eval-gate block", () => {
    const goMd = readFileSync(resolve(PLUGIN_ROOT, "commands/go.md"), "utf-8");
    expect(goMd).toContain(`<!-- workflow-fidelity:block:${GO_POST_ROUTE_SENTINEL}:start -->`);
    expect(goMd).toContain("implement");
    expect(goMd).toContain("protocol violation");
  });

  test("one-shot SKILL.md contains anti-bypass protocol", () => {
    const skill = readFileSync(resolve(PLUGIN_ROOT, "skills/one-shot/SKILL.md"), "utf-8");
    expect(skill).toContain(ONE_SHOT_ANTI_BYPASS_SENTINEL);
    expect(skill).toContain("FORBIDDEN");
    expect(skill).toContain(ONE_SHOT_DONE_MARKER);
  });

  test("workflowFidelityInstructions mentions slash commands for Grok", () => {
    expect(workflowFidelityInstructions("grok")).toContain("/one-shot");
    expect(workflowFidelityInstructions("grok")).toContain("FORBIDDEN");
  });

  test("AGENTS.core.md pins pipeline-skills never-inline hard rule", () => {
    const core = readFileSync(resolve(PLUGIN_ROOT, "../../AGENTS.core.md"), "utf-8");
    expect(core).toContain("hr-pipeline-skills-never-inline-after-go-route");
  });
});
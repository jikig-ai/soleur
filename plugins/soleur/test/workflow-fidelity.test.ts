import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";
import {
  isPipelineSkill,
  isHandoffSkill,
  isOneShotRoute,
  isBrainstormRoute,
  resolveGoSkillRoute,
  ONE_SHOT_DONE_MARKER,
  GO_POST_ROUTE_SENTINEL,
  ONE_SHOT_ANTI_BYPASS_SENTINEL,
  BRAINSTORM_ANTI_BYPASS_SENTINEL,
  PLAN_ANTI_BYPASS_SENTINEL,
  WORK_ANTI_BYPASS_SENTINEL,
  LIFECYCLE_HANDOFF_SENTINEL,
  SHIP_MERGE_DEPLOY_SENTINEL,
  POSTMERGE_HARNESS_SENTINEL,
  POST_MERGE_VERIFICATION_SKILLS,
  BRAINSTORM_CHILD_SKILLS,
  IMPLEMENTATION_TAIL,
  ONE_SHOT_CHILD_SKILLS,
  mandatorySuccessors,
  workflowFidelityInstructions,
} from "../lib/workflow-fidelity";
import { invokeSkill, routingInstructions, pollInstructions } from "../lib/harness";
import { dispatchGoRoute, expectedGrokSlashCommand, grokTestEnv } from "../lib/go-routing";

const PLUGIN_ROOT = resolve(import.meta.dir, "..");

describe("workflow-fidelity contract", () => {
  test("implement routes to one-shot", () => {
    expect(resolveGoSkillRoute("implement")).toBe("one-shot");
    expect(isOneShotRoute("implement")).toBe(true);
    expect(isOneShotRoute("default")).toBe(false);
  });

  test("default routes to brainstorm", () => {
    expect(resolveGoSkillRoute("default")).toBe("brainstorm");
    expect(isBrainstormRoute("default")).toBe(true);
    expect(isBrainstormRoute("implement")).toBe(false);
  });

  test("pipeline skills include one-shot, brainstorm, and drain skills", () => {
    expect(isPipelineSkill("one-shot")).toBe(true);
    expect(isPipelineSkill("brainstorm")).toBe(true);
    expect(isPipelineSkill("drain-prs")).toBe(true);
    expect(isPipelineSkill("plan")).toBe(false);
  });

  test("handoff skills include plan, work, review, compound, ship", () => {
    expect(isHandoffSkill("plan")).toBe(true);
    expect(isHandoffSkill("work")).toBe(true);
    expect(isHandoffSkill("review")).toBe(true);
    expect(isHandoffSkill("compound")).toBe(true);
    expect(isHandoffSkill("ship")).toBe(true);
    expect(isHandoffSkill("brainstorm")).toBe(false);
  });

  test("ship mandates postmerge verification successors", () => {
    expect(POST_MERGE_VERIFICATION_SKILLS).toEqual(["postmerge"]);
    expect(mandatorySuccessors("ship")).toEqual(["postmerge"]);
  });

  test("ONE_SHOT_CHILD_SKILLS derives from plan prefix + implementation tail", () => {
    expect(ONE_SHOT_CHILD_SKILLS).toEqual([
      "plan",
      "deepen-plan",
      "work",
      "review",
      "qa",
      "compound",
      "ship",
    ]);
    expect(IMPLEMENTATION_TAIL).toEqual(["work", "review", "qa", "compound", "ship"]);
    expect(BRAINSTORM_CHILD_SKILLS).toEqual(["plan", "one-shot"]);
  });

  test("mandatorySuccessors maps lifecycle handoffs", () => {
    expect(mandatorySuccessors("brainstorm")).toEqual(["plan", "one-shot"]);
    expect(mandatorySuccessors("plan")).toEqual(["work"]);
    expect(mandatorySuccessors("work")).toEqual(["review", "compound", "ship"]);
    expect(mandatorySuccessors("review")).toEqual(["compound"]);
    expect(mandatorySuccessors("compound")).toEqual(["ship"]);
    expect(mandatorySuccessors("ship")).toEqual(["postmerge"]);
  });

  test("grok routing instructions include lifecycle and merge-deploy polling", () => {
    const md = routingInstructions("grok");
    expect(md).toContain("Workflow fidelity");
    expect(md).toContain(ONE_SHOT_DONE_MARKER);
    expect(md).toContain("never bypass");
    expect(md).toContain("/brainstorm");
    expect(md).toContain("standalone `plan`");
    expect(md).toContain("AwaitShell");
    expect(md).toContain("/postmerge");
    expect(md).toContain("never ask the operator");
  });

  test("pollInstructions maps Grok to AwaitShell and Claude to Monitor", () => {
    expect(pollInstructions("grok")).toContain("AwaitShell");
    expect(pollInstructions("grok")).toContain("FORBIDDEN");
    expect(pollInstructions("claude")).toContain("Monitor tool");
    expect(pollInstructions("claude")).toContain("postmerge");
  });

  test("one-shot invokeSkill stresses full pipeline on Grok", () => {
    const prev = { ...process.env };
    process.env.GROK_HOME = "/home/user/.grok";
    try {
      const inv = invokeSkill("one-shot", "#6325 implement Phase F");
      expect(inv.tool).toBe("slash_command");
      expect(inv.instruction).toContain(ONE_SHOT_DONE_MARKER);
      expect(inv.instruction).toContain("Steps 0–8");
      expect(inv.instruction).toContain("postmerge");
    } finally {
      Object.assign(process.env, prev);
    }
  });

  test("ship invokeSkill stresses merge-deploy polling on Grok", () => {
    const prev = { ...process.env };
    process.env.GROK_HOME = "/home/user/.grok";
    try {
      const inv = invokeSkill("ship", "");
      expect(inv.instruction).toContain("/postmerge");
      expect(inv.instruction).toContain("Do NOT ask the operator");
    } finally {
      Object.assign(process.env, prev);
    }
  });

  test("brainstorm invokeSkill stresses handoff on Grok", () => {
    const prev = { ...process.env };
    process.env.GROK_HOME = "/home/user/.grok";
    try {
      const inv = invokeSkill("brainstorm", "explore auth redesign");
      expect(inv.tool).toBe("slash_command");
      expect(inv.instruction).toContain("/plan");
      expect(inv.instruction).toContain("Do NOT write product code");
    } finally {
      Object.assign(process.env, prev);
    }
  });

  test("work invokeSkill stresses implementation tail on Grok", () => {
    const prev = { ...process.env };
    process.env.GROK_HOME = "/home/user/.grok";
    try {
      const inv = invokeSkill("work", "knowledge-base/project/plans/2026-07-11-feat-x-plan.md");
      expect(inv.instruction).toContain("/review");
      expect(inv.instruction).toContain("/ship");
      expect(inv.instruction).toContain("merged PR");
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

  test("default golden path dispatches /brainstorm under Grok", () => {
    const input = "explore a new billing model";
    const dispatch = dispatchGoRoute("default", input, grokTestEnv());
    expect(dispatch.kind).toBe("skill");
    if (dispatch.kind === "skill") {
      expect(dispatch.invocation.command).toBe(
        expectedGrokSlashCommand("brainstorm", input),
      );
      expect(dispatch.invocation.instruction).toContain("/plan");
    }
  });
});

describe("workflow-fidelity sentinel markers in skills", () => {
  test("go.md contains post-route eval-gate block with brainstorm", () => {
    const goMd = readFileSync(resolve(PLUGIN_ROOT, "commands/go.md"), "utf-8");
    expect(goMd).toContain(`<!-- workflow-fidelity:block:${GO_POST_ROUTE_SENTINEL}:start -->`);
    expect(goMd).toContain("implement");
    expect(goMd).toContain("brainstorm");
    expect(goMd).toContain("protocol violation");
    expect(goMd).toContain("IMPLEMENTATION_TAIL");
  });

  test("one-shot SKILL.md contains anti-bypass protocol", () => {
    const skill = readFileSync(resolve(PLUGIN_ROOT, "skills/one-shot/SKILL.md"), "utf-8");
    expect(skill).toContain(ONE_SHOT_ANTI_BYPASS_SENTINEL);
    expect(skill).toContain("FORBIDDEN");
    expect(skill).toContain(ONE_SHOT_DONE_MARKER);
    expect(skill).toContain("IMPLEMENTATION_TAIL");
  });

  test("brainstorm SKILL.md contains anti-bypass protocol", () => {
    const skill = readFileSync(resolve(PLUGIN_ROOT, "skills/brainstorm/SKILL.md"), "utf-8");
    expect(skill).toContain(BRAINSTORM_ANTI_BYPASS_SENTINEL);
    expect(skill).toContain("FORBIDDEN");
    expect(skill).toContain("BRAINSTORM_CHILD_SKILLS");
  });

  test("plan SKILL.md contains anti-bypass protocol", () => {
    const skill = readFileSync(resolve(PLUGIN_ROOT, "skills/plan/SKILL.md"), "utf-8");
    expect(skill).toContain(PLAN_ANTI_BYPASS_SENTINEL);
    expect(skill).toContain("/work");
  });

  test("work SKILL.md contains anti-bypass protocol", () => {
    const skill = readFileSync(resolve(PLUGIN_ROOT, "skills/work/SKILL.md"), "utf-8");
    expect(skill).toContain(WORK_ANTI_BYPASS_SENTINEL);
    expect(skill).toContain("IMPLEMENTATION_TAIL");
  });

  test("review and compound SKILL.md contain lifecycle handoff protocol", () => {
    const review = readFileSync(resolve(PLUGIN_ROOT, "skills/review/SKILL.md"), "utf-8");
    const compound = readFileSync(resolve(PLUGIN_ROOT, "skills/compound/SKILL.md"), "utf-8");
    expect(review).toContain(LIFECYCLE_HANDOFF_SENTINEL);
    expect(compound).toContain(LIFECYCLE_HANDOFF_SENTINEL);
  });

  test("ship and postmerge SKILL.md contain merge-deploy harness protocol", () => {
    const ship = readFileSync(resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), "utf-8");
    const postmerge = readFileSync(resolve(PLUGIN_ROOT, "skills/postmerge/SKILL.md"), "utf-8");
    const oneShot = readFileSync(resolve(PLUGIN_ROOT, "skills/one-shot/SKILL.md"), "utf-8");
    expect(ship).toContain(SHIP_MERGE_DEPLOY_SENTINEL);
    expect(ship).toContain("AwaitShell");
    expect(postmerge).toContain(POSTMERGE_HARNESS_SENTINEL);
    expect(oneShot).toContain("postmerge verification complete");
  });

  test("workflowFidelityInstructions mentions slash commands for Grok lifecycle", () => {
    const md = workflowFidelityInstructions("grok");
    expect(md).toContain("/one-shot");
    expect(md).toContain("/brainstorm");
    expect(md).toContain("FORBIDDEN");
    expect(md).toContain("/work");
  });

  test("AGENTS.core.md pins pipeline, lifecycle, and merge-deploy hard rules", () => {
    const core = readFileSync(resolve(PLUGIN_ROOT, "../../AGENTS.core.md"), "utf-8");
    expect(core).toContain("hr-pipeline-skills-never-inline-after-go-route");
    expect(core).toContain("hr-lifecycle-skills-never-inline-after-handoff");
    expect(core).toContain("hr-merge-deploy-monitor-without-asking");
  });
});
import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { readFileSync, mkdtempSync, writeFileSync, rmSync, existsSync } from "fs";
import { spawnSync } from "child_process";
import { resolve, join } from "path";
import { tmpdir } from "os";
import {
  pipelineInvocationSuffix,
  isPipelineSkill,
  isHandoffSkill,
  isOneShotRoute,
  isBrainstormRoute,
  resolveGoSkillRoute,
  ONE_SHOT_DONE_MARKER,
  GO_POST_ROUTE_SENTINEL,
  GROK_PRE_PUSH_GATE_SCRIPT,
  GROK_PRE_PUSH_GATE_SENTINEL,
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
  declaredTransitions,
  isDeclaredTransition,
  DECLARED_TRANSITIONS,
  DECLARED_SUB_STEPS,
  workflowFidelityInstructions,
} from "../lib/workflow-fidelity";
import { invokeSkill, routingInstructions, pollInstructions } from "../lib/harness";
import { dispatchGoRoute, expectedGrokSlashCommand, grokTestEnv } from "../lib/go-routing";

const PLUGIN_ROOT = resolve(import.meta.dir, "..");

/** Snapshot and isolate harness env — CLAUDECODE wins over GROK_* in detectHarness. */
const HARNESS_ENV_KEYS = [
  "CLAUDECODE",
  "GROK_HOME",
  "GROK_AGENT",
  "GROK_DEFAULT_MODEL",
  "GROK_SUBAGENTS",
  "CODEX_THREAD_ID",
] as const;

let savedHarnessEnv: Record<string, string | undefined>;

beforeEach(() => {
  savedHarnessEnv = {};
  for (const key of HARNESS_ENV_KEYS) {
    savedHarnessEnv[key] = process.env[key];
    delete process.env[key];
  }
});

afterEach(() => {
  for (const key of HARNESS_ENV_KEYS) {
    const val = savedHarnessEnv[key];
    if (val === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = val;
    }
  }
});

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
    expect(md).toContain(GROK_PRE_PUSH_GATE_SCRIPT);
    expect(md).toContain("test-all.sh");
  });

  test("pollInstructions maps Grok to AwaitShell and Claude to Monitor", () => {
    expect(pollInstructions("grok")).toContain("AwaitShell");
    expect(pollInstructions("grok")).toContain("FORBIDDEN");
    expect(pollInstructions("claude")).toContain("Monitor tool");
    expect(pollInstructions("claude")).toContain("postmerge");
  });

  test("one-shot invokeSkill stresses full pipeline on Grok", () => {
    process.env.GROK_HOME = "/home/user/.grok";
    const inv = invokeSkill("one-shot", "#6325 implement Phase F");
    expect(inv.tool).toBe("slash_command");
    expect(inv.harness).toBe("grok");
    expect(inv.instruction).toContain(ONE_SHOT_DONE_MARKER);
    expect(inv.instruction).toContain("Steps 0–8");
    expect(inv.instruction).toContain("postmerge");
  });

  test("one-shot invokeSkill is not fooled by leaked CLAUDECODE when GROK_HOME set", () => {
    process.env.CLAUDECODE = "1";
    process.env.GROK_HOME = "/home/user/.grok";
    const inv = invokeSkill("one-shot", "implement");
    // Document current precedence: CLAUDECODE wins — tests must clear it in beforeEach.
    expect(inv.harness).toBe("claude");
    expect(inv.tool).toBe("Skill");
  });

  test("ship invokeSkill stresses merge-deploy polling on Grok", () => {
    process.env.GROK_HOME = "/home/user/.grok";
    const inv = invokeSkill("ship", "");
    expect(inv.instruction).toContain("/postmerge");
    expect(inv.instruction).toContain("Do NOT ask the operator");
  });

  // arch F3 (#8299): the fidelity suffix used to emit the grok slash on EVERY harness, so
  // `invokeSkill("ship")` on Codex said "invoke /postmerge" — the #8299 class emitted by the
  // module ADR-226 names as the renderer. Each harness now receives its own form.
  test("ship invokeSkill on Codex names $soleur:postmerge, never the grok slash", () => {
    process.env.CODEX_THREAD_ID = "thread-1";
    const inv = invokeSkill("ship", "");
    expect(inv.harness).toBe("codex");
    expect(inv.instruction).toContain("$soleur:postmerge");
    expect(inv.instruction).not.toContain("/postmerge");
  });

  // Every branch of pipelineInvocationSuffix, not only `ship`: the first battery's N13 reverted
  // the one-shot branch and the ship-only assertion above survived it.
  test.each(["one-shot", "brainstorm", "plan", "work", "ship", "review", "compound"])(
    "%s invokeSkill on Codex carries no grok slash form of a pipeline skill",
    (skill) => {
      process.env.CODEX_THREAD_ID = "thread-1";
      const inv = invokeSkill(skill, "");
      expect(inv.harness).toBe("codex");
      expect(inv.instruction).not.toMatch(/(^|[^$\w:/])\/(postmerge|ship|plan|one-shot|work|review|qa|compound|brainstorm)\b/);
    },
  );

  test("work invokeSkill on Claude names the canonical tail, never the grok slash", () => {
    process.env.CLAUDECODE = "1";
    const inv = invokeSkill("work", "");
    expect(inv.harness).toBe("claude");
    expect(inv.instruction).toContain("soleur:review → soleur:compound → soleur:ship → soleur:postmerge");
    expect(inv.instruction).not.toContain("/review");
  });

  test("fidelity instructions render the successor chain per harness", () => {
    expect(workflowFidelityInstructions("codex")).toContain("`plan` → `$soleur:work`");
    expect(workflowFidelityInstructions("devin")).toContain("`plan` → `/soleur:work`");
    expect(workflowFidelityInstructions("claude")).toContain("`plan` → `soleur:work`");
    expect(workflowFidelityInstructions("grok")).toContain("`plan` → `/work`");
    expect(workflowFidelityInstructions("codex")).not.toContain("`/postmerge`");
  });

  test("brainstorm invokeSkill stresses handoff on Grok", () => {
    process.env.GROK_HOME = "/home/user/.grok";
    const inv = invokeSkill("brainstorm", "explore auth redesign");
    expect(inv.tool).toBe("slash_command");
    expect(inv.instruction).toContain("/plan");
    expect(inv.instruction).toContain("Do NOT write product code");
  });

  test("work invokeSkill stresses implementation tail on Grok", () => {
    process.env.GROK_HOME = "/home/user/.grok";
    const inv = invokeSkill("work", "knowledge-base/project/plans/2026-07-11-feat-x-plan.md");
    expect(inv.instruction).toContain("/review");
    expect(inv.instruction).toContain("/ship");
    expect(inv.instruction).toContain("merged PR");
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
    // The canonical id, not the grok slash: plugin docs name skills as `soleur:<name>` and the
    // adapter renders the harness form (ADR-226). The old `/work` pin would have survived
    // remediation only because the doc names `work/SKILL.md` inside a path (CTO #6a).
    expect(skill).toContain("soleur:work");
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
    expect(ship).toContain(GROK_PRE_PUSH_GATE_SENTINEL);
    expect(postmerge).toContain(POSTMERGE_HARNESS_SENTINEL);
    expect(oneShot).toContain("postmerge verification complete");
  });

  test("workflowFidelityInstructions mentions slash commands for Grok lifecycle", () => {
    const md = workflowFidelityInstructions("grok");
    expect(md).toContain("/one-shot");
    expect(md).toContain("/brainstorm");
    expect(md).toContain("FORBIDDEN");
    expect(md).toContain("/work");
    expect(md).toContain(GROK_PRE_PUSH_GATE_SCRIPT);
  });

  test("grok-pre-push-gate.sh mirrors CI test aggregator before push", () => {
    const gate = readFileSync(
      resolve(PLUGIN_ROOT, "scripts/grok-pre-push-gate.sh"),
      "utf-8",
    );
    expect(gate).toContain("scripts/test-all.sh");
    expect(gate).toContain("grok-fidelity-gate.sh");
    expect(gate).toContain("readme-counts");
  });

  // Behavioural, not a source grep: run the gate's own `run_step` against a stub step whose
  // exit code we choose. test-all.sh reserves 3 for "zero suites failed, >= 1 suite terminated
  // with a signal-shaped status" — unresolved, not failed — and `run_step` must keep the two
  // apart while stopping the push either way.
  // Temp dirs are tracked and removed rather than leaked: one was created per invocation
  // and never cleaned, and /tmp here is a machine-global tmpfs shared by parallel worktrees.
  const harnessDirs: string[] = [];
  afterEach(() => {
    for (const d of harnessDirs.splice(0)) rmSync(d, { recursive: true, force: true });
  });

  // The harness is written to a FILE and invoked as `bash <file> <gate> <code>` rather than
  // passed via `bash -c`. CodeQL flags the inline-script form (js/shell-command-injection-from-
  // environment, alert 214) because the command string is built next to an absolute path. The
  // path was already in argv rather than interpolated, so this is a shape change, not a
  // behaviour change: $1 and $2 keep exactly the same meaning.
  const runStepWithExit = (code: number) => {
    const dir = mkdtempSync(join(tmpdir(), "grok-pre-push-gate-"));
    harnessDirs.push(dir);
    const harness = join(dir, "harness.sh");
    writeFileSync(
      harness,
      [
        "set -euo pipefail",
        `eval "$(sed -n '/^step() {/,/^}/p;/^run_step() {/,/^}/p' "$1")"`,
        'run_step probe bash -c "exit $2"',
        "",
      ].join("\n"),
    );
    return spawnSync(
      "bash",
      [harness, resolve(PLUGIN_ROOT, "scripts/grok-pre-push-gate.sh"), String(code)],
      { encoding: "utf-8" },
    );
  };

  test("grok-pre-push-gate run_step: exit 3 is UNRESOLVED, other non-zero is FAIL, both stop the push", () => {
    const ok = runStepWithExit(0);
    expect(ok.status).toBe(0);
    expect(ok.stdout).toContain("[ok] probe");

    const unresolved = runStepWithExit(3);
    expect(unresolved.stderr).toContain("[UNRESOLVED] probe");
    expect(unresolved.stderr).not.toContain("[FAIL] probe");
    // toBe(3), not not.toBe(0): the point of the arm is that the gate FORWARDS the
    // class rather than collapsing it. `exit 3` -> `exit 1` survived `not.toBe(0)`.
    expect(unresolved.status).toBe(3);

    for (const code of [1, 2, 143]) {
      const failed = runStepWithExit(code);
      expect(failed.stderr).toContain("[FAIL] probe");
      expect(failed.stderr).not.toContain("[UNRESOLVED]");
      expect(failed.status).not.toBe(0);
    }
  });

  test("grok-fidelity-gate.sh runs AGENTS rule-budget lint when not skipped", () => {
    const gate = readFileSync(
      resolve(PLUGIN_ROOT, "scripts/grok-fidelity-gate.sh"),
      "utf-8",
    );
    expect(gate).toContain("lint-agents-rule-budget.py");
    expect(gate).toContain("GROK_FIDELITY_SKIP_BUDGET");
  });

  test("Grok invokeSkill tells the parent to Read SKILL.md in-process", () => {
    process.env.GROK_HOME = "/home/user/.grok";
    const inv = invokeSkill("brainstorm", "explore");
    expect(inv.harness).toBe("grok");
    expect(inv.instruction).toMatch(/in this process/i);
    expect(inv.instruction).toContain("SKILL.md");
    expect(inv.instruction).not.toMatch(/do not read/i);
  });

  test("Grok workflowFidelityInstructions sanctions in-process Read", () => {
    const md = workflowFidelityInstructions("grok");
    expect(md).toMatch(/in this process/i);
    expect(md).toContain("SKILL.md");
    expect(md).not.toMatch(/not reading SKILL\.md/i);
  });

  test("Claude workflowFidelityInstructions still forbids Read as a Skill-tool substitute", () => {
    const md = workflowFidelityInstructions("claude");
    expect(md).toMatch(/not reading SKILL\.md/i);
  });

  // The parked-deliverable contract reaches the hookless harnesses through THIS
  // channel and no other. An earlier revision shipped it as two exported const
  // arrays with zero importers plus three byte-identical SKILL.md paragraphs, one
  // of which no test read at all — a field the PR adds that nothing consumes.
  // Asserted per harness because grok/codex/devin are the ones with no Stop hook,
  // so for them this string IS the enforcement.
  for (const harness of ["grok", "codex", "devin", "claude"] as const) {
    test(`${harness} instructions carry the parked-deliverable contract`, () => {
      const md = workflowFidelityInstructions(harness);
      expect(md).toMatch(/Parking finished work is not a hand-off/i);
      // The exemptions are the load-bearing half: a rule that only says "never
      // stop" would veto the operator gates the corpus mandates.
      expect(md).toMatch(/in-flight/i);
      expect(md).toMatch(/hr-menu-option-ack-not-prod-write-auth/);
      expect(md).toMatch(/rf-never-skip-qa-review-before-merging/);
    });
  }
});

const IN_PROCESS_READ = /in this process/i;
const ADAPTER_CITE = /harness\.ts|invokeSkill/;
// ADR-226: the preamble carries the general rule, because a skill entered directly on Grok has
// only its preamble in context (spec-flow #1). Pinned here, where the carriers already are.
const CANONICAL_NAME_RULE = /a one-segment `soleur:<name>` in this document names a SKILL/i;
// The carve-out is the load-bearing half: these 12 docs carry 325+ AGENT ids between them
// (review alone has 188), and read literally the earlier skill-only wording told a Grok agent
// to Read `plugins/soleur/skills/engineering:review:security-sentinel/SKILL.md`.
const AGENT_CLAUSE = /names an AGENT: spawn it, never Read it/;
const LOCKED_PIPELINE_SKILLS = [
  "one-shot",
  "brainstorm",
  "drain-labeled-backlog",
  "drain-prs",
  "plan",
  "work",
  "review",
  "qa",
  "compound",
  "ship",
  "postmerge",
  "deepen-plan",
] as const;

describe("Guard 1 — locked skills cite adapter and Grok in-process Read", () => {
  test("walker is not vacuous (locked set is non-empty)", () => {
    expect(LOCKED_PIPELINE_SKILLS.length).toBeGreaterThan(0);
  });

  test.each([...LOCKED_PIPELINE_SKILLS])(
    "%s SKILL.md cites harness.ts or invokeSkill and has an in-process Read sentence",
    (name) => {
      const body = readFileSync(
        resolve(PLUGIN_ROOT, "skills", name, "SKILL.md"),
        "utf-8",
      );
      expect(body).toMatch(ADAPTER_CITE);
      expect(body).toMatch(IN_PROCESS_READ);
      expect(body).toContain("SKILL.md");
      expect(body).toMatch(CANONICAL_NAME_RULE);
      expect(body).toMatch(AGENT_CLAUSE);
    },
  );

  test("one-shot Steps 3-8 dual-voice Grok in-process Read (header-only is vacuous)", () => {
    const body = readFileSync(
      resolve(PLUGIN_ROOT, "skills/one-shot/SKILL.md"),
      "utf-8",
    );
    const start = body.indexOf("**Steps 3-8:");
    const end = body.indexOf("Start with step 0b now.");
    expect(start).toBeGreaterThanOrEqual(0);
    expect(end).toBeGreaterThan(start);
    const steps = body.slice(start, end);
    expect(steps).toMatch(IN_PROCESS_READ);
    expect(steps).toContain("SKILL.md");
    expect(steps).toContain("soleur:work");
    expect(steps).toContain("soleur:review");
    expect(steps).toContain("soleur:ship");
  });

  test("go.md Step 2.1 sanctions Grok in-process Read", () => {
    const goMd = readFileSync(resolve(PLUGIN_ROOT, "commands/go.md"), "utf-8");
    expect(goMd).toMatch(ADAPTER_CITE);
    expect(goMd).toMatch(IN_PROCESS_READ);
  });

  test("go.md live dispatch after Step 2.1 does not nested-slash on Grok", () => {
    // Header-only in-process Read is vacuous if the bullet the parent follows
    // still says "invoke via slash command" (the 2026-09-11 /go failure).
    const goMd = readFileSync(resolve(PLUGIN_ROOT, "commands/go.md"), "utf-8");
    const start = goMd.indexOf("If intent is clear, route without confirmation:");
    expect(start).toBeGreaterThanOrEqual(0);
    const end = goMd.indexOf("Map `soleur:<skill>`", start);
    expect(end).toBeGreaterThan(start);
    const block = goMd.slice(start, end);
    expect(block).toMatch(IN_PROCESS_READ);
    expect(block).toContain("SKILL.md");
    expect(block).not.toMatch(/invoke via \*\*slash command\*\*/i);
  });

  test("go.md Step 1 worktree-continue dual-voices Grok in-process Read", () => {
    const goMd = readFileSync(resolve(PLUGIN_ROOT, "commands/go.md"), "utf-8");
    const start = goMd.indexOf("## Step 1: Worktree Context");
    const end = goMd.indexOf("## Step 2:");
    expect(start).toBeGreaterThanOrEqual(0);
    expect(end).toBeGreaterThan(start);
    const step1 = goMd.slice(start, end);
    expect(step1).toMatch(IN_PROCESS_READ);
    expect(step1).toContain("work/SKILL.md");
    expect(step1).toContain("Skill tool");
  });

  test("go.md plugin-root resolves from the loader token, then GROK_PLUGIN_ROOT, with no CWD default", () => {
    // This test PINNED `ROOT="${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}"` from 2026-09-12 to
    // 2026-09-19 (#8061 -> #8308). The loader substitutes only the exact braced literal
    // `${CLAUDE_PLUGIN_ROOT}` — measured on Claude Code and Grok Build 1.0.34, #7450
    // phase-1-measurement.md §Arm 5 — so that form reached bash verbatim and expanded empty,
    // and all three /soleur:go session gates took their degraded branch while CI stayed green
    // over the literal. A guard that pins the defect is worse than no guard.
    const goMd = readFileSync(resolve(PLUGIN_ROOT, "commands/go.md"), "utf-8");
    // CALL-FORM anchors, not bare tokens. `toContain("GROK_PLUGIN_ROOT")` and
    // `toContain("SOLEUR_PLUGIN_ROOT_RESOLVE")` were both satisfied by this PR's OWN new
    // operator-facing prose ("Read the `SOLEUR_PLUGIN_ROOT_RESOLVE` line…", "`GROK_PLUGIN_ROOT`
    // is set but…"), so deleting all four echo lines and the entire grok-env arm left this test
    // green. The diff created the satisfier and the assertion together —
    // `cq-assert-anchor-not-bare-token`.
    expect(goMd).toContain('ROOT="${CLAUDE_PLUGIN_ROOT}"; SRC=plugin-root-token');
    expect(goMd).toContain('ROOT="$GROK_PLUGIN_ROOT"; SRC=grok-env');
    expect(goMd).toContain('echo "SOLEUR_PLUGIN_ROOT_RESOLVE gate=');
    expect(goMd).toContain("plugin-root-unverified");
    expect(goMd).toContain("grok inspect");
    // A bare `ROOT="${CLAUDE_PLUGIN_ROOT}"` prefix is not enough on its own: an indirection
    // (`XROOT="${CLAUDE_PLUGIN_ROOT}"; ROOT="${GROK_PLUGIN_ROOT:-$XROOT}"`) contains it while
    // functionally reverting the arm order, and dodges both negatives below. Measured green
    // before the call-form anchors above were added.
    expect(goMd).not.toContain(":-$CLAUDE_PLUGIN_ROOT");
    expect(goMd).not.toContain(":-./plugins/soleur");
    expect(goMd).not.toMatch(/ROOT="\$\{GROK_PLUGIN_ROOT:-/);
    const namePin = `grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"'`;
    expect(goMd.split(namePin).length - 1).toBeGreaterThanOrEqual(3);
  });

  test("public getting-started does not overclaim Grok support", () => {
    const page = readFileSync(
      resolve(PLUGIN_ROOT, "docs/pages/getting-started.njk"),
      "utf-8",
    );
    expect(page).not.toMatch(/full Grok support/i);
    expect(page).not.toMatch(/zero configuration/i);
  });

  test("AGENTS.rules.md pins pipeline, lifecycle, and merge-deploy hard rules", () => {
    const core = readFileSync(resolve(PLUGIN_ROOT, "../../AGENTS.rules.md"), "utf-8");
    expect(core).toContain("hr-pipeline-skills-never-inline-after-go-route");
    expect(core).toContain("BEHIND");
    expect(core).toContain("resync main");
    expect(core).not.toContain("hr-lifecycle-skills-never-inline-after-handoff");
    const syncScript = readFileSync(
      resolve(PLUGIN_ROOT, "scripts/sync-pr-behind.sh"),
      "utf-8",
    );
    expect(syncScript).toContain("mergeStateStatus");
  });
});

const SETTINGS_PATH = resolve(PLUGIN_ROOT, "../../.claude/settings.json");
const HOOK_EVENTS = ["PreToolUse", "PostToolUse"] as const;
/** Grok alias table (user-guide 10-hooks.md, CLI 1.0.29, 2026-09-11).
 * Bash already matches run_terminal_command; Write/Edit/MultiEdit already
 * match search_replace; Task already matches spawn_subagent. Duplicate
 * matcher objects for those names double-fire on Grok. */
const ALIASED_GROK_NAMES = [
  "run_terminal_command",
  "search_replace",
  "spawn_subagent",
] as const;
/** Unaliased Grok names that still need exact-name twins. */
const UNALIASED_GROK_NAMES = ["ask_user_question", "write"] as const;

type HookEntry = { matcher?: string; hooks?: { command?: string }[] };

describe("Guard 2 — Skill/Monitor stay; aliased Grok twins are forbidden (measured 2026-09-11)", () => {
  const src = readFileSync(SETTINGS_PATH, "utf-8");
  const settings = JSON.parse(src) as { hooks: Record<string, HookEntry[]> };
  const allMatchers = HOOK_EVENTS.flatMap((e) =>
    (settings.hooks[e] ?? []).map((x) => x.matcher ?? ""),
  );

  test("chokepoint is repo-root .claude/settings.json (not a fixture path)", () => {
    const posix = SETTINGS_PATH.replace(/\\/g, "/");
    expect(posix).not.toMatch(/\/test\/|\/fixtures\//);
    const gitRoot = spawnSync("git", ["rev-parse", "--show-toplevel"], {
      encoding: "utf-8",
      cwd: PLUGIN_ROOT,
    });
    expect(gitRoot.status).toBe(0);
    expect(posix).toBe(
      resolve(gitRoot.stdout.trim(), ".claude/settings.json").replace(/\\/g, "/"),
    );
    expect(Array.isArray(settings.hooks.PreToolUse)).toBe(true);
    expect(settings.hooks.PreToolUse.length).toBeGreaterThan(0);
  });

  test('Skill and Monitor remain as exact matcher tokens (not toContain("S"), not case-folded)', () => {
    expect(src).toContain('"matcher": "Skill"');
    expect(src).toContain('"matcher": "Monitor"');
    expect(allMatchers).toContain("Skill");
    expect(allMatchers).toContain("Monitor");
    expect(allMatchers).not.toContain("skill");
  });

  test("no matcher substring-ORs a Grok exact name (regex-OR is forbidden; split-on-| is not the gate)", () => {
    for (const m of allMatchers) {
      if (!m.includes("|")) continue;
      for (const grokName of [...ALIASED_GROK_NAMES, ...UNALIASED_GROK_NAMES]) {
        expect(m.includes(grokName)).toBe(false);
      }
    }
  });

  test("unaliased Grok names stay as anchored standalone matcher tokens", () => {
    for (const name of UNALIASED_GROK_NAMES) {
      // Regex-EVALUATE each matcher against the Grok wire name — never
      // string-compare. The Devin audit (#8205) anchored these twins
      // (`write` -> `^write$`): identical Grok coverage, but the unanchored
      // form over-bound `todo_write` under Devin, so bare substrings are now
      // forbidden for every matcher that fires on the name.
      // nosemgrep: javascript.lang.security.audit.detect-non-literal-regexp.detect-non-literal-regexp -- allMatchers are repo-controlled config strings, not user input
      const hits = allMatchers.filter((m) => new RegExp(m).test(name));
      expect(hits.length).toBeGreaterThan(0);
      for (const m of hits) {
        // Only the anchored form is acceptable — bare `write` over-binds
        // `todo_write` under Devin (envelope-capture §1, the measured defect).
        expect(m).toBe(`^${name}$`);
      }
    }
  });

  test("aliased Grok names must not appear as standalone matchers (they double-fire)", () => {
    for (const name of ALIASED_GROK_NAMES) {
      expect(allMatchers).not.toContain(name);
    }
  });

  test("Skill and Monitor are not faked as Grok matchers (SOLEUR_HOOK_SKIP reason=no-tool)", () => {
    expect(allMatchers).not.toContain("skill");
    expect(allMatchers).not.toContain("monitor");
    const fidelity = readFileSync(
      resolve(PLUGIN_ROOT, "lib/workflow-fidelity.ts"),
      "utf-8",
    );
    expect(fidelity).toContain("SOLEUR_HOOK_SKIP reason=no-tool");
    expect(fidelity).toContain("SOLEUR_HOOK_SKIP reason=untrusted-session");
  });
});
// ---------------------------------------------------------------------------
// Declared transitions (#8302) — the permitted-edge set, kept SEPARATE from
// mandatorySuccessors().
//
// WHY TWO FUNCTIONS. mandatorySuccessors() is not a transition set: its result
// is rendered into the prompt as "When standalone, invoke next: /X, /Y"
// (workflow-fidelity.ts, workflowFidelityInstructions). Putting a back-edge
// there would instruct the model to re-enter planning after every work run.
// A permitted transition and a mandatory successor are different concepts and
// must not share a function — the `mandatorySuccessors maps lifecycle handoffs`
// test pins the latter with toEqual, so this is enforced rather than merely
// documented. (A content anchor, not a line number: cq-cite-content-anchor.)
// ---------------------------------------------------------------------------
describe("declaredTransitions — permitted edges, including back-edges", () => {
  test("every lifecycle node declares its edge set", () => {
    expect(declaredTransitions("brainstorm")).toEqual(["plan", "one-shot"]);
    expect(declaredTransitions("plan")).toEqual(["work"]);
    expect(declaredTransitions("work")).toEqual(["review", "compound", "ship", "plan"]);
    expect(declaredTransitions("review")).toEqual(["compound", "work"]);
    expect(declaredTransitions("compound")).toEqual(["ship"]);
    expect(declaredTransitions("ship")).toEqual(["postmerge", "work"]);
    expect(declaredTransitions("postmerge")).toEqual(["work"]);
  });

  test("the four operator-approved back-edges are declared", () => {
    expect(isDeclaredTransition("review", "work")).toBe(true);
    expect(isDeclaredTransition("ship", "work")).toBe(true);
    expect(isDeclaredTransition("postmerge", "work")).toBe(true);
    expect(isDeclaredTransition("work", "plan")).toBe(true);
  });

  // The product requirement, asserted as an ABSENCE. plan -> ship is the path
  // that lets an agent skip review entirely, which surfaces only post-merge —
  // the operator-facing loss this work exists to make visible. Nothing else in
  // the suite would notice if it were added.
  test("plan -> ship is NOT declared (skipping review is the defect)", () => {
    expect(isDeclaredTransition("plan", "ship")).toBe(false);
    expect(declaredTransitions("plan")).not.toContain("ship");
  });

  // Declared 2026-09-19 (#8325): seven sessions took this edge, five of them
  // re-entering work -> review -> compound -> ship -> postmerge in full; the
  // recovery path was recorded on the ship node until then.
  test("postmerge -> work is the post-merge verification recovery edge", () => {
    expect(isDeclaredTransition("postmerge", "work")).toBe(true);
    expect(declaredTransitions("postmerge")).toEqual(["work"]);
  });

  // The semantic separation, pinned from the other side: a back-edge must never
  // leak into the collection that renders as prompt text.
  test("mandatorySuccessors stays forward-only and excludes every back-edge", () => {
    expect(mandatorySuccessors("work")).not.toContain("plan");
    expect(mandatorySuccessors("review")).not.toContain("work");
    expect(mandatorySuccessors("ship")).not.toContain("work");
    expect(mandatorySuccessors("postmerge")).not.toContain("work");
  });

  // THE WIRE BETWEEN THE TWO FUNCTIONS. The toEqual pins on mandatorySuccessors
  // and the edge-set pins above are two covered endpoints; nothing above says
  // the successors collection is CONSISTENT with the edge set. Review's escape:
  // `case "plan": return ["work", "ship"]` in mandatorySuccessors renders an
  // instruction to skip review while isDeclaredTransition("plan","ship") stays
  // false and every test above stays green. Successors must be a subset of the
  // declared edges, node by node.
  test("every mandatory successor is a declared transition (successors ⊆ edges)", () => {
    for (const from of Object.keys(DECLARED_TRANSITIONS)) {
      for (const to of mandatorySuccessors(from)) {
        expect(
          isDeclaredTransition(from, to),
          `mandatorySuccessors(${from}) names ${to}, which is not a declared edge`,
        ).toBe(true);
      }
    }
  });

  // `harness` is required (no default — a default silently reproduced the #8299 defect);
  // the back-edge property is harness-agnostic, so grok is pinned here as the literal-slash form.
  test("the rendered directive never names a back-edge", () => {
    // pipelineInvocationSuffix is the emitter of "invoke next:"; the first
    // version of this test negated that string against
    // workflowFidelityInstructions, which never emits it, so the negative was
    // vacuously green (review F8). Positive anchor first, then the negative on
    // the same emitter for the node that carries a back-edge.
    // review and compound take the generic "invoke next:" branch; plan, work
    // and ship carry bespoke prose. Each is anchored on the string it emits.
    expect(pipelineInvocationSuffix("review", "grok")).toContain("invoke next: /compound");
    expect(pipelineInvocationSuffix("review", "grok")).not.toContain("/work");
    expect(pipelineInvocationSuffix("compound", "grok")).toContain("invoke next: /ship");
    expect(pipelineInvocationSuffix("compound", "grok")).not.toContain("/work");
    expect(pipelineInvocationSuffix("work", "grok")).toContain("/review");
    expect(pipelineInvocationSuffix("work", "grok")).not.toContain("/plan");
    expect(pipelineInvocationSuffix("ship", "grok")).toContain("/postmerge");
    expect(pipelineInvocationSuffix("ship", "grok")).not.toContain("/work");
    // postmerge DECLARES `work` as of #8325, and mandatorySuccessors("postmerge")
    // is still empty — which is the whole point of the permitted-vs-mandatory
    // split. These two assert the ABSENCE of the back-edge from rendered prompt
    // text: a legal transition must never render as a directive.
    expect(pipelineInvocationSuffix("postmerge", "grok")).toContain("Phase 7");
    expect(pipelineInvocationSuffix("postmerge", "grok")).not.toContain("/work");
  });

  // Typo guard: every destination must itself be a declared node, so a mistyped
  // edge fails here rather than silently never matching at classification time.
  test("every edge destination is a known node", () => {
    const nodes = Object.keys(DECLARED_TRANSITIONS);
    const extraTerminals = ["one-shot"]; // a route out of the lifecycle, not a node
    for (const [from, tos] of Object.entries(DECLARED_TRANSITIONS)) {
      for (const to of tos) {
        expect(
          nodes.includes(to) || extraTerminals.includes(to),
          `edge ${from} -> ${to}: destination is not a declared node`,
        ).toBe(true);
      }
    }
  });

  test("an unknown node declares no transitions", () => {
    expect(declaredTransitions("not-a-skill")).toEqual([]);
    expect(isDeclaredTransition("not-a-skill", "work")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Derived-view parity (#8302).
//
// DECLARED_TRANSITIONS is canonical and bundled, because the plugin ships as
// ./plugins/soleur and does not carry .claude/ — a runtime read there returns
// nothing on a customer install. But the offline transition classifier is a bash
// script and cannot read a TypeScript const, so it reads a DERIVED JSON view.
// Two copies means drift, so the drift is what gets pinned.
//
// The view lives in its own file rather than as a `transitions` key inside
// .claude/phase-surface-map.json: that file is deep-equal'd against the bundled
// web copy by apps/web-platform/test/phase-surface-map-parity.test.ts, so adding
// a key there would force FSM edges through the web bundle, which has no
// consumer for them.
// ---------------------------------------------------------------------------
describe("declared-transitions derived view parity", () => {
  // Walk up to the marker the precedent (phase-surface-map-parity.test.ts)
  // walks to, rather than a hard-coded `../..` — the precedent's own header
  // calls that shape brittle.
  function findRepoRoot(start: string): string {
    let dir = start;
    for (let i = 0; i < 8; i++) {
      if (existsSync(join(dir, ".claude", "workflow-transitions.json"))) return dir;
      dir = resolve(dir, "..");
    }
    throw new Error("repo root with .claude/workflow-transitions.json not found above " + start);
  }
  const REPO_ROOT = findRepoRoot(PLUGIN_ROOT);
  const VIEW_PATH = join(REPO_ROOT, ".claude", "workflow-transitions.json");

  test("the derived view exists and is valid JSON", () => {
    expect(existsSync(VIEW_PATH)).toBe(true);
    const raw = readFileSync(VIEW_PATH, "utf-8");
    expect(() => JSON.parse(raw)).not.toThrow();
  });

  test("the derived view deep-equals the canonical const", () => {
    const view = JSON.parse(readFileSync(VIEW_PATH, "utf-8")) as Record<string, unknown>;
    delete view._comment;
    // Round-trip the const through JSON so readonly/tuple types normalise to
    // plain arrays for a structural compare.
    const canonical = JSON.parse(
      JSON.stringify({ transitions: DECLARED_TRANSITIONS, sub_steps: DECLARED_SUB_STEPS }),
    );
    expect(view).toEqual(canonical);
  });

  // Direction matters: a view carrying an edge the const does not is just as
  // wrong as one missing an edge, and only an exact compare catches both. A
  // subset assertion would pass on a view that silently permits plan -> ship.
  test("the view declares no edge absent from the const", () => {
    const view = JSON.parse(readFileSync(VIEW_PATH, "utf-8")) as {
      transitions: Record<string, string[]>;
    };
    for (const [from, tos] of Object.entries(view.transitions)) {
      for (const to of tos) {
        expect(
          isDeclaredTransition(from, to),
          `view declares ${from} -> ${to}, which the canonical const does not`,
        ).toBe(true);
      }
    }
  });

  // Same direction check for the sub-step map (#8325): a view collapsing a
  // record the const does not name would silently delete pairs from the
  // classifier's reading.
  test("the view names no sub-step absent from the const", () => {
    const view = JSON.parse(readFileSync(VIEW_PATH, "utf-8")) as {
      sub_steps: Record<string, string[]>;
    };
    for (const [node, subs] of Object.entries(view.sub_steps)) {
      for (const sub of subs) {
        expect(
          (DECLARED_SUB_STEPS[node] ?? []).includes(sub),
          `view names sub-step ${node} : ${sub}, which the canonical const does not`,
        ).toBe(true);
      }
    }
  });

  // Name both key sets outright (#8399): a missing mirror key then fails with a
  // named message rather than inside a deep-equal diff.
  test("the view's sub_steps and transitions key sets are the reviewed ones", () => {
    const view = JSON.parse(readFileSync(VIEW_PATH, "utf-8")) as {
      transitions: Record<string, string[]>;
      sub_steps: Record<string, string[]>;
    };
    expect(Object.keys(view.sub_steps).sort()).toEqual(["brainstorm", "plan", "postmerge", "ship"]);
    expect(Object.keys(view.transitions).sort()).toEqual([
      "brainstorm", "compound", "plan", "postmerge", "review", "ship", "work",
    ]);
  });

  // THE RATCHET'S NODE SET IS THIS SET. scripts/lint-skill-body-budget.py derives
  // "lifecycle skill" from the view's keys and destinations, and refuses a node
  // with no ceiling row and a row with no node. That is enforced in Python at
  // CI time; this pins the same identity from the TS side so the budget file
  // cannot drift from the const between CI runs, and so the ratchet's scope
  // guard does not depend on a job named for a different concern.
  test("skill-body-budget.json ceilings are exactly the lifecycle set (FSM keys ∪ destinations ∪ ONE_SHOT_CHILD_SKILLS)", () => {
    const BUDGET = join(PLUGIN_ROOT, "test", "skill-body-budget.json");
    const budget = JSON.parse(readFileSync(BUDGET, "utf-8")) as { ceilings: Record<string, number> };
    // "Lifecycle skill" is NOT only "FSM node": IMPLEMENTATION_TAIL and
    // ONE_SHOT_CHILD_SKILLS run qa and deepen-plan on every pipeline, and the
    // FSM does not model them. Review measured deepen-plan at 72 KB with no
    // ceiling while the ratchet's node set said the lifecycle was covered.
    const nodes = new Set<string>(Object.keys(DECLARED_TRANSITIONS));
    for (const tos of Object.values(DECLARED_TRANSITIONS)) for (const to of tos) nodes.add(to);
    for (const s of ONE_SHOT_CHILD_SKILLS) nodes.add(s);
    expect(Object.keys(budget.ceilings).sort()).toEqual([...nodes].sort());
  });

});

// ---------------------------------------------------------------------------
// Sub-step map invariants (#8325). DECLARED_SUB_STEPS is consumed by the
// classifier AFTER its node filter and BEFORE pairing, so an entry is only
// meaningful when both sides are lifecycle nodes and the value is not already a
// declared successor of the key (the collapse would delete a declared pair).
// Each test opens with a non-empty check so an emptied const cannot pass as a
// zero-iteration loop.
// ---------------------------------------------------------------------------
describe("DECLARED_SUB_STEPS invariants", () => {
  const nodes = Object.keys(DECLARED_TRANSITIONS);

  // THE SET, not just its members. Every invariant below constrains the SHAPE
  // of an entry; none of them says which entries exist, so a rule-legal
  // addition (e.g. `postmerge: ["plan"]` — key is a node, value is a node, value
  // is not a declared successor of its key) passes all of them while silently
  // deleting every real `postmerge -> plan` pair from the classifier. Adding a
  // sub-step is a semantic claim about a SKILL.md, so it must be made here.
  test("DECLARED_SUB_STEPS is exactly the reviewed set", () => {
    expect(DECLARED_SUB_STEPS).toEqual({
      brainstorm: ["compound"],
      plan: ["compound"],
      postmerge: ["compound"],
      ship: ["compound"],
    });
  });

  // A sub-step entry is a claim about a SKILL.md: the key's own run invokes the
  // value. Pin that claim to the section that makes it, so moving or deleting
  // the call fails here instead of silently collapsing real pairs (#8399).
  // Section-scoped, not file-wide: ship names `skill: soleur:compound` in
  // Headless Mode Detection too, which would survive deleting Phase 2.
  // `brainstorm` is scoped by its H3 `### Phase 4: Handoff`: an H2 scope would
  // stop at the `## Domain Assessments` line that sits inside a fenced markdown
  // template earlier in that file. LIMITS (accepted, #8399 review): the match is
  // textual, so a sentence that merely MENTIONS the call ("do not run `skill:
  // soleur:compound`") satisfies it, and one surviving call in a section with
  // several (ship Phase 2 has three) keeps it green. It proves the designed call
  // is named where the entry says, not that it is the only or an unconditional
  // one, and it cannot see a designed call the map does not list.
  test("every sub-step is invoked by its key's SKILL.md in the section that owns it", () => {
    const SECTION: Record<string, string> = {
      brainstorm: "### Phase 4: Handoff",
      plan: "## Exit Gate",
      postmerge: "## Phase 6: Update Issue and Compound",
      ship: "## Phase 2: Capture Learnings",
    };
    let checks = 0;
    for (const [node, subs] of Object.entries(DECLARED_SUB_STEPS)) {
      expect(node in SECTION, `sub_steps key ${node} has no SKILL.md anchor section in this test`).toBe(true);
      const text = readFileSync(join(PLUGIN_ROOT, "skills", node, "SKILL.md"), "utf-8");
      const heading = SECTION[node];
      const lines = text.split("\n");
      const start = lines.findIndex((l) => l.startsWith(heading));
      expect(start, `${node}/SKILL.md has no section starting "${heading}"`).toBeGreaterThanOrEqual(0);
      const rest = lines.slice(start + 1);
      const end = rest.findIndex((l) => l.startsWith("## "));
      const scope = (end === -1 ? rest : rest.slice(0, end)).join("\n");
      for (const sub of subs) {
        expect(
          new RegExp(`skill: soleur:${sub}(?![\\w-])`).test(scope),
          `${node}/SKILL.md ${heading} does not invoke \`skill: soleur:${sub}\``,
        ).toBe(true);
        checks++;
      }
    }
    expect(checks).toBeGreaterThan(0);
    expect(checks).toBe(Object.values(DECLARED_SUB_STEPS).flat().length);
  });

  // Same gap one level up: the edge set's members are each pinned by toEqual,
  // but nothing pinned which KEYS exist, so a mirrored `qa: ["ship"]` entered
  // fully green (the budget-ceiling test only catches a name that is not
  // already a ceiling row).
  test("DECLARED_TRANSITIONS is exactly the seven lifecycle nodes", () => {
    expect(Object.keys(DECLARED_TRANSITIONS).sort()).toEqual([
      "brainstorm", "compound", "plan", "postmerge", "review", "ship", "work",
    ]);
  });

  test("every sub_steps key is a lifecycle node", () => {
    expect(Object.keys(DECLARED_SUB_STEPS).length).toBeGreaterThan(0);
    for (const node of Object.keys(DECLARED_SUB_STEPS)) {
      expect(nodes.includes(node), `sub_steps key ${node} is not a lifecycle node`).toBe(true);
    }
  });

  test("every sub_steps value is a lifecycle node — a non-node is removed by the classifier before the collapse, so the entry would be dead", () => {
    // Guard the collection this test actually LOOPS over: a key-count check
    // leaves `{brainstorm: []}` as a zero-iteration quantifier.
    expect(Object.values(DECLARED_SUB_STEPS).flat().length).toBeGreaterThan(0);
    for (const [node, subs] of Object.entries(DECLARED_SUB_STEPS)) {
      for (const sub of subs) {
        expect(nodes.includes(sub), `sub_steps ${node} : ${sub} is not a lifecycle node`).toBe(true);
      }
    }
  });

  test("a sub_steps value is not a declared successor of its key — the collapse would delete a declared pair", () => {
    expect(Object.values(DECLARED_SUB_STEPS).flat().length).toBeGreaterThan(0);
    for (const [node, subs] of Object.entries(DECLARED_SUB_STEPS)) {
      for (const sub of subs) {
        expect(
          isDeclaredTransition(node, sub),
          `sub_steps ${node} : ${sub} is also a declared edge ${node} -> ${sub}`,
        ).toBe(false);
      }
    }
  });
});

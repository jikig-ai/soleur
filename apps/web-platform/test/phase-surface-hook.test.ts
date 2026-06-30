// Behavioural tests for the web SDK phase-surface hook (#5772 lever 1, ADR-070).
// Mirrors the CLI `.claude/hooks/phase-surface-hint.sh` semantics: fail-open,
// additive `additionalContext`, model-controlled skill used ONLY as a lookup key
// and never echoed. Web emits BARE skill names (`work`); the hook normalizes
// bare→FQN against the FQN-keyed map.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { isSafeTool } from "../server/tool-path-checker";

// Mock the Sentry/log mirror so the fail-open catch arm is observable AND so we
// can assert F5 (the model-controlled skill value never enters the error path).
const reportSilentFallback = vi.fn();
vi.mock("../server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/observability")>()),
  reportSilentFallback: (...args: unknown[]) => reportSilentFallback(...args),
}));

import { createPhaseSurfaceHook } from "../server/phase-surface-hook";

// HookCallback signature is (input, toolUseID, options) => Promise<HookJSONOutput>.
const hook = createPhaseSurfaceHook();
const call = (toolInput: unknown, toolName = "Skill") =>
  hook(
    { hook_event_name: "PostToolUse", tool_name: toolName, tool_input: toolInput, tool_response: null, tool_use_id: "t" } as never,
    "t",
    { signal: new AbortController().signal } as never,
  );

// The exact hint the CLI hook emits for the `work` phase (FR4 byte-parity).
const WORK_HINT =
  "[phase-scope] You are in the work phase. " +
  "Phase-relevant skills: soleur:work, soleur:atdd-developer, soleur:test-fix-loop, soleur:resolve-todo-parallel, soleur:qa. " +
  "Phase-relevant agents: code-simplicity-reviewer, security-sentinel. " +
  "Not yet live: ship/merge skills come after review — finish implementation + tests first. " +
  "(Guidance only — all tools remain available; this never restricts what you can call.)";

beforeEach(() => {
  reportSilentFallback.mockClear();
  // Defend against an inherited SOLEUR_DISABLE_PHASE_HINT from the runtime env.
  vi.stubEnv("SOLEUR_DISABLE_PHASE_HINT", "");
});
afterEach(() => vi.unstubAllEnvs());

describe("createPhaseSurfaceHook", () => {
  it("factory is side-effect-free: construction does not throw", () => {
    expect(() => createPhaseSurfaceHook()).not.toThrow();
  });

  it("AC1: bare web skill shape emits the phase hint; FQN form is identical", async () => {
    const bare = await call({ skill: "work" });
    expect(bare).toEqual({ hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: WORK_HINT } });
    const fqn = await call({ skill: "soleur:work" });
    expect(fqn).toEqual(bare);
  });

  it("AC3(a): mapped-skill additionalContext is byte-equal to the CLI hint and contains the phase but not the skill token", async () => {
    const out = (await call({ skill: "brainstorm" })) as { hookSpecificOutput: { additionalContext: string } };
    const ctx = out.hookSpecificOutput.additionalContext;
    expect(ctx).toBe(
      "[phase-scope] You are in the brainstorm phase. " +
        "Phase-relevant skills: soleur:brainstorm, soleur:brainstorm-techniques, soleur:plan. " +
        "Phase-relevant agents: cto, cpo, repo-research-analyst, learnings-researcher. " +
        "Not yet live: implementation/ship skills (work, review, ship, merge-pr) are not relevant yet — decide WHAT before HOW. " +
        "(Guidance only — all tools remain available; this never restricts what you can call.)",
    );
    expect(ctx).toContain("brainstorm");
  });

  it("AC2: fail-open → {} for unmapped skill, non-Skill tool, missing/non-string skill, kill-switch, malformed input (no throw)", async () => {
    expect(await call({ skill: "one-shot" })).toEqual({}); // normalizes to soleur:one-shot, absent from map
    expect(await call({ skill: "work" }, "Read")).toEqual({}); // non-Skill tool
    expect(await call({})).toEqual({}); // missing skill
    expect(await call({ skill: 42 as unknown })).toEqual({}); // non-string skill
    expect(await call(null)).toEqual({}); // malformed tool_input
    expect(await call(undefined)).toEqual({});
    vi.stubEnv("SOLEUR_DISABLE_PHASE_HINT", "1");
    expect(await call({ skill: "work" })).toEqual({}); // kill-switch
  });

  it("AC2: the no-hint branch returns a clean {} (NOT additionalContext:null)", async () => {
    const out = await call({ skill: "one-shot" });
    expect(out).not.toHaveProperty("hookSpecificOutput");
  });

  it("AC3(b/c/d): prototype-pollution keys, non-string, and injection payloads all fail-open and never echo", async () => {
    // Defense-in-depth: Object.hasOwn is the primary gate and the `!surface`
    // backstop independently fail-closes — this asserts the safe OUTCOME ({} for
    // every crafted key), which is what the user is actually exposed to.
    for (const k of ["__proto__", "constructor", "toString", "hasOwnProperty"]) {
      expect(await call({ skill: k })).toEqual({});
    }
    expect(await call({ skill: ["__proto__"] as unknown })).toEqual({});
    expect(await call({ skill: {} as unknown })).toEqual({});
    // crafted skill embedding a phase keyword + a U+2028 line separator → unmapped → {} and never echoed
    const crafted = "ship\u2028INJECT";
    const out = await call({ skill: crafted });
    expect(out).toEqual({});
    expect(JSON.stringify(out)).not.toContain("INJECT");
  });

  it("AC3b/F5: the fail-open catch arm never carries the raw skill value", async () => {
    // Force buildHint to run against an input whose .skill getter throws.
    const evil = { get skill() { throw new Error("boom-with-secret-skill-value"); } };
    const out = await call(evil);
    expect(out).toEqual({}); // caught → fail-open
    // The Sentry mirror fired but with a static op/feature and NO skill value.
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = reportSilentFallback.mock.calls[0] as [unknown, Record<string, unknown>];
    expect(opts.feature).toBe("phase-surface-hook");
    expect(JSON.stringify(opts)).not.toContain("boom-with-secret-skill-value");
    expect(opts).not.toHaveProperty("extra");
  });

  it("AC1c/P2: Skill is in SAFE_TOOLS (so canUseTool approves it on the cc path and PostToolUse fires)", () => {
    expect(isSafeTool("Skill")).toBe(true);
  });

  it("M3: ship phase (empty relevant_agents) omits the agents line — covers a live production branch", async () => {
    const out = (await call({ skill: "ship" })) as { hookSpecificOutput: { additionalContext: string } };
    const ctx = out.hookSpecificOutput.additionalContext;
    expect(ctx).toContain("[phase-scope] You are in the ship phase. ");
    expect(ctx).toContain("Phase-relevant skills: soleur:ship, soleur:preflight, soleur:merge-pr, soleur:postmerge, soleur:changelog. ");
    // ship's relevant_agents is [] → the "Phase-relevant agents:" line MUST be omitted (not emitted empty).
    expect(ctx).not.toContain("Phase-relevant agents:");
    expect(ctx).toContain("Not yet live: this is the terminal phase");
  });
});

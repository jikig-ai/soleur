import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { detectHarness } from "../lib/harness";
import {
  resolveAdvisorFallback,
  resolveAdvisorTier,
  resolveModelTier,
  SEMANTIC_TIERS,
  TIER_MAPS,
  type SemanticTier,
} from "../lib/harness-model-map";
import { PLUGIN_ROOT } from "./helpers";

const SKILLS_DIR = resolve(PLUGIN_ROOT, "skills");

const PINNED_WORKFLOWS = [
  "review/workflows/review.workflow.js",
  "plan-review/workflows/plan-review.workflow.js",
  "deepen-plan/workflows/deepen-plan.workflow.js",
  "resolve-parallel/workflows/resolve-parallel.workflow.js",
  "resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js",
  "resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js",
  "drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js",
] as const;

const MAP_FENCE_START = "<!-- harness-model-map:start -->";
const MAP_FENCE_END = "<!-- harness-model-map:end -->";

function env(overrides: Record<string, string | undefined>): NodeJS.ProcessEnv {
  const base: NodeJS.ProcessEnv = {};
  for (const [key, val] of Object.entries(overrides)) {
    if (val !== undefined) base[key] = val;
  }
  return base;
}

let savedWarn: typeof console.warn;

beforeEach(() => {
  savedWarn = console.warn;
});

afterEach(() => {
  console.warn = savedWarn;
});

describe("harness-model-map (ADR-110)", () => {
  test("semantic tier set is cheap|standard|strong|advisor|inherit", () => {
    expect([...SEMANTIC_TIERS].sort()).toEqual(
      ["advisor", "cheap", "inherit", "standard", "strong"].sort(),
    );
  });

  test("claude fixture map: cheap→haiku, standard→sonnet, strong→opus, advisor→fable, inherit→inherit", () => {
    expect(resolveModelTier("cheap", "claude")).toBe("haiku");
    expect(resolveModelTier("standard", "claude")).toBe("sonnet");
    expect(resolveModelTier("strong", "claude")).toBe("opus");
    expect(resolveModelTier("advisor", "claude")).toBe("fable");
    expect(resolveModelTier("inherit", "claude")).toBe("inherit");
  });

  test("grok fixture map uses live CLI spawn slugs (grok models 1.0.29: grok-4.6, grok-4.5)", () => {
    // cheap is grok-4.5 — the only non-default slug `grok models` lists.
    // grok-build-0.1 is an xAI API SKU (docs.x.ai Text API) but is NOT a
    // Grok Build CLI spawn slug as of 1.0.29; do not pin it here.
    expect(resolveModelTier("cheap", "grok")).toBe("grok-4.5");
    expect(resolveModelTier("standard", "grok")).toBe("grok-4.6");
    expect(resolveModelTier("strong", "grok")).toBe("grok-4.6");
    expect(resolveModelTier("advisor", "grok")).toBe("grok-4.6");
    expect(resolveModelTier("inherit", "grok")).toBe("inherit");
    expect(TIER_MAPS.grok.cheap).not.toBe("grok-build-0.1");
  });

  test("every non-inherit tier resolves to a non-empty value for claude and grok", () => {
    for (const harness of ["claude", "grok"] as const) {
      for (const tier of SEMANTIC_TIERS) {
        const value = resolveModelTier(tier, harness);
        expect(value.length).toBeGreaterThan(0);
      }
    }
  });

  test("unknown tier throws", () => {
    expect(() => resolveModelTier("opus" as SemanticTier, "claude")).toThrow(
      /unknown semantic tier/i,
    );
    expect(() => resolveModelTier("sonnet" as SemanticTier, "grok")).toThrow(
      /unknown semantic tier/i,
    );
  });

  test("unknown harness: inherit passes through; non-inherit warns and returns inherit", () => {
    const warnings: string[] = [];
    console.warn = (...args: unknown[]) => {
      warnings.push(args.map(String).join(" "));
    };
    expect(resolveModelTier("inherit", "unknown")).toBe("inherit");
    expect(warnings).toEqual([]);
    expect(resolveModelTier("standard", "unknown")).toBe("inherit");
    expect(warnings.some((w) => /unknown harness/i.test(w))).toBe(true);
  });

  test("reuses detectHarness() — GROK_SESSION is not a grok marker", () => {
    expect(detectHarness(env({ GROK_SESSION: "1" }))).toBe("unknown");
    expect(detectHarness(env({ GROK_HOME: "/home/user/.grok" }))).toBe("grok");
    expect(detectHarness(env({ CLAUDECODE: "1" }))).toBe("claude");
    expect(
      resolveModelTier("standard", detectHarness(env({ GROK_SESSION: "1" }))),
    ).toBe("inherit");
    expect(
      resolveModelTier("cheap", detectHarness(env({ GROK_HOME: "/tmp/.grok" }))),
    ).toBe("grok-4.5");
  });

  test("resolveAdvisorTier is fable on Claude and strong-map on Grok; fallback is strong", () => {
    expect(resolveAdvisorTier("claude")).toBe("fable");
    expect(resolveAdvisorFallback("claude")).toBe("opus");
    expect(resolveAdvisorTier("grok")).toBe("grok-4.6");
    expect(resolveAdvisorFallback("grok")).toBe("grok-4.6");
  });

  test("TIER_MAPS is the exported fixture (one file to bump per vendor generation)", () => {
    expect(TIER_MAPS.claude.cheap).toBe("haiku");
    expect(TIER_MAPS.claude.standard).toBe("sonnet");
    expect(TIER_MAPS.grok.standard).toBe("grok-4.6");
  });
});

describe("workflow inline resolver is a copy of TIER_MAPS (no import in workflow runtime)", () => {
  function extractFence(src: string): string {
    const start = src.indexOf(MAP_FENCE_START);
    const end = src.indexOf(MAP_FENCE_END);
    expect(start).toBeGreaterThanOrEqual(0);
    expect(end).toBeGreaterThan(start);
    return src.slice(start, end + MAP_FENCE_END.length);
  }

  test("every pinned workflow inlines the same resolver fence", () => {
    const fences = PINNED_WORKFLOWS.map((rel) =>
      extractFence(readFileSync(join(SKILLS_DIR, rel), "utf-8")),
    );
    for (const fence of fences.slice(1)) {
      expect(fence).toBe(fences[0]);
    }
  });

  test("inlined maps match TIER_MAPS (claude + grok SKUs)", () => {
    const fence = extractFence(
      readFileSync(join(SKILLS_DIR, PINNED_WORKFLOWS[0]), "utf-8"),
    );
    expect(fence).toContain(`cheap: '${TIER_MAPS.claude.cheap}'`);
    expect(fence).toContain(`standard: '${TIER_MAPS.claude.standard}'`);
    expect(fence).toContain(`strong: '${TIER_MAPS.claude.strong}'`);
    expect(fence).toContain(`advisor: '${TIER_MAPS.claude.advisor}'`);
    expect(fence).toContain(`cheap: '${TIER_MAPS.grok.cheap}'`);
    expect(fence).toContain(`standard: '${TIER_MAPS.grok.standard}'`);
    expect(fence).not.toMatch(/\bmodel\s*:/);
  });

  test("agent-native-audit workflow has no resolver fence (zero-pin exemption)", () => {
    const rel = "agent-native-audit/workflows/agent-native-audit.workflow.js";
    expect(existsSync(join(SKILLS_DIR, rel))).toBe(true);
    const src = readFileSync(join(SKILLS_DIR, rel), "utf-8");
    expect(src).not.toContain(MAP_FENCE_START);
  });

  test("workflow discovery still finds the seven pin files", () => {
    const found: string[] = [];
    for (const skill of readdirSync(SKILLS_DIR)) {
      const wfDir = join(SKILLS_DIR, skill, "workflows");
      if (!existsSync(wfDir)) continue;
      for (const f of readdirSync(wfDir)) {
        if (f.endsWith(".workflow.js")) found.push(`${skill}/workflows/${f}`);
      }
    }
    for (const rel of PINNED_WORKFLOWS) {
      expect(found).toContain(rel);
    }
  });
});

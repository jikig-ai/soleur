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

  test("grok fixture map uses live CLI spawn slugs", () => {
    // cheap ≠ grok-build-0.1 (API SKU, not a CLI slug). Rationale: ADR-110 addendum 2026-09-23.
    expect(resolveModelTier("cheap", "grok")).toBe("grok-4.5");
    expect(resolveModelTier("standard", "grok")).toBe("grok-4.7");
    expect(resolveModelTier("strong", "grok")).toBe("grok-4.7");
    expect(resolveModelTier("advisor", "grok")).toBe("grok-4.7");
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
    expect(warnings.some((w) => /unmapped harness unknown/i.test(w))).toBe(true);
  });

  test("codex (and any harness not in TIER_MAPS) inherits instead of throwing", () => {
    const warnings: string[] = [];
    console.warn = (...args: unknown[]) => {
      warnings.push(args.map(String).join(" "));
    };
    expect(resolveModelTier("inherit", "codex")).toBe("inherit");
    expect(warnings).toEqual([]);
    expect(resolveModelTier("standard", "codex")).toBe("inherit");
    expect(warnings.some((w) => /unmapped harness codex/i.test(w))).toBe(true);
    expect(
      resolveModelTier("cheap", detectHarness(env({ CODEX_THREAD_ID: "thread-1" }))),
    ).toBe("inherit");
    expect(() =>
      resolveModelTier("standard", detectHarness(env({ CODEX_THREAD_ID: "t" }))),
    ).not.toThrow();
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
    expect(resolveAdvisorTier("grok")).toBe("grok-4.7");
    expect(resolveAdvisorFallback("grok")).toBe("grok-4.7");
  });

  test("TIER_MAPS is the exported fixture (one file to bump per vendor generation)", () => {
    expect(TIER_MAPS.claude.cheap).toBe("haiku");
    expect(TIER_MAPS.claude.standard).toBe("sonnet");
    expect(TIER_MAPS.grok.standard).toBe("grok-4.7");
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
    const litRe =
      /\{ cheap: '([^']+)', standard: '([^']+)', strong: '([^']+)', advisor: '([^']+)', inherit: '([^']+)' \}/g;
    const lits = [...fence.matchAll(litRe)];
    expect(lits.length).toBe(3);
    const toMap = (m: RegExpMatchArray) => ({
      cheap: m[1],
      standard: m[2],
      strong: m[3],
      advisor: m[4],
      inherit: m[5],
    });
    expect(toMap(lits[0])).toEqual({ ...TIER_MAPS.grok });
    expect(toMap(lits[1])).toEqual({ ...TIER_MAPS.claude });
    expect(toMap(lits[2])).toEqual({
      cheap: "inherit",
      standard: "inherit",
      strong: "inherit",
      advisor: "inherit",
      inherit: "inherit",
    });
    expect(fence).not.toMatch(/\bmodel\s*:/);
  });

  test("agent-native-audit workflow has no resolver fence (zero-pin exemption)", () => {
    const rel = "agent-native-audit/workflows/agent-native-audit.workflow.js";
    expect(existsSync(join(SKILLS_DIR, rel))).toBe(true);
    const src = readFileSync(join(SKILLS_DIR, rel), "utf-8");
    expect(src).not.toContain(MAP_FENCE_START);
  });

  test("the set of fenced workflows equals PINNED_WORKFLOWS (no unlisted or dropped fence)", () => {
    // Membership, not presence: a new workflow carrying a stale fence, or a
    // PINNED_WORKFLOWS entry removed while its fence stays, must red.
    const fenced: string[] = [];
    let scanned = 0;
    for (const skill of readdirSync(SKILLS_DIR)) {
      const wfDir = join(SKILLS_DIR, skill, "workflows");
      if (!existsSync(wfDir)) continue;
      for (const f of readdirSync(wfDir)) {
        if (!f.endsWith(".workflow.js")) continue;
        scanned++;
        const rel = `${skill}/workflows/${f}`;
        if (readFileSync(join(SKILLS_DIR, rel), "utf-8").includes(MAP_FENCE_START)) {
          fenced.push(rel);
        }
      }
    }
    expect(scanned).toBeGreaterThan(PINNED_WORKFLOWS.length); // exemptions exist (agent-native-audit)
    expect(fenced.sort()).toEqual([...PINNED_WORKFLOWS].sort());
  });

  test("the inlined fence EXECUTES like resolveModelTier(detectHarness(env)) and rewrites opts.model", () => {
    // The fence re-implements harness detection and wraps the host `agent`;
    // text equality cannot see an inverted map choice, a dropped marker, or a
    // disabled wrapper. Run it.
    console.warn = () => {};
    const envCases: Array<Record<string, string>> = [
      {},
      { CLAUDECODE: "1" },
      { GROK_HOME: "/h/.grok" },
      { GROK_AGENT: "1" },
      { GROK_DEFAULT_MODEL: "grok-4.7" },
      { GROK_SUBAGENTS: "1" },
      { CLAUDECODE: "1", GROK_HOME: "/h/.grok" },
      { CODEX_THREAD_ID: "t" },
      { GROK_HOME: "/h/.grok", CODEX_THREAD_ID: "t" },
      // Devin markers (harness.ts DEVIN_ENV_MARKERS): no Devin map exists, so
      // both paths must inherit. The fence has no argv/title fallback — env only.
      { DEVIN: "1" },
      { DEVIN_HOME: "/h/.devin" },
    ];
    let checked = 0;
    for (const rel of PINNED_WORKFLOWS) {
      const src = readFileSync(join(SKILLS_DIR, rel), "utf-8");
      const start = src.indexOf(MAP_FENCE_START);
      const end = src.indexOf(MAP_FENCE_END);
      const body = src.slice(src.lastIndexOf("\n", start) + 1, end);
      for (const e of envCases) {
        const seen: unknown[] = [];
        const host = (_p: unknown, opts: { model?: string }) => {
          seen.push(opts?.model);
          return null;
        };
        const load = new Function(
          "process",
          "agent",
          `${body}\nreturn { resolveWorkflowModel, agent };`,
        ) as (proc: unknown, a: unknown) => {
          resolveWorkflowModel: (t: string) => string;
          agent: (p: unknown, o: { model?: string }) => unknown;
        };
        const fence = load({ env: { ...e } }, host);
        const harness = detectHarness(env(e));
        for (const tier of SEMANTIC_TIERS) {
          const want = resolveModelTier(tier, harness);
          expect(fence.resolveWorkflowModel(tier), `${rel} ${JSON.stringify(e)} ${tier}`).toBe(want);
          fence.agent("p", { model: tier });
          expect(seen.at(-1), `${rel} wrapper ${JSON.stringify(e)} ${tier}`).toBe(want);
        }
        // The wrapper must pass through calls that carry no model — real call
        // sites (review.workflow.js classify/file) omit it; resolving
        // `undefined` would throw "unknown semantic tier" in production.
        fence.agent("p", { label: "x" } as { model?: string });
        expect(seen.at(-1), `${rel} wrapper no-model ${JSON.stringify(e)}`).toBeUndefined();
        expect(() => fence.agent("p", undefined as unknown as { model?: string })).not.toThrow();
      }
    }
  });

  test("every model: literal in a pinned workflow is a semantic tier, never a vendor SKU", () => {
    const tiers = new Set<string>(SEMANTIC_TIERS);
    let literals = 0;
    for (const rel of PINNED_WORKFLOWS) {
      const src = readFileSync(join(SKILLS_DIR, rel), "utf-8");
      const outside =
        src.slice(0, src.indexOf(MAP_FENCE_START)) +
        src.slice(src.indexOf(MAP_FENCE_END) + MAP_FENCE_END.length);
      for (const m of outside.matchAll(/\bmodel:\s*'([^']+)'/g)) {
        literals++;
        expect(tiers.has(m[1]), `${rel}: model '${m[1]}' is not a semantic tier`).toBe(true);
      }
    }
    expect(literals).toBeGreaterThan(0);
  });
});

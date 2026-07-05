import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { computeNamedPanel, NAMED_LENSES } from "../skills/plan-review/lib/named-panel.mjs";

// ---------------------------------------------------------------------------
// Named CEO/design/devex panel composition (ADR-084 / #5985).
//
// Deterministic, NO live agents (AC11/AC12): the panel-composition decision is a
// pure function of the detect step's INDEPENDENT relevance signals. These tests
// prove the gate does not trust the plan's own `## Domain Review` verdict, and
// that a broken registry/gate for ANY single lens fails CI.
// ---------------------------------------------------------------------------

const PLUGIN_ROOT = resolve(import.meta.dir, "..");
const WORKFLOW = resolve(
  PLUGIN_ROOT,
  "skills/plan-review/workflows/plan-review.workflow.js",
);

describe("plan-review named panel composition (pure, no live agents)", () => {
  // AC11 — INDEPENDENT activation: a plan whose Domain Review verdict says
  // Product: NONE but whose Files-to-Edit contains a components/**/*.tsx path
  // STILL activates ux-design-lead + cpo. The verdict does not suppress the
  // mechanical UI-surface hit (CPO Condition 1 — correlated-failure fix).
  test("AC11: UI-surface hit overrides a `Product: NONE` verdict → ux + cpo", () => {
    const panel = computeNamedPanel({
      uiSurfaceHit: true, // Files-to-Edit has components/**/*.tsx
      // Fresh signals all false, mimicking a plan whose verdict said NONE:
      productSignal: false,
      marketingSignal: false,
      uxSignal: false,
      devexSignal: false,
    });
    expect(panel).toContain("ux-design-lead");
    expect(panel).toContain("cpo");
  });

  // AC11 — a pure plugin-tooling fixture activates ONLY cto (the worked
  // example for THIS plan: plugin-tooling Files-to-Edit, no UI surface).
  test("AC11: pure plugin-tooling plan → only cto", () => {
    const panel = computeNamedPanel({
      uiSurfaceHit: false,
      productSignal: false,
      marketingSignal: false,
      uxSignal: false,
      devexSignal: true,
    });
    expect(panel).toEqual(["cto"]);
  });

  // AC12 — anti-rot: each of the four named lenses is activated by at least one
  // fixture, so a broken registry entry or gate for any single lens fails CI.
  test("AC12: each named lens (cpo, cmo, cto, ux-design-lead) activates ≥1×", () => {
    const activatedAcrossFixtures = new Set<string>();
    const fixtures = [
      { uiSurfaceHit: true }, // → ux-design-lead + cpo
      { marketingSignal: true }, // → cmo
      { devexSignal: true }, // → cto
      { productSignal: true }, // → cpo
      { uxSignal: true }, // → ux-design-lead
    ];
    for (const f of fixtures) {
      for (const lens of computeNamedPanel(f)) activatedAcrossFixtures.add(lens);
    }
    for (const lens of NAMED_LENSES) {
      expect(
        activatedAcrossFixtures.has(lens),
        `named lens "${lens}" was never activated across the fixtures — its registry entry or gate is broken.`,
      ).toBe(true);
    }
  });

  test("no signals → empty named panel (eng panel still runs)", () => {
    expect(computeNamedPanel({})).toEqual([]);
    expect(computeNamedPanel(undefined)).toEqual([]);
  });

  test("output is stable-ordered and deduped (uiSurfaceHit + productSignal both → cpo once)", () => {
    const panel = computeNamedPanel({ uiSurfaceHit: true, productSignal: true });
    expect(panel).toEqual(["cpo", "ux-design-lead"]);
  });
});

describe("plan-review workflow keeps the named panel wired (drift guard)", () => {
  const src = readFileSync(WORKFLOW, "utf-8");
  const LIB = resolve(PLUGIN_ROOT, "skills/plan-review/lib/named-panel.mjs");
  const libSrc = readFileSync(LIB, "utf-8");

  // Extract `NAMED_LENSES = [...]` + `function computeNamedPanel(...)` from a
  // source file and normalize away comments, the `export` keyword, and
  // whitespace — so the ONLY thing this compares is the activation logic. The
  // Workflow runtime cannot import, so the workflow inlines a duplicate of the
  // lib's decision function (self-contained convention). The lib copy is what
  // the AC11/AC12 unit tests above exercise; the workflow copy is what actually
  // runs. This guard fails if the two logic bodies diverge — the copy that runs
  // must stay behaviorally identical to the copy that is tested.
  const extractLogic = (source: string): string => {
    const lenses = source.match(/NAMED_LENSES\s*=\s*\[[^\]]*\]/);
    const fn = source.match(/function computeNamedPanel\(signals\)\s*\{[\s\S]*?\n\}/);
    if (!lenses || !fn) return "";
    const norm = (s: string) =>
      s
        .replace(/\/\/[^\n]*\n/g, "\n") // strip line comments
        .replace(/\s+/g, " ")
        .trim();
    return `${norm(lenses[0])} || ${norm(fn[0])}`;
  };

  test("workflow carries the computeNamedPanel duplicate", () => {
    expect(src).toContain("function computeNamedPanel(");
  });

  test("workflow copy is behaviorally identical to the lib copy (no logic drift)", () => {
    const workflowLogic = extractLogic(src);
    const libLogic = extractLogic(libSrc);
    expect(workflowLogic).not.toBe(""); // both copies must be extractable
    expect(libLogic).not.toBe("");
    expect(workflowLogic).toBe(libLogic);
  });

  // The four named agents must each be referenced by agentType, or a lens is
  // dead. Pairs with the pure-function AC12 (the function names lenses; this
  // asserts the workflow can actually spawn each).
  for (const agentType of [
    "soleur:product:cpo",
    "soleur:marketing:cmo",
    "soleur:product:design:ux-design-lead",
    "soleur:engineering:cto",
  ]) {
    test(`workflow references ${agentType}`, () => {
      expect(src).toContain(agentType);
    });
  }

  test("workflow classifies findings with decisionClass", () => {
    expect(src).toContain("decisionClass");
  });
});

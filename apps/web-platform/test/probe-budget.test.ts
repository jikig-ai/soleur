// #10111 Part 1, Guard 5 — the $4 per-run cap of the scheduled real-SDK ask probe.
// The probe's top level cannot be imported by a test (it runs the model on import), so the cap arithmetic lives in
// scripts/lib/probe-budget.ts and is exercised here.
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  RUN_BUDGET_USD,
  perCaseBudgetUsd,
  resolveRunBudgetUsd,
  costFromResult,
  caseCostUsd,
  isBudgetExceededResult,
  createLedger,
  shouldRunCase,
} from "../scripts/lib/probe-budget";

describe("probe-budget: the cap constant (Guard 5 row 2)", () => {
  it("pins the per-run cap at $4", () => {
    expect(RUN_BUDGET_USD).toBe(4);
  });

  it("divides the run cap evenly across the cases (maxBudgetUsd per case)", () => {
    expect(perCaseBudgetUsd(8)).toBeCloseTo(0.5, 10);
    expect(perCaseBudgetUsd(8) * 8).toBeLessThanOrEqual(RUN_BUDGET_USD);
    expect(perCaseBudgetUsd(1)).toBe(RUN_BUDGET_USD);
  });

  it("splits a smaller (rerun) budget, and never returns NaN/Infinity for a zero case count", () => {
    expect(perCaseBudgetUsd(8, 0.8)).toBeCloseTo(0.1, 10);
    expect(Number.isFinite(perCaseBudgetUsd(0))).toBe(true);
  });
});

describe("probe-budget: PROBE_RUN_BUDGET_USD is honoured downward only", () => {
  it("returns the cap when unset, empty or garbage", () => {
    for (const raw of [undefined, "", "abc", "NaN", "-1", "0", "Infinity", "1e999"]) {
      expect(resolveRunBudgetUsd(raw)).toBe(RUN_BUDGET_USD);
    }
  });

  it("honours a smaller value (the runner's rerun remainder)", () => {
    expect(resolveRunBudgetUsd("0.80")).toBeCloseTo(0.8, 10);
    expect(resolveRunBudgetUsd("3.99")).toBeCloseTo(3.99, 10);
  });

  it("ignores a larger value: nothing can raise the cap", () => {
    expect(resolveRunBudgetUsd("40")).toBe(RUN_BUDGET_USD);
    expect(resolveRunBudgetUsd("4.01")).toBe(RUN_BUDGET_USD);
    expect(resolveRunBudgetUsd("4")).toBe(RUN_BUDGET_USD);
  });
});

describe("probe-budget: costFromResult reads the latest total_cost_usd (Guard 5 rows 1, 5)", () => {
  it("reads total_cost_usd from the result frame (a floor of one real cost sample)", () => {
    const samples = [{ type: "result", total_cost_usd: 0.42 }, { type: "result", total_cost_usd: 1.5 }];
    expect(samples.length).toBeGreaterThanOrEqual(1);
    expect(costFromResult(samples[0])).toBeCloseTo(0.42, 10);
    expect(costFromResult(samples[1])).toBeCloseTo(1.5, 10);
  });

  it("treats a missing, non-numeric, negative or non-finite cost as 0, never NaN", () => {
    for (const frame of [undefined, null, {}, { total_cost_usd: "1.2" }, { total_cost_usd: NaN }, { total_cost_usd: -3 }, { total_cost_usd: Infinity }, "x", 7]) {
      const c = costFromResult(frame);
      expect(c).toBe(0);
      expect(Number.isNaN(c)).toBe(false);
    }
  });
});

describe("probe-budget: error_max_budget_usd is a budget stop, never FAIL (Guard 5 row 4)", () => {
  it("recognises the SDK subtype", () => {
    expect(isBudgetExceededResult({ type: "result", subtype: "error_max_budget_usd" })).toBe(true);
  });
  it("does not claim other subtypes or garbage", () => {
    for (const f of [{ subtype: "success" }, { subtype: "error_max_turns" }, { subtype: "error_during_execution" }, {}, undefined, null, "error_max_budget_usd"]) {
      expect(isBudgetExceededResult(f)).toBe(false);
    }
  });
});

describe("probe-budget: the cumulative ledger (Guard 5 rows 1, 3)", () => {
  it("adds recorded costs (a ledger that never adds is RED)", () => {
    const l = createLedger();
    l.record(1.25);
    l.record(0.75);
    expect(l.totalUsd()).toBeCloseTo(2, 10);
    expect(l.remainingUsd()).toBeCloseTo(2, 10);
    expect(l.exhausted()).toBe(false);
  });

  it("ignores a non-numeric or negative recorded cost instead of poisoning the total with NaN", () => {
    const l = createLedger();
    l.record(NaN);
    l.record(-1);
    l.record(0.5);
    expect(l.totalUsd()).toBeCloseTo(0.5, 10);
  });

  it("is exhausted exactly at the cap and a run at $3.99 completes (must-PASS row)", () => {
    const l = createLedger();
    l.record(3.99);
    expect(l.exhausted()).toBe(false);
    expect(shouldRunCase(l)).toBe(true);
    l.record(0.01);
    expect(l.exhausted()).toBe(true);
    expect(shouldRunCase(l)).toBe(false);
  });

  it("stops every remaining case once exhausted: no case runs after the first stop", () => {
    const l = createLedger();
    const costs = [1, 1, 1, 1, 1, 1, 1, 1];
    const ran: number[] = [];
    const skipped: number[] = [];
    costs.forEach((c, i) => {
      if (shouldRunCase(l)) {
        ran.push(i);
        l.record(c);
      } else {
        skipped.push(i);
      }
    });
    expect(ran).toEqual([0, 1, 2, 3]);
    expect(skipped).toEqual([4, 5, 6, 7]);
    expect(l.totalUsd()).toBeCloseTo(RUN_BUDGET_USD, 10);
  });

  it("bounds the total by the cap plus at most one case's own cap", () => {
    const l = createLedger();
    const perCase = perCaseBudgetUsd(8);
    for (let i = 0; i < 8; i++) if (shouldRunCase(l)) l.record(perCase); // each case spends exactly its own cap
    expect(l.totalUsd()).toBeLessThanOrEqual(RUN_BUDGET_USD + perCase);
  });

  it("uses a smaller (rerun) budget as its own cap", () => {
    const l = createLedger(0.8);
    l.record(0.8);
    expect(l.exhausted()).toBe(true);
  });
});

describe("probe-budget: a case with NO result frame is charged its cap (D4)", () => {
  it("charges the measured total_cost_usd when a result frame is present", () => {
    expect(caseCostUsd({ type: "result", total_cost_usd: 0.42 }, 0.5)).toEqual({ costUsd: 0.42, basis: "measured" });
    // A frame that carries no usable cost is still a frame: the measurement is 0, as costFromResult defines it.
    expect(caseCostUsd({ type: "result" }, 0.5)).toEqual({ costUsd: 0, basis: "measured" });
  });

  it("charges the per-case cap when the case ended with no result frame (error, abort, stranded request)", () => {
    for (const frame of [undefined, null]) {
      expect(caseCostUsd(frame, 0.5)).toEqual({ costUsd: 0.5, basis: "cap" });
    }
    expect(caseCostUsd(undefined, 0.1)).toEqual({ costUsd: 0.1, basis: "cap" });
  });

  it("a run of eight hung cases exhausts the ledger at the run cap instead of reading as free", () => {
    const l = createLedger();
    const perCase = perCaseBudgetUsd(8);
    for (let i = 0; i < 8; i++) {
      expect(shouldRunCase(l)).toBe(true);
      l.record(caseCostUsd(undefined, perCase).costUsd);
    }
    expect(l.totalUsd()).toBeCloseTo(RUN_BUDGET_USD, 10);
    expect(l.exhausted()).toBe(true);
  });

  it("with the old charge of 0 the same eight hung cases would have recorded nothing (the control the cap defeats)", () => {
    const l = createLedger();
    for (let i = 0; i < 8; i++) l.record(costFromResult(undefined));
    expect(l.totalUsd()).toBe(0);
  });
});

// The probe's top level runs the model on import, so its wiring is pinned against its COMMENT-STRIPPED source with anchored call forms.
// A symbol-presence grep would stay green with a call removed (it would still match the import and the header prose).
function stripComments(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[ \t])\/\/.*$/gm, "$1");
}

describe("probe-budget: the probe source is wired to the helpers (anchored call forms, comments stripped)", () => {
  const raw = readFileSync(resolve(__dirname, "..", "scripts", "dev-probe-destroy-ask.ts"), "utf8");
  const src = stripComments(raw);

  it("the comment stripper removes block and line comments but keeps URLs inside strings", () => {
    const out = stripComments('/* a */ const x = "https://h/1"; // note\nconst y = 1; /** b */');
    expect(out).toContain('"https://h/1"');
    expect(out).not.toMatch(/note|\ba\b|\bb\b/);
    expect(src).not.toContain("HARNESS-ONLY");
  });

  it("imports every helper from ./lib/probe-budget", () => {
    const m = /import \{([^}]*)\} from "\.\/lib\/probe-budget";/.exec(src);
    expect(m).not.toBeNull();
    const names = (m?.[1] ?? "").split(",").map((x) => x.trim());
    for (const sym of ["resolveRunBudgetUsd", "perCaseBudgetUsd", "caseCostUsd", "isBudgetExceededResult", "createLedger", "shouldRunCase"]) {
      expect(names).toContain(sym);
    }
  });

  it("derives the run budget from PROBE_RUN_BUDGET_USD and builds the ledger and per-case cap from it", () => {
    expect(src).toMatch(/const runBudgetUsd = resolveRunBudgetUsd\(process\.env\.PROBE_RUN_BUDGET_USD\);/);
    expect(src).toMatch(/const ledger = createLedger\(runBudgetUsd\);/);
    expect(src).toMatch(/const caseBudgetUsd = perCaseBudgetUsd\(selected\.length, runBudgetUsd\);/);
  });

  it("sets maxBudgetUsd to the per-case cap on the probe's own copy of the options, never through the production builder's arguments", () => {
    expect(src).toMatch(/\(opts as any\)\.maxBudgetUsd = caseBudgetUsd;/);
    expect(src).not.toMatch(/buildAgentQueryOptions\(\{[^}]*maxBudgetUsd/s);
    expect(src.indexOf("buildAgentQueryOptions({")).toBeLessThan(src.indexOf("(opts as any).maxBudgetUsd = caseBudgetUsd;"));
  });

  it("guards the case loop with shouldRunCase(ledger) and stops with a budget CANT-RUN before any model call", () => {
    expect(src).toMatch(
      /for \(const c of selected\) \{\s*if \(!shouldRunCase\(ledger\)\) \{\s*console\.log\(`PROBE \$\{c\.name\} verdict=CANT-RUN:budget-exceeded[^`]*`\);\s*cantRun = true;\s*budgetHit = true;\s*continue;\s*\}/,
    );
    // The guard precedes the only runCase call.
    expect(src.indexOf("if (!shouldRunCase(ledger))")).toBeLessThan(src.indexOf("await runCase(c, caseBudgetUsd)"));
  });

  it("records the case cost on the ledger straight after the case runs", () => {
    expect(src).toMatch(/const r = await runCase\(c, caseBudgetUsd\);\s*ran \+= 1;\s*ledger\.record\(r\.costUsd\);/);
  });

  it("keeps the LATEST result frame and charges the case through caseCostUsd(lastResult, caseBudgetUsd)", () => {
    expect(src).toMatch(/if \(m\.type === "result"\) \{ release\(\); lastResult = m; \}/);
    expect(src).toMatch(/const cost = caseCostUsd\(lastResult, caseBudgetUsd\);/);
    expect(src).toMatch(/costUsd: cost\.costUsd, costBasis: cost\.basis, budgetExceeded: isBudgetExceededResult\(lastResult\)/);
    expect(src).toMatch(/costUsd=\$\{r\.costUsd\.toFixed\(4\)\} costBasis=\$\{r\.costBasis\}/);
  });

  it("maps the SDK budget stop to a budget-exceeded verdict that sets budgetHit, and budgetHit wins the CANT-RUN reason", () => {
    expect(src).toMatch(/if \(r\.budgetExceeded\) verdict = "BUDGET-EXCEEDED";/);
    expect(src).toMatch(/if \(verdict === "BUDGET-EXCEEDED"\) \{ cantRun = true; budgetHit = true; \}/);
    expect(src).toMatch(/`CANT-RUN:\$\{budgetHit \? "budget-exceeded" : cantRunReason\}`/);
    expect(src).toMatch(/verdict=\$\{verdict === "BUDGET-EXCEEDED" \? "CANT-RUN:budget-exceeded" : verdict\}/);
  });

  it("prints TOTAL costUsd=<ledger total> immediately before the RESULT line", () => {
    expect(src).toMatch(/console\.log\(`TOTAL costUsd=\$\{ledger\.totalUsd\(\)\.toFixed\(4\)\}`\);\s*console\.log\(`RESULT: \$\{outcome\} /);
  });
});

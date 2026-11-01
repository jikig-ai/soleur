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

describe("probe-budget: the probe source is wired to the helpers", () => {
  const src = readFileSync(resolve(__dirname, "..", "scripts", "dev-probe-destroy-ask.ts"), "utf8");
  it("imports the helpers and uses every call site", () => {
    expect(src).toMatch(/from "\.\/lib\/probe-budget"/);
    for (const sym of ["resolveRunBudgetUsd", "perCaseBudgetUsd", "costFromResult", "isBudgetExceededResult", "createLedger", "shouldRunCase"]) {
      expect(src).toContain(sym);
    }
  });
  it("sets maxBudgetUsd on the probe's own copy of the options, not through the production option builder's arguments", () => {
    // The builder already has an optional, unset-by-default `maxBudgetUsd` argument that production callers do not use; the
    // harness-only cap is assigned after the builder returns so the production option shape is unchanged by this probe.
    expect(src).toMatch(/\(opts as any\)\.maxBudgetUsd = /);
    expect(src).not.toMatch(/buildAgentQueryOptions\(\{[^}]*maxBudgetUsd/s);
  });
  it("maps error_max_budget_usd to CANT-RUN:budget-exceeded and prints the TOTAL line before RESULT", () => {
    expect(src).toContain("budget-exceeded");
    expect(src.lastIndexOf("TOTAL costUsd=")).toBeGreaterThan(-1);
    expect(src.lastIndexOf("TOTAL costUsd=")).toBeLessThan(src.lastIndexOf("RESULT: ${outcome}"));
  });
});

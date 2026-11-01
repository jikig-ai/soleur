/**
 * #10111 Part 1 / ADR-284 amendment — cost cap arithmetic for scripts/dev-probe-destroy-ask.ts.
 *
 * The probe's top level runs the model on import, so a test cannot import it; the cap lives here instead and is pinned by
 * apps/web-platform/test/probe-budget.test.ts. These helpers are HARNESS-ONLY: nothing here is part of the production option
 * shape (`maxBudgetUsd` is set by the probe on its own copy of the options and must never reach agent-runner-query-options.ts).
 *
 * Semantics measured from the SDK typings (sdk.d.ts): `maxBudgetUsd` stops a `query()` with an `error_max_budget_usd` result, and
 * `total_cost_usd` on a result frame is the CUMULATIVE estimated cost of that one `query()` call, so the latest frame is read, never
 * summed within a case. Each probe case is its own `query()`, so the ledger sums ACROSS cases. The figure is an estimate, not a bill.
 */

/** Hard per-run cap in USD. The scheduled workflow, the runner and the ADR-284 amendment quote this figure. */
export const RUN_BUDGET_USD = 4;

/**
 * Per-case `maxBudgetUsd`: the run budget split evenly over the cases. A zero/invalid case count is treated as one case so the result
 * is always finite.
 */
export function perCaseBudgetUsd(caseCount: number, runBudgetUsd: number = RUN_BUDGET_USD): number {
  const n = Number.isFinite(caseCount) && caseCount >= 1 ? Math.floor(caseCount) : 1;
  return runBudgetUsd / n;
}

/**
 * PROBE_RUN_BUDGET_USD is honoured DOWNWARD ONLY: the runner passes the remainder on a rerun, and nothing (env typo, larger value,
 * garbage) can raise the cap above RUN_BUDGET_USD.
 */
export function resolveRunBudgetUsd(raw: string | undefined): number {
  if (raw === undefined || raw.trim() === "") return RUN_BUDGET_USD;
  const v = Number(raw);
  if (!Number.isFinite(v) || v <= 0 || v >= RUN_BUDGET_USD) return RUN_BUDGET_USD;
  return v;
}

/** `total_cost_usd` of a result frame; a missing, non-numeric, negative or non-finite value is 0 (never NaN). */
export function costFromResult(frame: unknown): number {
  if (typeof frame !== "object" || frame === null) return 0;
  const v = (frame as { total_cost_usd?: unknown }).total_cost_usd;
  return typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : 0;
}

/** True for the SDK's budget stop (`error_max_budget_usd`); that is a could-not-measure outcome, never a FAIL. */
export function isBudgetExceededResult(frame: unknown): boolean {
  if (typeof frame !== "object" || frame === null) return false;
  return (frame as { subtype?: unknown }).subtype === "error_max_budget_usd";
}

export type Ledger = {
  /** Add one case's cost; a non-finite or negative value is ignored. */
  record(costUsd: number): void;
  totalUsd(): number;
  remainingUsd(): number;
  exhausted(): boolean;
};

export function createLedger(runBudgetUsd: number = RUN_BUDGET_USD): Ledger {
  let total = 0;
  return {
    record(costUsd: number) {
      if (typeof costUsd === "number" && Number.isFinite(costUsd) && costUsd > 0) total += costUsd;
    },
    totalUsd: () => total,
    remainingUsd: () => Math.max(0, runBudgetUsd - total),
    exhausted: () => total >= runBudgetUsd - 1e-9,
  };
}

/** Gate before each case: once the ledger is exhausted every remaining case is CANT-RUN:budget-exceeded without a model call. */
export function shouldRunCase(ledger: Ledger): boolean {
  return !ledger.exhausted();
}

// Cost-cap env-var reader for the cc-soleur-go runner.
//
// Plan: knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md
// Stage 2.18. Recalibrated 2026-04-24 (RERUN §"Cost caps vs measured
// reality"): $5 brainstorm / $2 work / $25 user-daily / $500 global-daily.
// CFO gate at Stage 6.5.1 before merge.
//
// The runner (`soleur-go-runner.ts`) takes `defaultCostCaps` via
// dependency injection. The call site (ws-handler wiring, Stage 2.12/2.13)
// will call `readCcCostCaps()` once at conversation start and pass the
// result. Env var names are the contract with Doppler.

import type { CostCaps } from "./soleur-go-runner";

export const ENV_VARS = {
  brainstorm: "CC_MAX_COST_USD_BRAINSTORM",
  work: "CC_MAX_COST_USD_WORK",
  default: "CC_MAX_COST_USD_DEFAULT",
  userDaily: "CC_USER_DAILY_USD_CAP",
  globalDaily: "CC_GLOBAL_DAILY_USD_CAP",
} as const;

export interface DailyCostCaps {
  perUserDailyUsd: number;
  globalDailyUsd: number;
}

// Defaults from plan RERUN §"Cost caps vs measured reality".
// Prior values ($2.50/$0.50/$10/$200) had no empirical basis and would
// have tripped on the first real brainstorm measured.
export const FALLBACK_COST_CAPS: CostCaps = {
  perWorkflow: {
    brainstorm: 5.0,
    work: 2.0,
  },
  default: 2.0,
};

export const FALLBACK_DAILY_CAPS: DailyCostCaps = {
  perUserDailyUsd: 25.0,
  globalDailyUsd: 500.0,
};

function parsePositive(raw: string | undefined, fallback: number): number {
  if (raw === undefined || raw === "") return fallback;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return n;
}

export function readCcCostCaps(
  env: Record<string, string | undefined> = process.env,
): CostCaps {
  return {
    perWorkflow: {
      brainstorm: parsePositive(
        env[ENV_VARS.brainstorm],
        FALLBACK_COST_CAPS.perWorkflow.brainstorm ?? 5.0,
      ),
      work: parsePositive(
        env[ENV_VARS.work],
        FALLBACK_COST_CAPS.perWorkflow.work ?? 2.0,
      ),
    },
    default: parsePositive(env[ENV_VARS.default], FALLBACK_COST_CAPS.default),
  };
}

export function readCcDailyCaps(
  env: Record<string, string | undefined> = process.env,
): DailyCostCaps {
  return {
    perUserDailyUsd: parsePositive(
      env[ENV_VARS.userDaily],
      FALLBACK_DAILY_CAPS.perUserDailyUsd,
    ),
    globalDailyUsd: parsePositive(
      env[ENV_VARS.globalDaily],
      FALLBACK_DAILY_CAPS.globalDailyUsd,
    ),
  };
}

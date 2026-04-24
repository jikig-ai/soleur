import { describe, it, expect } from "vitest";

import {
  readCcCostCaps,
  readCcDailyCaps,
  FALLBACK_COST_CAPS,
  FALLBACK_DAILY_CAPS,
  ENV_VARS,
} from "@/server/cc-cost-caps";

// Stage 2.18 coverage: CC_MAX_COST_USD_* readers. Defaults reflect the
// 2026-04-24 recalibration (RERUN §"Cost caps vs measured reality").
// CFO gate at Stage 6.5.1 before merge.

describe("readCcCostCaps (Stage 2.18)", () => {
  it("returns fallbacks when env is empty", () => {
    expect(readCcCostCaps({})).toEqual(FALLBACK_COST_CAPS);
  });

  it("parses BRAINSTORM + WORK + DEFAULT from env", () => {
    expect(
      readCcCostCaps({
        [ENV_VARS.brainstorm]: "7.5",
        [ENV_VARS.work]: "3.25",
        [ENV_VARS.default]: "1.1",
      }),
    ).toEqual({
      perWorkflow: { brainstorm: 7.5, work: 3.25 },
      default: 1.1,
    });
  });

  it("ignores non-numeric values and falls back", () => {
    const caps = readCcCostCaps({
      [ENV_VARS.brainstorm]: "nope",
      [ENV_VARS.work]: "",
    });
    expect(caps.perWorkflow.brainstorm).toBe(
      FALLBACK_COST_CAPS.perWorkflow.brainstorm,
    );
    expect(caps.perWorkflow.work).toBe(FALLBACK_COST_CAPS.perWorkflow.work);
  });

  it("ignores zero and negative values (fail-closed to fallback)", () => {
    const caps = readCcCostCaps({
      [ENV_VARS.brainstorm]: "0",
      [ENV_VARS.work]: "-1",
    });
    expect(caps.perWorkflow.brainstorm).toBe(
      FALLBACK_COST_CAPS.perWorkflow.brainstorm,
    );
    expect(caps.perWorkflow.work).toBe(FALLBACK_COST_CAPS.perWorkflow.work);
  });

  it("fallback brainstorm cap is $5.00 (recalibrated 2026-04-24)", () => {
    expect(FALLBACK_COST_CAPS.perWorkflow.brainstorm).toBe(5.0);
  });

  it("fallback work cap is $2.00 (recalibrated 2026-04-24)", () => {
    expect(FALLBACK_COST_CAPS.perWorkflow.work).toBe(2.0);
  });
});

describe("readCcDailyCaps (Stage 2.18)", () => {
  it("returns fallbacks when env is empty", () => {
    expect(readCcDailyCaps({})).toEqual(FALLBACK_DAILY_CAPS);
  });

  it("parses USER_DAILY + GLOBAL_DAILY from env", () => {
    expect(
      readCcDailyCaps({
        [ENV_VARS.userDaily]: "40",
        [ENV_VARS.globalDaily]: "1000",
      }),
    ).toEqual({
      perUserDailyUsd: 40,
      globalDailyUsd: 1000,
    });
  });

  it("fallback user daily is $25.00; global daily is $500.00 (recalibrated 2026-04-24)", () => {
    expect(FALLBACK_DAILY_CAPS.perUserDailyUsd).toBe(25.0);
    expect(FALLBACK_DAILY_CAPS.globalDailyUsd).toBe(500.0);
  });
});

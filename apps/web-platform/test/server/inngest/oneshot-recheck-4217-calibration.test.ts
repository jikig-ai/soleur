import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  oneshotRecheck4217Calibration,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/oneshot-recheck-4217-calibration";
import { KILL_ESCALATION_MS } from "@/server/inngest/functions/_cron-claude-eval-substrate";

describe("oneshotRecheck4217Calibration — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(oneshotRecheck4217Calibration).toBeDefined();
    expect(typeof oneshotRecheck4217Calibration).toBe("object");
  });
});

describe("oneshotRecheck4217Calibration — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 20 minutes (matches GHA timeout-minutes: 20)", () => {
    expect(MAX_TURN_DURATION_MS).toBe(20 * 60 * 1000);
  });

  it("KILL_ESCALATION_MS is 5 seconds (SIGTERM → SIGKILL grace)", () => {
    expect(KILL_ESCALATION_MS).toBe(5_000);
  });
});

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/oneshot-recheck-4217-calibration.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "oneshot-recheck-4217-calibration"', "canonical function id"],
    ['event: "oneshot/recheck-4217-calibration.fire"', "event trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "single retry on failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });

  it("does NOT contain a cron trigger (oneshots have no schedule)", () => {
    expect(SUT_SOURCE).not.toMatch(/\bcron:\s*"/);
  });

  it("does NOT contain postSentryHeartbeat (no Sentry cron monitor for oneshots)", () => {
    expect(SUT_SOURCE).not.toContain("postSentryHeartbeat");
  });
});

describe("handler source anchors", () => {
  it.each([
    ["date guard", "D3 cross-fire defense"],
    ["expected_date", "event payload date field"],
    ["expectedAuthor", "D5 author pin"],
    ["expectedCreatedAt", "D5 immutability pin"],
    ["buildSpawnEnv", "spawn env allowlist function"],
    ["spawnClaudeEval", "substrate spawn call"],
    ["setupEphemeralWorkspace", "workspace setup"],
    ["teardownEphemeralWorkspace", "workspace cleanup"],
    ["reportSilentFallback", "error reporting (no Sentry cron monitor)"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("buildSpawnEnv allowlist", () => {
  it("exports only PATH, HOME, NODE_ENV, ANTHROPIC_API_KEY, GH_TOKEN", () => {
    const envBlock = SUT_SOURCE.match(
      /function buildSpawnEnv[\s\S]*?^}/m,
    )?.[0];
    expect(envBlock).toBeDefined();
    const keys = envBlock!.match(/\b(process\.env\.\w+)/g) ?? [];
    const envNames = keys.map((k) => k.replace("process.env.", ""));
    expect(envNames.sort()).toEqual(
      ["ANTHROPIC_API_KEY", "HOME", "NODE_ENV", "PATH"].sort(),
    );
  });
});

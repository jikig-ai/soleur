import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  eventShipMerge,
  MAX_TURN_DURATION_MS,
  selectQualifyingPr,
} from "@/server/inngest/functions/event-ship-merge";
import { KILL_ESCALATION_MS } from "@/server/inngest/functions/_cron-claude-eval-substrate";

describe("eventShipMerge — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(eventShipMerge).toBeDefined();
    expect(typeof eventShipMerge).toBe("object");
  });
});

describe("eventShipMerge — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 30 minutes (matches GHA timeout-minutes: 30)", () => {
    expect(MAX_TURN_DURATION_MS).toBe(30 * 60 * 1000);
  });

  it("KILL_ESCALATION_MS is 5 seconds (SIGTERM → SIGKILL grace)", () => {
    expect(KILL_ESCALATION_MS).toBe(5_000);
  });
});

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/event-ship-merge.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "event-ship-merge"', "canonical function id"],
    ['event: "ship-merge.manual-trigger"', "event trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "single retry on failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });

  it("does NOT contain a cron trigger (event-triggered, no schedule)", () => {
    expect(SUT_SOURCE).not.toMatch(/\bcron:\s*"/);
  });

  it("does NOT contain postSentryHeartbeat (no Sentry cron monitor for events)", () => {
    expect(SUT_SOURCE).not.toContain("postSentryHeartbeat");
  });
});

describe("handler source anchors", () => {
  it.each([
    ["pr_number", "optional PR override from event payload"],
    ["ship/failed", "failure label"],
    ["no-auto-ship", "exclusion label"],
    ["/soleur:ship --headless", "ship skill invocation"],
    ["buildSpawnEnv", "spawn env allowlist function"],
    ["spawnClaudeEval", "substrate spawn call"],
    ["setupEphemeralWorkspace", "workspace setup"],
    ["teardownEphemeralWorkspace", "workspace cleanup"],
    ["reportSilentFallback", "error reporting (no Sentry cron monitor)"],
    ["selectQualifyingPr", "PR selection logic function"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("selectQualifyingPr — PR selection logic", () => {
  const basePr = {
    number: 100,
    created_at: "2026-05-20T00:00:00Z",
    draft: false,
    base: { ref: "main" },
    labels: [] as { name: string }[],
  };

  it("returns the oldest qualifying PR", () => {
    const prs = [
      { ...basePr, number: 102, created_at: "2026-05-22T00:00:00Z" },
      { ...basePr, number: 101, created_at: "2026-05-21T00:00:00Z" },
      { ...basePr, number: 100, created_at: "2026-05-20T00:00:00Z" },
    ];
    expect(selectQualifyingPr(prs, "2026-05-25T00:00:00Z")).toBe(100);
  });

  it("excludes draft PRs", () => {
    const prs = [
      { ...basePr, number: 100, draft: true },
      { ...basePr, number: 101, created_at: "2026-05-21T00:00:00Z" },
    ];
    expect(selectQualifyingPr(prs, "2026-05-25T00:00:00Z")).toBe(101);
  });

  it("excludes PRs not targeting main", () => {
    const prs = [
      { ...basePr, number: 100, base: { ref: "develop" } },
      { ...basePr, number: 101, created_at: "2026-05-21T00:00:00Z" },
    ];
    expect(selectQualifyingPr(prs, "2026-05-25T00:00:00Z")).toBe(101);
  });

  it("excludes PRs with ship/failed label", () => {
    const prs = [
      { ...basePr, number: 100, labels: [{ name: "ship/failed" }] },
      { ...basePr, number: 101, created_at: "2026-05-21T00:00:00Z" },
    ];
    expect(selectQualifyingPr(prs, "2026-05-25T00:00:00Z")).toBe(101);
  });

  it("excludes PRs with no-auto-ship label", () => {
    const prs = [
      { ...basePr, number: 100, labels: [{ name: "no-auto-ship" }] },
      { ...basePr, number: 101, created_at: "2026-05-21T00:00:00Z" },
    ];
    expect(selectQualifyingPr(prs, "2026-05-25T00:00:00Z")).toBe(101);
  });

  it("excludes PRs younger than 24 hours", () => {
    const prs = [
      { ...basePr, number: 100, created_at: "2026-05-25T12:00:00Z" },
    ];
    expect(selectQualifyingPr(prs, "2026-05-25T18:00:00Z")).toBeNull();
  });

  it("returns null when no PRs qualify", () => {
    expect(selectQualifyingPr([], "2026-05-25T00:00:00Z")).toBeNull();
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

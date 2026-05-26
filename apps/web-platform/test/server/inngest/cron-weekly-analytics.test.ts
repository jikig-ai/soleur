import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronWeeklyAnalytics,
  SYNTHETIC_CHECK_NAMES,
} from "@/server/inngest/functions/cron-weekly-analytics";

describe("cronWeeklyAnalytics — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronWeeklyAnalytics).toBeDefined();
    expect(typeof cronWeeklyAnalytics).toBe("object");
  });
});

describe("cronWeeklyAnalytics — exported constants", () => {
  it("SYNTHETIC_CHECK_NAMES has 7 entries", () => {
    expect(SYNTHETIC_CHECK_NAMES).toHaveLength(7);
  });
});

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-weekly-analytics.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-weekly-analytics"', "canonical function id"],
    ['cron: "0 6 * * 1"', "Monday 06:00 UTC schedule"],
    ['event: "cron/weekly-analytics.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "single retry on failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("handler source anchors", () => {
  it.each([
    ["weekly-analytics.sh", "delegates to existing analytics script"],
    ["PLAUSIBLE_API_KEY", "Plausible API key env var"],
    ["PLAUSIBLE_SITE_ID", "Plausible site ID env var"],
    ["kpi_miss", "KPI miss detection output"],
    ["inngest.send", "cascade dispatch via Inngest events"],
    ["cron/seo-aeo-audit.manual-trigger", "cascade target C5"],
    ["cron/growth-execution.manual-trigger", "cascade target C4"],
    ["cron/content-generator.manual-trigger", "cascade target C2"],
    ["postSentryHeartbeat", "Sentry cron heartbeat"],
    ["scheduled-weekly-analytics", "Sentry monitor slug"],
    ["bot-pr", "bot-PR pattern reference"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("cascade targets (T2 ordering constraint)", () => {
  it("contains all 3 cascade target event names", () => {
    expect(SUT_SOURCE).toContain("cron/seo-aeo-audit.manual-trigger");
    expect(SUT_SOURCE).toContain("cron/growth-execution.manual-trigger");
    expect(SUT_SOURCE).toContain("cron/content-generator.manual-trigger");
  });

  it("dispatches cascade inside inngest.send() call", () => {
    expect(SUT_SOURCE).toContain("inngest.send");
  });
});

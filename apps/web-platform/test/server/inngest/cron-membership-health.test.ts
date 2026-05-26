// TR9 Phase-2 — cron-membership-health unit tests.
//
// Test coverage:
//   (a) Registration smoke test — import loads without throwing.
//   (b) Source-shape anchor tests — id, cron, event, concurrency, retries.
//   (c) Exported constants — FLAGS_URL, HEALTH_URL, FLAG_NAME.

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronMembershipHealth,
  FLAGS_URL,
  HEALTH_URL,
  FLAG_NAME,
} from "@/server/inngest/functions/cron-membership-health";

// =============================================================================
// Registration smoke test
// =============================================================================

describe("cronMembershipHealth — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronMembershipHealth).toBeDefined();
    expect(typeof cronMembershipHealth).toBe("object");
  });
});

// =============================================================================
// Exported constants
// =============================================================================

describe("cronMembershipHealth — exported constants", () => {
  it("FLAGS_URL points to soleur.ai/api/flags?role=prd", () => {
    expect(FLAGS_URL).toBe("https://soleur.ai/api/flags?role=prd");
  });

  it("HEALTH_URL points to soleur.ai/api/health/team-membership", () => {
    expect(HEALTH_URL).toBe("https://soleur.ai/api/health/team-membership");
  });

  it("FLAG_NAME is team-workspace-invite", () => {
    expect(FLAG_NAME).toBe("team-workspace-invite");
  });
});

// =============================================================================
// Source-shape anchor tests
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-membership-health.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-membership-health"', "canonical function id"],
    ['cron: "17 * * * *"', "hourly at :17 schedule"],
    ['event: "cron/membership-health.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on probe failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("cron-membership-health — Sentry monitor slug", () => {
  it("source contains the correct Sentry monitor slug", () => {
    expect(SUT_SOURCE).toContain('"scheduled-membership-health"');
  });
});

describe("cron-membership-health — key logic anchors", () => {
  it.each([
    ["team-workspace-invite", "flag name used in probe logic"],
    ["health_status", "health endpoint response field check"],
    ["[P0] Team membership health degraded", "incident issue title"],
    ["type/incident", "incident label"],
    ["severity/p0", "severity label"],
    ["area/workspace", "area label"],
    ["fail-closed-to-OFF", "fail-closed behavior on flag check failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

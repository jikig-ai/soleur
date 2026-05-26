// TR9 Phase-2 — cron-plausible-goals handler unit tests.
//
// Coverage:
//   1. Registration shape (cron + manual-trigger, concurrency, retries).
//   2. Source-shape anchors (cron schedule, event name, concurrency).
//   3. CANONICAL_GOALS exported constant — count and shape.
//   4. Canonical goals parity with provision-plausible-goals.sh.

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronPlausibleGoals,
  CANONICAL_GOALS,
} from "@/server/inngest/functions/cron-plausible-goals";

// =============================================================================
// Registration smoke test
// =============================================================================

describe("cronPlausibleGoals — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronPlausibleGoals).toBeDefined();
    expect(typeof cronPlausibleGoals).toBe("object");
  });
});

// =============================================================================
// Source-shape anchors
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-plausible-goals.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-plausible-goals"', "canonical function id"],
    ['cron: "0 7 1 * *"', "1st of month 07:00 UTC schedule"],
    [
      'event: "cron/plausible-goals.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("source contains key constants", () => {
  it.each([
    ["scheduled-plausible-goals", "Sentry monitor slug"],
    ["PLAUSIBLE_API_KEY", "API key env var"],
    ["PLAUSIBLE_SITE_ID", "site ID env var"],
    ["https://plausible.io", "Plausible base URL"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

// =============================================================================
// CANONICAL_GOALS — exported constant
// =============================================================================

describe("CANONICAL_GOALS", () => {
  it("exports exactly 8 canonical goals", () => {
    expect(CANONICAL_GOALS).toHaveLength(8);
  });

  it("contains both event and page goal types", () => {
    const types = new Set(CANONICAL_GOALS.map((g) => g.goal_type));
    expect(types).toContain("event");
    expect(types).toContain("page");
  });

  it("contains the expected event goals", () => {
    const eventNames = CANONICAL_GOALS
      .filter((g) => g.goal_type === "event")
      .map((g) => g.value);
    expect(eventNames).toContain("Newsletter Signup");
    expect(eventNames).toContain("Waitlist Signup");
    expect(eventNames).toContain("Outbound Link: Click");
    expect(eventNames).toContain("kb.chat.opened");
    expect(eventNames).toContain("kb.chat.selection_sent");
    expect(eventNames).toContain("kb.chat.thread_resumed");
  });

  it("contains the expected page goals", () => {
    const pagePaths = CANONICAL_GOALS
      .filter((g) => g.goal_type === "page")
      .map((g) => g.value);
    expect(pagePaths).toContain("/pages/getting-started.html");
    expect(pagePaths).toContain("/blog/*");
  });
});

// =============================================================================
// Canonical goals parity with provision-plausible-goals.sh
// =============================================================================

describe("CANONICAL_GOALS parity with provision-plausible-goals.sh", () => {
  const repoRoot = join(__dirname, "..", "..", "..", "..", "..");
  const script = readFileSync(
    join(repoRoot, "scripts", "provision-plausible-goals.sh"),
    "utf-8",
  );

  it("every canonical goal's value appears in the shell script", () => {
    for (const goal of CANONICAL_GOALS) {
      expect(script).toContain(goal.value);
    }
  });

  it("shell script goal count matches TS constant", () => {
    // Count provision_goal invocations (lines starting with provision_goal
    // followed by a quoted goal_type argument — excludes the function
    // definition and internal error-message references).
    const provisionCalls = script.match(/^provision_goal\s+"(event|page)"/gm);
    expect(provisionCalls).not.toBeNull();
    expect(provisionCalls!.length).toBe(CANONICAL_GOALS.length);
  });
});

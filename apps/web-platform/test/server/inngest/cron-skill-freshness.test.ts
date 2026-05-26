// TR9 Phase-2 — cron-skill-freshness handler unit tests.
//
// Coverage:
//   1. Registration shape (cron + manual-trigger, concurrency, retries).
//   2. Source-shape anchors (cron schedule, event name, concurrency).
//   3. Exported constants (CAP_PER_RUN, SKILL_NAME_RE).

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronSkillFreshness,
  CAP_PER_RUN,
  SKILL_NAME_RE,
} from "@/server/inngest/functions/cron-skill-freshness";

// =============================================================================
// Registration smoke test
// =============================================================================

describe("cronSkillFreshness — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronSkillFreshness).toBeDefined();
    expect(typeof cronSkillFreshness).toBe("object");
  });
});

// =============================================================================
// Source-shape anchors
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-skill-freshness.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-skill-freshness"', "canonical function id"],
    ['cron: "0 2 1 * *"', "1st of month 02:00 UTC schedule"],
    [
      'event: "cron/skill-freshness.manual-trigger"',
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

describe("source contains key constants and paths", () => {
  it.each([
    ["scheduled-skill-freshness", "Sentry monitor slug and issue label"],
    [".claude/.skill-invocations.jsonl", "invocations JSONL path"],
    ["plugins/soleur/skills", "skills directory path"],
    [
      "knowledge-base/engineering/operations/skill-freshness.json",
      "report output path",
    ],
    ["setupEphemeralWorkspace", "ephemeral workspace setup import"],
    ["teardownEphemeralWorkspace", "ephemeral workspace teardown import"],
    ["do-not-autoclose", "issue label preventing autoclose"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

// =============================================================================
// Exported constants
// =============================================================================

describe("CAP_PER_RUN", () => {
  it("is 3 (matches GHA workflow env)", () => {
    expect(CAP_PER_RUN).toBe(3);
  });
});

describe("SKILL_NAME_RE", () => {
  it("accepts simple kebab-case skill names", () => {
    expect(SKILL_NAME_RE.test("plan")).toBe(true);
    expect(SKILL_NAME_RE.test("plan-review")).toBe(true);
    expect(SKILL_NAME_RE.test("fix-issue")).toBe(true);
  });

  it("accepts namespaced skill names (plugin:skill)", () => {
    // The regex ^[a-z][a-z0-9-]*(:[a-z0-9-]+)?$ accepts an optional
    // :suffix for plugin-namespaced names like "soleur:plan".
    expect(SKILL_NAME_RE.test("soleur:plan")).toBe(true);
    expect(SKILL_NAME_RE.test("abc:def-ghi")).toBe(true);
  });

  it("validates the full regex pattern", () => {
    // Valid names
    expect(SKILL_NAME_RE.test("a")).toBe(true);
    expect(SKILL_NAME_RE.test("abc")).toBe(true);
    expect(SKILL_NAME_RE.test("abc-def")).toBe(true);
    expect(SKILL_NAME_RE.test("abc123")).toBe(true);
    expect(SKILL_NAME_RE.test("abc:def")).toBe(true);
    expect(SKILL_NAME_RE.test("abc-def:ghi-jkl")).toBe(true);

    // Invalid names
    expect(SKILL_NAME_RE.test("")).toBe(false);
    expect(SKILL_NAME_RE.test("123")).toBe(false);
    expect(SKILL_NAME_RE.test("-abc")).toBe(false);
    expect(SKILL_NAME_RE.test("ABC")).toBe(false);
    expect(SKILL_NAME_RE.test("abc_def")).toBe(false);
    expect(SKILL_NAME_RE.test("abc:")).toBe(false);
    expect(SKILL_NAME_RE.test(":abc")).toBe(false);
    expect(SKILL_NAME_RE.test("abc:def:ghi")).toBe(false);
  });
});

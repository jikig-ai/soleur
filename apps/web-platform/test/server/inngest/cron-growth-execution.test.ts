// TR9 Phase-2 — cron-growth-execution handler unit tests.
//
// Minimal test coverage focused on the invariants the multi-agent review
// flagged as load-bearing:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (seo-refresh-queue, Priority 1, growth fix,
//      validate-seo, MANDATORY FINAL STEP) — original anchors from the GHA
//      prompt that must survive silent paraphrasing across plan→work→ship
//      cycles.
//   3. Timing constants exported (MAX_TURN_DURATION_MS, KILL_ESCALATION_MS)
//      so the substrate-extraction follow-up can centralise them without
//      breaking parity with the handler's actual values.
//   4. buildSpawnEnv allowlist — positive class (5 base vars) AND negative
//      class (sensitive denylist + spread operator). This is the primary
//      security regression detector.

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE all ES-module imports below — sets NEXT_PHASE so
// the inngest client's startup-key check short-circuits (same path Next.js
// `next build` uses). Mirrors cron-roadmap-review.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronGrowthExecution,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-growth-execution";

describe("cronGrowthExecution — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    // Smoke test: the import at the top of this file already drove the
    // module's top-level code; if registration shape were structurally
    // broken (missing trigger, malformed concurrency), it would have
    // thrown during inngest.createFunction at module load.
    expect(cronGrowthExecution).toBeDefined();
    expect(typeof cronGrowthExecution).toBe("object");
  });
});

describe("cronGrowthExecution — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 30 minutes (biweekly growth budget)", () => {
    expect(MAX_TURN_DURATION_MS).toBe(30 * 60 * 1000);
  });

  it("KILL_ESCALATION_MS is 5 seconds (SIGTERM → SIGKILL grace)", () => {
    expect(KILL_ESCALATION_MS).toBe(5_000);
  });
});

// Source-file-content tests — read the SUT file and assert the prompt
// constant and buildSpawnEnv allowlist contain the verbatim anchors. Per
// AGENTS.md `cq-test-fixtures-synthesized-only`, we read the production
// source via readFileSync rather than synthesising a parallel prompt
// fixture (the prompt + allowlist ARE the artifacts under test).

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-growth-execution.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-growth-execution"', "canonical function id"],
    ['cron: "0 10 1,15 * *"', "biweekly 1st/15th @ 10:00 UTC schedule"],
    [
      'event: "cron/growth-execution.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on agent-loop failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("GROWTH_EXECUTION_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["seo-refresh-queue", "SEO queue file reference"],
      ["Priority 1", "priority level for stale pages"],
      ["growth fix", "skill invocation verb"],
      ["validate-seo", "build validation script"],
      ["MANDATORY FINAL STEP", "PR-creation block heading"],
      ["[Scheduled] Growth Execution", "issue-title format"],
      ["scheduled-growth-execution", "label / Sentry monitor slug"],
      ["gh pr create", "PR-creation gh invocation"],
      ["gh pr merge", "auto-merge gh invocation"],
      ["MILESTONE RULE:", "rule keyword"],
      [
        "Do NOT push directly to main",
        "PR-based commit pattern (no direct main writes)",
      ],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });
});

describe("buildSpawnEnv allowlist (security surface)", () => {
  // Extract the buildSpawnEnv function body from SUT_SOURCE for targeted
  // grep. The function is a single returned object literal; we slice from
  // the function signature to its closing brace.
  const buildEnvMatch = SUT_SOURCE.match(
    /function buildSpawnEnv\([\s\S]+?\n\}\n/,
  );
  const buildEnvBody = buildEnvMatch ? buildEnvMatch[0] : "";

  it("buildSpawnEnv function is present in source", () => {
    expect(buildEnvBody.length).toBeGreaterThan(0);
  });

  describe("positive class — base vars MUST be allowlisted", () => {
    it.each([
      "PATH",
      "HOME",
      "NODE_ENV",
      "ANTHROPIC_API_KEY",
    ])("allowlist contains %s", (key) => {
      expect(buildEnvBody).toContain(`${key}: process.env.${key}`);
    });

    it("allowlist contains GH_TOKEN from installationToken", () => {
      expect(buildEnvBody).toContain("GH_TOKEN: installationToken");
    });
  });

  describe("negative class — sensitive vars MUST NOT be allowlisted", () => {
    it.each([
      ["DOPPLER_TOKEN", "Doppler service token; full secrets-read on prd"],
      [
        "GITHUB_APP_PRIVATE_KEY",
        "GitHub App PEM; full repo write across installations",
      ],
      [
        "SENTRY_AUTH_TOKEN",
        "Sentry write API token; full project access",
      ],
      [
        "SUPABASE_SERVICE_ROLE_KEY",
        "Supabase service role; bypasses RLS",
      ],
      [
        "INNGEST_SIGNING_KEY",
        "Inngest substrate auth; arbitrary event forging",
      ],
      [
        "INNGEST_EVENT_KEY",
        "Inngest substrate auth; arbitrary event forging",
      ],
      ["STRIPE_SECRET_KEY", "Stripe API; payment surface"],
      ["RESEND_API_KEY", "Resend email; impersonation surface"],
      [
        "BYOK_ENCRYPTION_KEY",
        "Symmetric key for user BYOK secrets; full plaintext recovery",
      ],
    ])("allowlist does NOT contain %s (%s)", (key) => {
      expect(buildEnvBody).not.toContain(key);
    });

    it("allowlist does NOT use ...process.env spread (would defeat allowlist)", () => {
      expect(buildEnvBody).not.toMatch(/\.\.\.process\.env/);
    });
  });
});

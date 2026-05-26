// TR9 Phase 2 — cron-growth-audit handler unit tests.
//
// Minimal test coverage focused on load-bearing invariants:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (growth audit, Content Audit, AEO Audit,
//      Technical SEO, Content Plan, tracking issues, MANDATORY FINAL STEP)
//      — original anchors from the GHA prompt that must survive silent
//      paraphrasing.
//   3. Timing constants exported (MAX_TURN_DURATION_MS, KILL_ESCALATION_MS).
//   4. buildSpawnEnv allowlist — positive class (5 base vars) AND negative
//      class (sensitive denylist + spread operator).

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE all ES-module imports below — sets NEXT_PHASE so
// the inngest client's startup-key check short-circuits (same path Next.js
// `next build` uses). Mirrors cron-roadmap-review.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronGrowthAudit,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-growth-audit";

describe("cronGrowthAudit — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronGrowthAudit).toBeDefined();
    expect(typeof cronGrowthAudit).toBe("object");
  });
});

describe("cronGrowthAudit — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 70 minutes (from 75 min GHA timeout minus headroom)", () => {
    expect(MAX_TURN_DURATION_MS).toBe(70 * 60 * 1000);
  });

  it("KILL_ESCALATION_MS is 5 seconds (SIGTERM → SIGKILL grace)", () => {
    expect(KILL_ESCALATION_MS).toBe(5_000);
  });
});

// Source-file-content tests — read the SUT file and assert the prompt
// constant contains the verbatim anchors. Per AGENTS.md
// `cq-test-fixtures-synthesized-only`, we read the production source via
// readFileSync rather than synthesising a parallel prompt fixture.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-growth-audit.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-growth-audit"', "canonical function id"],
    ['cron: "0 7 * * 1"', "Monday 07:00 UTC schedule (staggered from 09:00)"],
    ['event: "cron/growth-audit.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on agent-loop failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("GROWTH_AUDIT_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["growth audit", "audit scope declaration"],
      ["Content Audit", "step 1 header"],
      ["AEO Audit", "step 2 header"],
      ["Technical SEO", "step 3 header"],
      ["Content Plan", "step 4 header"],
      ["tracking issues", "step 5.5 tracking-issue creation"],
      ["MANDATORY FINAL STEP", "persist-via-PR pattern"],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });

  describe("safety-guard anchors (cohort discipline)", () => {
    it.each([
      [
        "Do NOT push directly to main",
        "PR-based commit pattern (no direct main writes)",
      ],
      [
        "git checkout -b",
        "PR branch creation in Persist-via-PR step",
      ],
      [
        "gh pr merge",
        "Persist-via-PR auto-merge",
      ],
      [
        "scheduled-growth-audit",
        "label name for audit issue",
      ],
      [
        "MILESTONE RULE:",
        "milestone enforcement rule keyword",
      ],
      [
        "soleur:growth auditing",
        "growth auditing skill invocation",
      ],
      [
        "soleur:seo-aeo",
        "SEO/AEO audit skill invocation",
      ],
      [
        "knowledge-base/marketing/audits/soleur-ai/",
        "audit report output directory",
      ],
      [
        "knowledge-base/product/roadmap.md",
        "roadmap milestone reference",
      ],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });
});

describe("buildSpawnEnv allowlist (security surface)", () => {
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
  });

  describe("negative class — sensitive vars MUST NOT be allowlisted", () => {
    it.each([
      ["DOPPLER_TOKEN", "Doppler service token; full secrets-read on prd"],
      ["GITHUB_APP_PRIVATE_KEY", "GitHub App PEM; full repo write across installations"],
      ["SENTRY_AUTH_TOKEN", "Sentry write API token; full project access"],
      ["SUPABASE_SERVICE_ROLE_KEY", "Supabase service role; bypasses RLS"],
      ["INNGEST_SIGNING_KEY", "Inngest substrate auth; arbitrary event forging"],
      ["INNGEST_EVENT_KEY", "Inngest substrate auth; arbitrary event forging"],
      ["STRIPE_SECRET_KEY", "Stripe API; payment surface"],
      ["RESEND_API_KEY", "Resend email; impersonation surface"],
      ["BYOK_ENCRYPTION_KEY", "Symmetric key for user BYOK secrets"],
    ])("allowlist does NOT contain %s (%s)", (key) => {
      expect(buildEnvBody).not.toContain(key);
    });

    it("allowlist does NOT use ...process.env spread (would defeat allowlist)", () => {
      expect(buildEnvBody).not.toMatch(/\.\.\.process\.env/);
    });
  });
});

// TR9 Phase-2 — cron-seo-aeo-audit handler unit tests.
//
// Minimal test coverage focused on the invariants the multi-agent review
// flagged as load-bearing:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (seo-aeo, SEO/AEO Audit, scheduled-seo-aeo-audit,
//      Do NOT run git add) — anchors that must
//      survive silent paraphrasing across plan→work→ship cycles.
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
  cronSeoAeoAudit,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-seo-aeo-audit";

describe("cronSeoAeoAudit — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    // Smoke test: the import at the top of this file already drove the
    // module's top-level code; if registration shape were structurally
    // broken (missing trigger, malformed concurrency), it would have
    // thrown during inngest.createFunction at module load.
    expect(cronSeoAeoAudit).toBeDefined();
    expect(typeof cronSeoAeoAudit).toBe("object");
  });
});

describe("cronSeoAeoAudit — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 30 minutes (weekly SEO audit budget)", () => {
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
    "../../../server/inngest/functions/cron-seo-aeo-audit.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-seo-aeo-audit"', "canonical function id"],
    ['cron: "0 11 * * 1"', "Monday 11:00 UTC schedule (staggered)"],
    [
      'event: "cron/seo-aeo-audit.manual-trigger"',
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

describe("SEO_AEO_AUDIT_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["seo-aeo", "skill reference"],
      ["SEO/AEO Audit", "issue title fragment"],
      ["scheduled-seo-aeo-audit", "label / Sentry monitor slug"],
      ["PERSISTENCE: Do NOT run git add", "platform-persistence directive (#5091)"],
      ["opens a PR for your changes", "handler-side persistence note (#5091)"],
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

describe("#4730 — output-aware heartbeat (always-create producer)", () => {
  it("gates the heartbeat on output, not the bare spawn exit code", () => {
    // This cron creates a `[Scheduled] SEO/AEO Audit - <today>` summary issue
    // every run, so a clean exit that produced no artifact must turn the monitor
    // RED (output-aware) instead of false-green. Mirrors the 3 producers wired
    // by PR #4714. The pre-fix line was the forbidden `ok: spawnResult.ok`.
    expect(SUT_SOURCE).not.toContain("ok: spawnResult.ok");
    expect(SUT_SOURCE).toContain("resolveOutputAwareOk(");
    expect(SUT_SOURCE).toContain("runStartedAt");
    expect(SUT_SOURCE).toContain("ok: heartbeatOk");
  });
});

// #5786 — producer-side date-dedup serialization anchor (AC6). The cohort
// behavioral test (cron-cohort-dedup.test.ts) proves the exactly-one-digest
// invariant; that fake-store test serializes by invoking the handler twice in
// sequence, so it CANNOT exercise real Inngest concurrency. This anchors the
// registration's `{ scope: "fn", limit: 1 }` — the serializer BOTH the handler
// dedup and the cohort test's "invocation #2 sees #1's create" depend on.
describe("#5786 producer-side dedup — concurrency serialization anchor (AC6)", () => {
  it('registration concurrency contains { scope: "fn", limit: 1 }', () => {
    expect(SUT_SOURCE).toContain('{ scope: "fn", limit: 1 }');
  });
});

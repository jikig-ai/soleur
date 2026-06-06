// TR9 Phase 2 — cron-content-generator handler unit tests.
//
// Minimal test coverage focused on load-bearing invariants:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (seo-refresh-queue, content-writer,
//      social-distribute, validate-blog-links, MANDATORY FINAL STEP) —
//      original anchors from the GHA prompt that must survive silent
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
  cronContentGenerator,
  ensureContentGeneratorAuditIssue,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-content-generator";
import type { Octokit } from "@octokit/core";

describe("cronContentGenerator — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronContentGenerator).toBeDefined();
    expect(typeof cronContentGenerator).toBe("object");
  });
});

describe("cronContentGenerator — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 55 minutes (from 60 min GHA timeout minus headroom)", () => {
    expect(MAX_TURN_DURATION_MS).toBe(55 * 60 * 1000);
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
    "../../../server/inngest/functions/cron-content-generator.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-content-generator"', "canonical function id"],
    ['cron: "0 10 * * 2,4"', "Tuesday/Thursday 10:00 UTC schedule"],
    ['event: "cron/content-generator.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on agent-loop failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("CONTENT_GENERATOR_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["seo-refresh-queue", "topic queue source"],
      ["content-writer", "article generation skill"],
      ["social-distribute", "distribution content skill"],
      ["validate-blog-links", "link validation script"],
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
        "scheduled-content-generator",
        "label name for audit issue",
      ],
      [
        'MILESTONE RULE:',
        "milestone enforcement rule keyword",
      ],
      [
        '@11ty/eleventy',
        "Eleventy build validation",
      ],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });
});

// ---------------------------------------------------------------------------
// Silence-hole fallback guard (#4960). The handler can terminate without the
// prompt's STEP 6 audit issue (mid-eval crash / API 500 / max-turns kill); the
// `ensure-audit-issue` step creates a self-reported FAILED audit issue so the
// run is never silent and the cron-cloud-task-heartbeat watchdog stays green.
// ---------------------------------------------------------------------------

describe("ensure-audit-issue fallback — source-shape anchors (#4960)", () => {
  it.each([
    ['"ensure-audit-issue"', "handler fallback step id"],
    ["[Scheduled] Content Generator -", "audit-issue title prefix literal"],
    ["scheduled-content-generator", "audit-issue label literal"],
    ["ensure-audit-issue-failed", "reportSilentFallback op for a failed fallback create"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });

  it("fallback step is gated on the output-aware result (heartbeatOk === false)", () => {
    // The create must NOT fire when the prompt already produced an issue.
    expect(SUT_SOURCE).toMatch(/if\s*\(\s*!heartbeatOk\s*\)/);
  });

  it("fallback create is wrapped in try/catch → reportSilentFallback (never throws)", () => {
    const stepMatch = SUT_SOURCE.match(
      /"ensure-audit-issue"[\s\S]+?reportSilentFallback\([\s\S]+?op:\s*"ensure-audit-issue-failed"/,
    );
    expect(stepMatch).not.toBeNull();
  });

  it("does NOT bump the turn budget — --max-turns 50 is unchanged (Deliverable 3)", () => {
    expect(SUT_SOURCE).toContain('"--max-turns",\n  "50",');
  });
});

describe("ensureContentGeneratorAuditIssue — behavioral (injected octokit)", () => {
  const RUN_STARTED_AT = "2026-06-05T15:05:11.992Z";
  const SPAWN = {
    exitCode: 1,
    signal: null,
    abortedByTimeout: false,
    durationMs: 368727,
    stdoutTail: "API Error: 500 Internal server error.",
    stderrTail: "",
  };

  function fakeOctokit(getData: Array<{ title: string }>) {
    const calls: Array<{ route: string; params: Record<string, unknown> }> = [];
    const octokit = {
      request: vi.fn(async (route: string, params: Record<string, unknown>) => {
        calls.push({ route, params });
        if (route.startsWith("GET")) return { data: getData };
        return { data: { number: 9999 } };
      }),
    } as unknown as Octokit;
    return { octokit, calls };
  }

  it("creates exactly one labeled audit issue when none exists in the window", async () => {
    const { octokit, calls } = fakeOctokit([]);
    const res = await ensureContentGeneratorAuditIssue({
      runStartedAt: RUN_STARTED_AT,
      spawnResult: SPAWN,
      octokit,
    });
    expect(res.created).toBe(true);
    const posts = calls.filter((c) => c.route.startsWith("POST"));
    expect(posts).toHaveLength(1);
    expect(posts[0].params.title).toBe(
      "[Scheduled] Content Generator - 2026-06-05",
    );
    expect(posts[0].params.labels).toEqual(["scheduled-content-generator"]);
    // Self-diagnosing body carries the failure evidence.
    expect(String(posts[0].params.body)).toContain("API Error: 500");
    expect(String(posts[0].params.body)).toContain("exitCode");
  });

  it("does NOT double-file when today's audit issue already exists (retries:1 dedup)", async () => {
    const { octokit, calls } = fakeOctokit([
      { title: "[Scheduled] Content Generator - 2026-06-05" },
    ]);
    const res = await ensureContentGeneratorAuditIssue({
      runStartedAt: RUN_STARTED_AT,
      spawnResult: SPAWN,
      octokit,
    });
    expect(res.created).toBe(false);
    expect(calls.filter((c) => c.route.startsWith("POST"))).toHaveLength(0);
  });

  it("dedup is title-PREFIX (a suffixed prompt issue still suppresses the fallback)", async () => {
    const { octokit, calls } = fakeOctokit([
      { title: "[Scheduled] Content Generator - 2026-06-05 (manual)" },
    ]);
    const res = await ensureContentGeneratorAuditIssue({
      runStartedAt: RUN_STARTED_AT,
      spawnResult: SPAWN,
      octokit,
    });
    expect(res.created).toBe(false);
    expect(calls.filter((c) => c.route.startsWith("POST"))).toHaveLength(0);
  });

  it("dedup GET is label-scoped, state:all, explicitly sorted newest-first", async () => {
    const { octokit, calls } = fakeOctokit([]);
    await ensureContentGeneratorAuditIssue({
      runStartedAt: RUN_STARTED_AT,
      spawnResult: SPAWN,
      octokit,
    });
    const get = calls.find((c) => c.route.startsWith("GET"));
    expect(get?.params.labels).toBe("scheduled-content-generator");
    expect(get?.params.state).toBe("all");
    expect(get?.params.sort).toBe("created");
    expect(get?.params.direction).toBe("desc");
  });

  it("scrubs secrets and neutralizes markdown-breakout chars in the issue body", async () => {
    const { octokit, calls } = fakeOctokit([]);
    await ensureContentGeneratorAuditIssue({
      runStartedAt: RUN_STARTED_AT,
      spawnResult: {
        ...SPAWN,
        // crash-path stderr spilling an Anthropic key + table-breaking chars
        // (incl. a literal backslash-pipe to exercise escape-order, js/incomplete-sanitization)
        stderrTail: "boom sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAA \\| pipe `tick`",
      },
      octokit,
    });
    const body = String(
      calls.find((c) => c.route.startsWith("POST"))!.params.body,
    );
    expect(body).not.toContain("sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAA");
    expect(body).toContain("[redacted-key]");
    // table-breaking chars are escaped/neutralized inside the inline-code cell:
    // backslash is escaped FIRST (js/incomplete-sanitization) so an input `\|`
    // becomes `\\\|` (escaped backslash + escaped pipe), pipe → "\|" (markdown
    // literal, no row break), backtick → "ʼ" (no span break).
    expect(body).toContain("\\\\\\| pipe"); // input `\| ` → `\\\| `
    expect(body).toContain("ʼtickʼ");
    expect(body).not.toContain("`tick`");
  });

  it("propagates a create failure to the caller (handler wraps it in reportSilentFallback)", async () => {
    const octokit = {
      request: vi.fn(async (route: string) => {
        if (route.startsWith("GET")) return { data: [] };
        throw new Error("GitHub 503");
      }),
    } as unknown as Octokit;
    await expect(
      ensureContentGeneratorAuditIssue({
        runStartedAt: RUN_STARTED_AT,
        spawnResult: SPAWN,
        octokit,
      }),
    ).rejects.toThrow("GitHub 503");
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

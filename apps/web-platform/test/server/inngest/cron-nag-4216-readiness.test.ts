// TR9 Phase 2 T9 — cron-nag-4216-readiness handler unit tests.
//
// Covers: happy path (issue open → nag posted), skip path (issue closed),
// constants match GHA workflow, registration shape, and source-shape anchors.

import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

// --- Module mocks (hoisted by vitest) ----------------------------------------

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

const octokitRequestSpy = vi.fn();
vi.mock("@octokit/core", () => ({
  Octokit: vi.fn(() => ({ request: octokitRequestSpy })),
}));

vi.mock("@/server/github/probe-octokit", () => ({
  createProbeOctokit: vi.fn(async () => ({ request: octokitRequestSpy })),
}));

vi.mock("@/server/github-app", () => ({
  generateInstallationToken: vi.fn(async () => "ghs_test_token_1234567890"),
}));

// --- Helpers -----------------------------------------------------------------

interface MockStep {
  calls: { name: string; result: unknown }[];
  run<T>(name: string, cb: () => Promise<T>): Promise<T>;
}

function makeStep(): MockStep {
  const calls: { name: string; result: unknown }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      const result = await cb();
      calls.push({ name, result });
      return result;
    },
  };
}

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

const ORIGINAL_ENV = {
  SENTRY_INGEST_DOMAIN: process.env.SENTRY_INGEST_DOMAIN,
  SENTRY_PROJECT_ID: process.env.SENTRY_PROJECT_ID,
  SENTRY_PUBLIC_KEY: process.env.SENTRY_PUBLIC_KEY,
  GITHUB_APP_ID: process.env.GITHUB_APP_ID,
  GITHUB_APP_PRIVATE_KEY: process.env.GITHUB_APP_PRIVATE_KEY,
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_DEV: process.env.INNGEST_DEV,
};

function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) delete process.env[key];
  else process.env[key] = ORIGINAL_ENV[key];
}

beforeEach(() => {
  vi.resetModules();
  reportSilentFallbackSpy.mockReset();
  octokitRequestSpy.mockReset();
  octokitRequestSpy.mockImplementation(async (route: string) => {
    if (route === "GET /repos/{owner}/{repo}/installation")
      return { data: { id: 12345 } };
    return { data: {} };
  });
  logger.info.mockReset();
  logger.warn.mockReset();
  logger.error.mockReset();
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("", { status: 202 })));

  process.env.SENTRY_INGEST_DOMAIN = "ingest.sentry.io";
  process.env.SENTRY_PROJECT_ID = "999";
  process.env.SENTRY_PUBLIC_KEY = "abc123def4567890abc123def4567890";
  process.env.GITHUB_APP_ID = "12345";
  process.env.GITHUB_APP_PRIVATE_KEY =
    "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----";
  process.env.INNGEST_SIGNING_KEY =
    "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY =
    "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  process.env.INNGEST_DEV = "1";
});

afterEach(() => {
  vi.unstubAllGlobals();
  (Object.keys(ORIGINAL_ENV) as Array<keyof typeof ORIGINAL_ENV>).forEach(
    restoreEnv,
  );
});

async function importHandler() {
  return await import(
    "@/server/inngest/functions/cron-nag-4216-readiness"
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("exported constants match GHA workflow", () => {
  it("ISSUE_NUMBER is 4216", async () => {
    const { ISSUE_NUMBER } = await importHandler();
    expect(ISSUE_NUMBER).toBe(4216);
  });

  it("PR_I_MERGE_DATE is 2026-05-21", async () => {
    const { PR_I_MERGE_DATE } = await importHandler();
    expect(PR_I_MERGE_DATE).toBe("2026-05-21");
  });
});

describe("cronNag4216ReadinessHandler — issue is OPEN", () => {
  it("posts readiness nag comment and returns ok: true", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}")
        return { data: { state: "open" } };
      if (route === "GET /repos/{owner}/{repo}/installation")
        return { data: { id: 12345 } };
      return { data: {} };
    });

    const { cronNag4216ReadinessHandler } = await importHandler();
    const step = makeStep();
    const out = await cronNag4216ReadinessHandler({ step, logger });

    expect(out.ok).toBe(true);
    expect(out.skipped).toBeUndefined();
    expect(out.daysSince).toBeGreaterThanOrEqual(0);

    // Verify comment was posted
    const comments = octokitRequestSpy.mock.calls.filter(
      ([route]: [string]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(comments.length).toBe(1);
    expect(comments[0]![1]).toMatchObject({ issue_number: 4216 });
    // Verify comment body contains expected content
    const commentBody = comments[0]![1].body as string;
    expect(commentBody).toContain("Weekly readiness check");
    expect(commentBody).toContain("PR-I (#4078) merged");
    expect(commentBody).toContain("draft_one_click");
    expect(commentBody).toContain("Misclassification signal");
    expect(commentBody).toContain("/soleur:go #4216");
  });

  it("step ordering: mint → check-and-nag → sentry-heartbeat", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}")
        return { data: { state: "open" } };
      if (route === "GET /repos/{owner}/{repo}/installation")
        return { data: { id: 12345 } };
      return { data: {} };
    });

    const { cronNag4216ReadinessHandler } = await importHandler();
    const step = makeStep();
    await cronNag4216ReadinessHandler({ step, logger });

    const names = step.calls.map((c) => c.name);
    expect(names).toEqual([
      "mint-installation-token",
      "check-and-nag",
      "sentry-heartbeat",
    ]);
  });
});

describe("cronNag4216ReadinessHandler — issue is CLOSED", () => {
  it("skips nag and returns ok: true, skipped: true", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}")
        return { data: { state: "closed" } };
      if (route === "GET /repos/{owner}/{repo}/installation")
        return { data: { id: 12345 } };
      return { data: {} };
    });

    const { cronNag4216ReadinessHandler } = await importHandler();
    const step = makeStep();
    const out = await cronNag4216ReadinessHandler({ step, logger });

    expect(out.ok).toBe(true);
    expect(out.skipped).toBe(true);

    // No comment posted
    const comments = octokitRequestSpy.mock.calls.filter(
      ([route]: [string]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(comments.length).toBe(0);
  });
});

describe("cronNag4216ReadinessHandler — API error", () => {
  it("returns ok: false when issue fetch fails", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}")
        throw new Error("API unavailable");
      if (route === "GET /repos/{owner}/{repo}/installation")
        return { data: { id: 12345 } };
      return { data: {} };
    });

    const { cronNag4216ReadinessHandler } = await importHandler();
    const step = makeStep();
    const out = await cronNag4216ReadinessHandler({ step, logger });

    expect(out.ok).toBe(false);
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
  });
});

describe("cronNag4216Readiness — registration shape", () => {
  it("function id is cron-nag-4216-readiness", async () => {
    const mod = await importHandler();
    const fn = mod.cronNag4216Readiness as unknown as {
      id: () => string;
      opts: { id: string };
    };
    const id = typeof fn.id === "function" ? fn.id() : fn.opts.id;
    expect(id).toContain("cron-nag-4216-readiness");
  });
});

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-nag-4216-readiness.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-nag-4216-readiness"', "canonical function id"],
    ['cron: "0 14 * * 1"', "weekly Monday 14:00 schedule"],
    [
      'event: "cron/nag-4216-readiness.manual-trigger"',
      "manual trigger event",
    ],
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
    ["ISSUE_NUMBER = 4216", "tracked issue number"],
    ['PR_I_MERGE_DATE = "2026-05-21"', "PR-I merge date"],
    ["postSentryHeartbeat", "Sentry cron monitor heartbeat"],
    ["reportSilentFallback", "error reporting"],
    ["mintInstallationToken", "GH installation token minting"],
    ["Weekly readiness check", "nag comment heading"],
    ["draft_one_click", "readiness criterion 1"],
    ["Misclassification signal", "readiness criterion 2"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

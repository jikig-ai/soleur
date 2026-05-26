// TR9 Phase 2 T8 — cron-linkedin-token-check handler unit tests.
//
// Covers: happy path (both tokens valid), skip path (tokens unset),
// expired-token issue filing, stale-issue closure, JSON validation guard,
// registration shape, and source-shape anchors.

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
  LINKEDIN_ACCESS_TOKEN: process.env.LINKEDIN_ACCESS_TOKEN,
  LINKEDIN_ORG_ACCESS_TOKEN: process.env.LINKEDIN_ORG_ACCESS_TOKEN,
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
    if (route === "GET /search/issues") return { data: { items: [] } };
    if (route === "GET /repos/{owner}/{repo}/installation")
      return { data: { id: 12345 } };
    return { data: {} };
  });
  logger.info.mockReset();
  logger.warn.mockReset();
  logger.error.mockReset();
  vi.stubGlobal("fetch", vi.fn());

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
  // Default: both tokens set
  process.env.LINKEDIN_ACCESS_TOKEN = "test-personal-token";
  process.env.LINKEDIN_ORG_ACCESS_TOKEN = "test-org-token";
});

afterEach(() => {
  vi.unstubAllGlobals();
  (Object.keys(ORIGINAL_ENV) as Array<keyof typeof ORIGINAL_ENV>).forEach(
    restoreEnv,
  );
});

async function importHandler() {
  return await import(
    "@/server/inngest/functions/cron-linkedin-token-check"
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("cronLinkedinTokenCheckHandler — both tokens valid", () => {
  it("returns ok: true when both tokens get 200", async () => {
    const fetchSpy = vi.fn().mockImplementation((url: string) => {
      if (url === "https://api.linkedin.com/v2/userinfo") {
        return Promise.resolve(
          new Response(JSON.stringify({ name: "Test User" }), { status: 200 }),
        );
      }
      // Sentry heartbeat
      return Promise.resolve(new Response("", { status: 202 }));
    });
    vi.stubGlobal("fetch", fetchSpy);

    const { cronLinkedinTokenCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await cronLinkedinTokenCheckHandler({ step, logger });
    expect(out.ok).toBe(true);
    expect(out.results).toHaveLength(2);
    expect(out.results[0].status).toBe("valid");
    expect(out.results[1].status).toBe("valid");
  });

  it("step ordering: mint → check-tokens → sentry-heartbeat", async () => {
    const fetchSpy = vi.fn().mockImplementation((url: string) => {
      if (url === "https://api.linkedin.com/v2/userinfo") {
        return Promise.resolve(
          new Response(JSON.stringify({ name: "Test" }), { status: 200 }),
        );
      }
      return Promise.resolve(new Response("", { status: 202 }));
    });
    vi.stubGlobal("fetch", fetchSpy);

    const { cronLinkedinTokenCheckHandler } = await importHandler();
    const step = makeStep();
    await cronLinkedinTokenCheckHandler({ step, logger });
    const names = step.calls.map((c) => c.name);
    expect(names).toEqual([
      "mint-installation-token",
      "check-tokens",
      "sentry-heartbeat",
    ]);
  });
});

describe("cronLinkedinTokenCheckHandler — tokens unset (skip path)", () => {
  it("skips when both tokens are unset", async () => {
    delete process.env.LINKEDIN_ACCESS_TOKEN;
    delete process.env.LINKEDIN_ORG_ACCESS_TOKEN;

    const fetchSpy = vi.fn().mockResolvedValue(new Response("", { status: 202 }));
    vi.stubGlobal("fetch", fetchSpy);

    const { cronLinkedinTokenCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await cronLinkedinTokenCheckHandler({ step, logger });
    expect(out.ok).toBe(true);
    expect(out.results[0].status).toBe("skipped");
    expect(out.results[1].status).toBe("skipped");
  });
});

describe("cronLinkedinTokenCheckHandler — expired token (401)", () => {
  it("files issue when token returns 401", async () => {
    const fetchSpy = vi.fn().mockImplementation((url: string) => {
      if (url === "https://api.linkedin.com/v2/userinfo") {
        return Promise.resolve(new Response("Unauthorized", { status: 401 }));
      }
      return Promise.resolve(new Response("", { status: 202 }));
    });
    vi.stubGlobal("fetch", fetchSpy);

    const { cronLinkedinTokenCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await cronLinkedinTokenCheckHandler({ step, logger });
    expect(out.ok).toBe(false);
    expect(out.results[0].status).toBe("expired");

    // Should have filed issues for both expired tokens
    const issueCreates = octokitRequestSpy.mock.calls.filter(
      ([route]: any[]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(issueCreates.length).toBe(2);
    expect(issueCreates[0]![1]).toMatchObject({
      title:
        "[Action Required] LinkedIn OAuth token has expired (LINKEDIN_ACCESS_TOKEN)",
      labels: ["action-required"],
    });
  });

  it("comments on existing issue instead of creating new one", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues")
        return { data: { items: [{ number: 5555 }] } };
      if (route === "GET /repos/{owner}/{repo}/installation")
        return { data: { id: 12345 } };
      return { data: {} };
    });

    const fetchSpy = vi.fn().mockImplementation((url: string) => {
      if (url === "https://api.linkedin.com/v2/userinfo") {
        return Promise.resolve(new Response("Unauthorized", { status: 401 }));
      }
      return Promise.resolve(new Response("", { status: 202 }));
    });
    vi.stubGlobal("fetch", fetchSpy);

    const { cronLinkedinTokenCheckHandler } = await importHandler();
    const step = makeStep();
    await cronLinkedinTokenCheckHandler({ step, logger });

    const comments = octokitRequestSpy.mock.calls.filter(
      ([route]: any[]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    const creates = octokitRequestSpy.mock.calls.filter(
      ([route]: any[]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(comments.length).toBeGreaterThanOrEqual(2);
    expect(creates.length).toBe(0);
  });
});

describe("cronLinkedinTokenCheckHandler — stale issue closure on recovery", () => {
  it("closes stale renewal issue when token is valid", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues")
        return { data: { items: [{ number: 7777 }] } };
      if (route === "GET /repos/{owner}/{repo}/installation")
        return { data: { id: 12345 } };
      return { data: {} };
    });

    const fetchSpy = vi.fn().mockImplementation((url: string) => {
      if (url === "https://api.linkedin.com/v2/userinfo") {
        return Promise.resolve(
          new Response(JSON.stringify({ name: "Valid User" }), { status: 200 }),
        );
      }
      return Promise.resolve(new Response("", { status: 202 }));
    });
    vi.stubGlobal("fetch", fetchSpy);

    const { cronLinkedinTokenCheckHandler } = await importHandler();
    const step = makeStep();
    await cronLinkedinTokenCheckHandler({ step, logger });

    const patches = octokitRequestSpy.mock.calls.filter(
      ([route]: any[]) =>
        route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
    );
    expect(patches.length).toBeGreaterThanOrEqual(1);
    expect(patches[0]![1]).toMatchObject({
      issue_number: 7777,
      state: "closed",
    });
  });
});

describe("checkToken — JSON validation guard", () => {
  it("returns invalid_json when response is not valid JSON", async () => {
    const fetchSpy = vi.fn().mockImplementation((url: string) => {
      if (url === "https://api.linkedin.com/v2/userinfo") {
        return Promise.resolve(
          new Response("<html>Service Unavailable</html>", {
            status: 200,
            headers: { "content-type": "text/html" },
          }),
        );
      }
      return Promise.resolve(new Response("", { status: 202 }));
    });
    vi.stubGlobal("fetch", fetchSpy);

    const { checkToken } = await importHandler();
    const mockOctokit = { request: octokitRequestSpy } as unknown as import("@octokit/core").Octokit;
    const result = await checkToken(
      "LINKEDIN_ACCESS_TOKEN",
      "test-token",
      mockOctokit,
    );
    expect(result.status).toBe("invalid_json");
  });
});

describe("cronLinkedinTokenCheck — registration shape", () => {
  it("function id is cron-linkedin-token-check", async () => {
    const mod = await importHandler();
    const fn = mod.cronLinkedinTokenCheck as unknown as {
      id: () => string;
      opts: { id: string };
    };
    const id = typeof fn.id === "function" ? fn.id() : fn.opts.id;
    expect(id).toContain("cron-linkedin-token-check");
  });
});

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-linkedin-token-check.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-linkedin-token-check"', "canonical function id"],
    ['cron: "0 11 * * 1"', "weekly Monday 11:00 schedule"],
    [
      'event: "cron/linkedin-token-check.manual-trigger"',
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
    ["LINKEDIN_ACCESS_TOKEN", "personal token env var"],
    ["LINKEDIN_ORG_ACCESS_TOKEN", "org token env var"],
    ["api.linkedin.com/v2/userinfo", "LinkedIn userinfo endpoint"],
    ["postSentryHeartbeat", "Sentry cron monitor heartbeat"],
    ["reportSilentFallback", "error reporting"],
    ["mintInstallationToken", "GH installation token minting"],
    ["checkToken", "exported token check function"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });

  it("does NOT read tokens at module load (no process.env.LINKEDIN at top level)", () => {
    // Ensure token reads are inside the handler, not at module scope.
    // Split source into top-level (before handler function) and handler.
    const handlerStart = SUT_SOURCE.indexOf(
      "export async function cronLinkedinTokenCheckHandler",
    );
    const topLevel = SUT_SOURCE.slice(0, handlerStart);
    expect(topLevel).not.toContain("process.env.LINKEDIN_ACCESS_TOKEN");
    expect(topLevel).not.toContain("process.env.LINKEDIN_ORG_ACCESS_TOKEN");
  });
});

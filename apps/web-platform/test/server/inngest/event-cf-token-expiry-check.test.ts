// TR9 Phase 2 T10 — event-cf-token-expiry-check handler unit tests.
//
// Covers: healthy path (token far from expiry), warning path (token expiring
// soon → issue filed), skip paths (env vars missing, non-JSON response),
// stale issue closure, registration shape, and no-cron/no-Sentry assertions.

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
  Octokit: vi.fn(function (this: Record<string, unknown>) {
    this.request = octokitRequestSpy;
  }),
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

// Helper: create a CF API response with a token expiring in N days from now
function makeCfResponse(daysFromNow: number) {
  const expiresAt = new Date(
    Date.now() + daysFromNow * 86_400_000,
  ).toISOString();
  return {
    result: [
      {
        name: "github-actions-deploy",
        expires_at: expiresAt,
      },
    ],
  };
}

const ORIGINAL_ENV = {
  CF_API_TOKEN: process.env.CF_API_TOKEN,
  CF_ACCOUNT_ID: process.env.CF_ACCOUNT_ID,
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
  // Default: CF env vars set
  process.env.CF_API_TOKEN = "test-cf-api-token";
  process.env.CF_ACCOUNT_ID = "test-cf-account-id";
});

afterEach(() => {
  vi.unstubAllGlobals();
  (Object.keys(ORIGINAL_ENV) as Array<keyof typeof ORIGINAL_ENV>).forEach(
    restoreEnv,
  );
});

async function importHandler() {
  return await import(
    "@/server/inngest/functions/event-cf-token-expiry-check"
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("eventCfTokenExpiryCheckHandler — healthy token (far from expiry)", () => {
  it("returns ok: true with daysRemaining when token is healthy", async () => {
    const cfResp = makeCfResponse(90);
    const fetchSpy = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(cfResp), { status: 200 }),
    );
    vi.stubGlobal("fetch", fetchSpy);

    const { eventCfTokenExpiryCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await eventCfTokenExpiryCheckHandler({ step, logger });
    expect(out.ok).toBe(true);
    expect(out.daysRemaining).toBeGreaterThan(30);
  });

  it("step ordering: mint → check-cf-token (no sentry heartbeat)", async () => {
    const cfResp = makeCfResponse(90);
    const fetchSpy = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(cfResp), { status: 200 }),
    );
    vi.stubGlobal("fetch", fetchSpy);

    const { eventCfTokenExpiryCheckHandler } = await importHandler();
    const step = makeStep();
    await eventCfTokenExpiryCheckHandler({ step, logger });
    const names = step.calls.map((c) => c.name);
    expect(names).toEqual(["mint-installation-token", "check-cf-token"]);
  });
});

describe("eventCfTokenExpiryCheckHandler — token expiring soon", () => {
  it("files issue when daysRemaining <= WARN_DAYS", async () => {
    const cfResp = makeCfResponse(15);
    const fetchSpy = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(cfResp), { status: 200 }),
    );
    vi.stubGlobal("fetch", fetchSpy);

    const { eventCfTokenExpiryCheckHandler, WARN_DAYS } = await importHandler();
    expect(WARN_DAYS).toBe(30);

    const step = makeStep();
    const out = await eventCfTokenExpiryCheckHandler({ step, logger });
    expect(out.ok).toBe(true);
    expect(out.daysRemaining).toBeLessThanOrEqual(WARN_DAYS);

    const issueCreates = octokitRequestSpy.mock.calls.filter(
      ([route]: any[]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(issueCreates.length).toBe(1);
    expect(issueCreates[0]![1]).toMatchObject({
      labels: ["action-required"],
    });
    expect(issueCreates[0]![1].title).toContain(
      "[Action Required] Cloudflare Access token expiring",
    );
  });

  it("comments on existing issue instead of creating new one", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues")
        return { data: { items: [{ number: 8888 }] } };
      if (route === "GET /repos/{owner}/{repo}/installation")
        return { data: { id: 12345 } };
      return { data: {} };
    });

    const cfResp = makeCfResponse(10);
    const fetchSpy = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(cfResp), { status: 200 }),
    );
    vi.stubGlobal("fetch", fetchSpy);

    const { eventCfTokenExpiryCheckHandler } = await importHandler();
    const step = makeStep();
    await eventCfTokenExpiryCheckHandler({ step, logger });

    const comments = octokitRequestSpy.mock.calls.filter(
      ([route]: any[]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    const creates = octokitRequestSpy.mock.calls.filter(
      ([route]: any[]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(comments.length).toBe(1);
    expect(comments[0]![1]).toMatchObject({ issue_number: 8888 });
    expect(creates.length).toBe(0);
  });
});

describe("eventCfTokenExpiryCheckHandler — stale issue closure", () => {
  it("closes stale issue when token is healthy", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues")
        return { data: { items: [{ number: 9999 }] } };
      if (route === "GET /repos/{owner}/{repo}/installation")
        return { data: { id: 12345 } };
      return { data: {} };
    });

    const cfResp = makeCfResponse(90);
    const fetchSpy = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(cfResp), { status: 200 }),
    );
    vi.stubGlobal("fetch", fetchSpy);

    const { eventCfTokenExpiryCheckHandler } = await importHandler();
    const step = makeStep();
    await eventCfTokenExpiryCheckHandler({ step, logger });

    const patches = octokitRequestSpy.mock.calls.filter(
      ([route]: any[]) =>
        route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
    );
    expect(patches.length).toBe(1);
    expect(patches[0]![1]).toMatchObject({
      issue_number: 9999,
      state: "closed",
    });
  });
});

describe("eventCfTokenExpiryCheckHandler — skip paths", () => {
  it("skips when CF_API_TOKEN is unset", async () => {
    delete process.env.CF_API_TOKEN;

    const { eventCfTokenExpiryCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await eventCfTokenExpiryCheckHandler({ step, logger });
    expect(out.ok).toBe(true);
    expect(out.skipped).toBe(true);
    expect(out.reason).toContain("CF_API_TOKEN");
  });

  it("skips when CF_ACCOUNT_ID is unset", async () => {
    delete process.env.CF_ACCOUNT_ID;

    const { eventCfTokenExpiryCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await eventCfTokenExpiryCheckHandler({ step, logger });
    expect(out.ok).toBe(true);
    expect(out.skipped).toBe(true);
    expect(out.reason).toContain("CF_ACCOUNT_ID");
  });

  it("skips when CF API returns non-JSON", async () => {
    const fetchSpy = vi.fn().mockResolvedValue(
      new Response("<html>Rate Limited</html>", { status: 200 }),
    );
    vi.stubGlobal("fetch", fetchSpy);

    const { eventCfTokenExpiryCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await eventCfTokenExpiryCheckHandler({ step, logger });
    expect(out.ok).toBe(true);
    expect(out.skipped).toBe(true);
    expect(out.reason).toBe("invalid_json");
  });

  it("skips when token name not found in response", async () => {
    const fetchSpy = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({ result: [{ name: "other-token", expires_at: "2027-01-01T00:00:00Z" }] }),
        { status: 200 },
      ),
    );
    vi.stubGlobal("fetch", fetchSpy);

    const { eventCfTokenExpiryCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await eventCfTokenExpiryCheckHandler({ step, logger });
    expect(out.ok).toBe(true);
    expect(out.skipped).toBe(true);
    expect(out.reason).toBe("token_not_found");
  });
});

describe("eventCfTokenExpiryCheck — registration shape", () => {
  it("function id is event-cf-token-expiry-check", async () => {
    const mod = await importHandler();
    const fn = mod.eventCfTokenExpiryCheck as unknown as {
      id: () => string;
      opts: { id: string };
    };
    const id = typeof fn.id === "function" ? fn.id() : fn.opts.id;
    expect(id).toContain("event-cf-token-expiry-check");
  });
});

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/event-cf-token-expiry-check.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (event-triggered, no cron)", () => {
  it.each([
    ['id: "event-cf-token-expiry-check"', "canonical function id"],
    [
      'event: "cf-token-expiry-check.manual-trigger"',
      "event trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "single retry on failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });

  it("does NOT contain a cron trigger (event-triggered, no schedule)", () => {
    expect(SUT_SOURCE).not.toMatch(/\bcron:\s*"/);
  });

  it("does NOT contain postSentryHeartbeat (no Sentry cron monitor for events)", () => {
    expect(SUT_SOURCE).not.toContain("postSentryHeartbeat");
  });
});

describe("handler source anchors", () => {
  it.each([
    ["CF_API_TOKEN", "CF API token env var"],
    ["CF_ACCOUNT_ID", "CF account ID env var"],
    ["api.cloudflare.com", "CF API endpoint"],
    ["access/service_tokens", "CF service tokens endpoint"],
    ["github-actions-deploy", "token name constant"],
    ["WARN_DAYS", "warning threshold constant"],
    ["reportSilentFallback", "error reporting (no Sentry cron monitor)"],
    ["mintInstallationToken", "GH installation token minting"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });

  it("WARN_DAYS is exported and equals 30", async () => {
    const { WARN_DAYS } = await importHandler();
    expect(WARN_DAYS).toBe(30);
  });
});

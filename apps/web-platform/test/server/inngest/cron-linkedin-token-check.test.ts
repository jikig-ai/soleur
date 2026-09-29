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

const USERINFO_URL = "https://api.linkedin.com/v2/userinfo";
const ORG_ACLS_URL =
  "https://api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED";

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

function mockLinkedInPerToken(opts: {
  userinfo?: () => Response;
  orgAcls?: () => Response;
}) {
  return vi.fn().mockImplementation((url: string) => {
    if (url === USERINFO_URL) {
      return Promise.resolve(
        opts.userinfo?.() ??
          new Response(JSON.stringify({ name: "Test User" }), { status: 200 }),
      );
    }
    if (url === ORG_ACLS_URL) {
      return Promise.resolve(
        opts.orgAcls?.() ??
          new Response(
            JSON.stringify({
              elements: [
                { organizationalTarget: "urn:li:organization:129094054" },
              ],
            }),
            { status: 200 },
          ),
      );
    }
    // Sentry heartbeat
    return Promise.resolve(new Response("", { status: 202 }));
  });
}

function linkedInFetchUrls(fetchSpy: ReturnType<typeof vi.fn>) {
  return fetchSpy.mock.calls
    .map(([u]: any[]) => String(u))
    .filter((u: string) => new URL(u).host === "api.linkedin.com");
}

describe("cronLinkedinTokenCheckHandler — both tokens valid", () => {
  it("returns ok: true when both tokens get 200, probing each at its per-token endpoint", async () => {
    const fetchSpy = mockLinkedInPerToken({});
    vi.stubGlobal("fetch", fetchSpy);

    const { cronLinkedinTokenCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await cronLinkedinTokenCheckHandler({ step, logger });
    expect(out.ok).toBe(true);
    expect(out.results).toHaveLength(2);
    expect(out.results[0].status).toBe("valid");
    expect(out.results[1].status).toBe("valid");

    // Per-token probe routing: personal -> userinfo, org -> organizationalEntityAcls.
    expect(linkedInFetchUrls(fetchSpy)).toEqual([USERINFO_URL, ORG_ACLS_URL]);
    // ACL payload has no `name` — holder is the administered-org count.
    expect(out.results[1].holder).toBe("1 administered org(s)");
  });

  it("step ordering: mint → check-tokens → sentry-heartbeat", async () => {
    const fetchSpy = mockLinkedInPerToken({});
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
    const fetchSpy = mockLinkedInPerToken({
      userinfo: () => new Response("Unauthorized", { status: 401 }),
      orgAcls: () => new Response("Unauthorized", { status: 401 }),
    });
    vi.stubGlobal("fetch", fetchSpy);

    const { cronLinkedinTokenCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await cronLinkedinTokenCheckHandler({ step, logger });
    expect(out.ok).toBe(false);
    expect(out.results[0].status).toBe("expired");
    expect(out.results[1].status).toBe("expired");

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
    // Renewal steps name the app that can actually mint each token.
    expect(issueCreates[0]![1].body).toContain("clientId=78wtm2wu15iikn");
    expect(issueCreates[1]![1]).toMatchObject({
      title:
        "[Action Required] LinkedIn OAuth token has expired (LINKEDIN_ORG_ACCESS_TOKEN)",
    });
    expect(issueCreates[1]![1].body).toContain("clientId=78s808ujpe6lve");
  });

  it("comments on existing issue instead of creating new one", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues")
        return { data: { items: [{ number: 5555 }] } };
      if (route === "GET /repos/{owner}/{repo}/installation")
        return { data: { id: 12345 } };
      return { data: {} };
    });

    const fetchSpy = mockLinkedInPerToken({
      userinfo: () => new Response("Unauthorized", { status: 401 }),
      orgAcls: () => new Response("Unauthorized", { status: 401 }),
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

    const fetchSpy = mockLinkedInPerToken({});
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

  it("auto-closes an open org-token issue when the ACL probe returns 2xx", async () => {
    octokitRequestSpy.mockImplementation(async (route: string, args: any) => {
      if (route === "GET /search/issues") {
        // Only the org-token issue is open — discriminate on the title query.
        return String(args?.q).includes("LINKEDIN_ORG_ACCESS_TOKEN")
          ? { data: { items: [{ number: 7606 }] } }
          : { data: { items: [] } };
      }
      if (route === "GET /repos/{owner}/{repo}/installation")
        return { data: { id: 12345 } };
      return { data: {} };
    });

    const fetchSpy = mockLinkedInPerToken({});
    vi.stubGlobal("fetch", fetchSpy);

    const { cronLinkedinTokenCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await cronLinkedinTokenCheckHandler({ step, logger });

    expect(out.results[1].status).toBe("valid");
    const comments = octokitRequestSpy.mock.calls.filter(
      ([route, args]: any[]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments" &&
        args?.issue_number === 7606,
    );
    expect(
      comments.some(([, args]: any[]) =>
        String(args?.body).includes("LINKEDIN_ORG_ACCESS_TOKEN is valid"),
      ),
    ).toBe(true);
    const closes = octokitRequestSpy.mock.calls.filter(
      ([route, args]: any[]) =>
        route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}" &&
        args?.issue_number === 7606 &&
        args?.state === "closed",
    );
    expect(closes.length).toBe(1);
  });
});

describe("cronLinkedinTokenCheckHandler — org token wrong-scope (403)", () => {
  it("files the org issue (not unknown) with an HTTP-403-aware body", async () => {
    // Personal token valid, org token 403 on the ACL probe — live but minted
    // without the Community app's org scopes.
    const fetchSpy = mockLinkedInPerToken({
      orgAcls: () => new Response("ACCESS_DENIED", { status: 403 }),
    });
    vi.stubGlobal("fetch", fetchSpy);

    const { cronLinkedinTokenCheckHandler } = await importHandler();
    const step = makeStep();
    const out = await cronLinkedinTokenCheckHandler({ step, logger });

    // Per-token isolation: only the org leg files.
    expect(out.ok).toBe(false);
    expect(out.results[0].status).toBe("valid");
    expect(out.results[1].status).toBe("expired");
    expect(out.results[1].httpStatus).toBe(403);

    const issueCreates = octokitRequestSpy.mock.calls.filter(
      ([route]: any[]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(issueCreates.length).toBe(1);
    expect(issueCreates[0]![1]).toMatchObject({
      title:
        "[Action Required] LinkedIn OAuth token has expired (LINKEDIN_ORG_ACCESS_TOKEN)",
      labels: ["action-required"],
    });
    const body = String(issueCreates[0]![1].body);
    expect(body).toContain("403");
    expect(body).toContain("clientId=78s808ujpe6lve");
  });
});

describe("checkToken — JSON validation guard", () => {
  it("returns invalid_json when response is not valid JSON", async () => {
    const fetchSpy = vi.fn().mockImplementation((url: string) => {
      if (url === USERINFO_URL) {
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

  it("fails loud (unknown + reportSilentFallback) for a tokenName with no configured probe", async () => {
    const fetchSpy = vi.fn().mockResolvedValue(new Response("", { status: 202 }));
    vi.stubGlobal("fetch", fetchSpy);

    const { checkToken } = await importHandler();
    const mockOctokit = { request: octokitRequestSpy } as unknown as import("@octokit/core").Octokit;
    const result = await checkToken(
      "LINKEDIN_FUTURE_TOKEN",
      "test-token",
      mockOctokit,
    );
    expect(result.status).toBe("unknown");
    // A missing table entry must never silently default to an endpoint.
    expect(fetchSpy).not.toHaveBeenCalledWith(
      expect.stringContaining("api.linkedin.com"),
      expect.anything(),
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
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
    ["api.linkedin.com/v2/userinfo", "LinkedIn userinfo endpoint (personal token probe)"],
    [
      "api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED",
      "LinkedIn org-ACL endpoint (org token probe — no openid on the Community app)",
    ],
    ['clientId: "78wtm2wu15iikn"', "Soleur app clientId (personal token probe table entry)"],
    ['clientId: "78s808ujpe6lve"', "Soleur Community app clientId (org token probe table entry)"],
    ["rw_organization_admin", "org-token scope guidance in the renewal runbook body"],
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

// The operator-side renewal script must probe each token at the same endpoint
// the cron uses — a bootstrap "live" pass must imply a cron pass.
const BOOTSTRAP_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../../../knowledge-base/project/specs/feat-linkedin-token-renewal/bootstrap.sh",
  ),
  "utf-8",
);

describe("bootstrap.sh source anchors (per-token probe parity)", () => {
  it.each([
    [
      'TOKEN_GENERATOR_URL_PERSONAL="https://www.linkedin.com/developers/tools/oauth/token-generator?clientId=78wtm2wu15iikn"',
      "personal token generator URL (Soleur app)",
    ],
    [
      'TOKEN_GENERATOR_URL_ORG="https://www.linkedin.com/developers/tools/oauth/token-generator?clientId=78s808ujpe6lve"',
      "org token generator URL (Soleur Community app)",
    ],
    [
      'LINKEDIN_ORG_ACLS="https://api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED"',
      "org ACL probe constant",
    ],
    ["rw_organization_admin", "org-scope guidance (the ACL probe's own requirement)"],
  ])("contains %s (%s)", (anchor) => {
    expect(BOOTSTRAP_SOURCE).toContain(anchor);
  });

  it("token_probe classifies 403 as rejected-with-code, not transport (cron 403 contract parity)", () => {
    expect(BOOTSTRAP_SOURCE).toContain('"$code" == 401 || "$code" == 403');
    expect(BOOTSTRAP_SOURCE).toContain("printf 'rejected %s'");
    expect(BOOTSTRAP_SOURCE).toMatch(/rejected\*\)/);
  });

  it("token_probe is endpoint-parameterized (value + url)", () => {
    expect(BOOTSTRAP_SOURCE).toContain('token_probe "$tok" "$probe_url"');
    expect(BOOTSTRAP_SOURCE).toContain('token_probe "$1" "$2"');
  });

  it("stage_2_org routes the org token through LINKEDIN_ORG_ACLS", () => {
    // `[^|]` keeps the match inside the call — the org stage must pass the ACL
    // probe on its own mint_or_reuse line, not merely contain the URL later.
    expect(BOOTSTRAP_SOURCE).toMatch(
      /mint_or_reuse "LINKEDIN_ORG_ACCESS_TOKEN"[^|]*\$LINKEDIN_ORG_ACLS[^|]*\|\| return 1/,
    );
  });
});

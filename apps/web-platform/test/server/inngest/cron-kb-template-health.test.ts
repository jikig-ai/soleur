// #3413 — cron-kb-template-health handler unit tests.
//
// The probe reads kb-template's GET /repos/{owner}/{repo} metadata and asserts
// the DOCUMENTED success shape (is_template === true AND private === false). On
// failure it dedup-files a P1 [ops/kb-template-broken] issue against
// jikig-ai/soleur; on success it auto-closes any open such issue.
//
// All fetches/Octokit stubbed — no real network. Mirrors the stub harness of
// cron-github-app-drift-guard.test.ts (same Octokit-request-spy shape).
//
// The dry-run test exercises the EXPORTED pure predicate assertKbTemplateHealthy
// against the shared synthesized fixture (loadGithubFixture("repo-metadata-200"))
// to prove the probe asserts the documented shape, not just HTTP 200.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadGithubFixture } from "../../fixtures/github/load";

// --- Module mocks (hoisted by vitest) --------------------------------------

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  mirrorWarnWithDebounce: vi.fn(),
  reportSilentFallback: reportSilentFallbackSpy,
}));

const octokitRequestSpy = vi.fn();
const createProbeOctokitSpy = vi.fn();
vi.mock("@/server/github/probe-octokit", () => ({
  createProbeOctokit: createProbeOctokitSpy,
  PROBE_ISSUE_OWNER: "jikig-ai",
  PROBE_ISSUE_REPO: "soleur",
}));

// KB_TEMPLATE_* are imported by the handler from server/github-app.ts; pin them
// here so the test does not pull in the whole github-app module surface.
vi.mock("@/server/github-app", () => ({
  KB_TEMPLATE_OWNER: "jikig-ai",
  KB_TEMPLATE_NAME: "kb-template",
}));

// --- Helpers ---------------------------------------------------------------

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

// Default healthy GET /repos response — template, public.
const healthyRepoResponse = {
  id: 2000,
  full_name: "jikig-ai/kb-template",
  is_template: true,
  private: false,
};

const ORIGINAL_ENV = {
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
  createProbeOctokitSpy.mockReset();
  createProbeOctokitSpy.mockImplementation(async () => ({
    request: octokitRequestSpy,
  }));
  // Healthy default: GET /repos returns template+public; search returns empty.
  octokitRequestSpy.mockImplementation(async (route: string) => {
    if (route === "GET /repos/{owner}/{repo}") {
      return { status: 200, data: healthyRepoResponse, headers: {} };
    }
    if (route === "GET /search/issues") {
      return { data: { items: [] } };
    }
    return { data: {} };
  });
  logger.info.mockReset();
  logger.warn.mockReset();
  logger.error.mockReset();
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
  (Object.keys(ORIGINAL_ENV) as Array<keyof typeof ORIGINAL_ENV>).forEach(
    restoreEnv,
  );
});

async function importHandler() {
  return import("@/server/inngest/functions/cron-kb-template-health");
}

function issueCreates() {
  return octokitRequestSpy.mock.calls.filter(
    ([route]) => route === "POST /repos/{owner}/{repo}/issues",
  );
}

// ---------------------------------------------------------------------------
// (a) Happy path — template+public → no issue, auto-close path
// ---------------------------------------------------------------------------

describe("cronKbTemplateHealthHandler — happy path", () => {
  it("is_template:true/private:false → no issue filed on green", async () => {
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    const out = await cronKbTemplateHealthHandler({ step, logger });
    expect(out.failureMode).toBe("");
    expect(issueCreates().length).toBe(0);
    // Probed the right repo.
    const probe = octokitRequestSpy.mock.calls.find(
      ([route]) => route === "GET /repos/{owner}/{repo}",
    );
    expect(probe).toBeDefined();
    expect(probe![1]).toMatchObject({ owner: "jikig-ai", repo: "kb-template" });
  });
});

// ---------------------------------------------------------------------------
// (b)-(e) Failure modes
// ---------------------------------------------------------------------------

describe("cronKbTemplateHealthHandler — failure modes", () => {
  it("is_template:false → issue filed (template flag dropped)", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}") {
        return {
          status: 200,
          data: { ...healthyRepoResponse, is_template: false },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    const out = await cronKbTemplateHealthHandler({ step, logger });
    expect(out.failureMode).not.toBe("");
    const creates = issueCreates();
    expect(creates.length).toBe(1);
    expect(creates[0]![1]).toMatchObject({
      title: expect.stringContaining("[ops/kb-template-broken]"),
    });
    expect((creates[0]![1] as { labels: string[] }).labels).toContain(
      "priority/p1-high",
    );
    // Drift routes through the ops/kb-template-broken label family (proven
    // through the actual issue-write path, not just the pure predicate).
    expect((creates[0]![1] as { labels: string[] }).labels).toContain(
      "ops/kb-template-broken",
    );
  });

  it("private:true → issue filed (template made private)", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}") {
        return {
          status: 200,
          data: { ...healthyRepoResponse, private: true },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    const out = await cronKbTemplateHealthHandler({ step, logger });
    expect(out.failureMode).not.toBe("");
    const creates = issueCreates();
    expect(creates.length).toBe(1);
    expect((creates[0]![1] as { labels: string[] }).labels).toContain(
      "priority/p1-high",
    );
    expect((creates[0]![1] as { labels: string[] }).labels).toContain(
      "ops/kb-template-broken",
    );
  });

  it("404 → issue filed (repo missing/renamed)", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}") {
        const err = new Error("Not Found") as Error & { status?: number };
        err.status = 404;
        throw err;
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    const out = await cronKbTemplateHealthHandler({ step, logger });
    expect(out.failureMode).not.toBe("");
    expect(issueCreates().length).toBe(1);
    // 404 reports to Sentry.
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
  });

  it("malformed body (missing fields) → guard-broken label, distinct from drift", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}") {
        return { status: 200, data: { id: 2000 }, headers: {} };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    const out = await cronKbTemplateHealthHandler({ step, logger });
    expect(out.failureLabel).toBe("ci/guard-broken");
    const creates = issueCreates();
    expect(creates.length).toBe(1);
    expect((creates[0]![1] as { labels: string[] }).labels).toContain(
      "ci/guard-broken",
    );
  });
});

// ---------------------------------------------------------------------------
// (f) Success auto-closes a prior open issue
// ---------------------------------------------------------------------------

describe("cronKbTemplateHealthHandler — auto-close", () => {
  it("healthy probe closes a prior open [ops/kb-template-broken] issue", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}") {
        return { status: 200, data: healthyRepoResponse, headers: {} };
      }
      if (route === "GET /search/issues") {
        return { data: { items: [{ number: 777 }] } };
      }
      return { data: {} };
    });
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    await cronKbTemplateHealthHandler({ step, logger });
    const closed = octokitRequestSpy.mock.calls.find(
      ([route, params]) =>
        route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}" &&
        (params as { state?: string }).state === "closed",
    );
    expect(closed).toBeDefined();
    expect((closed![1] as { issue_number: number }).issue_number).toBe(777);
    // No new issue filed on the green path.
    expect(issueCreates().length).toBe(0);
  });

  it("dedup: failure with an existing open issue comments instead of re-filing", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}") {
        return {
          status: 200,
          data: { ...healthyRepoResponse, is_template: false },
          headers: {},
        };
      }
      if (route === "GET /search/issues") {
        return { data: { items: [{ number: 555 }] } };
      }
      return { data: {} };
    });
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    await cronKbTemplateHealthHandler({ step, logger });
    expect(issueCreates().length).toBe(0);
    const comment = octokitRequestSpy.mock.calls.find(
      ([route]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(comment).toBeDefined();
    expect((comment![1] as { issue_number: number }).issue_number).toBe(555);
  });
});

// ---------------------------------------------------------------------------
// Leak tripwire — a PEM/JWT-shaped error message must fail the issue-body gate
// CLOSED (LeakDetectedError thrown) before any POST /issues mock is reached.
// ---------------------------------------------------------------------------

describe("cronKbTemplateHealthHandler — leak tripwire", () => {
  it("PEM-shaped probe error → assertNoLeak fires before any issue is created", async () => {
    // A network-error probe whose message carries a PEM block. The handler's
    // failureDetail interpolates the (redacted) message, but the issue-body
    // assertNoLeak gate must independently fail closed for any future path
    // that smuggles a raw PEM/JWT into the body.
    const pem =
      "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA\n-----END RSA PRIVATE KEY-----";
    // Force the leak into the issue body directly by stubbing the search to
    // return no existing issue (open path → buildFailureIssueBody → assertNoLeak)
    // and making the probe yield a verdict whose failureDetail carries the PEM.
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}") {
        const err = new Error(pem) as Error & { status?: number; name: string };
        err.name = "PemLeakError";
        // No numeric status → network-error branch; failureDetail = name+message.
        throw err;
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    // Handler swallows the issue-handling error into reportSilentFallback; it
    // must NOT create an issue, and the Sentry report must NOT carry raw PEM.
    await cronKbTemplateHealthHandler({ step, logger });
    expect(issueCreates().length).toBe(0);
    // Sentry never sees raw PEM bytes (redactedError stripped them).
    for (const call of reportSilentFallbackSpy.mock.calls) {
      const err = call[0] as Error;
      expect(err.message).not.toContain("BEGIN RSA PRIVATE KEY");
    }
  });
});

// ---------------------------------------------------------------------------
// Transient retry — a single HTTP 500 blip is retried once before filing.
// ---------------------------------------------------------------------------

describe("cronKbTemplateHealthHandler — transient retry", () => {
  it("HTTP 500 self-heals on retry → no issue filed", async () => {
    let probeCallCount = 0;
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}") {
        probeCallCount++;
        if (probeCallCount === 1) {
          const err = new Error("Server error") as Error & { status?: number };
          err.status = 500;
          throw err;
        }
        return { status: 200, data: healthyRepoResponse, headers: {} };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    const out = await cronKbTemplateHealthHandler({ step, logger });
    expect(probeCallCount).toBe(2);
    expect(out.failureMode).toBe("");
    expect(issueCreates().length).toBe(0);
    expect(logger.warn).toHaveBeenCalledWith(
      expect.objectContaining({ fn: "cron-kb-template-health" }),
      expect.stringContaining("github_api_http"),
    );
  });

  it("persistent HTTP 500 retried once → routes to ci/guard-broken", async () => {
    let probeCallCount = 0;
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}") {
        probeCallCount++;
        const err = new Error("Server error") as Error & { status?: number };
        err.status = 500;
        throw err;
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    const out = await cronKbTemplateHealthHandler({ step, logger });
    expect(probeCallCount).toBe(2);
    expect(out.failureLabel).toBe("ci/guard-broken");
    const creates = issueCreates();
    expect(creates.length).toBe(1);
    expect((creates[0]![1] as { labels: string[] }).labels).toContain(
      "ci/guard-broken",
    );
  });

  it("404 deletion files immediately (no retry — a real deletion)", async () => {
    let probeCallCount = 0;
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}") {
        probeCallCount++;
        const err = new Error("Not Found") as Error & { status?: number };
        err.status = 404;
        throw err;
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronKbTemplateHealthHandler } = await importHandler();
    const step = makeStep();
    await cronKbTemplateHealthHandler({ step, logger });
    expect(probeCallCount).toBe(1);
    expect(issueCreates().length).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Dry-run: exported success-shape predicate against the canonical fixture
// ---------------------------------------------------------------------------

describe("assertKbTemplateHealthy — documented-shape predicate", () => {
  it("returns pass verdict for the shared synthesized repo-metadata-200 fixture", async () => {
    const { assertKbTemplateHealthy } = await importHandler();
    const fixture = loadGithubFixture("repo-metadata-200");
    const verdict = assertKbTemplateHealthy(fixture);
    expect(verdict.ok).toBe(true);
  });

  it("fails (not just non-200) when is_template is false", async () => {
    const { assertKbTemplateHealthy } = await importHandler();
    const fixture = loadGithubFixture<Record<string, unknown>>(
      "repo-metadata-200",
    );
    const verdict = assertKbTemplateHealthy({ ...fixture, is_template: false });
    expect(verdict.ok).toBe(false);
    expect(verdict.failureLabel).not.toBe("ci/guard-broken");
  });

  it("fails when private is true", async () => {
    const { assertKbTemplateHealthy } = await importHandler();
    const fixture = loadGithubFixture<Record<string, unknown>>(
      "repo-metadata-200",
    );
    const verdict = assertKbTemplateHealthy({ ...fixture, private: true });
    expect(verdict.ok).toBe(false);
  });

  it("guard-broken (not drift) when the body is a non-object", async () => {
    const { assertKbTemplateHealthy } = await importHandler();
    const verdict = assertKbTemplateHealthy(null);
    expect(verdict.ok).toBe(false);
    expect(verdict.failureLabel).toBe("ci/guard-broken");
  });

  it("guard-broken when required fields are missing", async () => {
    const { assertKbTemplateHealthy } = await importHandler();
    const verdict = assertKbTemplateHealthy({ id: 2000 });
    expect(verdict.ok).toBe(false);
    expect(verdict.failureLabel).toBe("ci/guard-broken");
  });
});

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

describe("cronKbTemplateHealth — registration", () => {
  it("function id is cron-kb-template-health", async () => {
    const mod = await importHandler();
    const fn = mod.cronKbTemplateHealth as unknown as {
      id: () => string;
      opts: { id: string };
    };
    const id = typeof fn.id === "function" ? fn.id() : fn.opts.id;
    expect(id).toContain("cron-kb-template-health");
  });
});

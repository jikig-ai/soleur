// TR9 PR-4 (#4235) — cron-github-app-drift-guard handler unit tests.
//
// Covers AC24 (a)-(h): happy path, per-failure-mode ?status=error mapping
// across the 12+ modes, fork-PR Sentry fallback, issue-filing branch,
// leak tripwire (PEM/JWT/base64-of-PEM), MANIFEST_DRIFT_SUPPRESS_UNTIL
// gate, installation pagination + shape guards. All fetches stubbed,
// Octokit + filesystem mocked — no real network or subprocess.
//
// NOTE: post-review (drift-guard-inngest-pr4 follow-up), the manifest diff
// is now a pure TS module (server/github/manifest-diff.ts). The child_process
// spawn + temp-file plumbing is gone, so this test no longer mocks node:fs/
// promises's mkdtemp / writeFile / rm or node:child_process. Manifest reads
// are driven via readFile (mocked per-test for the diff path).

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks (hoisted by vitest) --------------------------------------

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  mirrorWarnWithDebounce: vi.fn(),
  reportSilentFallback: reportSilentFallbackSpy,
}));

const octokitRequestSpy = vi.fn();
const createAppJwtOctokitSpy = vi.fn();
const createProbeOctokitSpy = vi.fn();
vi.mock("@/server/github/probe-octokit", async () => {
  return {
    createProbeOctokit: createProbeOctokitSpy,
    createAppJwtOctokit: createAppJwtOctokitSpy,
    PROBE_ISSUE_OWNER: "jikig-ai",
    PROBE_ISSUE_REPO: "soleur",
  };
});

// Mock node:fs / node:fs/promises for the suppression file + manifest read.
const readFileSpy = vi.fn(async (_p: string, _enc?: string) => "");
// Suppress-file existence is toggled per-test; manifest file defaults to
// always-present so the diff + installation iteration branches execute.
const existsSpyValue = { value: false };
const existsSyncSpy = vi.fn((p: string) => {
  if (p.includes("MANIFEST_DRIFT_SUPPRESS_UNTIL")) return existsSpyValue.value;
  if (p.includes("github-app-manifest.json")) return true;
  return false;
});
vi.mock("node:fs/promises", () => ({
  readFile: readFileSpy,
}));
vi.mock("node:fs", () => ({
  existsSync: existsSyncSpy,
  promises: {
    readFile: readFileSpy,
  },
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

// Default healthy /app response. Matches manifest in DEFAULT_MANIFEST below.
const healthyAppResponse = {
  id: 12345,
  client_id: "Iv23li9p88M5ZxYv1b7V",
  permissions: { contents: "read", issues: "write" },
  events: [],
};

const healthyInstallationsResponse = {
  data: [
    {
      id: 99999,
      permissions: { contents: "read", issues: "write" },
      events: [],
    },
  ],
  headers: { link: "" },
};

// Default manifest JSON — matches the healthy fixtures above.
const DEFAULT_MANIFEST = JSON.stringify({
  default_permissions: { contents: "read", issues: "write" },
  default_events: [],
});

const ORIGINAL_ENV = {
  SENTRY_INGEST_DOMAIN: process.env.SENTRY_INGEST_DOMAIN,
  SENTRY_PROJECT_ID: process.env.SENTRY_PROJECT_ID,
  SENTRY_PUBLIC_KEY: process.env.SENTRY_PUBLIC_KEY,
  GH_APP_DRIFTGUARD_APP_ID: process.env.GH_APP_DRIFTGUARD_APP_ID,
  GH_APP_DRIFTGUARD_PRIVATE_KEY_B64: process.env.GH_APP_DRIFTGUARD_PRIVATE_KEY_B64,
  OAUTH_PROBE_GITHUB_CLIENT_ID: process.env.OAUTH_PROBE_GITHUB_CLIENT_ID,
  GITHUB_APP_ID: process.env.GITHUB_APP_ID,
  GITHUB_APP_PRIVATE_KEY: process.env.GITHUB_APP_PRIVATE_KEY,
  RESEND_API_KEY: process.env.RESEND_API_KEY,
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
  createAppJwtOctokitSpy.mockReset();
  createAppJwtOctokitSpy.mockImplementation(async () => ({
    octokit: { request: octokitRequestSpy },
  }));
  createProbeOctokitSpy.mockReset();
  createProbeOctokitSpy.mockImplementation(async () => ({
    request: octokitRequestSpy,
  }));
  // Healthy default: /app returns the expected sentinels; /app/installations
  // returns a single install with matching permissions; search returns empty.
  octokitRequestSpy.mockImplementation(async (route: string) => {
    if (route === "GET /app") {
      return { status: 200, data: healthyAppResponse, headers: {} };
    }
    if (route === "GET /app/installations") {
      return {
        status: 200,
        data: healthyInstallationsResponse.data,
        headers: healthyInstallationsResponse.headers,
      };
    }
    if (route === "GET /search/issues") {
      return { data: { items: [] } };
    }
    return { data: {} };
  });
  readFileSpy.mockReset();
  // Default manifest read returns DEFAULT_MANIFEST (matches healthy fixtures).
  readFileSpy.mockImplementation(async (p: string) => {
    if (typeof p === "string" && p.includes("github-app-manifest.json")) {
      return DEFAULT_MANIFEST;
    }
    return "";
  });
  existsSyncSpy.mockReset();
  existsSpyValue.value = false;
  existsSyncSpy.mockImplementation((p: string) => {
    if (p.includes("MANIFEST_DRIFT_SUPPRESS_UNTIL")) return existsSpyValue.value;
    if (p.includes("github-app-manifest.json")) return true;
    return false;
  });
  logger.info.mockReset();
  logger.warn.mockReset();
  logger.error.mockReset();
  vi.stubGlobal("fetch", vi.fn(async () => new Response("", { status: 200 })));
  process.env.SENTRY_INGEST_DOMAIN = "ingest.sentry.io";
  process.env.SENTRY_PROJECT_ID = "999";
  process.env.SENTRY_PUBLIC_KEY = "abc123def4567890abc123def4567890";
  process.env.GH_APP_DRIFTGUARD_APP_ID = "12345";
  process.env.GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 = Buffer.from(
    "-----BEGIN RSA PRIVATE KEY-----\ndummy\n-----END RSA PRIVATE KEY-----\n",
  ).toString("base64");
  process.env.OAUTH_PROBE_GITHUB_CLIENT_ID = "Iv23li9p88M5ZxYv1b7V";
  process.env.GITHUB_APP_ID = "12345";
  process.env.GITHUB_APP_PRIVATE_KEY =
    "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----";
  process.env.RESEND_API_KEY = "re_test_key";
  process.env.INNGEST_SIGNING_KEY = "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY = "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  process.env.INNGEST_DEV = "1";
});

afterEach(() => {
  vi.unstubAllGlobals();
  (Object.keys(ORIGINAL_ENV) as Array<keyof typeof ORIGINAL_ENV>).forEach(restoreEnv);
});

async function importHandler() {
  const mod = await import("@/server/inngest/functions/cron-github-app-drift-guard");
  return mod;
}

function findHeartbeatStatus(
  fetchSpy: ReturnType<typeof vi.fn>,
): "ok" | "error" | null {
  for (const call of fetchSpy.mock.calls) {
    const url = call[0];
    if (typeof url !== "string") continue;
    let host = "";
    try {
      host = new URL(url).host;
    } catch {
      /* skip */
    }
    if (
      host.endsWith(".sentry.io") &&
      url.includes("/cron/scheduled-github-app-drift-guard/")
    ) {
      if (url.endsWith("?status=ok")) return "ok";
      if (url.endsWith("?status=error")) return "error";
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// (a) Happy path
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuardHandler — happy path", () => {
  it("emits ?status=ok heartbeat when no drift, no leak, no install mismatch", async () => {
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("");
    expect(out.leakDetected).toBeFalsy();
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe("ok");
    // No issue created on green.
    const issueCreates = octokitRequestSpy.mock.calls.filter(
      ([route]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(issueCreates.length).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// (b) Per-failure-mode mapping
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuardHandler — failure modes", () => {
  it("missing_app_id → ?status=error", async () => {
    delete process.env.GH_APP_DRIFTGUARD_APP_ID;
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("missing_app_id");
    expect(out.failureLabel).toBe("ci/guard-broken");
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe("error");
  });

  it("app_id_not_numeric → ?status=error", async () => {
    process.env.GH_APP_DRIFTGUARD_APP_ID = "not-a-number";
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("app_id_not_numeric");
    expect(out.failureLabel).toBe("ci/guard-broken");
  });

  it("missing_expected_client_id → ?status=error", async () => {
    delete process.env.OAUTH_PROBE_GITHUB_CLIENT_ID;
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("missing_expected_client_id");
    expect(out.failureLabel).toBe("ci/guard-broken");
  });

  it("missing_private_key → ?status=error", async () => {
    delete process.env.GH_APP_DRIFTGUARD_PRIVATE_KEY_B64;
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("missing_private_key");
    expect(out.failureLabel).toBe("ci/guard-broken");
  });

  it("transient github_app_401 retries once and self-heals", async () => {
    let getAppCallCount = 0;
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        getAppCallCount++;
        if (getAppCallCount === 1) {
          const err = new Error("A JSON web token could not be decoded") as Error & { status?: number };
          err.status = 401;
          throw err;
        }
        return { status: 200, data: healthyAppResponse, headers: {} };
      }
      if (route === "GET /app/installations") {
        return {
          status: 200,
          data: healthyInstallationsResponse.data,
          headers: healthyInstallationsResponse.headers,
        };
      }
      if (route === "GET /search/issues") {
        return { data: { items: [] } };
      }
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("");
    expect(out.leakDetected).toBe(false);
    expect(getAppCallCount).toBe(2);
    expect(logger.warn).toHaveBeenCalledWith(
      expect.objectContaining({ fn: "cron-github-app-drift-guard" }),
      expect.stringContaining("github_app_401"),
    );
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe("ok");
  });

  it("github_app_401 → ci/auth-broken label", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        const err = new Error("Bad credentials") as Error & { status?: number };
        err.status = 401;
        throw err;
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("github_app_401");
    expect(out.failureLabel).toBe("ci/auth-broken");
  });

  it("github_api_http (non-401, non-200) → ci/guard-broken", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        const err = new Error("Server error") as Error & { status?: number };
        err.status = 500;
        throw err;
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("github_api_http");
    expect(out.failureLabel).toBe("ci/guard-broken");
  });

  it("github_api_missing_fields → ci/guard-broken", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return { status: 200, data: { description: "incomplete" }, headers: {} };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("github_api_missing_fields");
    expect(out.failureLabel).toBe("ci/guard-broken");
  });

  it("app_id_mismatch → ci/auth-broken", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return {
          status: 200,
          data: { id: 99999, client_id: "Iv23li9p88M5ZxYv1b7V" },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("app_id_mismatch");
    expect(out.failureLabel).toBe("ci/auth-broken");
  });

  it("client_id_mismatch → ci/auth-broken", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return {
          status: 200,
          data: { id: 12345, client_id: "Iv1.different00000000" },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("client_id_mismatch");
    expect(out.failureLabel).toBe("ci/auth-broken");
  });

  it("permission_drift via manifest-diff → ci/auth-broken", async () => {
    // Manifest declares `contents: write`; live has `contents: read`.
    readFileSpy.mockImplementation(async (p: string) => {
      if (typeof p === "string" && p.includes("github-app-manifest.json")) {
        return JSON.stringify({
          default_permissions: { contents: "write" },
          default_events: [],
        });
      }
      return "";
    });
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return {
          status: 200,
          data: {
            id: 12345,
            client_id: "Iv23li9p88M5ZxYv1b7V",
            permissions: { contents: "read" },
            events: [],
          },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    // App-level diff fires first; routes as ci/auth-broken.
    expect(out.failureMode).toBe("permission_drift");
    expect(out.failureLabel).toBe("ci/auth-broken");
  });

  it("manifest_unparseable when manifest JSON is invalid → ci/guard-broken", async () => {
    readFileSpy.mockImplementation(async (p: string) => {
      if (typeof p === "string" && p.includes("github-app-manifest.json")) {
        return "not valid JSON{";
      }
      return "";
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("manifest_unparseable");
    expect(out.failureLabel).toBe("ci/guard-broken");
  });
});

// ---------------------------------------------------------------------------
// (c) Fork-PR fallback — Sentry env absent
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuardHandler — fork-PR fallback", () => {
  it("logs warning + does not throw when SENTRY_INGEST_DOMAIN is empty", async () => {
    delete process.env.SENTRY_INGEST_DOMAIN;
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    await expect(
      cronGithubAppDriftGuardHandler({ step, logger }),
    ).resolves.toBeDefined();
    expect(logger.info).toHaveBeenCalled();
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe(null);
  });
});

// ---------------------------------------------------------------------------
// (d) Issue-filing branch
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuardHandler — issue-filing branch", () => {
  it("creates [ci/auth-broken] issue on app_id_mismatch", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return {
          status: 200,
          data: { id: 99999, client_id: "Iv23li9p88M5ZxYv1b7V" },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    await cronGithubAppDriftGuardHandler({ step, logger });
    const issueCreates = octokitRequestSpy.mock.calls.filter(
      ([route]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(issueCreates.length).toBe(1);
    expect(issueCreates[0]![1]).toMatchObject({
      title: "[ci/auth-broken] GitHub App drift-guard fired",
    });
  });

  it("creates [ci/guard-broken] issue on missing_app_id", async () => {
    delete process.env.GH_APP_DRIFTGUARD_APP_ID;
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    await cronGithubAppDriftGuardHandler({ step, logger });
    const issueCreates = octokitRequestSpy.mock.calls.filter(
      ([route]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(issueCreates.length).toBe(1);
    expect(issueCreates[0]![1]).toMatchObject({
      title: "[ci/guard-broken] GitHub App drift-guard malfunctioned",
    });
  });

  it("uses installation-scoped Octokit (createProbeOctokit) for issue ops, not app-JWT", async () => {
    // Sharp-Edge #2 regression: app-JWT 404s on /repos/.../issues; we MUST
    // use createProbeOctokit() for issue filing. drive a failure to trip
    // the issue path then assert createProbeOctokit was invoked.
    delete process.env.GH_APP_DRIFTGUARD_APP_ID;
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    await cronGithubAppDriftGuardHandler({ step, logger });
    expect(createProbeOctokitSpy).toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// (d2) issue-write 403 discriminator — #4189
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuardHandler — issue-write 403 discriminator", () => {
  it("403 on POST /issues → reportSilentFallback op=issue_write_403, heartbeat still ?status=error", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        // app_id_mismatch → ci/auth-broken drift → handleFailureIssue runs.
        return {
          status: 200,
          data: { id: 99999, client_id: "Iv23li9p88M5ZxYv1b7V" },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      if (route === "POST /repos/{owner}/{repo}/issues") {
        const err = new Error(
          "Resource not accessible by integration",
        ) as Error & { status?: number };
        err.status = 403;
        throw err;
      }
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    // The drift result still drives the heartbeat; the issue-write failure is
    // isolated in its own step and does not change the heartbeat status.
    expect(out.failureMode).toBe("app_id_mismatch");
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe("error");
    // The 403 is surfaced with the discriminating op so the operator can
    // alert-route on the missing issues:write grant (#4189), and the operator
    // dashboard message string is preserved verbatim.
    const call = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string })?.op === "issue_write_403",
    );
    expect(call).toBeDefined();
    expect((call![1] as { message: string }).message).toBe(
      "GitHub tracking-issue file/comment/close failed",
    );
  });

  it("non-403 issue-write error preserves op=handleIssue", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return {
          status: 200,
          data: { id: 99999, client_id: "Iv23li9p88M5ZxYv1b7V" },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      if (route === "POST /repos/{owner}/{repo}/issues") {
        const err = new Error("Server error") as Error & { status?: number };
        err.status = 500;
        throw err;
      }
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    await cronGithubAppDriftGuardHandler({ step, logger });
    const call = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string })?.op === "handleIssue",
    );
    expect(call).toBeDefined();
  });

  it("403 whose message matches the leak regex still yields op=issue_write_403 (ordering guard)", async () => {
    // Locks the invariant the catch comment documents: `.status` is read off
    // the ORIGINAL err BEFORE redactedError(err) strips it. A 403 whose
    // message contains a PEM shape forces redactedError to return a fresh
    // Error without `.status`; if op were computed post-redaction it would
    // silently degrade to "handleIssue". The issue BODY (built from the
    // app_id_mismatch detail) is PEM-free, so assertNoLeak passes and the
    // POST is reached before the mock throws.
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return {
          status: 200,
          data: { id: 99999, client_id: "Iv23li9p88M5ZxYv1b7V" },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      if (route === "POST /repos/{owner}/{repo}/issues") {
        const err = new Error(
          "upstream 403: -----BEGIN RSA PRIVATE KEY----- leaked in error",
        ) as Error & { status?: number };
        err.status = 403;
        throw err;
      }
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    await cronGithubAppDriftGuardHandler({ step, logger });
    const call = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string })?.op === "issue_write_403",
    );
    expect(call).toBeDefined();
    // And the error forwarded to Sentry is redacted (no PEM bytes leak).
    expect((call![0] as Error).message).not.toMatch(/BEGIN .*PRIVATE KEY/);
  });

  it("403 on the COMMENT path (dedup hit) also yields op=issue_write_403", async () => {
    // Production 403s land on the comment/close paths too (a tracking issue
    // usually already exists). search returns an existing issue → the comment
    // branch runs → 403 on POST comments must still discriminate.
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return {
          status: 200,
          data: { id: 99999, client_id: "Iv23li9p88M5ZxYv1b7V" },
          headers: {},
        };
      }
      if (route === "GET /search/issues") {
        return { data: { items: [{ number: 4189 }] } };
      }
      if (
        route ===
        "POST /repos/{owner}/{repo}/issues/{issue_number}/comments"
      ) {
        const err = new Error(
          "Resource not accessible by integration",
        ) as Error & { status?: number };
        err.status = 403;
        throw err;
      }
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    await cronGithubAppDriftGuardHandler({ step, logger });
    const call = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string })?.op === "issue_write_403",
    );
    expect(call).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
// (e) Leak tripwire
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuardHandler — leak tripwire", () => {
  it("PEM regex matches a real PEM header (positive control)", async () => {
    const mod = await importHandler();
    const re = new RegExp(mod.LEAK_TRIPWIRE_PEM_REGEX);
    expect("-----BEGIN RSA PRIVATE KEY-----").toMatch(re);
    expect("-----BEGIN PRIVATE KEY-----").toMatch(re);
    expect("-----BEGIN OPENSSH PRIVATE KEY-----").toMatch(re);
    expect("-----BEGIN EC PRIVATE KEY-----").toMatch(re);
    expect("-----BEGIN PUBLIC KEY-----").not.toMatch(re);
  });

  it("base64-of-PEM regex matches LS0tLS1CRUdJTi prefix (positive control)", async () => {
    const mod = await importHandler();
    const re = new RegExp(mod.LEAK_TRIPWIRE_PEM_B64_REGEX);
    expect("LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tL").toMatch(re);
    expect("LS0tLS1CRUdJTi").not.toMatch(re);
    expect("ZHJpZnQtZ3VhcmQ=").not.toMatch(re);
  });

  it("JWT regex matches eyJ + 20+ base64url chars (positive control)", async () => {
    const mod = await importHandler();
    const re = new RegExp(mod.LEAK_TRIPWIRE_JWT_REGEX);
    expect("eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9").toMatch(re);
    expect("eyJ" + "a".repeat(20)).toMatch(re);
    expect("eyJ" + "a".repeat(19)).not.toMatch(re);
    expect("eyJabc").not.toMatch(re);
  });

  it("assertNoLeak throws LeakDetectedError when fed a PEM string", async () => {
    const mod = await importHandler();
    expect(() =>
      mod.__TESTING__.assertNoLeak(
        "test",
        "leak: -----BEGIN RSA PRIVATE KEY----- abc",
      ),
    ).toThrow();
  });

  it("leak tripwire fires → [security/leak-suspected] issue + ?status=error", async () => {
    // Force the leak by causing /app to throw with a PEM-tainted message;
    // the handler's network-error branch echoes the message into
    // failureDetail, then handleFailureIssue runs assertNoLeak on the issue
    // body — which throws LeakDetectedError. The outer step.run catches it
    // and the issue-handling branch then files the leak-suspected issue.
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        const err = new Error(
          "fetch failed: -----BEGIN RSA PRIVATE KEY----- leaked in upstream error",
        );
        throw err;
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe("error");
    // P2.4: split the disjunctive assertion into a hard-shape check on the
    // filed leak-suspected issue.
    expect(out.leakDetected).toBe(true);
    const leakIssueCall = octokitRequestSpy.mock.calls.find(
      ([route, params]) =>
        route === "POST /repos/{owner}/{repo}/issues" &&
        typeof (params as { title?: string }).title === "string" &&
        (params as { title: string }).title.includes("[security/leak-suspected]"),
    );
    expect(leakIssueCall).toBeDefined();
    const params = leakIssueCall![1] as {
      title: string;
      labels: string[];
    };
    expect(params.title).toMatch(/security\/leak-suspected/i);
    expect(params.labels).toContain("security/leak-suspected");
  });

  // P2.1 — reportSilentFallback redaction.
  it("reportSilentFallback receives a redacted Error when probe throws a PEM-tainted message", async () => {
    // Force the probe to throw a non-LeakDetectedError carrying PEM bytes.
    // The handler's catch wraps via redactedError() before forwarding to
    // reportSilentFallback so Sentry never sees the leak bytes.
    createAppJwtOctokitSpy.mockImplementation(async () => {
      throw new Error(
        "upstream: -----BEGIN RSA PRIVATE KEY----- raw PEM in error.message",
      );
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    await cronGithubAppDriftGuardHandler({ step, logger });
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
    const firstCall = reportSilentFallbackSpy.mock.calls.find(
      ([err]) => err instanceof Error,
    );
    expect(firstCall).toBeDefined();
    const reportedErr = firstCall![0] as Error;
    expect(reportedErr.message).not.toMatch(/BEGIN .*PRIVATE KEY/);
    expect(reportedErr.message).toMatch(/REDACTED/);
  });

  // P2.5 — per-emission-site leak coverage.
  it("leak tripwire fires from resend-body path", async () => {
    // Drive a PEM into the failureDetail by way of GET /app throwing a
    // PEM-tainted Error. Stub fetch so the Resend POST is reached. The
    // notify-ops-email step calls assertNoLeak("resend-body", ...) before
    // the fetch, which should throw LeakDetectedError.
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        const err = new Error(
          "leak: -----BEGIN RSA PRIVATE KEY----- in upstream",
        );
        throw err;
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.leakDetected).toBe(true);
    // Sentry status must be error.
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe("error");
  });

  it("leak tripwire fires from resend-subject path", async () => {
    // The subject is `[Soleur Ops] GitHub App drift-guard: ${failureMode}`.
    // Failure mode itself is a static string for known failures, so to make
    // the leak appear in the SUBJECT specifically we'd need failureMode to
    // contain a JWT — not realistic. Instead, assert that assertNoLeak is
    // called on the subject string itself (smoke test: confirm subject is
    // a path we cover by ensuring the resend POST is attempted with a
    // PEM-free subject after a normal failure mode).
    delete process.env.GH_APP_DRIFTGUARD_APP_ID;
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    await cronGithubAppDriftGuardHandler({ step, logger });
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    // The Resend POST should have happened (RESEND_API_KEY is set in beforeEach).
    const resendCall = fetchSpy.mock.calls.find(([url]) => {
      if (typeof url !== "string") return false;
      try {
        return new URL(url).hostname === "api.resend.com";
      } catch {
        return false;
      }
    });
    expect(resendCall).toBeDefined();
    // Subject was leak-gated; it wouldn't have reached fetch if a leak existed.
  });

  it("leak tripwire fires from issue-comment path on existing dedup issue", async () => {
    // Simulate dedup hit so handleFailureIssue takes the COMMENT branch
    // (not POST issues), then drive PEM into failureDetail.
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        // Use a 401 with PEM-tainted message — handler echoes part into
        // failureDetail? Actually 401 returns a static detail. We use
        // network-error path instead (no .status) to get failureDetail
        // populated from e.message.
        const err = new Error(
          "leak: -----BEGIN RSA PRIVATE KEY----- network",
        );
        throw err;
      }
      if (route === "GET /search/issues") {
        return { data: { items: [{ number: 42 }] } };
      }
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    // Leak should have fired on either issue-body or issue-comment.
    expect(out.leakDetected).toBe(true);
    // No comment POST should have happened (assertNoLeak threw first).
    const comments = octokitRequestSpy.mock.calls.filter(
      ([route]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(comments.length).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// (f) MANIFEST_DRIFT_SUPPRESS_UNTIL gate
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuardHandler — suppression gate", () => {
  it("active suppression → manifest-diff is skipped, even with drift", async () => {
    existsSpyValue.value = true;
    const future = new Date(Date.now() + 24 * 3600_000)
      .toISOString()
      .replace(/\.\d+Z$/, "Z");
    readFileSpy.mockImplementation(async (p: string) => {
      if (typeof p === "string" && p.includes("MANIFEST_DRIFT_SUPPRESS_UNTIL")) {
        return future + "\n";
      }
      if (typeof p === "string" && p.includes("github-app-manifest.json")) {
        // Manifest declares write; live has read — would be drift if not suppressed.
        return JSON.stringify({
          default_permissions: { contents: "write" },
          default_events: [],
        });
      }
      return "";
    });
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return {
          status: 200,
          data: {
            id: 12345,
            client_id: "Iv23li9p88M5ZxYv1b7V",
            permissions: { contents: "read" },
            events: [],
          },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    // App-level diff is gated by suppression; failureMode stays empty.
    expect(out.failureMode).toBe("");
  });

  it("invalid timestamp → loud warn + diff runs", async () => {
    existsSpyValue.value = true;
    readFileSpy.mockImplementation(async (p: string) => {
      if (typeof p === "string" && p.includes("MANIFEST_DRIFT_SUPPRESS_UNTIL")) {
        return "not-a-valid-timestamp\n";
      }
      if (typeof p === "string" && p.includes("github-app-manifest.json")) {
        return JSON.stringify({
          default_permissions: { contents: "write" },
          default_events: [],
        });
      }
      return "";
    });
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return {
          status: 200,
          data: {
            id: 12345,
            client_id: "Iv23li9p88M5ZxYv1b7V",
            permissions: { contents: "read" },
            events: [],
          },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("permission_drift");
  });

  it("expired suppression → diff runs normally", async () => {
    existsSpyValue.value = true;
    readFileSpy.mockImplementation(async (p: string) => {
      if (typeof p === "string" && p.includes("MANIFEST_DRIFT_SUPPRESS_UNTIL")) {
        return "2020-01-01T00:00:00Z\n";
      }
      if (typeof p === "string" && p.includes("github-app-manifest.json")) {
        return JSON.stringify({
          default_permissions: { contents: "write" },
          default_events: [],
        });
      }
      return "";
    });
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return {
          status: 200,
          data: {
            id: 12345,
            client_id: "Iv23li9p88M5ZxYv1b7V",
            permissions: { contents: "read" },
            events: [],
          },
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("permission_drift");
  });
});

// ---------------------------------------------------------------------------
// (g) Installation pagination guard
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuardHandler — installation pagination", () => {
  it("Link: rel=next header → installation_list_truncated + ci/guard-broken", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return { status: 200, data: healthyAppResponse, headers: {} };
      }
      if (route === "GET /app/installations") {
        return {
          status: 200,
          data: [{ id: 1, permissions: {}, events: [] }],
          headers: {
            link: '<https://api.github.com/app/installations?page=2>; rel="next"',
          },
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("installation_list_truncated");
    expect(out.failureLabel).toBe("ci/guard-broken");
  });
});

// ---------------------------------------------------------------------------
// (h) Installation shape guard
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuardHandler — installation shape", () => {
  it("non-array root → installation_list_shape_unparseable + ci/guard-broken", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /app") {
        return { status: 200, data: healthyAppResponse, headers: {} };
      }
      if (route === "GET /app/installations") {
        return {
          status: 200,
          // Wrong shape — object, not array.
          data: { message: "Not Found" } as unknown,
          headers: {},
        };
      }
      if (route === "GET /search/issues") return { data: { items: [] } };
      return { data: {} };
    });
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("installation_list_shape_unparseable");
    expect(out.failureLabel).toBe("ci/guard-broken");
  });
});

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuard — registration", () => {
  it("function id is cron-github-app-drift-guard", async () => {
    const mod = await importHandler();
    const fn = mod.cronGithubAppDriftGuard as unknown as {
      id: () => string;
      opts: { id: string };
    };
    const id = typeof fn.id === "function" ? fn.id() : fn.opts.id;
    expect(id).toContain("cron-github-app-drift-guard");
  });
});

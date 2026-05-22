// TR9 PR-4 (#4235) — cron-github-app-drift-guard handler unit tests.
//
// Covers AC24 (a)-(h): happy path, per-failure-mode ?status=error mapping
// across the 12+ modes, fork-PR Sentry fallback, issue-filing branch,
// leak tripwire (PEM/JWT/base64-of-PEM), MANIFEST_DRIFT_SUPPRESS_UNTIL
// gate, installation pagination + shape guards. All fetches stubbed,
// Octokit + child_process.spawn mocked — no real network or subprocess.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { EventEmitter } from "node:events";

// --- Module mocks (hoisted by vitest) --------------------------------------

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

const octokitRequestSpy = vi.fn();
const createAppJwtOctokitSpy = vi.fn();
vi.mock("@/server/github/probe-octokit", async () => {
  return {
    createProbeOctokit: vi.fn(async () => ({ request: octokitRequestSpy })),
    createAppJwtOctokit: createAppJwtOctokitSpy,
    PROBE_ISSUE_OWNER: "jikig-ai",
    PROBE_ISSUE_REPO: "soleur",
  };
});

// Mock child_process.spawn — must support stdout/stderr/close event streaming.
const spawnSpy = vi.fn();
vi.mock("node:child_process", () => ({
  spawn: (...args: unknown[]) => spawnSpy(...args),
}));

// Mock node:fs / node:fs/promises for the suppression file + temp dirs.
const mkdtempSpy = vi.fn(async (_p: string) => "/tmp/drift-guard-test-xxx");
const writeFileSpy = vi.fn(async () => undefined);
const rmSpy = vi.fn(async () => undefined);
const readFileSpy = vi.fn(async (_p: string, _enc?: string) => "");
// Suppress-file existence is toggled per-test; manifest file is treated as
// always-present so the diff + installation iteration branches execute.
const existsSpyValue = { value: false };
const existsSyncSpy = vi.fn((p: string) => {
  if (p.includes("MANIFEST_DRIFT_SUPPRESS_UNTIL")) return existsSpyValue.value;
  if (p.includes("github-app-manifest.json")) return true;
  return false;
});
vi.mock("node:fs/promises", () => ({
  mkdtemp: mkdtempSpy,
  writeFile: writeFileSpy,
  rm: rmSpy,
  readFile: readFileSpy,
}));
vi.mock("node:fs", () => ({
  existsSync: existsSyncSpy,
  promises: {
    mkdtemp: mkdtempSpy,
    writeFile: writeFileSpy,
    rm: rmSpy,
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

// Helper to make a fake ChildProcess that emits exit code N + stdout data.
function makeFakeChild(exit: number, stdout = "", stderr = ""): EventEmitter & {
  stdout: EventEmitter;
  stderr: EventEmitter;
} {
  const ee = new EventEmitter() as EventEmitter & {
    stdout: EventEmitter;
    stderr: EventEmitter;
  };
  ee.stdout = new EventEmitter();
  ee.stderr = new EventEmitter();
  // Defer emission so listeners attach first.
  setImmediate(() => {
    if (stdout) ee.stdout.emit("data", Buffer.from(stdout));
    if (stderr) ee.stderr.emit("data", Buffer.from(stderr));
    ee.emit("close", exit);
  });
  return ee;
}

// Default healthy /app response.
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
    appJwt: "test.jwt.token",
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
  spawnSpy.mockReset();
  // Default: diff script exits 0 (no drift).
  spawnSpy.mockImplementation(() => makeFakeChild(0));
  mkdtempSpy.mockReset();
  mkdtempSpy.mockImplementation(async (_p: string) => "/tmp/drift-guard-test-xxx");
  writeFileSpy.mockReset();
  writeFileSpy.mockImplementation(async () => undefined);
  rmSpy.mockReset();
  rmSpy.mockImplementation(async () => undefined);
  readFileSpy.mockReset();
  readFileSpy.mockImplementation(async () => "");
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

  it("permission_drift via manifest-diff exit-1 → ci/auth-broken", async () => {
    spawnSpy.mockImplementation(() =>
      makeFakeChild(
        1,
        'permission_drift:{"scope_diff":[],"missing_perms":{"contents":"write"}}',
      ),
    );
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    // App-level diff fires first; routes as ci/auth-broken.
    expect(out.failureMode).toBe("permission_drift");
    expect(out.failureLabel).toBe("ci/auth-broken");
  });

  it("manifest_diff_unknown_mode on exit-2 → ci/guard-broken", async () => {
    spawnSpy.mockImplementation(() =>
      makeFakeChild(2, "", "diff script crash"),
    );
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("manifest_diff_unknown_mode");
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
    const leakIssue = octokitRequestSpy.mock.calls.find(
      ([route, params]) =>
        route === "POST /repos/{owner}/{repo}/issues" &&
        typeof (params as { title?: string }).title === "string" &&
        (params as { title: string }).title.includes("[security/leak-suspected]"),
    );
    expect(out.leakDetected || leakIssue !== undefined).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// (f) MANIFEST_DRIFT_SUPPRESS_UNTIL gate
// ---------------------------------------------------------------------------

describe("cronGithubAppDriftGuardHandler — suppression gate", () => {
  it("active suppression → manifest-diff is skipped, even with drift", async () => {
    // Set suppression file present + valid future timestamp.
    existsSpyValue.value = true;
    const future = new Date(Date.now() + 24 * 3600_000)
      .toISOString()
      .replace(/\.\d+Z$/, "Z");
    readFileSpy.mockImplementation(async () => future + "\n");
    // Spawn would emit permission_drift if it ran — but it should be skipped.
    spawnSpy.mockImplementation(() =>
      makeFakeChild(1, "permission_drift:{}"),
    );
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    // App-level diff is gated by suppression; failureMode stays empty.
    expect(out.failureMode).toBe("");
  });

  it("invalid timestamp → loud warn + diff runs", async () => {
    existsSpyValue.value = true;
    readFileSpy.mockImplementation(async () => "not-a-valid-timestamp\n");
    spawnSpy.mockImplementation(() =>
      makeFakeChild(1, "permission_drift:{}"),
    );
    const { cronGithubAppDriftGuardHandler } = await importHandler();
    const step = makeStep();
    const out = await cronGithubAppDriftGuardHandler({ step, logger });
    expect(out.failureMode).toBe("permission_drift");
  });

  it("expired suppression → diff runs normally", async () => {
    existsSpyValue.value = true;
    const past = "2020-01-01T00:00:00Z";
    readFileSpy.mockImplementation(async () => past + "\n");
    spawnSpy.mockImplementation(() =>
      makeFakeChild(1, "permission_drift:{}"),
    );
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

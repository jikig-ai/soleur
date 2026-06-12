// PR #4457 — Unit tests for cron-stale-deferred-scope-outs Inngest function.
//
// Mirrors the test scaffolding shape of cron-github-app-drift-guard.test.ts
// (module mocks via vi.mock + reset in beforeEach; octokitRequestSpy fakes
// the GitHub API; reportSilentFallbackSpy verifies the Sentry mirror).
//
// Test coverage (matches the GHA-workflow policy carried verbatim):
//   (a) function is registered in the inngest substrate.
//   (b) dry-run mode lists candidates without commenting or closing.
//   (c) kill-switch label `do-not-autoclose` filters correctly.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks ---------------------------------------------------------

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

const octokitRequestSpy = vi.fn();
const createProbeOctokitSpy = vi.fn();
vi.mock("@/server/github/probe-octokit", async () => ({
  createProbeOctokit: createProbeOctokitSpy,
  PROBE_ISSUE_OWNER: "jikig-ai",
  PROBE_ISSUE_REPO: "soleur",
}));

// --- Helpers --------------------------------------------------------------

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
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_DEV: process.env.INNGEST_DEV,
};

function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) delete process.env[key];
  else process.env[key] = ORIGINAL_ENV[key];
}

function makeIssue(args: {
  number: number;
  updatedAt?: string;
  labels?: string[];
  title?: string;
  state?: string;
}) {
  return {
    number: args.number,
    title: args.title ?? `Issue #${args.number}`,
    updated_at: args.updatedAt ?? "2025-01-01T00:00:00Z",
    state: args.state ?? "open",
    labels: (args.labels ?? []).map((name) => ({ name })),
  };
}

/**
 * octokit's REAL thrown shape for an undici connect timeout: a RequestError
 * (name "HttpError", status 500) whose `.cause` is the raw TypeError, whose
 * own `.cause` carries the undici code. NEVER a bare TypeError — that would
 * let the test pass while isRetryableGithubError still misses the real wrapper
 * (plan AC4 rationale).
 */
function wrappedConnectTimeout(): Error {
  return Object.assign(new Error("fetch failed"), {
    name: "HttpError",
    status: 500,
    cause: Object.assign(new TypeError("fetch failed"), {
      cause: { code: "UND_ERR_CONNECT_TIMEOUT" },
    }),
  });
}

beforeEach(() => {
  vi.resetModules();
  reportSilentFallbackSpy.mockReset();
  octokitRequestSpy.mockReset();
  createProbeOctokitSpy.mockReset();
  createProbeOctokitSpy.mockImplementation(async () => ({
    request: octokitRequestSpy,
  }));
  logger.info.mockReset();
  logger.warn.mockReset();
  logger.error.mockReset();

  // Inngest client loads on import — supply signing/event keys so the
  // module-init guards don't throw during test imports.
  process.env.INNGEST_SIGNING_KEY = "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY = "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  process.env.INNGEST_DEV = "1";
});

afterEach(() => {
  (Object.keys(ORIGINAL_ENV) as Array<keyof typeof ORIGINAL_ENV>).forEach(restoreEnv);
});

async function importModule() {
  return await import(
    "@/server/inngest/functions/cron-stale-deferred-scope-outs"
  );
}

// --------------------------------------------------------------------------
// (a) Registration smoke
// --------------------------------------------------------------------------

describe("cronStaleDeferredScopeOuts — registration", () => {
  it("exports an inngest function with the canonical id", async () => {
    const mod = await importModule();
    expect(mod.cronStaleDeferredScopeOuts).toBeDefined();
    // Inngest InngestFunction exposes its id via .id() in newer SDKs;
    // fall back to the internal `opts.id` if .id() is absent.
    const fn = mod.cronStaleDeferredScopeOuts as unknown as {
      id?: () => string;
      opts?: { id?: string };
    };
    const id = typeof fn.id === "function" ? fn.id() : fn.opts?.id;
    // id may be prefixed with the Inngest app id ("soleur-runtime-")
    // depending on SDK version — accept either shape.
    expect(id).toMatch(/cron-stale-deferred-scope-outs/);
  });

  it("is exported by the registration barrel via importable name", async () => {
    const mod = await importModule();
    expect(typeof mod.cronStaleDeferredScopeOutsHandler).toBe("function");
    expect(mod.__TESTING__.TARGET_LABEL).toBe("deferred-scope-out");
    expect(mod.__TESTING__.KILLSWITCH_LABEL).toBe("do-not-autoclose");
  });
});

// --------------------------------------------------------------------------
// (b) Dry-run mode
// --------------------------------------------------------------------------

describe("cronStaleDeferredScopeOuts — dry-run mode", () => {
  it("lists candidates but does NOT comment or close in dry-run", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues") {
        return {
          data: {
            items: [
              makeIssue({ number: 100 }),
              makeIssue({ number: 101 }),
            ],
          },
        };
      }
      // Any write path is an unexpected call in dry-run.
      throw new Error(`unexpected route in dry-run: ${route}`);
    });

    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();
    const result = await cronStaleDeferredScopeOutsHandler({
      step,
      logger,
      event: { data: { dry_run: true } },
    });

    expect(result.dryRun).toBe(true);
    expect(result.total).toBe(2);
    expect(result.closed).toBe(0);
    expect(result.skipped).toBe(0);

    const writeCalls = octokitRequestSpy.mock.calls.filter(
      ([route]) =>
        route ===
          "POST /repos/{owner}/{repo}/issues/{issue_number}/comments" ||
        route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
    );
    expect(writeCalls).toHaveLength(0);
  });
});

// --------------------------------------------------------------------------
// (c) Kill-switch label filter
// --------------------------------------------------------------------------

describe("cronStaleDeferredScopeOuts — kill-switch label", () => {
  it("skips issues with the do-not-autoclose label", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues") {
        return {
          data: {
            items: [
              makeIssue({
                number: 200,
                labels: ["deferred-scope-out", "do-not-autoclose"],
              }),
              makeIssue({
                number: 201,
                labels: ["deferred-scope-out"],
              }),
            ],
          },
        };
      }
      if (
        route ===
          "POST /repos/{owner}/{repo}/issues/{issue_number}/comments" ||
        route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}"
      ) {
        return { data: {} };
      }
      return { data: {} };
    });

    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();
    const result = await cronStaleDeferredScopeOutsHandler({ step, logger });

    expect(result.total).toBe(2);
    expect(result.skipped).toBe(1);
    expect(result.closed).toBe(1);

    // Verify the comment+close targeted only #201 (the non-killswitched).
    const commentCalls = octokitRequestSpy.mock.calls.filter(
      ([route]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(commentCalls).toHaveLength(1);
    expect(commentCalls[0][1]).toMatchObject({ issue_number: 201 });

    const closeCalls = octokitRequestSpy.mock.calls.filter(
      ([route]) =>
        route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
    );
    expect(closeCalls).toHaveLength(1);
    expect(closeCalls[0][1]).toMatchObject({
      issue_number: 201,
      state: "closed",
      state_reason: "not_planned",
    });
  });
});

// --------------------------------------------------------------------------
// (d) Transient connect-timeout resilience (Sentry 448a4173…)
// --------------------------------------------------------------------------

describe("cronStaleDeferredScopeOuts — connect-timeout resilience", () => {
  it("recovers from a transient search connect timeout without escalating (AC4)", async () => {
    vi.useFakeTimers();
    try {
      let searchAttempts = 0;
      octokitRequestSpy.mockImplementation(async (route: string) => {
        if (route === "GET /search/issues") {
          searchAttempts += 1;
          // First attempt: octokit's real wrapped connect-timeout shape.
          if (searchAttempts === 1) throw wrappedConnectTimeout();
          return {
            data: {
              items: [makeIssue({ number: 300, labels: ["deferred-scope-out"] })],
            },
          };
        }
        // comment + close succeed.
        return { data: {} };
      });

      const { cronStaleDeferredScopeOutsHandler } = await importModule();
      const step = makeStep();
      const p = cronStaleDeferredScopeOutsHandler({ step, logger });
      await vi.runAllTimersAsync();
      const result = await p;

      // (a) sweep completes successfully (handler did NOT throw)
      expect(result.total).toBe(1);
      expect(result.closed).toBe(1);
      // (b) the transient was absorbed — no error-level mirror
      expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
      // (c) the candidate list reflects the SECOND (recovered) response
      expect(searchAttempts).toBe(2);
    } finally {
      vi.useRealTimers();
    }
  });

  it("does NOT retry a genuine 403 on the comment path; surfaces issue_write_403 (AC5)", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues") {
        return {
          data: {
            items: [makeIssue({ number: 400, labels: ["deferred-scope-out"] })],
          },
        };
      }
      if (
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments"
      ) {
        // Non-retryable: a genuine issues:write-missing 403.
        throw Object.assign(new Error("Forbidden"), {
          name: "HttpError",
          status: 403,
        });
      }
      return { data: {} };
    });

    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();
    const result = await cronStaleDeferredScopeOutsHandler({ step, logger });

    // Sweep continues (per-issue catch is the terminal net); nothing closed.
    expect(result.total).toBe(1);
    expect(result.closed).toBe(0);

    // The comment was attempted exactly ONCE (403 is non-retryable → rethrown
    // on attempt 1 straight into the existing per-issue catch).
    const commentCalls = octokitRequestSpy.mock.calls.filter(
      ([route]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(commentCalls).toHaveLength(1);

    // The issue_write_403 discriminator still fires.
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1]).toMatchObject({
      op: "issue_write_403",
    });
  });

  it("re-escalates a SUSTAINED search outage to the handler net (AC6)", async () => {
    vi.useFakeTimers();
    try {
      let searchAttempts = 0;
      octokitRequestSpy.mockImplementation(async (route: string) => {
        if (route === "GET /search/issues") {
          searchAttempts += 1;
          throw wrappedConnectTimeout(); // every attempt fails
        }
        return { data: {} };
      });

      const { cronStaleDeferredScopeOutsHandler } = await importModule();
      const step = makeStep();
      const p = cronStaleDeferredScopeOutsHandler({ step, logger });
      await vi.runAllTimersAsync();

      // Handler rethrows after the heartbeat (Inngest retry preserved).
      await expect(p).rejects.toThrow(/sweep failed/);

      // 3 attempts (1 + MAX_RETRIES) before exhaustion.
      expect(searchAttempts).toBe(3);

      // The sweep-level mirror fired with op:"sweep".
      expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
      expect(reportSilentFallbackSpy.mock.calls[0][1]).toMatchObject({
        op: "sweep",
      });

      // Heartbeat posted ok:false (the sentry-heartbeat step ran before rethrow).
      expect(step.calls.some((c) => c.name === "sentry-heartbeat")).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });
});


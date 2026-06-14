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

// Partial mock of _cron-shared so the Sentry heartbeat is spyable WITHOUT
// nuking the module's siblings (importActual spread preserves HandlerArgs et al).
// Asserting on this spy's `ok` arg is the only reliable signal: a `fetch` spy
// records zero calls (the real postSentryHeartbeat short-circuits on unset Sentry
// env in test), and makeStep().calls carries no `ok` (the heartbeat step returns
// void). See the heartbeat-gating plan §Phase 1.
const postSentryHeartbeatSpy = vi.fn();
vi.mock(
  "@/server/inngest/functions/_cron-shared",
  async (importOriginal) => ({
    ...(await importOriginal<
      typeof import("@/server/inngest/functions/_cron-shared")
    >()),
    postSentryHeartbeat: postSentryHeartbeatSpy,
  }),
);

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
  postSentryHeartbeatSpy.mockReset();
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
        "GET /repos/{owner}/{repo}/issues/{issue_number}/comments"
      ) {
        // No prior auto-close comment present → POST still fires.
        return { data: [] };
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
// (d) Retry-aware heartbeat gating — the "page before retry" fix.
//
// Sentry incident 5468023: a single transient GitHub fault flipped the monitor
// to error because the handler posted the status=error heartbeat on Inngest
// attempt 0, BEFORE the retries:1 retry that would have recovered. The fix gates
// the error heartbeat on the FINAL Inngest attempt. attempt is zero-indexed;
// retries:1 → maxAttempts:2 → final attempt is 1.
// --------------------------------------------------------------------------

describe("cronStaleDeferredScopeOuts — retry-aware heartbeat gating", () => {
  // A bare `{ status: 500 }` on the search call: NOT a retryable undici/timeout
  // shape (isRetryableGithubError only retries cause-chain network codes — see
  // #5227's github-retry), so withGithubRetry passes it straight through and the
  // sweep throws → flips sweepFailed=true. This exercises the heartbeat-gating
  // path independently of the in-step connect-timeout retry.
  function mockSearchThrows() {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues") {
        throw Object.assign(new Error("boom"), { status: 500 });
      }
      throw new Error(`unexpected route: ${route}`);
    });
  }

  // A clean sweep (empty search result) — sweepFailed stays false.
  function mockSearchEmpty() {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues") {
        return { data: { items: [] } };
      }
      throw new Error(`unexpected route: ${route}`);
    });
  }

  it("A1: non-final attempt throw does NOT post a heartbeat, still rethrows + reports", async () => {
    mockSearchThrows();
    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();

    await expect(
      cronStaleDeferredScopeOutsHandler({
        step,
        logger,
        attempt: 0,
        maxAttempts: 2,
      }),
    ).rejects.toThrow(/sweep failed/);

    // The page is suppressed on a non-final attempt — no heartbeat POST at all
    // (posting `ok` would mask a persistent failure; posting `error` is the bug).
    expect(postSentryHeartbeatSpy).not.toHaveBeenCalled();
    // Forensic breadcrumb is still emitted so the burned attempt is visible.
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
  });

  it("A2: final attempt throw DOES post an error heartbeat and rethrows", async () => {
    mockSearchThrows();
    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();

    await expect(
      cronStaleDeferredScopeOutsHandler({
        step,
        logger,
        attempt: 1,
        maxAttempts: 2,
      }),
    ).rejects.toThrow(/sweep failed/);

    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: false }),
    );
  });

  it("A3: legacy no-attempt call shape pages on failure (backward-compat)", async () => {
    mockSearchThrows();
    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();

    // No attempt/maxAttempts → attempt=0, maxAttempts=1 → isFinalAttempt=true →
    // behaves exactly as before (error heartbeat on failure).
    await expect(
      cronStaleDeferredScopeOutsHandler({ step, logger }),
    ).rejects.toThrow(/sweep failed/);

    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: false }),
    );
    // Distinct fingerprint vs A2 (which shares the ok:false assertion): the
    // legacy shape reads attempt=0, so it must never emit the recovered-flap warn.
    expect(logger.warn).not.toHaveBeenCalledWith(
      expect.objectContaining({ recovered_after_attempts: expect.anything() }),
      expect.anything(),
    );
  });

  it("A6: attempt set but maxAttempts undefined defaults to final (fail-safe paging)", async () => {
    // maxAttempts is OPTIONAL on Inngest's BaseContext. If a fire ever delivers
    // attempt without maxAttempts, isFinalAttempt = attempt >= ((undefined ?? 1)-1)
    // = attempt >= 0 = always true → the cron treats the attempt as final and
    // pages on failure rather than silently suppressing. Lock that safe default.
    mockSearchThrows();
    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();

    await expect(
      cronStaleDeferredScopeOutsHandler({ step, logger, attempt: 1 }),
    ).rejects.toThrow(/sweep failed/);

    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: false }),
    );
  });

  it("A4: success on a non-final attempt still posts an ok heartbeat", async () => {
    mockSearchEmpty();
    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();

    const result = await cronStaleDeferredScopeOutsHandler({
      step,
      logger,
      attempt: 0,
      maxAttempts: 2,
    });

    expect(result.total).toBe(0);
    // Gating must NOT over-reach: a successful non-final check-in still posts ok.
    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
    // attempt 0 success is a clean run — no recovered-flap warn.
    expect(logger.warn).not.toHaveBeenCalledWith(
      expect.objectContaining({ recovered_after_attempts: expect.anything() }),
      expect.anything(),
    );
  });

  it("A5: success on a retry emits the recovered-after-attempts flap signal", async () => {
    mockSearchEmpty();
    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();

    await cronStaleDeferredScopeOutsHandler({
      step,
      logger,
      attempt: 1,
      maxAttempts: 2,
    });

    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
    // A recovered transient is queryable as a trend instead of looking identical
    // to a clean attempt-0 run.
    expect(logger.warn).toHaveBeenCalledWith(
      expect.objectContaining({ recovered_after_attempts: 1 }),
      expect.anything(),
    );
  });
});

// --------------------------------------------------------------------------
// (e) Transient connect-timeout resilience (Sentry 448a4173…)
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
        if (
          route ===
          "GET /repos/{owner}/{repo}/issues/{issue_number}/comments"
        ) {
          // No prior auto-close comment → POST still fires.
          return { data: [] };
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
        route ===
        "GET /repos/{owner}/{repo}/issues/{issue_number}/comments"
      ) {
        // No prior auto-close comment → POST is reached (and 403s below).
        return { data: [] };
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

  it("retries a transient timeout on the comment POST and still closes (AC3 wrapper proof)", async () => {
    vi.useFakeTimers();
    try {
      let commentAttempts = 0;
      octokitRequestSpy.mockImplementation(async (route: string) => {
        if (route === "GET /search/issues") {
          return {
            data: {
              items: [makeIssue({ number: 500, labels: ["deferred-scope-out"] })],
            },
          };
        }
        if (
          route ===
          "GET /repos/{owner}/{repo}/issues/{issue_number}/comments"
        ) {
          // No prior auto-close comment → POST path is exercised.
          return { data: [] };
        }
        if (
          route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments"
        ) {
          commentAttempts += 1;
          // Transient on the FIRST comment attempt, succeed on the second.
          if (commentAttempts === 1) throw wrappedConnectTimeout();
          return { data: {} };
        }
        return { data: {} };
      });

      const { cronStaleDeferredScopeOutsHandler } = await importModule();
      const step = makeStep();
      const p = cronStaleDeferredScopeOutsHandler({ step, logger });
      await vi.runAllTimersAsync();
      const result = await p;

      // The comment was retried (proving the comment POST is wrapped, not just
      // the search) and the issue still closed; no error-level mirror.
      expect(commentAttempts).toBe(2);
      expect(result.closed).toBe(1);
      expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
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
      // Attach the rejection assertion BEFORE advancing timers — the handler
      // rejects DURING runAllTimersAsync, so a late .rejects would surface as
      // an unhandled rejection.
      const rejection = expect(p).rejects.toThrow(/sweep failed/);
      await vi.runAllTimersAsync();
      await rejection;

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

// --------------------------------------------------------------------------
// (f) GET-before-POST comment idempotency guard (issue #5231)
//
// On an Inngest replay the comment POST may already have landed. The guard
// GETs the issue's comments first and, if COMMENT_BODY is already present,
// SKIPS the re-POST — but the close PATCH still fires (close is a no-op when
// the issue is already closed, so re-issuing it is safe and keeps the counter
// advancing on the replay).
// --------------------------------------------------------------------------

describe("cronStaleDeferredScopeOuts — comment idempotency guard", () => {
  it("skips the comment POST when COMMENT_BODY already present, but still closes", async () => {
    const { cronStaleDeferredScopeOutsHandler, __TESTING__ } =
      await importModule();

    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues") {
        return {
          data: {
            items: [makeIssue({ number: 600, labels: ["deferred-scope-out"] })],
          },
        };
      }
      if (
        route ===
        "GET /repos/{owner}/{repo}/issues/{issue_number}/comments"
      ) {
        // The auto-close comment already landed on a prior (replayed) attempt.
        return { data: [{ body: __TESTING__.COMMENT_BODY }] };
      }
      return { data: {} };
    });

    const step = makeStep();
    const result = await cronStaleDeferredScopeOutsHandler({ step, logger });

    // The issue still closes (close is idempotent) and the counter advances.
    expect(result.total).toBe(1);
    expect(result.closed).toBe(1);

    // The POST was SKIPPED — the guard short-circuited the double-comment.
    const commentCalls = octokitRequestSpy.mock.calls.filter(
      ([route]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(commentCalls).toHaveLength(0);

    // The close PATCH still fired exactly once.
    const closeCalls = octokitRequestSpy.mock.calls.filter(
      ([route]) =>
        route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
    );
    expect(closeCalls).toHaveLength(1);
    expect(closeCalls[0][1]).toMatchObject({ issue_number: 600 });

    // No error-level mirror — this is the happy idempotent path.
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });
});


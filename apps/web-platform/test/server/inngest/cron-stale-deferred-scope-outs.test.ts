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
    // The sweep now targets a SET. The original single-label assertions are
    // preserved as membership checks so this test still pins the pre-existing
    // behaviour rather than merely being relaxed to accommodate the change.
    expect(mod.__TESTING__.TARGET_LABELS).toContain("deferred-scope-out");
    expect(mod.__TESTING__.KILLSWITCH_LABELS).toContain("do-not-autoclose");
    expect(mod.__TESTING__.TARGET_LABELS).toContain("meta/machinery");
    expect(mod.__TESTING__.KILLSWITCH_LABELS).toContain("keep-open");
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
      octokitRequestSpy.mockImplementation(async (route: string, params?: { q?: string }) => {
        if (route === "GET /search/issues") {
          // #8076: the run-report arm's per-label searches are not under test
          // here — answer them empty without counting.
          if (String(params?.q ?? "").includes('label:"scheduled-')) return { data: { items: [] } };
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
      octokitRequestSpy.mockImplementation(async (route: string, params?: { q?: string }) => {
        if (route === "GET /search/issues") {
          // #8076: the run-report arm's searches answer empty (not under test).
          if (String(params?.q ?? "").includes('label:"scheduled-')) return { data: { items: [] } };
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
// On a sequential retry the comment POST may already have landed. The guard
// GETs the issue's comments first and, if the COMMENT_MARKER sentinel is already
// present, SKIPS the re-POST — but the close PATCH still fires (close is a no-op when
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

  it("matches the sentinel even when GitHub returns the body with CRLF line endings (no re-POST)", async () => {
    const { cronStaleDeferredScopeOutsHandler, __TESTING__ } =
      await importModule();

    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues") {
        return {
          data: {
            items: [makeIssue({ number: 601, labels: ["deferred-scope-out"] })],
          },
        };
      }
      if (
        route === "GET /repos/{owner}/{repo}/issues/{issue_number}/comments"
      ) {
        // GitHub can store/return multi-line comment bodies with CRLF. The guard
        // matches on COMMENT_MARKER via `includes`, so it must still recognise
        // its own comment here. Full-body `=== COMMENT_BODY` (which is `\n`-joined)
        // would WRONGLY miss this and re-POST — this case is the regression guard
        // for that brittleness.
        const stored = __TESTING__.COMMENT_BODY.replace(/\n/g, "\r\n");
        return { data: [{ body: stored }] };
      }
      return { data: {} };
    });

    const step = makeStep();
    const result = await cronStaleDeferredScopeOutsHandler({ step, logger });

    expect(result.closed).toBe(1);
    const commentCalls = octokitRequestSpy.mock.calls.filter(
      ([route]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(commentCalls).toHaveLength(0);
  });

  it("posts the comment when prior comments exist but none carry the sentinel", async () => {
    const { cronStaleDeferredScopeOutsHandler } = await importModule();

    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues") {
        return {
          data: {
            items: [makeIssue({ number: 602, labels: ["deferred-scope-out"] })],
          },
        };
      }
      if (
        route === "GET /repos/{owner}/{repo}/issues/{issue_number}/comments"
      ) {
        // Realistic steady state: prior human comments, none from the bot.
        return {
          data: [
            { body: "Still relevant — please keep open." },
            { body: ":+1:" },
          ],
        };
      }
      return { data: {} };
    });

    const step = makeStep();
    const result = await cronStaleDeferredScopeOutsHandler({ step, logger });

    expect(result.closed).toBe(1);
    const commentCalls = octokitRequestSpy.mock.calls.filter(
      ([route]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(commentCalls).toHaveLength(1);
  });
});


// --------------------------------------------------------------------------
// (g) The search-query SHAPE.
//
// This asserts the STRING, not the sweep result, and that distinction is the
// whole point. GitHub ANDs multiple `label:` qualifiers and ORs comma-separated
// values inside one. The wrong form --
//     label:"deferred-scope-out" label:"meta/machinery"
// -- matches only issues carrying BOTH, i.e. zero, and the sweep then returns
// {total: 0, closed: 0}, heartbeats `ok`, and logs "Auto-closed 0 stale
// issues", which is byte-identical to a healthy run over a drained backlog.
// No assertion on the RESULT can separate those two states. Only the query can.
// --------------------------------------------------------------------------
describe("cron-stale-deferred-scope-outs — search query shape", () => {
  it("emits ONE comma-joined label qualifier (OR), never repeated qualifiers (AND)", async () => {
    const mod = await importModule();
    const q = mod.__TESTING__.buildSearchQuery({
      owner: "jikig-ai",
      repo: "soleur",
      cutoffIso: "2026-06-12T00:00:00Z",
      labels: ["deferred-scope-out", "meta/machinery"],
    });

    // The correct form, asserted literally.
    expect(q).toContain('label:"deferred-scope-out","meta/machinery"');

    // The ANDed form must NOT appear. Anchored on the repeated-qualifier shape
    // rather than on a bare label name -- the label names legitimately appear
    // in the correct form too, so a bare-token assertion could never fail.
    expect(q).not.toMatch(/label:"[^"]+"\s+label:"/);

    // Exactly one `label:` qualifier in the whole query.
    expect(q.match(/label:/g) ?? []).toHaveLength(1);
  });

  it("still emits a single-label query correctly when the machinery arm is disarmed", async () => {
    const mod = await importModule();
    const q = mod.__TESTING__.buildSearchQuery({
      owner: "jikig-ai",
      repo: "soleur",
      cutoffIso: "2026-06-12T00:00:00Z",
      labels: ["deferred-scope-out"],
    });
    expect(q).toContain('label:"deferred-scope-out"');
    expect(q).not.toContain("meta/machinery");
    expect(q.match(/label:/g) ?? []).toHaveLength(1);
  });

  it("keeps sort:updated-asc and the is:open/is:issue scoping", async () => {
    const mod = await importModule();
    const q = mod.__TESTING__.buildSearchQuery({
      owner: "jikig-ai",
      repo: "soleur",
      cutoffIso: "2026-06-12T00:00:00Z",
      labels: ["deferred-scope-out", "meta/machinery"],
    });
    expect(q).toContain("is:issue");
    expect(q).toContain("is:open");
    expect(q).toContain("sort:updated-asc");
    expect(q).toContain("updated:<2026-06-12T00:00:00Z");
  });
});

// --------------------------------------------------------------------------
// (h) The never-close guards, and the date gate on the machinery arm.
// --------------------------------------------------------------------------
describe("cron-stale-deferred-scope-outs — never-close guards", () => {
  it("names every never-touch class as a distinct constant", async () => {
    const mod = await importModule();
    // keep-open is the one this sweeper previously ignored despite the label
    // existing in the repo.
    expect(mod.__TESTING__.KILLSWITCH_LABELS).toContain("keep-open");
    for (const l of [
      "domain/product",
      "type/feature",
      "action-required",
      "priority/p0-critical",
      "priority/p1-high",
    ]) {
      expect(mod.__TESTING__.PRODUCT_FACING_LABELS).toContain(l);
    }
  });

  it("caps CLOSES separately from the candidate search cap", async () => {
    const mod = await importModule();
    // The 200-item search cap bounds candidates, not closes. A single named
    // constant, asserted here so the runner and this test cannot drift.
    expect(mod.__TESTING__.MAX_CLOSES_PER_RUN).toBeGreaterThan(0);
    expect(mod.__TESTING__.MAX_CLOSES_PER_RUN).toBeLessThan(200);
  });

  it("gates the machinery arm on a DATE, because label novelty confers no age protection", async () => {
    const mod = await importModule();
    const notBefore = mod.__TESTING__.MACHINERY_SWEEP_NOT_BEFORE;
    // Shape: an ISO date the runner compares lexically against
    // now.toISOString().slice(0, 10).
    expect(notBefore).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    // It must be in the FUTURE relative to the merge window, or it buys nothing.
    expect(notBefore > "2026-09-10").toBe(true);
  });
});

// --------------------------------------------------------------------------
// (i) Per-label close caps.
//
// buildSearchQuery emits ONE `sort:updated-asc` query, and from
// MACHINERY_SWEEP_NOT_BEFORE the backfilled machinery cohort dominates
// oldest-first ordering (57% of the backlog is already past the window). A
// single shared cap would hand the whole budget to machinery every day and
// starve `deferred-scope-out` -- this function's original and only job until
// now -- and the starvation would be INVISIBLE behind one integer and one
// Sentry monitor covering both arms.
// --------------------------------------------------------------------------
describe("cron-stale-deferred-scope-outs — per-label close caps", () => {
  it("caps each arm separately, and the arms sum to no more than the overall cap", async () => {
    const mod = await importModule();
    const perLabel = mod.__TESTING__.MAX_CLOSES_PER_LABEL as Record<string, number>;
    const overall = mod.__TESTING__.MAX_CLOSES_PER_RUN as number;

    // Every target label has its OWN budget: a missing entry would silently
    // fall back to the shared cap, which is the starvation shape.
    for (const label of mod.__TESTING__.TARGET_LABELS) {
      expect(perLabel[label]).toBeGreaterThan(0);
    }
    const sum = Object.values(perLabel).reduce((a, b) => a + b, 0);
    expect(sum).toBeLessThanOrEqual(overall);
  });

  it("reserves a non-trivial share for the arm the cron was originally built for", async () => {
    const mod = await importModule();
    const perLabel = mod.__TESTING__.MAX_CLOSES_PER_LABEL as Record<string, number>;
    // The point of the split is that machinery cannot consume everything.
    expect(perLabel["deferred-scope-out"]).toBeGreaterThanOrEqual(
      perLabel["meta/machinery"],
    );
  });
});

// ---------------------------------------------------------------------------
// #8076 — the run-report arm. SUCCESS run-reports (the `[Scheduled] …` issues
// that ten crons MUST file) had no lifecycle: 43 open community digests, last
// bulk-closed by a person on 2026-07-27. This arm closes them at a per-label
// literal window (`closeAfterDays` in _cron-run-reports.ts), never a FAILED
// report, never a human-touched one, never a finding that merely borrowed the
// label (title shape + author), never campaign-calendar's standing issue or
// legal-audit's findings (rows with closeAfterDays: null are never queried).
// Guard Contract: plan §Guard 2.
// ---------------------------------------------------------------------------
describe("cronStaleDeferredScopeOuts — run-report arm (#8076)", () => {
  const NOW = new Date("2026-09-12T12:00:00Z");
  const RR_MARKER = "<!-- soleur:auto-close-run-report -->";

  function rrIssue(args: {
    number: number;
    label?: string;
    title?: string;
    createdAt?: string;
    updatedAt?: string;
    body?: string;
    labels?: string[];
    comments?: number;
    author?: string;
    stateReason?: string | null;
  }) {
    return {
      number: args.number,
      state_reason: args.stateReason ?? null,
      title: args.title ?? `[Scheduled] Community Monitor - 2026-08-${String(args.number % 28 + 1).padStart(2, "0")}`,
      created_at: args.createdAt ?? "2026-08-01T08:08:00Z",
      updated_at: args.updatedAt ?? "2026-08-01T08:08:00Z",
      state: "open",
      body: args.body ?? "## Community Monitor — 2026-08-01\n\n**Platform status:** ok",
      labels: (args.labels ?? [args.label ?? "scheduled-community-monitor"]).map((name) => ({ name })),
      comments: args.comments ?? 0,
      user: { login: args.author ?? "soleur-ai[bot]", type: args.author ? "User" : "Bot" },
    };
  }

  // Route the per-label run-report searches; scope-out searches get nothing.
  // `extra` answers first (return undefined to fall through to the defaults).
  function mockSearch(byLabel: Record<string, unknown[]>, extra?: (route: string, params: Record<string, unknown>) => unknown) {
    octokitRequestSpy.mockImplementation(async (route: string, params: Record<string, unknown>) => {
      if (route === "GET /search/issues") {
        const q = String(params.q ?? "");
        for (const [label, items] of Object.entries(byLabel)) {
          if (q.includes(`label:"${label}"`)) return { data: { items } };
        }
        return { data: { items: [] } };
      }
      if (extra) {
        const answer = extra(route, params);
        if (answer !== undefined) return answer;
      }
      if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}/comments") return { data: [] };
      return { data: {} };
    });
  }

  const closeCalls = () =>
    octokitRequestSpy.mock.calls.filter(([route]) => route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}");
  const commentCalls = () =>
    octokitRequestSpy.mock.calls.filter(([route]) => route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments");
  const searchQueries = () =>
    octokitRequestSpy.mock.calls
      .filter(([route]) => route === "GET /search/issues")
      .map(([, p]) => String((p as { q: string }).q));

  async function run() {
    const { __TESTING__ } = await importModule();
    return __TESTING__.sweepRunReports({
      octokit: { request: octokitRequestSpy } as never,
      now: NOW,
      dryRun: false,
      logger,
      paceMs: 0,
    });
  }
  const commentsRoute = "GET /repos/{owner}/{repo}/issues/{issue_number}/comments";
  const commentsCalls = () => octokitRequestSpy.mock.calls.filter(([route]) => route === commentsRoute);

  it("#7: closes a 10-day-old SUCCESS community digest with state_reason completed and its own marker comment", async () => {
    mockSearch({ "scheduled-community-monitor": [rrIssue({ number: 8000, createdAt: "2026-09-02T08:08:00Z" })] });
    const r = await run();
    expect(r.closed).toBe(1);
    expect(closeCalls()).toHaveLength(1);
    expect(closeCalls()[0][1]).toMatchObject({ issue_number: 8000, state: "closed", state_reason: "completed" });
    expect(commentCalls()).toHaveLength(1);
    expect(String((commentCalls()[0][1] as { body: string }).body)).toContain(RR_MARKER);
  });

  it("#1/#10: the query is created:-bounded, author-scoped, and per label", async () => {
    mockSearch({});
    await run();
    const qs = searchQueries();
    expect(qs.length).toBeGreaterThanOrEqual(8);
    for (const q of qs) {
      expect(q).toMatch(/is:open/);
      expect(q).toMatch(/author:app\/soleur-ai/);
      expect(q).toMatch(/created:<\d{4}-\d{2}-\d{2}/);
      expect(q).not.toMatch(/updated:/);
      expect(q.match(/label:/g) ?? []).toHaveLength(1);
    }
  });

  it("#11: never queries scheduled-legal-audit or scheduled-campaign-calendar", async () => {
    mockSearch({});
    await run();
    const joined = searchQueries().join("\n");
    expect(joined).not.toContain("scheduled-legal-audit");
    expect(joined).not.toContain("scheduled-campaign-calendar");
    expect(joined).toContain("scheduled-community-monitor");
    expect(joined).toContain("scheduled-roadmap-review");
  });

  it("#2: skips the #8027-shaped FAILED self-report (normal title, FAILED body prefix, p1-high)", async () => {
    mockSearch({
      "scheduled-community-monitor": [
        rrIssue({ number: 8027, createdAt: "2026-09-01T08:00:00Z", body: "Automated FAILED self-report from `cron-community-monitor`.", labels: ["scheduled-community-monitor", "priority/p1-high", "type/bug"] }),
      ],
    });
    const r = await run();
    expect(r.closed).toBe(0);
    expect(r.skippedByReason["failed-report"]).toBe(1);
    expect(closeCalls()).toHaveLength(0);
  });

  it("#3: skips a `- FAILED` title", async () => {
    mockSearch({ "scheduled-community-monitor": [rrIssue({ number: 7001, title: "[Scheduled] Community Monitor - FAILED", createdAt: "2026-09-01T08:00:00Z" })] });
    const r = await run();
    expect(r.closed).toBe(0);
    expect(r.skippedByReason["failed-report"]).toBe(1);
  });

  it("#4: skips action-required; kill-switch labels skip too", async () => {
    mockSearch({
      "scheduled-community-monitor": [
        rrIssue({ number: 7002, labels: ["scheduled-community-monitor", "action-required"], createdAt: "2026-09-01T08:00:00Z" }),
        rrIssue({ number: 7003, labels: ["scheduled-community-monitor", "keep-open"], createdAt: "2026-09-01T08:00:00Z" }),
        rrIssue({ number: 7004, labels: ["scheduled-community-monitor", "do-not-autoclose"], createdAt: "2026-09-01T08:00:00Z" }),
      ],
    });
    const r = await run();
    expect(r.closed).toBe(0);
    expect(closeCalls()).toHaveLength(0);
    expect(r.skipped).toBe(3);
  });

  it("#5/H2: does NOT skip a priority/p1-high digest (triage noise is not product signal) — the exact #8027 SUCCESS label set closes", async () => {
    mockSearch({
      "scheduled-community-monitor": [
        rrIssue({ number: 7005, labels: ["scheduled-community-monitor", "priority/p2-medium", "type/bug", "domain/operations"], createdAt: "2026-09-01T08:00:00Z" }),
        rrIssue({ number: 7006, labels: ["scheduled-community-monitor", "priority/p1-high"], createdAt: "2026-09-01T08:00:00Z" }),
      ],
    });
    const r = await run();
    expect(r.closed).toBe(2);
  });

  it("#6: a 20-day-old weekly roadmap review is NOT closed (window is 27 d)", async () => {
    mockSearch({ "scheduled-roadmap-review": [rrIssue({ number: 7007, label: "scheduled-roadmap-review", title: "[Scheduled] Weekly Roadmap Review - 2026-08-23", createdAt: "2026-08-23T09:00:00Z" })] });
    const r = await run();
    // The query's created:< cutoff would exclude it at GitHub; the client-side
    // age guard is the belt-and-suspenders that stops a stub-returned row.
    expect(r.closed).toBe(0);
  });

  it("#9: skips a finding-shaped title that borrowed the label (not-run-report-shape)", async () => {
    mockSearch({ "scheduled-community-monitor": [rrIssue({ number: 7008, title: "bug: the digest omits Bluesky", createdAt: "2026-09-01T08:00:00Z" })] });
    const r = await run();
    expect(r.closed).toBe(0);
    expect(r.skippedByReason["not-run-report-shape"]).toBe(1);
  });

  const withComments = (comments: unknown[]) => (route: string) =>
    route === commentsRoute ? { data: comments } : undefined;

  it("skips a human-commented report (non-bot comment)", async () => {
    mockSearch(
      { "scheduled-community-monitor": [rrIssue({ number: 7009, createdAt: "2026-09-01T08:00:00Z", comments: 1 })] },
      withComments([{ body: "keep this one", user: { login: "deruelle", type: "User" } }]),
    );
    const r = await run();
    expect(r.closed).toBe(0);
    expect(r.skippedByReason["human-triaged"]).toBe(1);
  });

  // Through 2026-09-09 daily triage commented as a PAT-driven `User` login via
  // the `claude` GitHub App; 75 of the 117 live candidates carry one. Its own
  // `**Automated Triage**` prefix + `performed_via_github_app` is automation.
  it("a PAT-era Automated Triage comment (User login, app-performed) is NOT a human comment", async () => {
    mockSearch(
      { "scheduled-community-monitor": [rrIssue({ number: 7012, createdAt: "2026-09-01T08:00:00Z", comments: 1 })] },
      withComments([{
        body: "**Automated Triage**\n\n**Priority:** p3",
        user: { login: "deruelle", type: "User" },
        performed_via_github_app: { slug: "claude" },
      }]),
    );
    const r = await run();
    expect(r.closed).toBe(1);
    expect(r.skippedByReason["human-triaged"]).toBeUndefined();
  });

  it("an app-performed comment WITHOUT the triage prefix is still a person (a Claude session is the operator)", async () => {
    mockSearch(
      { "scheduled-community-monitor": [rrIssue({ number: 7013, createdAt: "2026-09-01T08:00:00Z", comments: 1 })] },
      withComments([{
        body: "Leaving this open while I look into the digest.",
        user: { login: "deruelle", type: "User" },
        performed_via_github_app: { slug: "claude" },
      }]),
    );
    const r = await run();
    expect(r.closed).toBe(0);
    expect(r.skippedByReason["human-triaged"]).toBe(1);
  });

  it("isAutomationComment is the ONE predicate both arms share (Bot / known actor / app-performed triage; else a person)", async () => {
    const { __TESTING__ } = await importModule();
    const f = __TESTING__.isAutomationComment;
    expect(f({ user: { type: "Bot", login: "x[bot]" } })).toBe(true);
    expect(f({ user: { type: "User", login: "github-actions[bot]" } })).toBe(true);
    expect(f({ body: "**Automated Triage**", user: { type: "User", login: "deruelle" }, performed_via_github_app: {} })).toBe(true);
    expect(f({ body: "**Automated Triage**", user: { type: "User", login: "deruelle" } })).toBe(false);
    expect(f({ body: "hi", user: { type: "User", login: "deruelle" }, performed_via_github_app: {} })).toBe(false);
    expect(f({})).toBe(false);
  });

  it("#12: marker present on an OPEN, never-reopened issue (a retry whose PATCH failed — even a day later) → skips the POST but still PATCHes", async () => {
    mockSearch(
      { "scheduled-community-monitor": [rrIssue({ number: 7010, createdAt: "2026-09-01T08:00:00Z", comments: 1 })] },
      withComments([{ body: `Auto-closing …\n${RR_MARKER}`, user: { login: "soleur-ai[bot]", type: "Bot" }, created_at: "2026-09-10T12:00:00Z" }]),
    );
    const r = await run();
    expect(r.closed).toBe(1);
    expect(commentCalls()).toHaveLength(0);
    expect(closeCalls()).toHaveLength(1);
  });

  // The query is `created:<cutoff`, so a report a PERSON reopened is a
  // candidate again every day. GitHub stamps `state_reason: "reopened"` on
  // every reopen — after a sweeper close AND after a human bulk close that
  // left no marker — and that, not the marker's age, is the discriminator
  // (#8074 review + ship consult): a reopen is a keep-open signal.
  it("state_reason reopened (after a sweeper close, marker present) → skip, never re-close", async () => {
    mockSearch(
      { "scheduled-community-monitor": [rrIssue({ number: 7014, createdAt: "2026-09-01T08:00:00Z", comments: 1, stateReason: "reopened" })] },
      withComments([{ body: `Auto-closing …\n${RR_MARKER}`, user: { login: "soleur-ai[bot]", type: "Bot" }, created_at: "2026-09-10T12:00:00Z" }]),
    );
    const r = await run();
    expect(r.closed).toBe(0);
    expect(closeCalls()).toHaveLength(0);
    expect(r.skippedByReason["reopened-by-human"]).toBe(1);
    expect(commentsCalls()).toHaveLength(0); // decided from the search item; no comments read spent
  });

  it("state_reason reopened with NO marker and no comments (reopened after a pre-#8076 human bulk close) → skip", async () => {
    mockSearch({ "scheduled-community-monitor": [rrIssue({ number: 7015, createdAt: "2026-09-01T08:00:00Z", stateReason: "reopened" })] });
    const r = await run();
    expect(r.closed).toBe(0);
    expect(r.skippedByReason["reopened-by-human"]).toBe(1);
  });

  it("#3′: the FAILED title guard is case-insensitive", async () => {
    mockSearch({ "scheduled-community-monitor": [rrIssue({ number: 7016, createdAt: "2026-09-01T08:00:00Z", title: "[Scheduled] Community Monitor - Failed" })] });
    const r = await run();
    expect(r.closed).toBe(0);
    expect(r.skippedByReason["failed-report"]).toBe(1);
  });

  it("#8: cap — 26 eligible → exactly 25 closed + 1 deferred (asserted as counts), and the deferred one costs no comments GET", async () => {
    const items = Array.from({ length: 26 }, (_, i) => rrIssue({ number: 6000 + i, createdAt: "2026-08-20T08:00:00Z", comments: 1 }));
    mockSearch({ "scheduled-community-monitor": items }, withComments([{ body: "**Automated Triage**", user: { login: "soleur-ai[bot]", type: "Bot" } }]));
    const r = await run();
    expect(r.closed).toBe(25);
    expect(r.deferred).toBe(1);
    expect(closeCalls()).toHaveLength(25);
    // The cap is checked BEFORE the comments read (bounds reads, not only writes).
    expect(commentsCalls()).toHaveLength(25);
  });

  it("the WARN summary marker ships when something closed or was deferred, and stays silent on a quiet run", async () => {
    const warnSpy = vi.fn();
    const warnLogger = { ...logger, warn: warnSpy } as typeof logger;
    const { __TESTING__ } = await importModule();
    mockSearch({ "scheduled-community-monitor": [rrIssue({ number: 7017, createdAt: "2026-09-01T08:00:00Z" })] });
    await __TESTING__.sweepRunReports({ octokit: { request: octokitRequestSpy } as never, now: NOW, dryRun: false, logger: warnLogger, paceMs: 0 });
    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(warnSpy.mock.calls[0][0]).toMatchObject({ [__TESTING__.RUN_REPORT_SWEEP_MARKER]: true, closed: 1, deferred: 0 });
    warnSpy.mockClear();
    mockSearch({});
    await __TESTING__.sweepRunReports({ octokit: { request: octokitRequestSpy } as never, now: NOW, dryRun: false, logger: warnLogger, paceMs: 0 });
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("every sweepable row is queried with its OWN created:<cutoff (now − closeAfterDays), all eight of them", async () => {
    mockSearch({});
    await run();
    const { RUN_REPORT_CRONS } = await import("../../../server/inngest/functions/_cron-run-reports");
    const qs = searchQueries().filter((q) => q.includes('label:"scheduled-'));
    const sweepable = RUN_REPORT_CRONS.filter((r) => r.closeAfterDays !== null);
    expect(qs).toHaveLength(sweepable.length);
    expect(sweepable).toHaveLength(8);
    for (const row of sweepable) {
      const cutoff = new Date(NOW.getTime() - (row.closeAfterDays as number) * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
      expect(qs.some((q) => q.includes(`label:"${row.label}"`) && q.includes(`created:<${cutoff}`))).toBe(true);
    }
  });

  it("H1: an empty search page closes nothing and reports total 0 (not vacuously green)", async () => {
    mockSearch({});
    const r = await run();
    expect(r.total).toBe(0);
    expect(r.closed).toBe(0);
    expect(closeCalls()).toHaveLength(0);
  });

  it("dry run: closes nothing, counts eligibility", async () => {
    mockSearch({ "scheduled-community-monitor": [rrIssue({ number: 7011, createdAt: "2026-09-01T08:00:00Z" })] });
    const { __TESTING__ } = await importModule();
    const r = await __TESTING__.sweepRunReports({ octokit: { request: octokitRequestSpy } as never, now: NOW, dryRun: true, logger });
    expect(r.closed).toBe(0);
    expect(closeCalls()).toHaveLength(0);
  });

  it("#14: the handler runs the arm in its OWN step; a run-report search fault does not replay the scope-out arm", async () => {
    let scopeOutSearches = 0;
    octokitRequestSpy.mockImplementation(async (route: string, params: Record<string, unknown>) => {
      if (route === "GET /search/issues") {
        const q = String(params.q);
        if (q.includes("scheduled-")) throw new Error("boom: search down for run-reports");
        scopeOutSearches += 1;
        return { data: { items: [] } };
      }
      return { data: {} };
    });
    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();
    await expect(
      cronStaleDeferredScopeOutsHandler({ step, logger, attempt: 1, maxAttempts: 2 } as never),
    ).rejects.toThrow();
    expect(step.calls.some((c) => c.name === "sweep-stale-deferred-scope-outs")).toBe(true);
    // The scope-out arm ran exactly once within this invocation and the
    // run-report fault surfaced through the shared sweepFailed path. (Cross-
    // attempt memoization is Inngest's contract, not modelled by the fake step.)
    expect(scopeOutSearches).toBe(1);
    // The run-report arm has its OWN step id — the isolation the row is named for.
    expect(step.calls.map((c) => c.name)).not.toContain("sweep-run-reports");
  });

  it("the handler's step is literally `sweep-run-reports` and its result rides on the return value under `runReports`", async () => {
    mockSearch({ "scheduled-community-monitor": [rrIssue({ number: 7018, createdAt: "2026-09-01T08:00:00Z" })] });
    const { cronStaleDeferredScopeOutsHandler } = await importModule();
    const step = makeStep();
    const out = (await cronStaleDeferredScopeOutsHandler({ step, logger, attempt: 1, maxAttempts: 2 } as never)) as {
      runReports?: { closed: number };
    };
    expect(step.calls.some((c) => c.name === "sweep-run-reports")).toBe(true);
    expect(out.runReports?.closed).toBe(1);
  });
});

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
  // A transient 500 on the search call is the most-exposed throwing path
  // (fetchCandidates has no retry wrapping); it flips sweepFailed=true.
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


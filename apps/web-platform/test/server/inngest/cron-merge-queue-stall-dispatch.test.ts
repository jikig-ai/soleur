import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

import * as ts from "typescript";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE ES-module imports — set NEXT_PHASE so importing the
// inngest client (transitively pulled by the SUT) does not throw on the missing
// INNGEST_SIGNING_KEY in the test env. Mirrors cron-actions-queue-health-dispatch.test.ts.
const h = vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
  return {
    requestSpy: vi.fn(async (..._args: unknown[]) => ({ status: 204 })),
    reportSilentFallbackSpy: vi.fn((..._args: unknown[]) => {}),
    mintSpy: vi.fn(async (_opts: unknown) => "fake-installation-token"),
    heartbeatSpy: vi.fn(async (_opts: unknown) => {}),
    ctorSpy: vi.fn((_opts: unknown) => {}),
  };
});

// The SUT does `const { Octokit } = await import("@octokit/core")`; mocking it
// makes the dispatch call observable without hitting GitHub.
vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = h.requestSpy;
    constructor(opts: unknown) {
      // Record the constructor options so the minted token's journey to the
      // request (auth) is observable, not just the mint and the request args.
      h.ctorSpy(opts);
    }
  },
}));

// Stub the token mint (the minted permission scope is observable) and the
// Sentry heartbeat (the liveness signal is observable).
vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return {
    ...actual,
    mintInstallationToken: h.mintSpy,
    postSentryHeartbeat: h.heartbeatSpy,
  };
});

vi.mock("@/server/observability", async () => {
  const actual =
    await vi.importActual<typeof import("@/server/observability")>(
      "@/server/observability",
    );
  return { ...actual, reportSilentFallback: h.reportSilentFallbackSpy };
});

import {
  cronMergeQueueStallDispatch,
  cronMergeQueueStallDispatchHandler,
} from "@/server/inngest/functions/cron-merge-queue-stall-dispatch";

const SUT_RAW = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-merge-queue-stall-dispatch.ts",
  ),
  "utf-8",
);
// The header documents the same strings the anchors look for (retries, cron,
// grants), so anchors read the CODE only. Comments are removed by the
// TypeScript compiler itself, not a regex: a regex mistakes "/*" inside a
// string for a comment opener and deletes real code, and misses trailing
// same-line comments. Types are erased and formatting normalised, so anchors
// target the emitted shape.
const SUT_SOURCE = ts.transpileModule(SUT_RAW, {
  compilerOptions: {
    removeComments: true,
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.ESNext,
  },
}).outputText;

// An Octokit-shaped HTTP error: real request failures carry a numeric status.
function httpError(status: number, message: string): Error {
  return Object.assign(new Error(message), { status });
}

// A `step` that runs each callback inline (no Inngest durability in tests).
function makeStep() {
  return {
    run: async <T>(_name: string, cb: () => Promise<T>): Promise<T> => cb(),
  };
}

// A `step` that REPLAYS like Inngest: the whole handler re-executes after each
// step, and an already-run step name returns its memoized result without
// re-running the callback. A side effect placed OUTSIDE a step.run therefore
// repeats on every replay, which the inline fake above cannot show.
function makeReplayingStep() {
  const memo = new Map<string, { value: unknown } | { error: unknown }>();
  return {
    run: async <T>(name: string, cb: () => Promise<T>): Promise<T> => {
      const hit = memo.get(name);
      if (hit) {
        if ("error" in hit) throw hit.error;
        return hit.value as T;
      }
      try {
        const value = await cb();
        memo.set(name, { value });
        return value;
      } catch (error) {
        // A step that failed is memoized as failed, like Inngest does once
        // its retries are exhausted.
        memo.set(name, { error });
        throw error;
      }
    },
  };
}
const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

describe("cronMergeQueueStallDispatch — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronMergeQueueStallDispatch).toBeDefined();
    expect(typeof cronMergeQueueStallDispatch).toBe("object");
  });
});

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-merge-queue-stall-dispatch"', "canonical function id"],
    ['cron: "*/10 * * * *"', "every-10-minutes schedule matching the workflow fallback"],
    [
      'event: "cron/merge-queue-stall-dispatch.manual-trigger"',
      "operator manual trigger",
    ],
    ["concurrency: [", "concurrency lanes are declared as a real option"],
    ['{ scope: "fn", limit: 1 }', "fn-scoped serialization, limit 1"],
    [
      '{ scope: "account", key: \'"cron-dispatch"\', limit: 1 }',
      "own account lane (NOT the shared cron-platform lane), limit 1",
    ],
    ["retries: 1,", "single retry on failure"],
    [
      'SENTRY_MONITOR_SLUG = "scheduled-merge-queue-stall-dispatch"',
      "dispatcher-fed Sentry monitor slug",
    ],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("dispatch source anchors", () => {
  it.each([
    [
      "/repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
      "workflow_dispatch endpoint",
    ],
    [
      '"merge-queue-stall-check.yml"',
      "dispatches the stall-check GHA workflow by filename",
    ],
    ['ref: "main"', "dispatches against main"],
    ["@octokit/core", "uses the cron Octokit pattern"],
    ["reportSilentFallback", "loud dispatch-failure reporting"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("HARD NON-GOAL: dispatcher holds no probe credential (Guard contract)", () => {
  // The probe's grants (the queue read, issue filing) stay in the GitHub-hosted
  // runner that executes the workflow with its default GITHUB_TOKEN.
  it.each([
    ['actions: "read"', "no queue-probe grant"],
    ['issues: "write"', "no issue-filing grant"],
    ["mkdtemp", "no ephemeral workspace"],
    ["spawn(", "no child-process execution"],
    ["child_process", "no process-spawning import"],
  ])("source does NOT use %s (%s)", (forbidden) => {
    expect(SUT_SOURCE).not.toContain(forbidden);
  });
});

describe("dispatch target exists on disk and accepts workflow_dispatch", () => {
  const match = /WORKFLOW_FILE\s*=\s*"([^"]+)"/.exec(SUT_SOURCE);
  const workflow = match
    ? resolve(__dirname, "../../../../../.github/workflows", match[1])
    : "";

  it("the dispatched workflow file is present, so a rename fails CI not production", () => {
    expect(match).not.toBeNull();
    expect(existsSync(workflow)).toBe(true);
  });

  it("the dispatched workflow declares workflow_dispatch, or every POST would 422", () => {
    expect(readFileSync(workflow, "utf-8")).toMatch(/^\s*workflow_dispatch:/m);
  });

  it("the dispatched workflow serializes duplicates (dispatch + fallback schedule can fire together)", () => {
    const wf = readFileSync(workflow, "utf-8");
    expect(wf).toMatch(/^concurrency:\s*\n\s+group:\s*merge-queue-stall-check\s*$/m);
    expect(wf).toMatch(/^\s+cancel-in-progress:\s*false\s*$/m);
  });
});

describe("cronMergeQueueStallDispatchHandler — dispatch behavior", () => {
  beforeEach(() => {
    h.requestSpy.mockClear();
    h.reportSilentFallbackSpy.mockClear();
    h.mintSpy.mockClear();
    h.heartbeatSpy.mockReset();
    h.heartbeatSpy.mockResolvedValue(undefined);
    h.ctorSpy.mockClear();
    logger.info.mockClear();
    logger.warn.mockClear();
    h.requestSpy.mockReset();
    h.requestSpy.mockResolvedValue({ status: 204 });
    h.mintSpy.mockReset();
    h.mintSpy.mockResolvedValue("fake-installation-token");
  });

  it("mints a NARROWED token (actions:write, this repo only), POSTs the dispatch, heartbeats ok", async () => {
    const result = await cronMergeQueueStallDispatchHandler({
      step: makeStep(),
      logger,
    });

    // toEqual, not toMatchObject: an extra permission widens the credential.
    expect(h.mintSpy).toHaveBeenCalledTimes(1);
    expect(h.mintSpy.mock.calls[0][0]).toEqual({
      tokenMinLifetimeMs: 5 * 60 * 1000,
      permissions: { actions: "write" },
      repositories: ["soleur"],
    });

    expect(h.requestSpy).toHaveBeenCalledTimes(1);
    const [endpoint, params] = h.requestSpy.mock.calls[0];
    expect(endpoint).toBe(
      "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
    );
    // Exhaustive — an extra/leaked field (e.g. `inputs`) must fail the test.
    expect(params).toEqual({
      owner: "jikig-ai",
      repo: "soleur",
      workflow_id: "merge-queue-stall-check.yml",
      ref: "main",
    });
    expect(result).toEqual({ ok: true });
    expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();

    // The minted token must actually reach the request: an Octokit built with
    // no auth would 404 on every tick while the mint and params stay green.
    expect(h.ctorSpy).toHaveBeenCalledTimes(1);
    expect(h.ctorSpy.mock.calls[0][0]).toEqual({ auth: "fake-installation-token" });

    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({
      ok: true,
      sentryMonitorSlug: "scheduled-merge-queue-stall-dispatch",
      cronName: "cron-merge-queue-stall-dispatch",
    });
    expect((h.heartbeatSpy.mock.calls[0][0] as { logger: unknown }).logger).toBe(logger);
    expect(logger.info).toHaveBeenCalledTimes(1);
  });

  it("reports to Sentry, redacts the token, heartbeats not-ok and returns not-ok when the dispatch throws", async () => {
    // Derive the token from the mock, not a literal, so the redaction check is
    // not satisfied by a hard-coded string.
    const token = "tok-" + "different-from-the-default-mock-value";
    h.mintSpy.mockResolvedValue(token);
    // A class with its own name, to prove Error.name survives the redaction.
    class HttpError extends Error {
      status = 403;
      name = "HttpError";
    }
    h.requestSpy.mockRejectedValueOnce(new HttpError(`${token} leaked 403`));

    const result = await cronMergeQueueStallDispatchHandler({
      step: makeStep(),
      logger,
    });

    expect(result).toMatchObject({ ok: false });
    expect(result.errorSummary).toBeTruthy();
    // The minted token (not a literal) is what reached the request.
    expect(h.ctorSpy.mock.calls[0][0]).toEqual({ auth: token });
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [errArg, options] = h.reportSilentFallbackSpy.mock.calls[0];
    // Exhaustive: an extra field (for example the token in `extra`) must fail.
    expect(options).toEqual({
      feature: "cron-merge-queue-stall-dispatch",
      op: "dispatch-workflow",
      message: "merge-queue-stall-dispatch workflow_dispatch failed",
      extra: {
        fn: "cron-merge-queue-stall-dispatch",
        workflow: "merge-queue-stall-check.yml",
      },
    });
    expect(JSON.stringify(options)).not.toContain(token);
    // Read .message directly (JSON.stringify drops the non-enumerable field,
    // so a serialize-then-grep check would pass vacuously).
    expect(errArg).toBeInstanceOf(Error);
    const redacted = errArg as Error;
    expect(redacted.message).not.toContain(token);
    expect(redacted.stack ?? "").not.toContain(token);
    // Positive control: prove redaction ACTIVELY fired.
    expect(redacted.message).toContain("[REDACTED-INSTALLATION-TOKEN]");
    expect(redacted.name).toBe("HttpError");
    expect(result.errorSummary).not.toContain(token);

    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({
      ok: false,
      sentryMonitorSlug: "scheduled-merge-queue-stall-dispatch",
    });
  });

  it("a 4xx is a real defect: reported at once, with no retry", async () => {
    h.requestSpy.mockRejectedValue(httpError(404, "Not Found"));

    const result = await cronMergeQueueStallDispatchHandler({
      step: makeStep(),
      logger,
    });

    expect(result).toMatchObject({ ok: false });
    expect(h.requestSpy).toHaveBeenCalledTimes(1);
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
  });

  describe("transient failures get ONE in-step retry", () => {
    beforeEach(() => vi.useFakeTimers());
    afterEach(() => vi.useRealTimers());

    async function run() {
      const pending = cronMergeQueueStallDispatchHandler({
        step: makeStep(),
        logger,
      });
      await vi.advanceTimersByTimeAsync(2_000);
      return pending;
    }

    it.each([429, 500, 502])(
      "a %i followed by success dispatches, with no report, a warn log and an ok heartbeat",
      async (status) => {
        h.requestSpy.mockRejectedValueOnce(httpError(status, "transient"));

        const result = await run();

        expect(result).toEqual({ ok: true });
        expect(h.requestSpy).toHaveBeenCalledTimes(2);
        expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();
        expect(logger.warn).toHaveBeenCalledTimes(1);
        expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({ ok: true });
      },
    );

    it("waits the full retry delay before the second attempt", async () => {
      h.requestSpy.mockRejectedValueOnce(httpError(502, "Bad Gateway"));
      const pending = cronMergeQueueStallDispatchHandler({
        step: makeStep(),
        logger,
      });

      await vi.advanceTimersByTimeAsync(1_999);
      expect(h.requestSpy).toHaveBeenCalledTimes(1);
      await vi.advanceTimersByTimeAsync(1);
      expect(h.requestSpy).toHaveBeenCalledTimes(2);
      await expect(pending).resolves.toEqual({ ok: true });
    });

    it("a retried 5xx whose message embeds the token is redacted on the final report", async () => {
      const token = "tok-" + "retried-path-secret-value";
      h.mintSpy.mockResolvedValue(token);
      h.requestSpy.mockRejectedValue(httpError(503, `${token} unavailable`));

      const result = await run();

      expect(result).toMatchObject({ ok: false });
      expect(result.errorSummary).not.toContain(token);
      expect(result.errorSummary).toContain("[REDACTED-INSTALLATION-TOKEN]");
      expect(JSON.stringify(h.reportSilentFallbackSpy.mock.calls)).not.toContain(token);
    });

    it("a non-Error rejection whose toString carries the token is redacted, and one that throws is contained", async () => {
      const token = "tok-" + "tostring-secret-value";
      h.mintSpy.mockResolvedValue(token);
      h.requestSpy.mockRejectedValueOnce({ toString: () => `weird ${token}` });
      h.requestSpy.mockRejectedValueOnce({ toString: () => `weird ${token}` });

      const first = await run();
      expect(first).toMatchObject({ ok: false });
      expect(first.errorSummary).not.toContain(token);
      expect(first.errorSummary).toContain("[REDACTED-INSTALLATION-TOKEN]");

      h.requestSpy.mockReset();
      const hostile = Object.create(null) as object;
      h.requestSpy.mockRejectedValue(hostile);
      const second = await run();
      expect(second).toEqual({ ok: false, errorSummary: "unserializable error" });
    });

    it("a network error (no HTTP status) is retried the same way", async () => {
      h.requestSpy.mockRejectedValueOnce(new Error("socket hang up"));

      const result = await run();

      expect(result).toEqual({ ok: true });
      expect(h.requestSpy).toHaveBeenCalledTimes(2);
    });

    it("a second transient failure is reported once, after exactly two attempts", async () => {
      h.requestSpy.mockRejectedValue(httpError(503, "Service Unavailable"));

      const result = await run();

      expect(result).toMatchObject({ ok: false });
      expect(h.requestSpy).toHaveBeenCalledTimes(2);
      expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
      expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
    });

    it("a rejection with no value at all is reported, never thrown out of the step", async () => {
      h.requestSpy.mockRejectedValue(undefined);

      const result = await run();

      expect(result).toMatchObject({ ok: false, errorSummary: "undefined" });
      expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    });
  });

  it("a token-mint failure posts ONE not-ok heartbeat, then rethrows the SAME error, and never dispatches", async () => {
    const mintError = new Error("app auth failed");
    h.mintSpy.mockRejectedValueOnce(mintError);

    await expect(
      cronMergeQueueStallDispatchHandler({ step: makeStep(), logger }),
    ).rejects.toBe(mintError);

    expect(h.requestSpy).not.toHaveBeenCalled();
    // The Inngest middleware captures the rethrown error; a second report here
    // would double-page.
    expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();
    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({
      ok: false,
      sentryMonitorSlug: "scheduled-merge-queue-stall-dispatch",
    });
  });

  it("a failing error heartbeat does not replace the mint error", async () => {
    const mintError = new Error("app auth failed");
    h.mintSpy.mockRejectedValueOnce(mintError);
    h.heartbeatSpy.mockRejectedValueOnce(new Error("heartbeat down"));

    await expect(
      cronMergeQueueStallDispatchHandler({ step: makeStep(), logger }),
    ).rejects.toBe(mintError);
  });

  it("a heartbeat failure after a SUCCESSFUL dispatch is not reported as a dispatch failure", async () => {
    h.heartbeatSpy.mockRejectedValueOnce(new Error("sentry down"));

    await expect(
      cronMergeQueueStallDispatchHandler({ step: makeStep(), logger }),
    ).rejects.toThrow("sentry down");

    expect(h.requestSpy).toHaveBeenCalledTimes(1);
    expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();
    expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({ ok: true });
  });

  it("replay safety: a failed dispatch yields exactly one report and one heartbeat across replays", async () => {
    h.requestSpy.mockRejectedValueOnce(httpError(403, "boom 403"));
    const step = makeReplayingStep();

    // Inngest re-executes the whole handler after every step; the memoized
    // steps must not re-run, and nothing outside a step may repeat.
    const first = await cronMergeQueueStallDispatchHandler({ step, logger });
    const second = await cronMergeQueueStallDispatchHandler({ step, logger });
    const third = await cronMergeQueueStallDispatchHandler({ step, logger });

    expect(first).toMatchObject({ ok: false });
    expect(second).toEqual(first);
    expect(third).toEqual(first);
    expect(h.mintSpy).toHaveBeenCalledTimes(1);
    expect(h.requestSpy).toHaveBeenCalledTimes(1);
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
  });

  it("replay safety: a mint failure posts one error heartbeat across replays and keeps rethrowing", async () => {
    const mintError = new Error("app auth failed");
    h.mintSpy.mockRejectedValueOnce(mintError);
    const step = makeReplayingStep();

    for (let i = 0; i < 3; i++) {
      await expect(
        cronMergeQueueStallDispatchHandler({ step, logger }),
      ).rejects.toBe(mintError);
    }

    expect(h.mintSpy).toHaveBeenCalledTimes(1);
    expect(h.requestSpy).not.toHaveBeenCalled();
    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
  });
});

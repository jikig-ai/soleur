import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

import { beforeEach, describe, expect, it, vi } from "vitest";

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
  };
});

// The SUT does `const { Octokit } = await import("@octokit/core")`; mocking it
// makes the dispatch call observable without hitting GitHub.
vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = h.requestSpy;
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

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-merge-queue-stall-dispatch.ts",
  ),
  "utf-8",
);

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
  const memo = new Map<string, unknown>();
  return {
    run: async <T>(name: string, cb: () => Promise<T>): Promise<T> => {
      if (memo.has(name)) return memo.get(name) as T;
      const value = await cb();
      memo.set(name, value);
      return value;
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
    ['scope: "fn"', "fn-scoped serialization"],
    ['key: \'"cron-dispatch"', "own account lane — NOT the shared cron-platform lane"],
    ["retries: 1", "single retry on failure"],
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

describe("dispatch target exists on disk (Guard 1 row 4)", () => {
  it("the dispatched workflow file is present, so a rename fails CI not production", () => {
    const match = /WORKFLOW_FILE\s*=\s*"([^"]+)"/.exec(SUT_SOURCE);
    expect(match).not.toBeNull();
    const workflow = resolve(
      __dirname,
      "../../../../../.github/workflows",
      match![1],
    );
    expect(existsSync(workflow)).toBe(true);
  });
});

describe("cronMergeQueueStallDispatchHandler — dispatch behavior", () => {
  beforeEach(() => {
    h.requestSpy.mockClear();
    h.reportSilentFallbackSpy.mockClear();
    h.mintSpy.mockClear();
    h.heartbeatSpy.mockClear();
    h.requestSpy.mockResolvedValue({ status: 204 });
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

    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({
      ok: true,
      sentryMonitorSlug: "scheduled-merge-queue-stall-dispatch",
      cronName: "cron-merge-queue-stall-dispatch",
    });
  });

  it("reports to Sentry, redacts the token, heartbeats not-ok and returns not-ok when the dispatch throws", async () => {
    // Derive the token from the mock, not a literal, so the redaction check is
    // not satisfied by a hard-coded string.
    const token = "tok-" + "different-from-the-default-mock-value";
    h.mintSpy.mockResolvedValue(token);
    h.requestSpy.mockRejectedValueOnce(new Error(`${token} leaked 403`));

    const result = await cronMergeQueueStallDispatchHandler({
      step: makeStep(),
      logger,
    });

    expect(result).toMatchObject({ ok: false });
    expect(result.errorSummary).toBeTruthy();
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [errArg, options] = h.reportSilentFallbackSpy.mock.calls[0];
    expect(options).toMatchObject({ feature: "cron-merge-queue-stall-dispatch" });
    // Read .message directly (JSON.stringify drops the non-enumerable field,
    // so a serialize-then-grep check would pass vacuously).
    const errMessage =
      errArg instanceof Error ? errArg.message : String(errArg);
    expect(errMessage).not.toContain(token);
    // Positive control: prove redaction ACTIVELY fired.
    expect(errMessage).toContain("[REDACTED-INSTALLATION-TOKEN]");
    expect(result.errorSummary).not.toContain(token);

    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({
      ok: false,
      sentryMonitorSlug: "scheduled-merge-queue-stall-dispatch",
    });
  });

  it("a token-mint failure posts ONE not-ok heartbeat, then rethrows, and never dispatches", async () => {
    h.mintSpy.mockRejectedValueOnce(new Error("app auth failed"));

    await expect(
      cronMergeQueueStallDispatchHandler({ step: makeStep(), logger }),
    ).rejects.toThrow("app auth failed");

    expect(h.requestSpy).not.toHaveBeenCalled();
    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({
      ok: false,
      sentryMonitorSlug: "scheduled-merge-queue-stall-dispatch",
    });
  });

  it("replay safety: a failed dispatch yields exactly one report and one heartbeat across replays", async () => {
    h.requestSpy.mockRejectedValueOnce(new Error("boom 403"));
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
});

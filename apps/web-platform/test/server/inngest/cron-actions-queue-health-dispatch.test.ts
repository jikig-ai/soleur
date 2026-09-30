import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { beforeEach, describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE ES-module imports — set NEXT_PHASE so importing the
// inngest client (transitively pulled by the SUT) does not throw on the missing
// INNGEST_SIGNING_KEY in the test env. Mirrors cron-supabase-watchdog-dispatch.test.ts.
const h = vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
  return {
    requestSpy: vi.fn(async (..._args: unknown[]) => ({ status: 204 })),
    reportSilentFallbackSpy: vi.fn((..._args: unknown[]) => {}),
    mintSpy: vi.fn(async (_opts: unknown) => "fake-installation-token"),
  };
});

// Mock the dynamically-imported Octokit so the dispatch call is observable
// without hitting GitHub. The SUT does `const { Octokit } = await import("@octokit/core")`.
vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = h.requestSpy;
  },
}));

// Stub the installation-token mint so no GitHub App round-trip happens — and
// so the minted permission scope is observable (#9273: a revert to the full
// grant must fail red here).
vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return {
    ...actual,
    mintInstallationToken: h.mintSpy,
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
  cronActionsQueueHealthDispatch,
  cronActionsQueueHealthDispatchHandler,
} from "@/server/inngest/functions/cron-actions-queue-health-dispatch";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-actions-queue-health-dispatch.ts",
  ),
  "utf-8",
);

// A `step` that just runs each callback inline (no Inngest durability in tests).
function makeStep() {
  return {
    run: async <T>(_name: string, cb: () => Promise<T>): Promise<T> => cb(),
  };
}
const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

describe("cronActionsQueueHealthDispatch — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronActionsQueueHealthDispatch).toBeDefined();
    expect(typeof cronActionsQueueHealthDispatch).toBe("object");
  });
});

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-actions-queue-health-dispatch"', "canonical function id"],
    ['cron: "*/30 * * * *"', "every-30-minutes schedule matching the monitor cadence"],
    [
      'event: "cron/actions-queue-health-dispatch.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['key: \'"cron-dispatch"', "own account lane — NOT the shared cron-platform lane"],
    ["retries: 1", "single retry on failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("dispatch-hybrid source anchors", () => {
  it.each([
    [
      "/repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
      "workflow_dispatch endpoint",
    ],
    [
      '"scheduled-actions-queue-health.yml"',
      "dispatches the queue-health GHA workflow by filename",
    ],
    ['ref: "main"', "dispatches against main"],
    ["@octokit/core", "uses the cron Octokit pattern"],
    ["reportSilentFallback", "loud dispatch-failure reporting"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("HARD NON-GOAL: dispatcher holds no runner-queue credential (Guard contract)", () => {
  // The dispatch path must stay independent of the substrate it measures —
  // the probe's grants stay in the ephemeral GHA runner.
  it.each([
    ["actions: \"read\"", "no queue-probe grant"],
    ["issues: \"write\"", "no issue-filing grant"],
    ["mkdtemp", "no ephemeral workspace"],
    ["spawn(", "no child-process execution"],
    ["child_process", "no process-spawning import"],
  ])("source does NOT use %s (%s)", (forbidden) => {
    expect(SUT_SOURCE).not.toContain(forbidden);
  });
});

describe("cronActionsQueueHealthDispatchHandler — dispatch behavior", () => {
  beforeEach(() => {
    h.requestSpy.mockClear();
    h.reportSilentFallbackSpy.mockClear();
    h.mintSpy.mockClear();
    h.requestSpy.mockResolvedValue({ status: 204 });
  });

  it("mints a NARROWED token (actions:write, this repo only), POSTs the dispatch, returns ok", async () => {
    const result = await cronActionsQueueHealthDispatchHandler({
      step: makeStep(),
      logger,
    });

    // The narrowed scope is the load-bearing difference from sibling crons —
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
    // Exhaustive — an extra/leaked field (e.g. `inputs`) on a
    // credential-bearing dispatch call must fail the test.
    expect(params).toEqual({
      owner: "jikig-ai",
      repo: "soleur",
      workflow_id: "scheduled-actions-queue-health.yml",
      ref: "main",
    });
    expect(result).toEqual({ ok: true });
    expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("reports to Sentry and returns not-ok when the dispatch throws", async () => {
    h.requestSpy.mockRejectedValueOnce(
      new Error("fake-installation-token leaked 403"),
    );

    const result = await cronActionsQueueHealthDispatchHandler({
      step: makeStep(),
      logger,
    });

    expect(result).toEqual({ ok: false });
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [errArg, options] = h.reportSilentFallbackSpy.mock.calls[0];
    expect(options).toMatchObject({ feature: "cron-actions-queue-health-dispatch" });
    // The minted token must be redacted out of the Error handed to Sentry —
    // read .message directly (JSON.stringify drops the non-enumerable field,
    // so a serialize-then-grep check would pass vacuously).
    const errMessage =
      errArg instanceof Error ? errArg.message : String(errArg);
    expect(errMessage).not.toContain("fake-installation-token");
    // Positive control: prove redaction ACTIVELY fired.
    expect(errMessage).toContain("[REDACTED-INSTALLATION-TOKEN]");
  });
});

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
// so the minted permission scope is observable (#13096: a revert to the full
// grant, or a second broader mint used for the dispatch, must fail red here).
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
  cronMachineryDrain,
  cronMachineryDrainHandler,
} from "@/server/inngest/functions/cron-machinery-drain";
import { runLikeInngest } from "../../helpers/inngest-step-harness";

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

// Driven through the real step boundary (see cron-actions-queue-health-dispatch.test.ts
// for why the inline makeStep shape hides the SDK's re-invocation semantics).
// maxAttempts: 1 — a throwing dispatch callback is final on its first attempt.
function runHandler() {
  return runLikeInngest(({ step }) => cronMachineryDrainHandler({ step, logger }), {
    maxAttempts: 1,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("cronMachineryDrain — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronMachineryDrain).toBeDefined();
    expect(typeof cronMachineryDrain).toBe("object");
  });
});

describe("cronMachineryDrain — narrowed mint + single dispatch (#13096)", () => {
  it("mints exactly once with actions:write scoped to this repo, POSTs exactly one dispatch, returns ok", async () => {
    const out = await runHandler();
    expect(out.outcome).toBe("returned");
    expect(out.value).toEqual({ ok: true });

    // The narrowed scope is the load-bearing property — toEqual, not
    // toMatchObject: an extra permission widens the credential, and exactly
    // one mint means the token used for the dispatch IS the narrowly minted
    // one (no second broader mint can hide behind the literal).
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
    expect(params).toMatchObject({
      workflow_id: "scheduled-machinery-drain.yml",
      ref: "main",
    });
  });

  it("dispatch failure redacts the minted token before reportSilentFallback and returns ok:false", async () => {
    h.requestSpy.mockImplementationOnce(async () => {
      throw new Error("HTTP 403 for token fake-installation-token");
    });
    const out = await runHandler();
    expect(out.outcome).toBe("returned");
    expect(out.value).toEqual({ ok: false });

    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [errArg] = h.reportSilentFallbackSpy.mock.calls[0];
    // The credential must never reach the observability payload — the
    // redaction is the security property this test exists to pin.
    expect(String(errArg.message)).not.toContain("fake-installation-token");
    expect(String(errArg.message)).toContain("HTTP 403");
  });
});

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { beforeEach, describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE ES-module imports — set NEXT_PHASE so importing the
// inngest client (transitively pulled by the SUT) does not throw on the missing
// INNGEST_SIGNING_KEY in the test env. Mirrors cron-dev-migration-drift.test.ts.
const h = vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
  return {
    requestSpy: vi.fn(async (..._args: unknown[]) => ({ status: 204 })),
    reportSilentFallbackSpy: vi.fn((..._args: unknown[]) => {}),
  };
});

// Mock the dynamically-imported Octokit so the dispatch call is observable
// without hitting GitHub. The SUT does `const { Octokit } = await import("@octokit/core")`.
vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = h.requestSpy;
  },
}));

// Stub the installation-token mint so no GitHub App round-trip happens.
vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return {
    ...actual,
    mintInstallationToken: vi.fn(async () => "fake-installation-token"),
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
  cronDomainModelDrift,
  cronDomainModelDriftHandler,
} from "@/server/inngest/functions/cron-domain-model-drift";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-domain-model-drift.ts",
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

describe("cronDomainModelDrift — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronDomainModelDrift).toBeDefined();
    expect(typeof cronDomainModelDrift).toBe("object");
  });
});

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-domain-model-drift"', "canonical function id"],
    ['cron: "0 8 * * 1"', "weekly Mon 08:00 UTC schedule"],
    [
      'event: "cron/domain-model-drift.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
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
      '"scheduled-domain-model-drift.yml"',
      "dispatches the existing GHA workflow by filename",
    ],
    ['ref: "main"', "dispatches against main"],
    ["@octokit/core", "uses the cron Octokit pattern"],
    ["reportSilentFallback", "loud dispatch-failure reporting"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("HARD NON-GOAL: dispatcher runs no analyzer and clones no repo (AC3)", () => {
  // Anchor on execution-code CONSTRUCTS, not prose — the header comment
  // legitimately describes the deterministic analyzer to explain the hybrid.
  it.each([
    ["mkdtemp", "no ephemeral clone workspace"],
    ["spawn(", "no child-process execution"],
    ["child_process", "no process-spawning import"],
    ["buildAuthenticatedCloneUrl", "no git-clone URL builder"],
    ["resolveCronWorkspaceRoot", "no clone-workspace allocation"],
  ])("source does NOT use %s (%s)", (forbidden) => {
    expect(SUT_SOURCE).not.toContain(forbidden);
  });
});

describe("cronDomainModelDriftHandler — dispatch behavior", () => {
  beforeEach(() => {
    h.requestSpy.mockClear();
    h.reportSilentFallbackSpy.mockClear();
    h.requestSpy.mockResolvedValue({ status: 204 });
  });

  it("mints a token and POSTs the workflow_dispatch with ref=main, then returns ok", async () => {
    const result = await cronDomainModelDriftHandler({
      step: makeStep(),
      logger,
    });

    expect(h.requestSpy).toHaveBeenCalledTimes(1);
    const [endpoint, params] = h.requestSpy.mock.calls[0];
    expect(endpoint).toBe(
      "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
    );
    // Exhaustive (toEqual, not toMatchObject) — an extra/leaked field on a
    // credential-bearing dispatch call must fail the test. No `inputs`.
    expect(params).toEqual({
      owner: "jikig-ai",
      repo: "soleur",
      workflow_id: "scheduled-domain-model-drift.yml",
      ref: "main",
    });
    expect(result).toEqual({ ok: true });
    expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("reports to Sentry and returns not-ok when the dispatch throws", async () => {
    h.requestSpy.mockRejectedValueOnce(
      new Error("fake-installation-token leaked 403"),
    );

    const result = await cronDomainModelDriftHandler({
      step: makeStep(),
      logger,
    });

    expect(result).toEqual({ ok: false });
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [errArg, options] = h.reportSilentFallbackSpy.mock.calls[0];
    expect(options).toMatchObject({ feature: "cron-domain-model-drift" });
    // The minted token must be redacted out of the Error handed to Sentry.
    // Inspect the Error's .message directly — JSON.stringify(new Error(...))
    // drops the (non-enumerable) message, so a serialize-then-grep check would
    // pass vacuously whether or not redaction fired.
    const errMessage =
      errArg instanceof Error ? errArg.message : String(errArg);
    expect(errMessage).not.toContain("fake-installation-token");
    // Positive control: prove redaction ACTIVELY fired (an empty/dropped
    // message would also satisfy the negative assertion above).
    expect(errMessage).toContain("[REDACTED-INSTALLATION-TOKEN]");
  });
});

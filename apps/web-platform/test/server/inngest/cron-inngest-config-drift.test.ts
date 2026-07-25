import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { beforeEach, describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE ES-module imports — set NEXT_PHASE so importing the inngest client
// (transitively pulled by the SUT) does not throw on the missing INNGEST_SIGNING_KEY in the test
// env. Mirrors cron-terraform-drift.test.ts.
const h = vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
  return {
    requestSpy: vi.fn(async (..._args: unknown[]) => ({ status: 204 })),
    reportSilentFallbackSpy: vi.fn((..._args: unknown[]) => {}),
  };
});

vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = h.requestSpy;
  },
}));

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
  cronInngestConfigDrift,
  cronInngestConfigDriftHandler,
} from "@/server/inngest/functions/cron-inngest-config-drift";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-inngest-config-drift.ts",
  ),
  "utf-8",
);

function makeStep() {
  return {
    run: async <T>(_name: string, cb: () => Promise<T>): Promise<T> => cb(),
  };
}
const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

describe("cronInngestConfigDrift — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronInngestConfigDrift).toBeDefined();
    expect(typeof cronInngestConfigDrift).toBe("object");
  });
});

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-inngest-config-drift"', "canonical function id"],
    [
      'event: "cron/inngest-config-drift.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ["retries: 1", "single retry on failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("DORMANT: event-only until the #6178 cutover (HARD-11)", () => {
  // The comparator must NOT auto-fire pre-cutover (the marker it compares against only flows once
  // the host-side bake rides #6178). So the createFunction triggers array carries the manual-trigger
  // event and NO `{ cron: }` schedule. Anchor on the code construct `cron: "` — the header comment
  // legitimately says "{ cron: } schedule" in prose.
  it("has no live { cron: } schedule (event-only)", () => {
    expect(SUT_SOURCE).not.toContain('cron: "');
  });
});

describe("dispatch-hybrid source anchors", () => {
  it.each([
    [
      "/repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
      "workflow_dispatch endpoint",
    ],
    [
      '"inngest-config-drift.yml"',
      "dispatches the config-drift executor by filename",
    ],
    ['ref: "main"', "dispatches against main"],
    ["@octokit/core", "uses the cron Octokit pattern"],
    ["reportSilentFallback", "loud dispatch-failure reporting"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("HARD NON-GOAL: dispatcher runs no comparison and clones no repo", () => {
  // Anchor on execution-code CONSTRUCTS only — the header comment legitimately NAMES
  // betterstack-query.sh / inngest-config-drift-compare.sh in prose to explain the dispatch-hybrid,
  // so a bare-token negative on those would false-fail on the docstring.
  it.each([
    ["mkdtemp", "no ephemeral clone workspace"],
    ["spawn(", "no child-process execution"],
    ["child_process", "no process-spawning import"],
    ["execFile", "no external binary invocation"],
    ["readFileSync", "no in-process file read (pointer/marker parsing lives in the executor)"],
  ])("source does NOT use %s (%s)", (forbidden) => {
    expect(SUT_SOURCE).not.toContain(forbidden);
  });
});

describe("cronInngestConfigDriftHandler — dispatch behavior", () => {
  beforeEach(() => {
    h.requestSpy.mockClear();
    h.reportSilentFallbackSpy.mockClear();
    h.requestSpy.mockResolvedValue({ status: 204 });
  });

  it("mints a token and POSTs the workflow_dispatch with ref=main, then returns ok", async () => {
    const result = await cronInngestConfigDriftHandler({
      step: makeStep(),
      logger,
    });

    expect(h.requestSpy).toHaveBeenCalledTimes(1);
    const [endpoint, params] = h.requestSpy.mock.calls[0];
    expect(endpoint).toBe(
      "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
    );
    // Exhaustive (toEqual) — an extra/leaked field on a credential-bearing dispatch call fails.
    expect(params).toEqual({
      owner: "jikig-ai",
      repo: "soleur",
      workflow_id: "inngest-config-drift.yml",
      ref: "main",
    });
    expect(result).toEqual({ ok: true });
    expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("reports to Sentry and returns not-ok when the dispatch throws", async () => {
    h.requestSpy.mockRejectedValueOnce(
      new Error("fake-installation-token leaked 403"),
    );

    const result = await cronInngestConfigDriftHandler({
      step: makeStep(),
      logger,
    });

    expect(result).toEqual({ ok: false });
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [errArg, options] = h.reportSilentFallbackSpy.mock.calls[0];
    expect(options).toMatchObject({ feature: "cron-inngest-config-drift" });
    const errMessage =
      errArg instanceof Error ? errArg.message : String(errArg);
    expect(errMessage).not.toContain("fake-installation-token");
    expect(errMessage).toContain("[REDACTED-INSTALLATION-TOKEN]");
  });
});

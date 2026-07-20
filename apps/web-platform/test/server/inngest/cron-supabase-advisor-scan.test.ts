import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { beforeEach, describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE ES-module imports — set NEXT_PHASE so importing the
// inngest client (transitively pulled by the SUT) does not throw on the missing
// INNGEST_SIGNING_KEY in the test env. Without this the file errors at
// COLLECTION under CI (which has no inngest env), while passing locally under
// Doppler — mirrors cron-terraform-drift.test.ts.
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
  cronSupabaseAdvisorScan,
  cronSupabaseAdvisorScanHandler,
} from "@/server/inngest/functions/cron-supabase-advisor-scan";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-supabase-advisor-scan.ts",
  ),
  "utf-8",
);

function makeStep() {
  return {
    run: async <T>(_name: string, cb: () => Promise<T>): Promise<T> => cb(),
  };
}
const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

describe("cronSupabaseAdvisorScan — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronSupabaseAdvisorScan).toBeDefined();
    expect(typeof cronSupabaseAdvisorScan).toBe("object");
  });
});

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-supabase-advisor-scan"', "canonical function id"],
    ['cron: "37 3 * * *"', "nightly 03:37 UTC (20 min after the :17 self-heal)"],
    [
      'event: "cron/supabase-advisor-scan.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ["retries: 1", "single retry on failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("HARD NON-GOAL: the dispatcher holds no Supabase credential", () => {
  // The entire reason this is a dispatch hybrid rather than an in-process scan
  // is that the scan needs a Supabase cloud-admin PAT, which must not live on
  // the long-lived app host. Anchor on CONSTRUCTS the execution path would need
  // — not on prose, since the header comment legitimately discusses the PAT to
  // explain why it is absent.
  it.each([
    ["SUPABASE_ACCESS_TOKEN", "no Supabase PAT read"],
    ["api.supabase.com", "no direct Management API call"],
    ["advisors/security", "no advisor fetch in-process"],
    ["spawn(", "no child-process execution"],
    ["child_process", "no process-spawning import"],
  ])("source does NOT reference %s (%s)", (forbidden) => {
    expect(SUT_SOURCE).not.toContain(forbidden);
  });
});

describe("cronSupabaseAdvisorScanHandler — dispatch behavior", () => {
  beforeEach(() => {
    h.requestSpy.mockClear();
    h.reportSilentFallbackSpy.mockClear();
    h.requestSpy.mockResolvedValue({ status: 204 });
  });

  it("dispatches the workflow with source=inngest so the run may post its liveness check-in", async () => {
    const result = await cronSupabaseAdvisorScanHandler({
      step: makeStep(),
      logger,
    });

    expect(h.requestSpy).toHaveBeenCalledTimes(1);
    const [endpoint, params] = h.requestSpy.mock.calls[0];
    expect(endpoint).toBe(
      "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
    );
    // Exhaustive (toEqual, not toMatchObject) — an extra/leaked field on a
    // credential-bearing dispatch call must fail the test.
    expect(params).toEqual({
      owner: "jikig-ai",
      repo: "soleur",
      workflow_id: "scheduled-supabase-advisor-scan.yml",
      ref: "main",
      inputs: { source: "inngest" },
    });
    expect(result).toEqual({ ok: true });
    expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  // This assertion is why the test above uses toEqual. The workflow's Sentry
  // check-in is gated on inputs.source == 'inngest'. If this dispatcher ever
  // stopped sending it, the nightly run would scan correctly but post NO
  // check-in — and the monitor would page a missed check-in every night for a
  // gate that is actually working. The inverse of a fail-open, and just as
  // corrosive: an alarm that cries wolf gets muted, which is how #3366 rotted
  // for 71 days in the first place.
  it("sends the source input verbatim — the check-in gate depends on this exact value", async () => {
    await cronSupabaseAdvisorScanHandler({ step: makeStep(), logger });
    const [, params] = h.requestSpy.mock.calls[0];
    expect((params as { inputs?: Record<string, string> }).inputs?.source).toBe(
      "inngest",
    );
  });

  it("reports to Sentry and returns not-ok when the dispatch throws", async () => {
    h.requestSpy.mockRejectedValueOnce(
      new Error("fake-installation-token leaked 403"),
    );

    const result = await cronSupabaseAdvisorScanHandler({
      step: makeStep(),
      logger,
    });

    expect(result).toEqual({ ok: false });
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [errArg, options] = h.reportSilentFallbackSpy.mock.calls[0];
    expect(options).toMatchObject({ feature: "cron-supabase-advisor-scan" });
    // Inspect .message directly — JSON.stringify(new Error(...)) drops the
    // non-enumerable message, so a serialize-then-grep check would pass
    // vacuously whether or not redaction fired.
    const errMessage = errArg instanceof Error ? errArg.message : String(errArg);
    expect(errMessage).not.toContain("fake-installation-token");
    // Positive control: prove redaction ACTIVELY fired (an empty/dropped
    // message would also satisfy the negative assertion above).
    expect(errMessage).toContain("[REDACTED-INSTALLATION-TOKEN]");
  });
});

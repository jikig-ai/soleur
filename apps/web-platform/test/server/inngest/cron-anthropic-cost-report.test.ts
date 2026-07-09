import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Inngest-importing test → CI-equivalent guard (the cron module imports the
// inngest client, which throws on a missing INNGEST_SIGNING_KEY outside
// `next build`). Mirrors cron-compound-promote.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const { getAdminReportSpy, heartbeatSpy, dailyMarkerSpy, reportSilentFallbackSpy } =
  vi.hoisted(() => ({
    getAdminReportSpy: vi.fn(),
    heartbeatSpy: vi.fn(),
    dailyMarkerSpy: vi.fn(),
    reportSilentFallbackSpy: vi.fn(),
  }));

// Selective mock — keep AnthropicApiError + HandlerArgs real, override the two
// transport calls the handler makes.
vi.mock("@/server/inngest/functions/_cron-shared", async (orig) => {
  const actual =
    await orig<typeof import("@/server/inngest/functions/_cron-shared")>();
  return {
    ...actual,
    getAnthropicAdminReport: getAdminReportSpy,
    postSentryHeartbeat: heartbeatSpy,
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
}));

vi.mock("@/server/claude-cost-marker", () => ({
  emitClaudeCostDailyMarker: (...a: unknown[]) => dailyMarkerSpy(...a),
}));

import {
  cronAnthropicCostReportHandler,
  parseCostReportTotal,
  parseUsageReportModels,
  priorUtcDay,
} from "@/server/inngest/functions/cron-anthropic-cost-report";
import { AnthropicApiError } from "@/server/inngest/functions/_cron-shared";

// A step that just runs the callback (no memoization needed for the unit).
const step = { run: async <T>(_name: string, cb: () => Promise<T>) => cb() };
const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

const ORIGINAL_KEY = process.env.ANTHROPIC_ADMIN_KEY;
beforeEach(() => {
  getAdminReportSpy.mockReset();
  heartbeatSpy.mockReset();
  heartbeatSpy.mockResolvedValue(undefined);
  dailyMarkerSpy.mockReset();
  reportSilentFallbackSpy.mockReset();
  process.env.ANTHROPIC_ADMIN_KEY = "sk-ant-admin01-synthetic";
});
afterEach(() => {
  if (ORIGINAL_KEY === undefined) delete process.env.ANTHROPIC_ADMIN_KEY;
  else process.env.ANTHROPIC_ADMIN_KEY = ORIGINAL_KEY;
});

// -----------------------------------------------------------------------------
// Pure parse helpers (AC6b field-allowlist + amount unit)
// -----------------------------------------------------------------------------
describe("parseCostReportTotal (amount unit — plan R-D)", () => {
  it("sums decimal-string amounts across buckets/results as USD dollars", () => {
    const fixture = {
      data: [
        { results: [{ amount: "12.34", currency: "USD" }, { amount: "0.66" }] },
        { results: [{ amount: "1.00" }] },
      ],
    };
    expect(parseCostReportTotal(fixture)).toBeCloseTo(14.0, 5);
  });
  it("returns null when there are no result rows", () => {
    expect(parseCostReportTotal({ data: [] })).toBeNull();
    expect(parseCostReportTotal({})).toBeNull();
  });
});

describe("parseUsageReportModels (AC6b — curated keys only)", () => {
  it("builds per-model entries with ONLY the allowlisted keys (no api_key_id/workspace_id)", () => {
    const fixture = {
      data: [
        {
          results: [
            {
              model: "claude-opus-4-8",
              input_tokens: 100,
              output_tokens: 20,
              cache_read_input_tokens: 5,
              cache_creation_input_tokens: 3,
              // These MUST NOT leak into the marker (security F2):
              api_key_id: "apikey_secret",
              workspace_id: "wrkspc_secret",
            },
          ],
        },
      ],
    };
    const models = parseUsageReportModels(fixture);
    expect(models).toHaveLength(1);
    expect(Object.keys(models[0]).sort()).toEqual(
      [
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
        "cost_usd",
        "input_tokens",
        "model",
        "output_tokens",
      ].sort(),
    );
    expect(models[0]).not.toHaveProperty("api_key_id");
    expect(models[0]).not.toHaveProperty("workspace_id");
    expect(models[0].cost_usd).toBeNull();
  });
});

describe("priorUtcDay", () => {
  it("returns the prior UTC calendar day as YYYY-MM-DD", () => {
    expect(priorUtcDay(new Date("2026-07-09T03:00:00Z"))).toBe("2026-07-08");
  });
});

// -----------------------------------------------------------------------------
// Handler classify-fatal + fail-open (AC6)
// -----------------------------------------------------------------------------
describe("cronAnthropicCostReportHandler (AC6)", () => {
  it("missing ANTHROPIC_ADMIN_KEY → benign (no page) + a positive key-missing daily marker", async () => {
    delete process.env.ANTHROPIC_ADMIN_KEY;
    const res = await cronAnthropicCostReportHandler({ step, logger });
    expect(res).toEqual({ ok: true, status: "key-missing" });
    expect(dailyMarkerSpy).toHaveBeenCalledTimes(1);
    expect(dailyMarkerSpy.mock.calls[0][0]).toMatchObject({
      status: "key-missing",
      cost_usd: null,
      models: [],
    });
    // Benign heartbeat (ok:true — NOT a fleet-down page).
    expect(heartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ op: "anthropic-admin-key-missing" }),
    );
    expect(getAdminReportSpy).not.toHaveBeenCalled();
  });

  it("401 → RED heartbeat, no daily marker, classified fatal", async () => {
    getAdminReportSpy.mockRejectedValue(new AnthropicApiError(401, "bad key"));
    const res = await cronAnthropicCostReportHandler({ step, logger });
    expect(res).toEqual({ ok: false, status: "error" });
    expect(heartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: false }),
    );
    expect(dailyMarkerSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ op: "anthropic-admin-key-invalid" }),
    );
  });

  it("403 → RED heartbeat (classified fatal)", async () => {
    getAdminReportSpy.mockRejectedValue(new AnthropicApiError(403, "forbidden"));
    const res = await cronAnthropicCostReportHandler({ step, logger });
    expect(res).toEqual({ ok: false, status: "error" });
    expect(heartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: false }),
    );
  });

  it("429 on a NON-final attempt → rethrows for Inngest retry (no heartbeat)", async () => {
    getAdminReportSpy.mockRejectedValue(new AnthropicApiError(429, "rate limited"));
    await expect(
      cronAnthropicCostReportHandler({ step, logger, attempt: 0, maxAttempts: 2 }),
    ).rejects.toBeInstanceOf(AnthropicApiError);
    expect(heartbeatSpy).not.toHaveBeenCalled();
    expect(dailyMarkerSpy).not.toHaveBeenCalled();
  });

  it("429 on the FINAL attempt → RED heartbeat (retries exhausted)", async () => {
    getAdminReportSpy.mockRejectedValue(new AnthropicApiError(429, "rate limited"));
    const res = await cronAnthropicCostReportHandler({
      step,
      logger,
      attempt: 1,
      maxAttempts: 2,
    });
    expect(res).toEqual({ ok: false, status: "error" });
    expect(heartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: false }),
    );
  });

  it("success → GREEN heartbeat + authoritative SOLEUR_CLAUDE_COST_DAILY marker", async () => {
    getAdminReportSpy.mockImplementation(
      async (args: { path: string }) => {
        if (args.path.includes("cost_report")) {
          return { data: [{ results: [{ amount: "7.50", currency: "USD" }] }] };
        }
        return {
          data: [
            {
              results: [
                {
                  model: "claude-opus-4-8",
                  input_tokens: 100,
                  output_tokens: 20,
                  cache_read_input_tokens: 5,
                  cache_creation_input_tokens: 3,
                  api_key_id: "apikey_secret",
                },
              ],
            },
          ],
        };
      },
    );
    const res = await cronAnthropicCostReportHandler({ step, logger });
    expect(res).toEqual({ ok: true, status: "ok" });
    expect(getAdminReportSpy).toHaveBeenCalledTimes(2);
    expect(heartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
    expect(dailyMarkerSpy).toHaveBeenCalledTimes(1);
    const emitted = dailyMarkerSpy.mock.calls[0][0];
    expect(emitted).toMatchObject({ status: "ok", cost_usd: 7.5 });
    expect(emitted.models[0]).not.toHaveProperty("api_key_id");
    expect(emitted.models[0]).toMatchObject({
      model: "claude-opus-4-8",
      input_tokens: 100,
    });
  });
});

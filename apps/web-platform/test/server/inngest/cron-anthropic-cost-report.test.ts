import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Inngest-importing test → CI-equivalent guard (the cron module imports the
// inngest client, which throws on a missing INNGEST_SIGNING_KEY outside
// `next build`). Mirrors cron-compound-promote.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const {
  getAdminReportSpy,
  heartbeatSpy,
  dailyMarkerSpy,
  reportSilentFallbackSpy,
  warnSilentFallbackSpy,
} = vi.hoisted(() => ({
  getAdminReportSpy: vi.fn(),
  heartbeatSpy: vi.fn(),
  dailyMarkerSpy: vi.fn(),
  reportSilentFallbackSpy: vi.fn(),
  warnSilentFallbackSpy: vi.fn(),
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

// Both severities must be exported: the key-missing branch emits at WARNING
// (benign, non-paging) while 401/403 stays at ERROR. Omitting `warnSilentFallback`
// here makes the handler's import `undefined` and the suite dies with a
// `TypeError` instead of a clean assertion failure.
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: (...a: unknown[]) => warnSilentFallbackSpy(...a),
}));

vi.mock("@/server/claude-cost-marker", () => ({
  emitClaudeCostDailyMarker: (...a: unknown[]) => dailyMarkerSpy(...a),
}));

import {
  cronAnthropicCostReportHandler,
  daysSinceFirstDark,
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
  warnSilentFallbackSpy.mockReset();
  process.env.ANTHROPIC_ADMIN_KEY = "sk-ant-admin01-synthetic";
});
afterEach(() => {
  vi.useRealTimers();
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

describe("daysSinceFirstDark", () => {
  it("counts whole UTC days from the first observed dark fire (2026-07-10)", () => {
    expect(daysSinceFirstDark(new Date("2026-07-20T00:00:00Z"))).toBe(10);
    expect(daysSinceFirstDark(new Date("2026-07-10T00:00:00Z"))).toBe(0);
  });
  it("floors at 0 for a date before the constant (clock skew / backfill)", () => {
    expect(daysSinceFirstDark(new Date("2026-07-01T00:00:00Z"))).toBe(0);
  });
  // The midnight samples above are all exact multiples of 86.4e6, where
  // floor === ceil === round — so on their own they do NOT pin the flooring
  // semantics, and Math.ceil satisfies every one of them. These mid-day
  // samples are the ones that distinguish. 06:17 UTC is the real fire time.
  it("FLOORS a partial day rather than rounding or ceiling it", () => {
    expect(daysSinceFirstDark(new Date("2026-07-20T06:17:00Z"))).toBe(10);
    expect(daysSinceFirstDark(new Date("2026-07-20T23:59:59Z"))).toBe(10);
    expect(daysSinceFirstDark(new Date("2026-07-10T23:59:59Z"))).toBe(0);
  });
});

// -----------------------------------------------------------------------------
// Handler classify-fatal + fail-open (AC6)
// -----------------------------------------------------------------------------
describe("cronAnthropicCostReportHandler (AC6)", () => {
  it("missing ANTHROPIC_ADMIN_KEY → benign (no page) + a positive key-missing daily marker", async () => {
    delete process.env.ANTHROPIC_ADMIN_KEY;
    // Pin the clock so days_since_first_dark has one correct value to assert.
    // 2026-07-10 (FIRST_DARK_FIRE) + 25d = 2026-08-04; the mid-day time also
    // keeps this sample off the floor/ceil-equivalent midnight boundary.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-04T06:17:00Z"));
    const res = await cronAnthropicCostReportHandler({ step, logger });
    expect(res).toEqual({ ok: true, status: "key-missing" });
    expect(dailyMarkerSpy).toHaveBeenCalledTimes(1);
    expect(dailyMarkerSpy.mock.calls[0][0]).toMatchObject({
      status: "key-missing",
      cost_usd: null,
      models: [],
    });
    // The dark window carries its own age, so a stale mint is visible in the
    // marker rather than inferred from the absence of an `ok` row. Assert the
    // VALUE against a pinned clock — a `typeof … === "number"` check is
    // satisfied by a hardcoded 0, which is exactly the stale-reporting bug
    // this field exists to prevent.
    expect(dailyMarkerSpy.mock.calls[0][0].days_since_first_dark).toBe(25);
    // Benign heartbeat (ok:true — NOT a fleet-down page).
    expect(heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
    // The benign dark state must NOT reach Sentry at `level:error` — that is
    // what derives issue priority=high and fires the operator's "high priority
    // issues" notification rule, producing a daily false page (#6297).
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    expect(warnSilentFallbackSpy).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ op: "anthropic-admin-key-missing" }),
    );
    // Content anchor, not a bare `op:` token (cq-assert-anchor-not-bare-token):
    // the operator-facing string the Better Stack runbook documents. A bare
    // `op:` check would pass against an emptied message.
    expect(warnSilentFallbackSpy.mock.calls[0][1].message).toContain(
      "daily cost report is dark",
    );
    expect(getAdminReportSpy).not.toHaveBeenCalled();
  });

  it("401 → RED heartbeat, no daily marker, classified fatal", async () => {
    getAdminReportSpy.mockRejectedValue(new AnthropicApiError(401, "bad key"));
    const res = await cronAnthropicCostReportHandler({ step, logger });
    expect(res).toEqual({ ok: false, status: "error" });
    expect(heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: false }),
    );
    expect(dailyMarkerSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ op: "anthropic-admin-key-invalid" }),
    );
    // Regression guard: a future "just make it all warn" edit must not weaken
    // the genuinely-fatal arm to a non-paging severity.
    expect(warnSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("403 → RED heartbeat (classified fatal), still at ERROR severity", async () => {
    getAdminReportSpy.mockRejectedValue(new AnthropicApiError(403, "forbidden"));
    const res = await cronAnthropicCostReportHandler({ step, logger });
    expect(res).toEqual({ ok: false, status: "error" });
    expect(heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: false }),
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ op: "anthropic-admin-key-invalid" }),
    );
    expect(warnSilentFallbackSpy).not.toHaveBeenCalled();
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
    expect(heartbeatSpy).toHaveBeenCalledTimes(1);
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
    expect(heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
    expect(dailyMarkerSpy).toHaveBeenCalledTimes(1);
    const emitted = dailyMarkerSpy.mock.calls[0][0];
    expect(emitted).toMatchObject({ status: "ok", cost_usd: 7.5 });
    // The dark-window age is a key-missing-only field. Emitting it on `ok` rows
    // would make `JSONExtractInt(raw,'days_since_first_dark')` ambiguous between
    // "healthy row" and a genuine day-0 dark row (see the runbook's absent-vs-zero note).
    expect(emitted).not.toHaveProperty("days_since_first_dark");
    expect(emitted.models[0]).not.toHaveProperty("api_key_id");
    expect(emitted.models[0]).toMatchObject({
      model: "claude-opus-4-8",
      input_tokens: 100,
    });
  });
});

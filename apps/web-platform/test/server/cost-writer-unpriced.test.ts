// #9648 Phase B-0 — an unpriced model must never write a $0 BYOK ledger row.
// Both writers (fire-and-forget persistTurnCost AND the leader-loop's
// persistTurnCostAwaitable) treat a non-finite totalCostUsd as the
// "unpriced" sentinel: skip the audit/delegation write, alert Sentry with
// the queryable op tag, mark the cost marker "unpriced"/null — but still
// record token deltas on increment_conversation_cost.
import { beforeEach, describe, expect, it, vi } from "vitest";

const { markerMock, rpcMock, sentryMock } = vi.hoisted(() => ({
  markerMock: vi.fn(),
  rpcMock: vi.fn(async (_name: string, _args?: Record<string, unknown>) => ({ error: null })),
  sentryMock: vi.fn(),
}));
// Importing agent-on-spawn-requested calls inngest.createFunction at module
// load; NEXT_PHASE short-circuits the client's startup-key check
// (idiom from model-tiers.test.ts / cron-roadmap-review.test.ts:19-26).
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
vi.mock("@/lib/supabase/service", () => ({ createServiceClient: () => ({ rpc: rpcMock }) }));
vi.mock("@/server/ws-handler", () => ({ sendToClient: vi.fn() }));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: sentryMock,
}));
vi.mock("@/server/claude-cost-marker", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/claude-cost-marker")>()),
  emitClaudeCostMarker: markerMock,
}));

import { persistTurnCost, persistTurnCostAwaitable } from "@/server/cost-writer";

const usage = {
  input_tokens: 10,
  output_tokens: 5,
  cache_read_input_tokens: 0,
  cache_creation_input_tokens: 0,
};

const USER = "11111111-1111-4111-8111-111111111111";
const marker = { source: "leader-loop" as const, model: "unpriced-model", turn: 1, attempt: 1 };

beforeEach(() => {
  markerMock.mockClear();
  rpcMock.mockClear();
  sentryMock.mockClear();
});

describe.each(["awaitable", "sync"] as const)(
  "unpriced model fail-closed (#9648 B-0) — %s writer",
  (variant) => {
    const persist = (
      input: Parameters<typeof persistTurnCost>[4],
      delegation?: Parameters<typeof persistTurnCost>[6],
    ) =>
      variant === "awaitable"
        ? persistTurnCostAwaitable(USER, "conv-x", "cfo", USER, input, marker)
        : persistTurnCost(USER, "conv-x", "cfo", USER, input, marker, delegation);

    it.each([Number.NaN, Infinity, -Infinity])(
      "totalCostUsd=%s → no ledger write + Sentry op tag + marker 'unpriced'",
      async (cost) => {
        await persist({ totalCostUsd: cost, usage });
        const rpcNames = rpcMock.mock.calls.map((c) => c[0]);
        expect(rpcNames).not.toContain("write_byok_audit");
        expect(rpcNames).not.toContain("check_and_record_byok_delegation_use");
        expect(sentryMock).toHaveBeenCalledWith(
          expect.any(Error),
          expect.objectContaining({
            feature: "agent-cost-tracking",
            op: "unpriced-model",
          }),
        );
        expect(markerMock).toHaveBeenCalledWith(
          expect.objectContaining({ capture_status: "unpriced", cost_usd: null }),
        );
      },
    );

    it("token deltas still reach increment_conversation_cost with cost_delta 0", async () => {
      await persist({ totalCostUsd: Number.NaN, usage });
      const incr = rpcMock.mock.calls.find((c) => c[0] === "increment_conversation_cost");
      expect(incr?.[1]).toMatchObject({ cost_delta: 0, input_delta: 10, output_delta: 5 });
    });

    it("delegated path: unpriced turn never reaches check_and_record_byok_delegation_use", async () => {
      await persist(
        { totalCostUsd: Number.NaN, usage },
        { delegationId: "del-1", callerUserId: USER },
      );
      const rpcNames = rpcMock.mock.calls.map((c) => c[0]);
      expect(rpcNames).not.toContain("check_and_record_byok_delegation_use");
      expect(sentryMock).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({ op: "unpriced-model" }),
      );
    });

    it("priced path unchanged: write_byok_audit fires with rounded cents", async () => {
      await persist({ totalCostUsd: 0.0123, usage });
      const audit = rpcMock.mock.calls.find((c) => c[0] === "write_byok_audit");
      expect(audit?.[1]).toMatchObject({ p_unit_cost_cents: 1 });
      expect(markerMock).toHaveBeenCalledWith(
        expect.objectContaining({ capture_status: "ok", cost_usd: 0.0123 }),
      );
    });
  },
);

describe("resolveTurnCostUsd — producer-side NaN contract (#9648 B-0)", () => {
  it("a model absent from MODEL_PRICING resolves NaN, not 0", async () => {
    const { resolveTurnCostUsd, MODEL_PRICING } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const u = { input_tokens: 100, output_tokens: 10, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };
    expect(resolveTurnCostUsd("mistral-large-4", u)).toBeNaN();
    for (const key of Object.keys(MODEL_PRICING)) {
      expect(resolveTurnCostUsd(key, u)).toBeGreaterThan(0);
    }
  });
});

// Haiku 5.5 launch (2026-10-08): the REAL writers round a turn's dollars to integer cents
// with Math.round(cost * 100) and store that in the append-only audit_byok_use ledger. A
// typical Haiku 5.5 turn costs a fraction of a cent, so it is stored as 0. That is the
// documented #6945 gap (ADR-041 addendum 2026-10-08): this pins the CURRENT behaviour
// through the actual writers so a fix to #6945 is a deliberate test change, instead of a
// test that recomputes Math.round itself and cannot notice cost-writer.ts changing.
describe.each(["awaitable", "sync"] as const)(
  "integer-cent rounding through the real %s writer (#6945, pinned not endorsed)",
  (variant) => {
    const cents = async (totalCostUsd: number): Promise<number> => {
      rpcMock.mockClear();
      const input = { totalCostUsd, usage };
      if (variant === "awaitable") {
        await persistTurnCostAwaitable(USER, "conv-x", "cfo", USER, input, marker);
      } else {
        await persistTurnCost(USER, "conv-x", "cfo", USER, input, marker);
      }
      const audit = rpcMock.mock.calls.find((c) => c[0] === "write_byok_audit");
      expect(audit, "a priced turn always writes one ledger row, even at 0 cents").toBeDefined();
      return audit![1]!.p_unit_cost_cents as number;
    };

    it("sub-half-cent turns are stored as 0 cents (a typical Haiku 5.5 turn)", async () => {
      expect(await cents(0.0007)).toBe(0); // mostly cache reads
      expect(await cents(0.0025)).toBe(0); // 20K uncached input + 1K output
      expect(await cents(0.004999)).toBe(0);
    });

    it("the half-cent edge rounds UP to 1 cent; one cent and a half rounds to 2", async () => {
      expect(await cents(0.005)).toBe(1);
      expect(await cents(0.0149)).toBe(1);
      expect(await cents(0.015)).toBe(2);
    });

    it("an ALL-UNCACHED long-card turn is 5 cents; the same prompt as cache reads is only 1 cent", async () => {
      // 100,001 uncached input tokens on the Haiku 5.5 long card = 100001 * $0.50/M = $0.0500005
      expect(await cents(0.0500005)).toBe(5);
      // 100,001 CACHE-READ tokens = 100001 * $0.05/M = $0.00500005: half a cent, rounds to 1.
      // So the long-card cliff is up to 5x lower for cache-heavy prompts than the all-uncached case.
      expect(await cents(0.00500005)).toBe(1);
    });
  },
);

// #8978 Phase-0.3 — header-scoped tracesSampler + transaction-envelope scrub.
//
// `tracesSampleRate: 0` was replaced by a `tracesSampler` so the committed
// perf probe (`x-perf-probe: 1` request header) samples at 1.0 while all
// other traffic pays a ~0.02 floor — no env/Doppler change.
//
// The second gate is the #3829 interaction the plan names: transaction
// envelopes DO NOT flow through `beforeSend` — they flow through
// `beforeSendTransaction`. Enabling tracing without that callback would ship
// un-scrubbed transaction payloads (URL/headers/spans) to Sentry.

import { describe, it, expect, vi } from "vitest";

const { initSpy } = vi.hoisted(() => ({ initSpy: vi.fn() }));

vi.mock("@sentry/nextjs", () => ({ init: initSpy }));

async function loadOptions() {
  await import("../sentry.server.config");
  expect(initSpy).toHaveBeenCalledTimes(1);
  return initSpy.mock.calls[0][0] as {
    tracesSampler: (ctx: {
      name: string;
      normalizedRequest?: { headers?: Record<string, string> };
      inheritOrSampleWith?: (n: number) => number;
    }) => number | boolean;
    beforeSendTransaction?: (event: unknown) => unknown;
    tracesSampleRate?: number;
  };
}

describe("sentry.server.config tracesSampler (#8978)", () => {
  it("samples at 1.0 when the request carries x-perf-probe: 1", async () => {
    const opts = await loadOptions();
    expect(
      opts.tracesSampler({
        name: "GET /api/workspace/active-repo",
        normalizedRequest: { headers: { "x-perf-probe": "1" } },
      }),
    ).toBe(1);
  });

  it("header name match is case-insensitive on the normalized request", async () => {
    const opts = await loadOptions();
    expect(
      opts.tracesSampler({
        name: "GET /dashboard",
        normalizedRequest: { headers: { "X-Perf-Probe": "1" } },
      }),
    ).toBe(1);
  });

  it("applies the low floor when the header is absent or wrong-valued", async () => {
    const opts = await loadOptions();
    expect(opts.tracesSampler({ name: "GET /api/x" })).toBeLessThanOrEqual(
      0.05,
    );
    expect(
      opts.tracesSampler({
        name: "GET /api/x",
        normalizedRequest: { headers: {} },
      }),
    ).toBeLessThanOrEqual(0.05);
    expect(
      opts.tracesSampler({
        name: "GET /api/x",
        normalizedRequest: { headers: { "x-perf-probe": "yes" } },
      }),
    ).toBeLessThanOrEqual(0.05);
    // A non-zero floor keeps baseline tracing coverage for non-probe traffic.
    expect(opts.tracesSampler({ name: "GET /api/x" })).toBeGreaterThan(0);
  });

  it("transaction envelopes are scrubbed via beforeSendTransaction (not left to beforeSend)", async () => {
    const opts = await loadOptions();
    expect(typeof opts.beforeSendTransaction).toBe("function");
    const event = {
      type: "transaction",
      transaction: "GET /api/x",
      request: {
        headers: { authorization: "Bearer secret-token", host: "app.soleur.ai" },
      },
      extra: { userId: "00000000-0000-0000-0000-0000000000aa" },
    };
    const out = opts.beforeSendTransaction!(event) as typeof event & {
      extra: Record<string, unknown>;
    };
    expect(out.request.headers.authorization).toBe("[Redacted]");
    expect(out.request.headers.host).toBe("app.soleur.ai");
    // userId rename special-case: raw key dropped, pseudonymous hash written.
    expect(out.extra.userId).toBeUndefined();
    expect(out.extra.userIdHash).toBeDefined();
  });
});

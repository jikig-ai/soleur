import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock @sentry/nextjs BEFORE importing the SUT so `Sentry.init` is a spy
// when the config module's top-level call executes. vitest hoists vi.mock
// to the top of the file regardless of import order.
const initSpy = vi.fn();
vi.mock("@sentry/nextjs", () => ({
  init: (...args: unknown[]) => initSpy(...args),
}));

describe("sentry.server.config wiring", () => {
  beforeEach(() => {
    initSpy.mockClear();
    vi.resetModules();
  });

  it("wires beforeSend → scrubSentryEvent and beforeBreadcrumb → scrubSentryBreadcrumb", async () => {
    // Import the config module — its top-level `Sentry.init({...})` runs now.
    await import("@/sentry.server.config");
    const { scrubSentryEvent, scrubSentryBreadcrumb } = await import(
      "@/server/sentry-scrub"
    );

    expect(initSpy).toHaveBeenCalledTimes(1);
    const config = initSpy.mock.calls[0][0] as {
      beforeSend?: (e: unknown) => unknown;
      beforeBreadcrumb?: (b: unknown) => unknown;
    };

    // The hooks delegate to the scrubbers; functional equivalence is the
    // load-bearing contract (referential equality would also work but the
    // config wraps in arrow fns for clarity).
    const eventIn = { contexts: { byok: { apiKey: "PLAINTEXT_WIRING" } } };
    const eventOut = config.beforeSend!(eventIn) as {
      contexts: { byok: { apiKey: string } };
    };
    const expected = scrubSentryEvent(eventIn) as typeof eventOut;
    expect(eventOut.contexts.byok.apiKey).toBe(expected.contexts.byok.apiKey);
    expect(eventOut.contexts.byok.apiKey).toBe("[Redacted]");

    const bcIn = { data: { token: "PLAINTEXT_WIRING_BC" } };
    const bcOut = config.beforeBreadcrumb!(bcIn) as {
      data: { token: string };
    };
    const bcExpected = scrubSentryBreadcrumb(bcIn) as typeof bcOut;
    expect(bcOut.data.token).toBe(bcExpected.data.token);
    expect(bcOut.data.token).toBe("[Redacted]");
  });
});

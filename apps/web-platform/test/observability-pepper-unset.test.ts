import { describe, it, expect, vi, beforeEach } from "vitest";

// Pepper-unset (fail-closed) coverage. Lives in its own file so vitest's
// per-file worker isolation keeps `SENTRY_USERID_PEPPER` deleted at module
// load — module-init reads the env var once at top level.
//
// `consoleWarnSpy` is hoisted alongside the env-var delete so it's wrapping
// `console.warn` BEFORE the SUT's module-init `console.warn(...)` fires.
const { consoleWarnSpy } = vi.hoisted(() => {
  delete process.env.SENTRY_USERID_PEPPER;
  const spy = vi.fn();
  // eslint-disable-next-line no-console
  console.warn = spy;
  return { consoleWarnSpy: spy };
});

const {
  mockCaptureException,
  mockCaptureMessage,
  mockLoggerError,
  mockLoggerWarn,
} = vi.hoisted(() => ({
  mockCaptureException: vi.fn(),
  mockCaptureMessage: vi.fn(),
  mockLoggerError: vi.fn(),
  mockLoggerWarn: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: mockCaptureMessage,
}));

vi.mock("@/server/logger", () => ({
  default: { error: mockLoggerError, warn: mockLoggerWarn, info: vi.fn(), debug: vi.fn() },
}));

import {
  reportSilentFallback,
  warnSilentFallback,
  mirrorP0Deduped,
  hashUserId,
  __resetMirrorP0DedupForTests,
} from "../server/observability";

beforeEach(() => {
  mockCaptureException.mockReset();
  mockCaptureMessage.mockReset();
  mockLoggerError.mockReset();
  mockLoggerWarn.mockReset();
  __resetMirrorP0DedupForTests();
});

describe("pepper unset (fail-closed) — emits sentinel, never throws", () => {
  it("hashUserId returns the 'pepper_unset' sentinel when no pepper available", () => {
    expect(hashUserId("anything")).toBe("pepper_unset");
  });

  it("emits a one-shot boot warning at module load when pepper is unset", () => {
    // The console.warn fires once at module-init, captured by the spy above.
    expect(consoleWarnSpy).toHaveBeenCalled();
    const messages = consoleWarnSpy.mock.calls.map((c) => String(c[0] ?? ""));
    expect(messages.some((m) => m.includes("SENTRY_USERID_PEPPER"))).toBe(true);
  });

  it("reportSilentFallback emits userIdHash='pepper_unset' and does not throw", () => {
    const err = new Error("x");
    expect(() =>
      reportSilentFallback(err, {
        feature: "kb-share",
        op: "create",
        extra: { userId: "u1" },
      }),
    ).not.toThrow();

    const [, payload] = mockCaptureException.mock.calls[0];
    expect(payload.extra.userIdHash).toBe("pepper_unset");
    expect(payload.extra).not.toHaveProperty("userId");
  });

  it("warnSilentFallback emits userIdHash='pepper_unset' and does not throw", () => {
    expect(() =>
      warnSilentFallback("string-err", {
        feature: "foo",
        extra: { userId: "u2" },
      }),
    ).not.toThrow();
    const [, payload] = mockCaptureMessage.mock.calls[0];
    expect(payload.extra.userIdHash).toBe("pepper_unset");
    expect(payload.extra).not.toHaveProperty("userId");
  });

  it("mirrorP0Deduped emits userIdHash='pepper_unset' in tags+extra and does not throw", () => {
    const err = new Error("x");
    expect(() =>
      mirrorP0Deduped(err, {
        op: "o",
        userId: "u3",
        conversationId: "c",
      }),
    ).not.toThrow();
    const [, payload] = mockCaptureException.mock.calls[0];
    expect(payload.tags.userIdHash).toBe("pepper_unset");
    expect(payload.extra.userIdHash).toBe("pepper_unset");
    expect(payload.extra).not.toHaveProperty("userId");
    expect(payload.tags).not.toHaveProperty("userId");
  });
});

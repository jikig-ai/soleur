import { describe, it, expect, vi, beforeEach, afterAll } from "vitest";

const { mockCaptureException, mockCaptureMessage } = vi.hoisted(() => ({
  mockCaptureException: vi.fn(),
  mockCaptureMessage: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: mockCaptureMessage,
}));

import {
  reportSilentFallback,
  warnSilentFallback,
} from "@/lib/client-observability";

const consoleWarnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

// Typed helpers — one refactor site if Sentry's `captureException` /
// `captureMessage` signatures change, instead of seven brittle indexing
// sites that fail identically with cryptic "Cannot read undefined" errors.
type CapturedOptions = { extra?: Record<string, unknown> };
const lastExceptionExtra = (): Record<string, unknown> | undefined =>
  (mockCaptureException.mock.calls[0]?.[1] as CapturedOptions | undefined)
    ?.extra;
const lastMessageExtra = (): Record<string, unknown> | undefined =>
  (mockCaptureMessage.mock.calls[0]?.[1] as CapturedOptions | undefined)
    ?.extra;

beforeEach(() => {
  mockCaptureException.mockReset();
  mockCaptureMessage.mockReset();
  consoleWarnSpy.mockClear();
  vi.unstubAllEnvs();
});

afterAll(() => {
  vi.unstubAllEnvs();
  consoleWarnSpy.mockRestore();
});

describe("client-observability stripPiiKeys", () => {
  it("strips userId from extra on reportSilentFallback (Error path)", () => {
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded ClientExtra forbids `userId`; runtime
      // strip is the backstop being tested here.
      extra: { userId: "u1", segment: "dashboard" },
    });
    const extra = lastExceptionExtra();
    expect(extra?.userId).toBeUndefined();
    expect(extra?.segment).toBe("dashboard");
    expect(extra?.piiStripped).toEqual(["userId"]);
  });

  it("strips user_id (snake) + email from extra", () => {
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { user_id: "u1", email: "a@b.com", filename: "x.png" },
    });
    const extra = lastExceptionExtra();
    expect(extra?.user_id).toBeUndefined();
    expect(extra?.email).toBeUndefined();
    expect(extra?.filename).toBe("x.png");
    expect(extra?.piiStripped).toEqual(
      expect.arrayContaining(["user_id", "email"]),
    );
  });

  it("strips userId from extra on warnSilentFallback (Error path)", () => {
    warnSilentFallback(new Error("degraded"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { userId: "u1" },
    });
    const extra = lastExceptionExtra();
    expect(extra?.userId).toBeUndefined();
    expect(extra?.piiStripped).toEqual(["userId"]);
  });

  it("strips userId from extra on warnSilentFallback (non-Error path)", () => {
    warnSilentFallback(null, {
      feature: "test",
      message: "degraded",
      // @ts-expect-error — branded
      extra: { userId: "u1" },
    });
    const extra = lastMessageExtra();
    expect(extra?.userId).toBeUndefined();
    expect(extra?.piiStripped).toEqual(["userId"]);
  });

  it("passes through non-PII keys unchanged when no PII present", () => {
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      extra: { segment: "dashboard", digest: "abc" },
    });
    const extra = lastExceptionExtra();
    expect(extra?.segment).toBe("dashboard");
    expect(extra?.digest).toBe("abc");
    expect(extra?.piiStripped).toBeUndefined();
  });

  it("handles undefined extra without throwing", () => {
    reportSilentFallback(new Error("boom"), { feature: "test" });
    expect(mockCaptureException).toHaveBeenCalledOnce();
  });

  it("emits a dev-only console.warn when a strip fires", () => {
    vi.stubEnv("NODE_ENV", "development");
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { userId: "u1" },
    });
    expect(consoleWarnSpy).toHaveBeenCalledWith(
      expect.stringContaining("stripped PII keys"),
    );
  });

  it("is silent in production NODE_ENV", () => {
    vi.stubEnv("NODE_ENV", "production");
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { userId: "u1" },
    });
    expect(consoleWarnSpy).not.toHaveBeenCalled();
  });

  // Branded `extra` denies the canonical PiiKey union but allows arbitrary
  // other keys; case variants pass the brand at compile time and the
  // runtime strip catches them via the case-insensitive regex flag.
  // Per-variant rows so a regression that loses the `i` flag (or anchor
  // tightening) names the specific failing casing in the test report.
  it.each([["UserID"], ["USERID"], ["UserId"], ["USERid"], ["userid"]])(
    "strips case variant %s from extra",
    (variant) => {
      reportSilentFallback(new Error("boom"), {
        feature: "test",
        extra: { [variant]: "u1", segment: "kept" } as Record<
          string,
          unknown
        >,
      });
      const extra = lastExceptionExtra();
      expect(extra?.[variant]).toBeUndefined();
      expect(extra?.segment).toBe("kept");
    },
  );

  it("strips userId for non-Error path with extra (warnSilentFallback string)", () => {
    warnSilentFallback("some-string-err", {
      feature: "test",
      message: "fallback",
      // @ts-expect-error — branded
      extra: { userId: "u1", segment: "kept" },
    });
    const extra = lastMessageExtra();
    // The non-Error path also splices `err` into extra; verify userId is
    // stripped but `err` and non-PII keys survive.
    expect(extra?.userId).toBeUndefined();
    expect(extra?.segment).toBe("kept");
  });
});

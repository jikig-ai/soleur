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

const ORIGINAL_NODE_ENV = process.env.NODE_ENV;
const consoleWarnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

beforeEach(() => {
  mockCaptureException.mockReset();
  mockCaptureMessage.mockReset();
  consoleWarnSpy.mockClear();
  process.env.NODE_ENV = ORIGINAL_NODE_ENV;
});

afterAll(() => {
  process.env.NODE_ENV = ORIGINAL_NODE_ENV;
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
    const call = mockCaptureException.mock.calls[0]?.[1] as {
      extra?: Record<string, unknown>;
    };
    expect(call.extra?.userId).toBeUndefined();
    expect(call.extra?.segment).toBe("dashboard");
    expect(call.extra?.piiStripped).toEqual(["userId"]);
  });

  it("strips user_id (snake) + email from extra", () => {
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { user_id: "u1", email: "a@b.com", filename: "x.png" },
    });
    const call = mockCaptureException.mock.calls[0]?.[1] as {
      extra?: Record<string, unknown>;
    };
    expect(call.extra?.user_id).toBeUndefined();
    expect(call.extra?.email).toBeUndefined();
    expect(call.extra?.filename).toBe("x.png");
    expect(call.extra?.piiStripped).toEqual(
      expect.arrayContaining(["user_id", "email"]),
    );
  });

  it("strips userId from extra on warnSilentFallback (Error path)", () => {
    warnSilentFallback(new Error("degraded"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { userId: "u1" },
    });
    const call = mockCaptureException.mock.calls[0]?.[1] as {
      extra?: Record<string, unknown>;
    };
    expect(call.extra?.userId).toBeUndefined();
    expect(call.extra?.piiStripped).toEqual(["userId"]);
  });

  it("strips userId from extra on warnSilentFallback (non-Error path)", () => {
    warnSilentFallback(null, {
      feature: "test",
      message: "degraded",
      // @ts-expect-error — branded
      extra: { userId: "u1" },
    });
    const call = mockCaptureMessage.mock.calls[0]?.[1] as {
      extra?: Record<string, unknown>;
    };
    expect(call.extra?.userId).toBeUndefined();
    expect(call.extra?.piiStripped).toEqual(["userId"]);
  });

  it("passes through non-PII keys unchanged when no PII present", () => {
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      extra: { segment: "dashboard", digest: "abc" },
    });
    const call = mockCaptureException.mock.calls[0]?.[1] as {
      extra?: Record<string, unknown>;
    };
    expect(call.extra?.segment).toBe("dashboard");
    expect(call.extra?.digest).toBe("abc");
    expect(call.extra?.piiStripped).toBeUndefined();
  });

  it("handles undefined extra without throwing", () => {
    reportSilentFallback(new Error("boom"), { feature: "test" });
    expect(mockCaptureException).toHaveBeenCalledOnce();
  });

  it("emits a dev-only console.warn when a strip fires", () => {
    process.env.NODE_ENV = "development";
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
    process.env.NODE_ENV = "production";
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { userId: "u1" },
    });
    expect(consoleWarnSpy).not.toHaveBeenCalled();
  });

  it("matches case-insensitive userId variants (UserID, USERID)", () => {
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { UserID: "u1", USERID: "u2" } as Record<string, unknown>,
    });
    const call = mockCaptureException.mock.calls[0]?.[1] as {
      extra?: Record<string, unknown>;
    };
    expect(call.extra?.UserID).toBeUndefined();
    expect(call.extra?.USERID).toBeUndefined();
  });

  it("strips userId for non-Error path with extra (warnSilentFallback string)", () => {
    warnSilentFallback("some-string-err", {
      feature: "test",
      message: "fallback",
      // @ts-expect-error — branded
      extra: { userId: "u1", segment: "kept" },
    });
    const call = mockCaptureMessage.mock.calls[0]?.[1] as {
      extra?: Record<string, unknown>;
    };
    // The non-Error path also splices `err` into extra; verify userId is
    // stripped but `err` and non-PII keys survive.
    expect(call.extra?.userId).toBeUndefined();
    expect(call.extra?.segment).toBe("kept");
  });
});

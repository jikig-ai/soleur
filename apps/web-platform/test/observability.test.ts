import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockCaptureException, mockCaptureMessage, mockLoggerError, mockLoggerWarn } =
  vi.hoisted(() => ({
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

import { reportSilentFallback, warnSilentFallback } from "../server/observability";

beforeEach(() => {
  mockCaptureException.mockReset();
  mockCaptureMessage.mockReset();
  mockLoggerError.mockReset();
  mockLoggerWarn.mockReset();
});

describe("reportSilentFallback", () => {
  it("routes Error instances to Sentry.captureException with tags and extra", () => {
    const err = new Error("connection refused");
    reportSilentFallback(err, {
      feature: "kb-share",
      op: "create",
      extra: { userId: "u1", documentPath: "overview/doc.md" },
    });

    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    expect(mockCaptureException).toHaveBeenCalledWith(err, {
      tags: { feature: "kb-share", op: "create" },
      extra: { userId: "u1", documentPath: "overview/doc.md" },
    });
    expect(mockCaptureMessage).not.toHaveBeenCalled();
    expect(mockLoggerError).toHaveBeenCalledTimes(1);
  });

  it("routes non-Error values (string, null, DB error object) to Sentry.captureMessage", () => {
    const pgError = { message: "duplicate key", code: "23505" };
    reportSilentFallback(pgError, {
      feature: "kb-share",
      op: "create",
      extra: { userId: "u1" },
    });

    expect(mockCaptureException).not.toHaveBeenCalled();
    expect(mockCaptureMessage).toHaveBeenCalledTimes(1);
    expect(mockCaptureMessage).toHaveBeenCalledWith(
      "kb-share silent fallback",
      expect.objectContaining({
        level: "error",
        tags: { feature: "kb-share", op: "create" },
        extra: expect.objectContaining({ err: pgError, userId: "u1" }),
      }),
    );
  });

  it("uses a custom message when provided (and routes to captureMessage for null err)", () => {
    reportSilentFallback(null, {
      feature: "accept-terms",
      op: "record",
      message: "User row not found",
      extra: { userId: "u1" },
    });

    expect(mockCaptureMessage).toHaveBeenCalledWith(
      "User row not found",
      expect.objectContaining({
        level: "error",
        tags: { feature: "accept-terms", op: "record" },
      }),
    );
  });

  it("does not emit tags.op when op is omitted", () => {
    const err = new Error("boom");
    reportSilentFallback(err, { feature: "shared-token", extra: { token: "abc" } });

    expect(mockCaptureException).toHaveBeenCalledWith(err, {
      tags: { feature: "shared-token" },
      extra: { token: "abc" },
    });
  });

  it("always emits a pino logger.error for structured log aggregation", () => {
    const err = new Error("x");
    reportSilentFallback(err, { feature: "services", op: "delete", extra: { userId: "u2" } });

    expect(mockLoggerError).toHaveBeenCalledTimes(1);
    const [ctx, msg] = mockLoggerError.mock.calls[0];
    expect(ctx).toMatchObject({ err, feature: "services", op: "delete", userId: "u2" });
    expect(msg).toBe("services silent fallback");
  });
});

describe("warnSilentFallback", () => {
  it("emits at level=warning for both Error and non-Error inputs", () => {
    const err = new Error("timeout");
    warnSilentFallback(err, { feature: "stripe-webhook", op: "retry" });

    expect(mockCaptureException).toHaveBeenCalledWith(err, {
      level: "warning",
      tags: { feature: "stripe-webhook", op: "retry" },
      extra: undefined,
    });
    expect(mockLoggerWarn).toHaveBeenCalledTimes(1);

    warnSilentFallback("string-error", { feature: "foo" });
    expect(mockCaptureMessage).toHaveBeenCalledWith(
      "foo silent fallback",
      expect.objectContaining({ level: "warning" }),
    );
  });
});

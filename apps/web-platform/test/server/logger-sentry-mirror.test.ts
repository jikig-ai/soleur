// Unit tests for the pino → Sentry breadcrumb mirror in server/logger.ts.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const sentry = {
  addBreadcrumb: vi.fn(),
  captureException: vi.fn(),
};

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: (b: unknown) => sentry.addBreadcrumb(b),
  captureException: (e: unknown, opts?: unknown) =>
    sentry.captureException(e, opts),
}));

beforeEach(() => {
  vi.resetModules();
  sentry.addBreadcrumb.mockReset();
  sentry.captureException.mockReset();
  delete process.env.SENTRY_BREADCRUMB_LEVEL;
  delete process.env.LOG_LEVEL;
});
afterEach(() => vi.restoreAllMocks());

async function freshLogger() {
  const mod = await import("@/server/logger");
  return mod.default;
}

describe("logger → Sentry mirror", () => {
  it("emits breadcrumb on logger.warn", async () => {
    const logger = await freshLogger();
    logger.warn({ foo: "bar" }, "uh oh");
    expect(sentry.addBreadcrumb).toHaveBeenCalledTimes(1);
    const [b] = sentry.addBreadcrumb.mock.calls[0]!;
    expect(b).toMatchObject({
      category: "pino",
      message: "uh oh",
      level: "warning",
    });
  });

  it("emits breadcrumb on logger.error AND captureException when err present", async () => {
    const logger = await freshLogger();
    const err = new Error("boom");
    logger.error({ err, ctx: "auth" }, "auth blew up");
    expect(sentry.addBreadcrumb).toHaveBeenCalledTimes(1);
    expect(sentry.addBreadcrumb.mock.calls[0]![0]).toMatchObject({
      level: "error",
      message: "auth blew up",
    });
    expect(sentry.captureException).toHaveBeenCalledTimes(1);
    const [capturedErr, opts] = sentry.captureException.mock.calls[0]!;
    expect(capturedErr).toBe(err);
    expect(opts).toMatchObject({ tags: { feature: "pino-mirror" } });
  });

  it("does NOT mirror at info level by default (min = warn)", async () => {
    const logger = await freshLogger();
    logger.info({ foo: "bar" }, "routine");
    expect(sentry.addBreadcrumb).not.toHaveBeenCalled();
    expect(sentry.captureException).not.toHaveBeenCalled();
  });

  it("respects SENTRY_BREADCRUMB_LEVEL=info — mirrors info too", async () => {
    process.env.SENTRY_BREADCRUMB_LEVEL = "info";
    process.env.LOG_LEVEL = "info";
    const logger = await freshLogger();
    logger.info({ foo: "bar" }, "now we mirror");
    expect(sentry.addBreadcrumb).toHaveBeenCalledTimes(1);
  });

  it("error without `err` field emits breadcrumb but NOT captureException", async () => {
    const logger = await freshLogger();
    logger.error({ ctx: "auth", code: 401 }, "no err object here");
    expect(sentry.addBreadcrumb).toHaveBeenCalledTimes(1);
    expect(sentry.captureException).not.toHaveBeenCalled();
  });

  it("does NOT throw if Sentry SDK rejects the breadcrumb", async () => {
    sentry.addBreadcrumb.mockImplementation(() => {
      throw new Error("sentry down");
    });
    const logger = await freshLogger();
    expect(() => logger.warn({ x: 1 }, "still works")).not.toThrow();
  });

  it("handles string-first signature: logger.warn('plain msg')", async () => {
    const logger = await freshLogger();
    logger.warn("plain msg");
    expect(sentry.addBreadcrumb).toHaveBeenCalledTimes(1);
    expect(sentry.addBreadcrumb.mock.calls[0]![0]).toMatchObject({
      message: "plain msg",
    });
  });
});

// The REQUIRED-mode fatal paths of origin-tls.ts used to call process.exit(1) straight after reportSilentFallback: the Sentry SDK sends
// asynchronously, so the event the alert rule exists for (reason=unexpected-close, op=load/create under REQUIRED) could be dropped
// with the process. The default exit now flushes Sentry for a bounded time first (CTO ruling 2026-11-08, ADR-321 item 12).
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const flush = vi.fn();
const warnLog = vi.fn();
vi.mock("@/server/logger", async (importOriginal) => {
  const m = await importOriginal<typeof import("@/server/logger")>();
  return {
    ...m,
    createChildLogger: (name: string) => {
      const real = m.createChildLogger(name) as unknown as Record<string, unknown>;
      return new Proxy(real, {
        get: (t, k) => (k === "warn" ? (...a: unknown[]) => warnLog(...a) : t[k as string]),
      });
    },
  };
});
vi.mock("@sentry/nextjs", () => ({
  flush: (...a: unknown[]) => flush(...a),
  captureException: vi.fn(),
  captureMessage: vi.fn(),
  withScope: vi.fn(),
}));
// The reports themselves are covered in origin-tls.test.ts; here they are silenced so only the exit path is observed.
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { FATAL_FLUSH_MS } from "@/server/crash-handlers";
import {
  EXIT_FLUSH_MS,
  ORIGIN_TLS_REQUIRED_ENV,
  createExitAfterFlush,
  startOriginTlsListener,
} from "@/server/origin-tls";

beforeEach(() => {
  expect.hasAssertions();
  flush.mockReset();
  warnLog.mockReset();
});
afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("createExitAfterFlush", () => {
  test("the flush window is 2 s, and equals crash-handlers FATAL_FLUSH_MS (one bound, two modules)", () => {
    expect(EXIT_FLUSH_MS).toBe(2_000);
    expect(EXIT_FLUSH_MS).toBe(FATAL_FLUSH_MS);
  });

  test("flushes first with the bound, and exits only after the flush settled", async () => {
    let release!: (v: boolean) => void;
    flush.mockReturnValue(new Promise<boolean>((r) => (release = r)));
    const exit = vi.fn();
    createExitAfterFlush({ flush, exit })(1);

    expect(flush).toHaveBeenCalledWith(2_000);
    expect(exit).not.toHaveBeenCalled();
    release(true);
    await vi.waitFor(() => expect(exit).toHaveBeenCalledTimes(1));
    expect(exit).toHaveBeenCalledWith(1);
    expect(flush.mock.invocationCallOrder[0]).toBeLessThan(exit.mock.invocationCallOrder[0]);
  });

  test("a rejected flush still exits", async () => {
    flush.mockRejectedValue(new Error("transport down"));
    const exit = vi.fn();
    createExitAfterFlush({ flush, exit })(1);
    await vi.waitFor(() => expect(exit).toHaveBeenCalledWith(1));
  });

  test("a flush that throws synchronously still exits", async () => {
    flush.mockImplementation(() => {
      throw new Error("sdk not initialised");
    });
    const exit = vi.fn();
    createExitAfterFlush({ flush, exit })(1);
    await vi.waitFor(() => expect(exit).toHaveBeenCalledWith(1));
  });

  test("a flush that returns a non-promise (an automocked SDK) still exits", async () => {
    flush.mockReturnValue(undefined);
    const exit = vi.fn();
    createExitAfterFlush({ flush, exit })(1);
    await vi.waitFor(() => expect(exit).toHaveBeenCalledWith(1));
  });

  test("a flush that never settles is cut by the hard timer at 2250 ms, and not before", async () => {
    vi.useFakeTimers();
    flush.mockReturnValue(new Promise(() => {}));
    const exit = vi.fn();
    createExitAfterFlush({ flush, exit })(1);

    await vi.advanceTimersByTimeAsync(2_249);
    expect(exit).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(exit).toHaveBeenCalledTimes(1);
    expect(exit).toHaveBeenCalledWith(1);
  });

  test("two calls exit once, whether the flush or the timer wins the race", async () => {
    vi.useFakeTimers();
    let release!: (v: boolean) => void;
    flush.mockReturnValue(new Promise<boolean>((r) => (release = r)));
    const exit = vi.fn();
    const exitAfterFlush = createExitAfterFlush({ flush, exit });
    exitAfterFlush(1);
    exitAfterFlush(1);
    release(true);
    await vi.advanceTimersByTimeAsync(5_000);
    expect(exit).toHaveBeenCalledTimes(1);
    expect(flush).toHaveBeenCalledTimes(1);
  });

  test("a flush that resolves AFTER the hard timer already fired does not exit a second time", async () => {
    vi.useFakeTimers();
    let release!: (v: boolean) => void;
    flush.mockReturnValue(new Promise<boolean>((r) => (release = r)));
    const exit = vi.fn();
    createExitAfterFlush({ flush, exit })(1);
    await vi.advanceTimersByTimeAsync(2_250);
    expect(exit).toHaveBeenCalledTimes(1);
    release(true);
    await vi.advanceTimersByTimeAsync(10);
    expect(exit).toHaveBeenCalledTimes(1);
  });

  test("an exit that throws is contained (no unhandled rejection, no crash)", async () => {
    flush.mockResolvedValue(true);
    const exit = vi.fn(() => {
      throw new Error("injected exit failure");
    });
    createExitAfterFlush({ flush, exit })(1);
    await vi.waitFor(() => expect(exit).toHaveBeenCalledTimes(1));
  });

  test("the idempotence flag is per instance, so one test cannot leak a suppressed exit into the next", async () => {
    flush.mockResolvedValue(true);
    const exitA = vi.fn();
    const exitB = vi.fn();
    createExitAfterFlush({ flush, exit: exitA })(1);
    createExitAfterFlush({ flush, exit: exitB })(1);
    await vi.waitFor(() => expect(exitB).toHaveBeenCalledTimes(1));
    expect(exitA).toHaveBeenCalledTimes(1);
  });
});

describe("startOriginTlsListener default exit", () => {
  test("a REQUIRED start with absent material and NO injected exit flushes Sentry before process.exit", async () => {
    flush.mockResolvedValue(true);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((() => undefined) as never);
    const close = vi.fn();
    const closeIdleConnections = vi.fn();
    const closeAllConnections = vi.fn();
    const result = startOriginTlsListener({
      httpServer: { on: vi.fn(), close, closeIdleConnections, closeAllConnections } as never,
      env: { [ORIGIN_TLS_REQUIRED_ENV]: "1" },
    });
    expect(result).toBeNull();

    await vi.waitFor(() => expect(exitSpy).toHaveBeenCalledWith(1));
    expect(flush).toHaveBeenCalledWith(2_000);
    // The :80 server stops accepting BEFORE the flush starts, so a dying REQUIRED start cannot answer the deploy canary's /health.
    expect(close).toHaveBeenCalledTimes(1);
    // Idle sockets only: an in-flight request on :80 is not torn down by a process that is about to exit anyway.
    expect(closeIdleConnections).toHaveBeenCalledTimes(1);
    expect(closeAllConnections).not.toHaveBeenCalled();
    expect(close.mock.invocationCallOrder[0]).toBeLessThan(closeIdleConnections.mock.invocationCallOrder[0]);
    expect(close.mock.invocationCallOrder[0]).toBeLessThan(flush.mock.invocationCallOrder[0]);
    // Without this the vitest process.exit trap could make the assertion vacuous: flush must come strictly first.
    expect(flush.mock.invocationCallOrder[0]).toBeLessThan(exitSpy.mock.invocationCallOrder[0]);
  });

  test("a close() that throws does not stop the flush or the exit", async () => {
    flush.mockResolvedValue(true);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((() => undefined) as never);
    const close = vi.fn(() => {
      throw new Error("injected close failure");
    });
    const closeIdleConnections = vi.fn();
    startOriginTlsListener({
      httpServer: { on: vi.fn(), close, closeIdleConnections } as never,
      env: { [ORIGIN_TLS_REQUIRED_ENV]: "1" },
    });
    await vi.waitFor(() => expect(exitSpy).toHaveBeenCalledWith(1));
    expect(close).toHaveBeenCalledTimes(1);
    expect(flush).toHaveBeenCalledTimes(1);
    // The swallowed failure is still visible (pino -> Better Stack), as a warn carrying the error.
    expect(warnLog).toHaveBeenCalledTimes(1);
    expect(warnLog.mock.calls[0][0]).toMatchObject({ err: expect.any(Error) });
    expect(String(warnLog.mock.calls[0][1])).toContain("could not close the plain HTTP server");
  });

  test("an injected exit replaces the whole default path: no close, no flush", () => {
    const close = vi.fn();
    const closeIdleConnections = vi.fn();
    const closeAllConnections = vi.fn();
    const exit = vi.fn();
    startOriginTlsListener({
      httpServer: { on: vi.fn(), close, closeIdleConnections, closeAllConnections } as never,
      env: { [ORIGIN_TLS_REQUIRED_ENV]: "1" },
      exit,
    });
    expect(exit).toHaveBeenCalledWith(1);
    expect(close).not.toHaveBeenCalled();
    expect(closeIdleConnections).not.toHaveBeenCalled();
    expect(closeAllConnections).not.toHaveBeenCalled();
    expect(flush).not.toHaveBeenCalled();
  });

  test("a start that is not REQUIRED never exits, never flushes and never closes the :80 server", () => {
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((() => undefined) as never);
    const close = vi.fn();
    const closeIdleConnections = vi.fn();
    const result = startOriginTlsListener({ httpServer: { on: vi.fn(), close, closeIdleConnections } as never, env: {} });
    expect(result).toBeNull();
    expect(exitSpy).not.toHaveBeenCalled();
    expect(flush).not.toHaveBeenCalled();
    expect(close).not.toHaveBeenCalled();
    expect(closeIdleConnections).not.toHaveBeenCalled();
  });
});

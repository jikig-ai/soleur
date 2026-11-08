// The REQUIRED-mode fatal paths of origin-tls.ts used to call process.exit(1) straight after reportSilentFallback: the Sentry SDK sends
// asynchronously, so the event the alert rule exists for (reason=unexpected-close, op=load/create under REQUIRED) could be dropped
// with the process. The default exit now flushes Sentry for a bounded time first (CTO ruling 2026-11-08, ADR-321 item 12).
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const flush = vi.fn();
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

import {
  EXIT_FLUSH_MS,
  ORIGIN_TLS_REQUIRED_ENV,
  createExitAfterFlush,
  startOriginTlsListener,
} from "@/server/origin-tls";

beforeEach(() => {
  flush.mockReset();
});
afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("createExitAfterFlush", () => {
  test("the flush window is 2 s (the same bound as crash-handlers FATAL_FLUSH_MS)", () => {
    expect(EXIT_FLUSH_MS).toBe(2_000);
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
    const result = startOriginTlsListener({
      httpServer: { on: vi.fn() } as never,
      env: { [ORIGIN_TLS_REQUIRED_ENV]: "1" },
    });
    expect(result).toBeNull();

    await vi.waitFor(() => expect(exitSpy).toHaveBeenCalledWith(1));
    expect(flush).toHaveBeenCalledWith(2_000);
    // Without this the vitest process.exit trap could make the assertion vacuous: flush must come strictly first.
    expect(flush.mock.invocationCallOrder[0]).toBeLessThan(exitSpy.mock.invocationCallOrder[0]);
  });

  test("a start that is not REQUIRED never exits and never flushes", () => {
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((() => undefined) as never);
    const result = startOriginTlsListener({ httpServer: { on: vi.fn() } as never, env: {} });
    expect(result).toBeNull();
    expect(exitSpy).not.toHaveBeenCalled();
    expect(flush).not.toHaveBeenCalled();
  });
});

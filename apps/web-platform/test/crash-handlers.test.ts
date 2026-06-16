// RED/GREEN — top-level crash attribution (#5417 Deliverable C / AC4).
//
// Before this, a thrown uncaughtException / unhandledRejection that exits the
// Node process was un-attributable: `--restart unless-stopped` silently
// restarted the container with no Sentry event distinguishing crash-driven
// restarts from OOM-driven ones. These handlers capture the fatal to Sentry,
// flush via close(2000) (NOT flush() — close also DISABLES the SDK, correct for
// a process that will not recover), then process.exit(1) so the supervisor
// restarts a clean process instead of one in undefined post-throw state.
//
// Double-report guard: @sentry/node auto-installs OnUncaughtException +
// OnUnhandledRejection by default. sentry.server.config.ts filters both out so
// ONLY these manual handlers fire (asserted by sentry-server-config-no-auto-
// global-handlers.test.ts). Here we assert the handler reports-once-and-exits.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import * as Sentry from "@sentry/nextjs";

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
  close: vi.fn(async () => true),
}));

const captureException = vi.mocked(Sentry.captureException);
const close = vi.mocked(Sentry.close);

vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({
    fatal: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
    debug: vi.fn(),
  }),
}));

let exitSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  vi.resetModules(); // reset the module-level re-entrancy guard between tests
  captureException.mockClear();
  close.mockClear();
  // no-op exit so the handler's process.exit(1) does not kill the test runner
  exitSpy = vi
    .spyOn(process, "exit")
    .mockImplementation(((_code?: number) => undefined) as never);
});

afterEach(() => {
  exitSpy.mockRestore();
});

describe("reportFatalAndExit", () => {
  it("captures the error once, flushes via close(2000), then exits 1", async () => {
    const { reportFatalAndExit, FATAL_FLUSH_MS } = await import(
      "@/server/crash-handlers"
    );
    const err = new Error("boom");
    await reportFatalAndExit(err, "uncaughtException");

    expect(captureException).toHaveBeenCalledTimes(1);
    expect(captureException).toHaveBeenCalledWith(
      err,
      expect.objectContaining({
        tags: expect.objectContaining({ fatal: "uncaughtException" }),
      }),
    );
    // close (NOT flush) — flushes AND disables the SDK for a crashing process
    expect(close).toHaveBeenCalledTimes(1);
    expect(close).toHaveBeenCalledWith(FATAL_FLUSH_MS);
    expect(exitSpy).toHaveBeenCalledWith(1);
    // bounded flush window so a wedged transport cannot stall the restart
    expect(FATAL_FLUSH_MS).toBeLessThanOrEqual(2_000);
  });

  it("tags unhandledRejection distinctly from uncaughtException", async () => {
    const { reportFatalAndExit } = await import("@/server/crash-handlers");
    await reportFatalAndExit("rejected", "unhandledRejection");
    expect(captureException).toHaveBeenCalledWith(
      "rejected",
      expect.objectContaining({
        tags: expect.objectContaining({ fatal: "unhandledRejection" }),
      }),
    );
  });

  it("re-entrancy guard: a second fatal during handling does not re-report", async () => {
    const { reportFatalAndExit } = await import("@/server/crash-handlers");
    await reportFatalAndExit(new Error("first"), "uncaughtException");
    await reportFatalAndExit(new Error("second"), "uncaughtException");
    // first fatal wins — only one capture; both calls still drive an exit
    expect(captureException).toHaveBeenCalledTimes(1);
    expect(exitSpy).toHaveBeenCalledWith(1);
  });
});

describe("installCrashHandlers", () => {
  it("registers process.on handlers for both fatal classes", async () => {
    const { installCrashHandlers } = await import("@/server/crash-handlers");
    const onSpy = vi.spyOn(process, "on");
    installCrashHandlers();
    const events = onSpy.mock.calls.map((c) => c[0]);
    expect(events).toContain("uncaughtException");
    expect(events).toContain("unhandledRejection");
    onSpy.mockRestore();
  });
});

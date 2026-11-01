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

const warnSilentFallback = vi.fn();
vi.mock("@/server/observability", () => ({
  warnSilentFallback: (...args: unknown[]) => warnSilentFallback(...args),
}));

let exitSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  vi.resetModules(); // reset the module-level re-entrancy guard between tests
  captureException.mockClear();
  close.mockClear();
  warnSilentFallback.mockClear();
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

// #11772 — benign inbound client abort (vercel/next.js #49587): Node mints
// `Error: aborted` + `code: "ECONNRESET"` on `_http_server` when an inbound
// client resets mid-request. Upstream's body-clone path wipes the request's
// 'error' listeners so that abort reaches our process handlers — stock Next
// logs and continues, our ADR-062 contract must classify it non-fatal (warn
// mirror, no capture-close-exit) or the unauthenticated restart-DoS stays live.
describe("installCrashHandlers — benign client-abort classification", () => {
  type Listener = (e: unknown) => void;

  async function listeners() {
    const { installCrashHandlers } = await import("@/server/crash-handlers");
    const onSpy = vi.spyOn(process, "on");
    installCrashHandlers();
    const find = (name: string): Listener => {
      const call = onSpy.mock.calls.find((c) => c[0] === name);
      if (!call) throw new Error(`no ${name} listener registered`);
      const fn = call[1] as Listener;
      // The spy called through: a REAL listener was registered. Remove it —
      // otherwise pairs accumulate across arms and a stray later rejection
      // would hit the real handler in this worker.
      process.removeListener(name, fn);
      return fn;
    };
    const pair = {
      uncaught: find("uncaughtException"),
      rejection: find("unhandledRejection"),
    };
    onSpy.mockRestore();
    return pair;
  }

  function connResetException() {
    const err = new Error("aborted");
    (err as Error & { code?: string }).code = "ECONNRESET";
    return err;
  }

  // Let any queued reportFatalAndExit microtask land so a NOT-called
  // assertion on the fatal path is a real check, not a race won by sync code.
  const settle = () => new Promise((r) => setImmediate(r));

  it("uncaughtException: exact aborted+ECONNRESET pair warns and does NOT exit", async () => {
    const { uncaught } = await listeners();
    const err = connResetException();
    uncaught(err);
    await settle();
    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
    expect(warnSilentFallback).toHaveBeenCalledWith(
      err,
      expect.objectContaining({
        feature: "crash-handlers",
        op: "client-abort",
        tags: expect.objectContaining({ kind: "uncaughtException" }),
      }),
    );
    expect(captureException).not.toHaveBeenCalled();
    expect(close).not.toHaveBeenCalled();
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("unhandledRejection: exact aborted+ECONNRESET pair warns and does NOT exit", async () => {
    const { rejection } = await listeners();
    const err = connResetException();
    rejection(err);
    await settle();
    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
    expect(warnSilentFallback).toHaveBeenCalledWith(
      err,
      expect.objectContaining({
        feature: "crash-handlers",
        op: "client-abort",
        tags: expect.objectContaining({ kind: "unhandledRejection" }),
      }),
    );
    expect(captureException).not.toHaveBeenCalled();
    expect(close).not.toHaveBeenCalled();
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("Error('aborted') without .code still exits (dsar-export near-miss)", async () => {
    const { uncaught } = await listeners();
    uncaught(new Error("aborted"));
    await vi.waitFor(() => expect(exitSpy).toHaveBeenCalledWith(1));
    expect(captureException).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        tags: expect.objectContaining({ fatal: "uncaughtException" }),
      }),
    );
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  it("ECONNRESET code with a different message still exits", async () => {
    const { uncaught } = await listeners();
    const err = new Error("socket hang up");
    (err as Error & { code?: string }).code = "ECONNRESET";
    uncaught(err);
    await vi.waitFor(() => expect(exitSpy).toHaveBeenCalledWith(1));
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  it("non-Error rejection reason still exits", async () => {
    const { rejection } = await listeners();
    rejection("rejected");
    await vi.waitFor(() => expect(exitSpy).toHaveBeenCalledWith(1));
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  it("genuine error through the listener still takes the fatal path", async () => {
    const { uncaught } = await listeners();
    const err = new Error("boom");
    uncaught(err);
    await vi.waitFor(() => expect(exitSpy).toHaveBeenCalledWith(1));
    expect(captureException).toHaveBeenCalledWith(
      err,
      expect.objectContaining({
        tags: expect.objectContaining({ fatal: "uncaughtException" }),
      }),
    );
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  it("live socket abort mints the exact pair isBenignClientAbort accepts", async () => {
    const { createServer } = await import("node:http");
    const { connect } = await import("node:net");
    const { isBenignClientAbort } = await import("@/server/crash-handlers");
    const minted: unknown[] = [];
    const server = createServer((req) => {
      req.on("error", (e) => minted.push(e));
      // Never respond — the client is destroyed mid-request below.
    });
    await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
    const port = (server.address() as { port: number }).port;
    const socket = connect(port, "127.0.0.1", () => {
      socket.write(
        "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 100\r\n\r\npartial",
      );
      setTimeout(() => socket.destroy(), 50);
    });
    await vi.waitFor(() => expect(minted.length).toBeGreaterThan(0));
    server.close();
    expect(minted[0]).toBeInstanceOf(Error);
    expect(isBenignClientAbort(minted[0])).toBe(true);
  });
});

// Receiver-loss elimination for the Inngest ctx logger (#6703, Ref #6705).
//
// The crash this guards against: `ProxyLogger`'s methods open with
// `if (!this.enabled) return;` (inngest@3.54.2
// middleware/logger.js › ProxyLogger.info/warn/error/debug).
// Detaching one (`const f = ctx.logger.info`) drops the receiver, so strict-mode
// class code sees `this === undefined` and throws
// `TypeError: Cannot read properties of undefined (reading 'enabled')`.
// #6705 fixed one call site; `applyBoundLogger` makes the whole SHAPE safe
// fleet-wide by binding every function-valued property at the middleware
// boundary.
//
// The fake MUST be a class. An object literal has no `this` dependency and
// therefore cannot reproduce receiver loss — a test built on one passes against
// the fake and throws only in production.

import { describe, expect, it, vi } from "vitest";
// The REAL vendored ProxyLogger, not a fake. The fakes below pin the shape;
// this pins the actual vendor, so an `inngest` bump that changes ProxyLogger
// reds this suite instead of silently reintroducing the crash in production.
import { ProxyLogger } from "inngest";

import {
  applyBoundLogger,
  boundLoggerMiddleware,
} from "@/server/inngest/middleware/bound-logger";

/** Mirrors inngest's real ProxyLogger: `enabled` as an initialized instance
 *  field, every method gated on `this.enabled`. */
class ProxyLoggerLike {
  enabled = false;
  received: unknown[][] = [];

  info(...args: unknown[]) {
    if (!this.enabled) return;
    this.received.push(args);
  }
  warn(...args: unknown[]) {
    if (!this.enabled) return;
    this.received.push(args);
  }
  error(...args: unknown[]) {
    if (!this.enabled) return;
    this.received.push(args);
  }
  enable() {
    this.enabled = true;
  }
}

/** ProxyLogger's own constructor Proxy forwards unknown props to the user's
 *  logger (middleware/logger.js › ProxyLogger constructor), so the real ctx
 *  logger carries pino passthroughs (`child`, `level`) on top of its own
 *  prototype methods. A three-arrow-closure facade would drop all of them. */
class RicherProxyLoggerLike extends ProxyLoggerLike {
  level = "info";

  debug(...args: unknown[]) {
    if (!this.enabled) return;
    this.received.push(args);
  }
  child() {
    return this;
  }
}

function enabledLogger(): ProxyLoggerLike {
  const raw = new ProxyLoggerLike();
  raw.enable();
  return raw;
}

type BoundLogger = Record<string, (...args: unknown[]) => void>;

describe("applyBoundLogger — receiver-loss elimination", () => {
  // T1 — THE RED. Establishes the bug is real against the fake before any
  // claim that the fix removes it. If this ever stops throwing, the fake has
  // drifted from ProxyLogger and every assertion below is measuring nothing.
  it("T1: detaching from the RAW logger throws (the bug being eliminated)", () => {
    const raw = enabledLogger();
    const detached = raw.info;

    expect(() => detached("x")).toThrow(
      /Cannot read properties of undefined \(reading 'enabled'\)/,
    );
  });

  // T2 — the same detachment through the bound facade is safe AND still
  // delivers. "Does not throw" alone would pass for a facade that swallows.
  it("T2: detaching through the bound logger does not throw and still delivers", () => {
    const raw = enabledLogger();
    const bound = applyBoundLogger(raw) as BoundLogger;

    const detached = bound.info;
    expect(() => detached("x")).not.toThrow();
    expect(raw.received).toContainEqual(["x"]);
  });

  // T3/T4 — the synchronous detachment shapes, including the two the rejected
  // compile-time detector (Option A) silently missed.
  it("T3/T4: every synchronous detachment shape is safe", () => {
    const raw = enabledLogger();
    const bound = applyBoundLogger(raw) as BoundLogger;

    for (const call of [
      () => {
        const f = bound.info;
        f("extract");
      },
      () => {
        const { warn } = bound;
        warn("destructure");
      },
      () => [1].forEach(bound.info),
    ]) {
      expect(call).not.toThrow();
    }

    expect(raw.received).toContainEqual(["extract"]);
    expect(raw.received).toContainEqual(["destructure"]);
  });

  // T5 — the async shapes. Both are invoked for real rather than merely
  // registered: `expect(() => setTimeout(bound.error, 0)).not.toThrow()` would
  // pass even with a broken bind, because the throw happens on the timer tick,
  // not at registration. Asserting registration would be vacuous.
  it("T5a: setTimeout(bound.error, 0) is safe when the timer actually fires", () => {
    vi.useFakeTimers();
    try {
      const raw = enabledLogger();
      const bound = applyBoundLogger(raw) as BoundLogger;

      setTimeout(bound.error, 0);
      expect(() => vi.runAllTimers()).not.toThrow();
      expect(raw.received).toHaveLength(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it("T5b: p.catch(bound.error) is safe when the rejection actually settles", async () => {
    const raw = enabledLogger();
    const bound = applyBoundLogger(raw) as BoundLogger;

    const err = new Error("z");
    await expect(Promise.reject(err).catch(bound.error)).resolves.toBeUndefined();
    expect(raw.received).toContainEqual([err]);
  });

  // T6 / AC5 — binding must NOT defeat ProxyLogger's `enabled` gate. That gate
  // suppresses duplicate logging across Inngest's replay passes; defeating it
  // would multiply ctx-log volume across 60+ crons on every discovery pass.
  it("T6: the `enabled` gate is preserved — a disabled logger stays silent", () => {
    const off = new ProxyLoggerLike(); // enabled === false
    const bound = applyBoundLogger(off) as BoundLogger;

    bound.info("x");
    const detached = bound.warn;
    detached("y");

    expect(off.received).toHaveLength(0);
  });

  // AC3c — fail-open. `new Proxy(undefined, …)` THROWS, and a throw inside
  // transformInput would red EVERY cron on the surface over a logging concern.
  it("AC3c: a missing or non-object logger fails open rather than throwing", () => {
    for (const absent of [undefined, null, "not-an-object", 42]) {
      expect(() => applyBoundLogger(absent)).not.toThrow();
      expect(applyBoundLogger(absent)).toBeUndefined();
    }
  });

  // AC3d — the passthrough surface survives. This is the regression the
  // three-arrow-closure design ({ info, warn, error }) would have shipped:
  // `logger.debug is not a function` for any caller reaching past the trio.
  it("AC3d: debug / child / non-function passthroughs survive the facade", () => {
    const raw = new RicherProxyLoggerLike();
    raw.enable();
    const bound = applyBoundLogger(raw) as BoundLogger & { level: string };

    expect(typeof bound.debug).toBe("function");
    expect(typeof bound.child).toBe("function");
    expect(bound.level).toBe("info"); // non-function value passes through untouched

    const detachedDebug = bound.debug;
    expect(() => detachedDebug("x")).not.toThrow();
    expect(raw.received).toContainEqual(["x"]);
  });
});

// The fakes above cannot reproduce one production-critical property: the real
// ProxyLogger's CONSTRUCTOR RETURNS A PROXY (middleware/logger.js ›
// ProxyLogger constructor), so the facade
// wraps a Proxy in a Proxy. `v.bind(target)` therefore binds to the inner
// Proxy, and every `this.*` inside ProxyLogger re-enters that inner trap. A
// class fake exercises none of that. These run against the vendored SDK.
describe("applyBoundLogger — against the real vendored ProxyLogger", () => {
  function userLogger() {
    const received: unknown[][] = [];
    return {
      received,
      info: (...a: unknown[]) => received.push(["info", ...a]),
      warn: (...a: unknown[]) => received.push(["warn", ...a]),
      error: (...a: unknown[]) => received.push(["error", ...a]),
      debug: (...a: unknown[]) => received.push(["debug", ...a]),
      level: "info",
    };
  }

  it("reproduces the real receiver loss, then eliminates it", () => {
    const sink = userLogger();
    const real = new ProxyLogger(sink);
    real.enable();

    // The genuine bug, against the genuine vendor.
    const rawDetached = real.info;
    expect(() => rawDetached("boom")).toThrow(
      /Cannot read properties of undefined \(reading 'enabled'\)/,
    );

    const bound = applyBoundLogger(real) as BoundLogger;
    const boundDetached = bound.info;
    expect(() => boundDetached("delivered")).not.toThrow();
    expect(sink.received).toContainEqual(["info", "delivered"]);
  });

  it("preserves props ProxyLogger forwards to the user logger", () => {
    const sink = userLogger();
    const real = new ProxyLogger(sink);
    real.enable();
    const bound = applyBoundLogger(real) as BoundLogger & { level: string };

    // `level` reaches us only through ProxyLogger's OWN forwarding get trap;
    // `debug` is a real ProxyLogger prototype method (itself gated on
    // `this.enabled`), so it exercises the bind rather than the forward. Both
    // are surface the rejected three-arrow-closure facade would have lost.
    expect(bound.level).toBe("info");
    const d = bound.debug;
    expect(() => d("dbg")).not.toThrow();
    expect(sink.received).toContainEqual(["debug", "dbg"]);
  });

  it("keeps the SDK's enable/disable lifecycle authoritative over the facade", () => {
    const sink = userLogger();
    const real = new ProxyLogger(sink);
    const bound = applyBoundLogger(real) as BoundLogger;

    // Inngest calls enable()/disable() on its OWN closure reference to the
    // ProxyLogger (Inngest.js › builtInMiddleware), never via ctx. The facade
    // must stay
    // subordinate to that, or replay-pass suppression breaks fleet-wide.
    const detached = bound.info;
    detached("while-disabled");
    expect(sink.received).toHaveLength(0);

    real.enable();
    detached("while-enabled");
    expect(sink.received).toContainEqual(["info", "while-enabled"]);

    real.disable();
    detached("after-disable");
    expect(sink.received).toHaveLength(1);
  });
});

// The fail-open guard is deliberately non-throwing, which makes it exactly the
// shape that rots unnoticed. These pin that it REPORTS. Fail-open and
// fail-silent are separable; only the first is forced on us.
describe("applyBoundLogger — the fail-open path reports rather than going silent", () => {
  // Each case re-imports the module so the module-scope dedupe flag starts
  // fresh; without resetModules the earlier AC3c case would already have
  // consumed the single allowed report.
  async function freshModule(warnSilentFallback: unknown) {
    vi.resetModules();
    vi.doMock("@/server/observability", () => ({ warnSilentFallback }));
    return await import("@/server/inngest/middleware/bound-logger");
  }

  it("mirrors the first fail-open to Sentry, then dedupes", async () => {
    const warn = vi.fn();
    const { applyBoundLogger: fresh } = await freshModule(warn);

    expect(fresh(undefined)).toBeUndefined();
    expect(fresh(null)).toBeUndefined();
    expect(fresh("not-an-object")).toBeUndefined();

    // Once, not three times — this fires on every run of all 65 functions, so
    // an unthrottled mirror would flood Sentry.
    expect(warn).toHaveBeenCalledTimes(1);
    const [err, options] = warn.mock.calls[0] as [unknown, Record<string, unknown>];
    expect(err).toBeInstanceOf(Error);
    expect(options).toMatchObject({
      feature: "inngest-bound-logger",
      op: "transformInput",
    });

    vi.doUnmock("@/server/observability");
  });

  it("still does not throw when the mirror itself throws", async () => {
    const warn = vi.fn(() => {
      throw new Error("sentry transport down");
    });
    const { applyBoundLogger: fresh } = await freshModule(warn);

    // A reporting failure must never red 65 crons — this is the one place the
    // cert-reissue-marker swallow-the-catch exemption genuinely applies.
    expect(() => fresh(undefined)).not.toThrow();
    expect(warn).toHaveBeenCalledTimes(1);

    vi.doUnmock("@/server/observability");
  });

  it("does not report when the logger is present and wrappable", async () => {
    const warn = vi.fn();
    const { applyBoundLogger: fresh } = await freshModule(warn);

    expect(fresh(new ProxyLogger({ info() {}, warn() {}, error() {}, debug() {} }))).toBeDefined();
    expect(warn).not.toHaveBeenCalled();

    vi.doUnmock("@/server/observability");
  });
});

// Every case below was a REAL defect in the first cut of this middleware, found
// in review and verified against a live Proxy before being fixed. They are the
// ways a binding facade reintroduces the crash class it exists to remove.
describe("applyBoundLogger — hostile logger shapes must not throw", () => {
  it("does not violate the Proxy invariant on a frozen logger", () => {
    // For an own non-writable + non-configurable data property, [[Get]] demands
    // the trap return the target's EXACT value. Returning a bound copy throws —
    // AFTER the trap returns, so an internal try/catch cannot contain it.
    const frozen = Object.freeze({
      info(this: { tag?: string }) {
        return this?.tag ?? "no-receiver";
      },
      tag: "frozen",
    });
    const bound = applyBoundLogger(frozen) as { info: () => string };

    expect(() => bound.info).not.toThrow();
    // Unbound by necessity — the invariant forbids substitution. Not throwing
    // is the guarantee here; binding is not available at any price.
    expect(() => bound.info()).not.toThrow();
  });

  it("fails open when Reflect.get throws through a nested trap", () => {
    // Mirrors the real ProxyLogger whose own trap ends
    // `Reflect.get(target.logger, …)` with `logger` undefined.
    const hostile = new Proxy(
      { logger: undefined as unknown },
      {
        get(t, p, r) {
          if (p in t) return Reflect.get(t, p, r);
          return Reflect.get(t.logger as object, p, r); // throws
        },
      },
    );
    const bound = applyBoundLogger(hostile) as Record<string, unknown>;

    expect(() => bound.somethingUnknown).not.toThrow();
    expect(bound.somethingUnknown).toBeUndefined();
  });

  it("accepts a callable logger (function with methods attached)", () => {
    // debug / npmlog / roarr shape. Rejecting it would fail open against a
    // logger that is perfectly wrappable.
    const received: unknown[][] = [];
    const callable = Object.assign(function () {}, {
      info(...a: unknown[]) {
        received.push(a);
      },
    });

    const bound = applyBoundLogger(callable) as { info: (...a: unknown[]) => void };
    expect(bound).toBeDefined();
    const detached = bound.info;
    expect(() => detached("x")).not.toThrow();
    expect(received).toContainEqual(["x"]);
  });

  it("returns a stable identity and never cross-binds shared prototype methods", () => {
    const a = new ProxyLoggerLike();
    const b = new ProxyLoggerLike();
    a.enable();
    b.enable();
    const boundA = applyBoundLogger(a) as BoundLogger;
    const boundB = applyBoundLogger(b) as BoundLogger;

    // Identity stability — `emitter.off(logger.info)` must be able to match.
    expect(boundA.info).toBe(boundA.info);

    // `ProxyLoggerLike.prototype.info` is ONE function object shared by both
    // instances. A cache keyed on the method alone hands `b` a method bound to
    // `a`, silently routing one cron's logs into another's.
    expect(boundA.info).not.toBe(boundB.info);
    boundB.info("to-b");
    expect(b.received).toContainEqual(["to-b"]);
    expect(a.received).toHaveLength(0);
  });
});

// Nothing above exercises the middleware itself — every case calls
// applyBoundLogger directly. This drives the real hook chain, so a wiring
// regression (e.g. reading ctx.logger from onFunctionRun, where it is
// undefined) reds here instead of silently unbinding all 65 functions.
describe("boundLoggerMiddleware — the hook wiring", () => {
  function runTransformInput(ctx: Record<string, unknown>) {
    const init = boundLoggerMiddleware.init as unknown as () => {
      onFunctionRun: () => {
        transformInput: (a: { ctx: Record<string, unknown> }) =>
          { ctx?: { logger?: unknown } } | undefined;
      };
    };
    return init().onFunctionRun().transformInput({ ctx });
  }

  it("patches ctx.logger with a bound facade taken from transformInput's ctx", () => {
    const sink: unknown[][] = [];
    const real = new ProxyLogger({
      info: (...a: unknown[]) => {
        sink.push(a);
      },
      warn() {},
      error() {},
      debug() {},
    });
    real.enable();

    const patch = runTransformInput({ logger: real, runId: "r1" });
    const logger = patch?.ctx?.logger as BoundLogger;
    expect(logger).toBeDefined();
    expect(logger).not.toBe(real);

    const detached = logger.info;
    expect(() => detached("through-middleware")).not.toThrow();
    expect(sink).toContainEqual(["through-middleware"]);
  });

  it("returns no ctx patch when the run ctx carries no logger", () => {
    expect(runTransformInput({ runId: "r1" })).toBeUndefined();
  });
});

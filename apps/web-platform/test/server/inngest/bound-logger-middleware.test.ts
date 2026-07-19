// Receiver-loss elimination for the Inngest ctx logger (#6703, Ref #6705).
//
// The crash this guards against: `ProxyLogger`'s methods open with
// `if (!this.enabled) return;` (inngest@3.54.2 middleware/logger.js:37-52).
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

import { applyBoundLogger } from "@/server/inngest/middleware/bound-logger";

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
 *  logger (logger.js:32-35), so the real ctx logger also carries `debug` and
 *  pino passthroughs (`child`, `level`). A three-arrow-closure facade would
 *  silently drop all of them. */
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

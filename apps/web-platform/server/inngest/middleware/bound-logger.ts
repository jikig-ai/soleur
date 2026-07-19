// Inngest ctx-logger receiver-loss elimination (#6703, Ref #6705).
//
// Applied once at server/inngest/client.ts (LAST, after sentry-correlation and
// run-log); runs on every function invocation, so all 65 Inngest functions are
// covered without per-handler instrumentation.
//
// THE BUG CLASS. inngest's `ProxyLogger` methods open with
// `if (!this.enabled) return;` (inngest@3.54.2 middleware/logger.js › ProxyLogger.info/warn/error/debug).
// Detaching one — `const f = ctx.logger.info`, `p.catch(ctx.logger.error)`,
// `setTimeout(ctx.logger.info, 0)` — drops the receiver, so strict-mode class
// code sees `this === undefined` and throws
// `TypeError: Cannot read properties of undefined (reading 'enabled')`.
// #6705 fixed one such site in cron-gh-pages-cert-reissue's emitTerminal, where
// it turned a SUCCESSFUL probe into a reported failure. Nothing prevented the
// next occurrence: `HandlerArgs["logger"]` (_cron-shared.ts) declares plain
// `(...a: unknown[]) => void` properties with no `this` requirement, so the
// compiler accepts the detachment everywhere.
//
// This binds every function-valued property at the middleware boundary, which
// makes the shape HARMLESS rather than merely detectable. Elimination over
// detection: a type-level detector was measured to miss `p.catch(logger.error)`,
// `setTimeout(logger.info, 0)` and `forEach(logger.info)` — arguably the more
// idiomatic next occurrences in async cron code than the one that already
// happened.

import { InngestMiddleware } from "inngest";

import { warnSilentFallback } from "@/server/observability";

// Module-scope dedupe. If the guard below fires it fires on EVERY run of all 65
// functions, so an unthrottled mirror would flood Sentry with one issue per
// cron invocation. One report per process is enough to raise the alarm; the
// container restarts on every deploy, so this re-arms naturally.
let failOpenReported = false;

// Bound-method cache, so `logger.info === logger.info` across accesses. Without
// it every property read allocates a fresh closure (65 functions × every log
// call) and identity-sensitive callers break: `emitter.off(logger.info)` would
// never remove the listener, and Set/Map handler dedupe would double-register.
//
// TWO levels, keyed on the TARGET first. Class methods live on the shared
// prototype, so `ProxyLogger.prototype.info` is the SAME function object for
// every instance. A single WeakMap keyed on the method alone would hand the
// second logger a method bound to the FIRST logger's instance — silently
// routing one cron's logs through another's. Verified: it returns the wrong
// receiver, so the nesting is load-bearing, not defensive styling.
const boundCache = new WeakMap<object, WeakMap<object, unknown>>();

/**
 * Wrap a logger so every function-valued property comes out pre-bound to its
 * owner, making receiver loss impossible. Returns `undefined` when there is
 * nothing safe to wrap — see the fail-open note at the call site.
 *
 * Exported separately from the middleware so the detachment shapes can be
 * asserted directly, without standing up an Inngest run.
 */
export function applyBoundLogger(raw: unknown): unknown {
  // FAIL OPEN, BUT NOT FAIL SILENT — those are separable, and only the first is
  // forced. `new Proxy(undefined, …)` THROWS, and a throw inside transformInput
  // would red EVERY cron on the surface over a logging concern, so we must not
  // throw. That says nothing about whether we may REPORT.
  //
  // We report, because if this fires the consequence is severe and otherwise
  // invisible: all 65 functions silently revert to unbound loggers, the
  // receiver-loss TypeError class returns fleet-wide, and nothing surfaces it —
  // no throw for sentry-correlation to capture, no emit for Vector to ship, and
  // run-log records the run as `completed`. That is a fleet-wide regression
  // shaped exactly like health.
  //
  // This is NOT the cert-reissue-marker.ts exemption. That one is scoped to the
  // `catch` inside emitCertReissueMarker() around an emit that ALREADY FAILED,
  // where mirroring
  // would re-enter the same broken pino instance. Here nothing has been
  // attempted yet — this is an input-shape check — and the mirror target
  // (module-scope pino → Sentry) is a disjoint path from inngest's ctx
  // ProxyLogger. `ctx.logger` being absent implies nothing about module-scope
  // pino, so the re-entrancy argument does not transfer.
  //
  // Reachable by more than an SDK bump: reading ctx.logger from onFunctionRun
  // instead of transformInput lands here too (see the note on that hook below),
  // and tsc cannot catch that — `raw` is `unknown` and InitialRunInfo is
  // loosely typed. A refactor is the likelier trigger than a vendor change.
  // `typeof raw === "function"` is ACCEPTED, not rejected: the callable-logger
  // shape (a function with `info`/`warn`/`error` attached) is what debug, npmlog
  // and roarr hand you, and `new Proxy(fn, …)` is perfectly legal. Rejecting it
  // would fail open against a logger that is in fact wrappable.
  if (raw === null || (typeof raw !== "object" && typeof raw !== "function")) {
    if (!failOpenReported) {
      failOpenReported = true;
      try {
        warnSilentFallback(
          new Error("ctx.logger absent or unwrappable — bound-logger failed open"),
          {
            feature: "inngest-bound-logger",
            op: "transformInput",
            extra: { rawType: raw === null ? "null" : typeof raw },
          },
        );
      } catch {
        // Terminal fallback, and the ONE place the cert-reissue-marker
        // exemption genuinely applies: the emit itself failed, so mirroring it
        // would re-enter the path that just broke. Swallow — a reporting
        // failure must never red 65 crons.
      }
    }
    return;
  }

  // A Proxy, NOT a `{ info, warn, error }` object literal. ProxyLogger's own
  // constructor returns a Proxy forwarding unknown props to the user's logger
  // (middleware/logger.js › ProxyLogger constructor), so the real ctx logger
  // also carries pino passthroughs (`child`, `trace`, `fatal`, `level`) on top
  // of its own prototype methods. A three-method literal would silently drop all of them and trade
  // this crash for `TypeError: logger.debug is not a function`.
  return new Proxy(raw, {
    get(target, prop, receiver) {
      let v: unknown;
      try {
        v = Reflect.get(target, prop, receiver);
      } catch {
        // `Reflect.get` can throw THROUGH a nested trap. The real target is
        // itself a Proxy whose trap ends `Reflect.get(target.logger, …)`
        // (middleware/logger.js › ProxyLogger constructor); if `logger` is
        // undefined — e.g. a pino `child()` that returned undefined, which
        // Inngest.js › builtInMiddleware's try/catch does NOT guard against —
        // any unknown-prop read throws `Reflect.get called on non-object`.
        // Fail open to `undefined`: a missing log method must not red a cron.
        return undefined;
      }

      if (typeof v !== "function") return v; // e.g. `level` — pass through

      // PROXY INVARIANT. For an own data property that is non-writable AND
      // non-configurable, [[Get]] requires the trap to return the target's
      // EXACT value; returning a bound copy throws
      // `'get' on proxy: property … is a read-only and non-configurable data
      // property … but the proxy did not return its actual value`.
      // That check runs AFTER the trap returns, so a try/catch in here does
      // NOT contain it — verified. It must be avoided, not caught. A frozen
      // logger therefore keeps its unbound method: correctness (no throw) beats
      // binding, and throwing here would reintroduce the very crash class this
      // module exists to remove.
      const own = Reflect.getOwnPropertyDescriptor(target, prop);
      if (own && own.writable === false && own.configurable === false) return v;

      // `.bind(target)` rather than `.bind(receiver)`. Both work: binding to
      // `receiver` (this outer Proxy) would re-enter the trap on every internal
      // `this.*` access inside ProxyLogger, but `this.enabled` is a boolean and
      // `this.logger` an object, so neither takes the bind branch and both pass
      // through unchanged. `target` is preferred for being fewer hops and the
      // receiver the class actually expects — not because `receiver` is unsafe.
      // Either way the `enabled` replay-suppression gate still applies exactly
      // as before (asserted by T6 — binding must not turn suppression into a
      // passthrough and multiply log volume across 65 crons).
      let perTarget = boundCache.get(target);
      if (!perTarget) {
        perTarget = new WeakMap();
        boundCache.set(target, perTarget);
      }
      const fn = v as (...args: unknown[]) => unknown;
      const cached = perTarget.get(fn);
      if (cached) return cached;
      const bound = fn.bind(target);
      perTarget.set(fn, bound);
      return bound;
    },
  });
}

export const boundLoggerMiddleware = new InngestMiddleware({
  name: "bound-ctx-logger",
  init() {
    return {
      // NOTE the empty signature. `ctx.logger` MUST be read in transformInput,
      // never here: onFunctionRun's ctx is Inngest's InitialRunInfo
      // (`{ event, runId }` only — "does not necessarily contain all the
      // data"), and the full BaseContext is handed only to transformInput.
      // run-log.ts › runLogMiddleware documents the same trap for
      // attempt/maxAttempts.
      // Capturing `logger` here would silently yield `undefined`, the guard
      // below would fail open, and every cron would keep its unbound logger —
      // a silent no-op with no error to detect it.
      onFunctionRun() {
        return {
          transformInput({ ctx }) {
            const logger = applyBoundLogger(ctx.logger);
            if (!logger) return;
            // Returning a ctx patch is new to this repo (both existing
            // middlewares return void); the pattern is borrowed from Inngest's
            // own built-in logger middleware (Inngest.js › builtInMiddleware). Safe to
            // clobber `logger` specifically: the ctx merge is a shallow spread
            // in array order, last-write-wins (execution/v1.js ›
            // initializeMiddleware()), and
            // neither sibling middleware writes that key.
            return { ctx: { logger } };
          },
        };
      },
    };
  },
});

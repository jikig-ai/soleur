// Inngest ctx-logger receiver-loss elimination (#6703, Ref #6705).
//
// Applied once at server/inngest/client.ts (LAST, after sentry-correlation and
// run-log); runs on every function invocation, so all 60+ Inngest functions are
// covered without per-handler instrumentation.
//
// THE BUG CLASS. inngest's `ProxyLogger` methods open with
// `if (!this.enabled) return;` (inngest@3.54.2 middleware/logger.js:37-52).
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

/**
 * Wrap a logger so every function-valued property comes out pre-bound to its
 * owner, making receiver loss impossible. Returns `undefined` when there is
 * nothing safe to wrap — see the fail-open note at the call site.
 *
 * Exported separately from the middleware so the detachment shapes can be
 * asserted directly, without standing up an Inngest run.
 */
export function applyBoundLogger(raw: unknown): unknown {
  // FAIL OPEN. `new Proxy(undefined, …)` THROWS, and a throw inside
  // transformInput would red EVERY cron on the surface over a logging concern.
  // Sanctioned observability-of-observability exemption to
  // `cq-silent-fallback-must-mirror-to-sentry`, same rationale as
  // cert-reissue-marker.ts:34-37: a logging failure must NEVER red a cron, and
  // mirroring it would re-enter the path that is already broken. The residual
  // risk is bounded — this can only fire if Inngest stops supplying
  // ctx.logger, which is an SDK-breaking change the tests and tsc catch at the
  // next bump. Chosen deliberately over fail-loud despite run-log classifying a
  // non-throwing run as `completed` (2026-06-29 cron-health learning).
  if (!raw || typeof raw !== "object") return;

  // A Proxy, NOT a `{ info, warn, error }` object literal. ProxyLogger's own
  // constructor returns a Proxy forwarding unknown props to the user's logger
  // (logger.js:32-35), so the real ctx logger also carries `debug`
  // (logger.js:49-52) plus pino passthroughs (`child`, `trace`, `fatal`,
  // `level`). A three-method literal would silently drop all of them and trade
  // this crash for `TypeError: logger.debug is not a function`.
  return new Proxy(raw, {
    get(target, prop, receiver) {
      const v = Reflect.get(target, prop, receiver);
      // `.bind(target)`, NOT `.bind(receiver)`: `receiver` is this outer Proxy,
      // so binding to it would re-enter this trap on every internal `this.*`
      // access inside ProxyLogger — including `this.enabled` and `this.logger`.
      // Binding to `target` hands the method the receiver it actually expects,
      // which is also why the `enabled` replay-suppression gate still applies
      // exactly as before (asserted by T6 — binding must not turn suppression
      // into a passthrough and multiply log volume across 60+ crons).
      // Non-function values (e.g. `level`) pass through untouched.
      return typeof v === "function" ? v.bind(target) : v;
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
      // run-log.ts:121-127 documents the same trap for attempt/maxAttempts.
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
            // own built-in logger middleware (Inngest.js:673-676). Safe to
            // clobber `logger` specifically: the ctx merge is a shallow spread
            // in array order, last-write-wins (execution/v1.js:1087-1099), and
            // neither sibling middleware writes that key.
            return { ctx: { logger } };
          },
        };
      },
    };
  },
});

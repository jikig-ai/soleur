// Top-level crash attribution (#5417 Deliverable C).
//
// The container ran with NO top-level uncaughtException / unhandledRejection
// handler, so a thrown error that exits the process was un-attributable: the
// supervisor (`--restart unless-stopped`) silently restarted it and the only
// trace was a "Server startup" event, indistinguishable from an OOM restart.
//
// These handlers capture the fatal to Sentry, flush via close() (NOT flush() —
// close ALSO disables the SDK, the correct call for a process that will not
// recover), then process.exit(1). A process in undefined state after an
// uncaught throw must not keep serving — letting the supervisor restart a clean
// process is strictly better. The flush window is bounded so a wedged transport
// cannot delay the restart indefinitely.
//
// IMPORTANT: @sentry/node auto-installs OnUncaughtException + OnUnhandledRejection
// by default. sentry.server.config.ts filters BOTH out (see that file + its
// test) so ONLY these manual handlers fire — otherwise every fatal reports twice.

import * as Sentry from "@sentry/nextjs";
import { createChildLogger } from "./logger";
import { mirrorWarnWithDebounce } from "./observability";

const log = createChildLogger("crash-handler");

// Bounded flush window. Long enough to land the very event being attributed,
// short enough that a wedged Sentry transport cannot stall the restart. Mirrors
// the SIGTERM graceful-shutdown handler's Sentry.flush(2_000) in index.ts.
export const FATAL_FLUSH_MS = 2_000;

export type FatalKind = "uncaughtException" | "unhandledRejection";

// Re-entrancy guard: a throw INSIDE this handler (or a second fatal landing
// during the flush await) must not loop or double-report. First fatal wins;
// any re-entry force-exits immediately.
let handling = false;

export async function reportFatalAndExit(
  err: unknown,
  kind: FatalKind,
): Promise<void> {
  if (handling) {
    process.exit(1);
    return;
  }
  handling = true;

  try {
    log.fatal({ err, kind }, `fatal ${kind} — capturing to Sentry then exiting`);
  } catch {
    // the logger must never block the exit path
  }

  try {
    Sentry.captureException(err, { level: "fatal", tags: { fatal: kind } });
    await Sentry.close(FATAL_FLUSH_MS);
  } catch {
    // already crashing — the exit below is the contract, swallow flush errors
  }

  process.exit(1);
}

// #11772 — benign inbound client abort. Node mints `Error: aborted` +
// `code: "ECONNRESET"` (connResetException) on `_http_server` when an inbound
// client resets mid-request. vercel/next.js #49587: the proxy/middleware
// body-clone path (`getCloneableBody().finalize()` → `replaceRequestBody`)
// copies `_events` onto the IncomingMessage and wipes its 'error' listeners,
// so that otherwise-absorbed abort reaches our process handlers. Stock Next
// logs `⨯` and keeps serving; exiting here hands an unauthenticated client a
// one-request restart-DoS in prod and kills the e2e dev server. The pair is
// exact-match ONLY: outbound ECONNRESET ("socket hang up") and code-less
// Error("aborted") producers (e.g. `dsar-export.ts` › abort-signal arms) stay
// fatal — widening the predicate is how a real fatal becomes warn-level noise.
export function isBenignClientAbort(err: unknown): err is Error {
  return (
    err instanceof Error &&
    err.message === "aborted" &&
    (err as Error & { code?: unknown }).code === "ECONNRESET"
  );
}

// Sibling classifier: `server/abort-classifier.ts` classifies session-layer
// aborts — a different producer; do not unify these predicates.
//
// Hybrid bound (CTO ruling, #11772): the trigger is unauthenticated, so the
// Sentry arm rides `mirrorWarnWithDebounce` — ≤1 warn envelope per 5min per
// process under the constant "crash-handlers" key — while every abort still
// emits a pino warn carrying the tags, so the burst count (the detection
// signal) stays full-fidelity in container stdout. An undebounced Sentry
// emitter here would hand a client a quota dial that spike-protects away
// every OTHER error signal during an attack.
function classifyAbortOrFatal(err: unknown, kind: FatalKind): void {
  if (isBenignClientAbort(err)) {
    log.warn(
      { feature: "crash-handlers", op: "client-abort", kind },
      "benign inbound client abort — non-fatal, Sentry debounced",
    );
    mirrorWarnWithDebounce(
      err,
      { feature: "crash-handlers", op: "client-abort", tags: { kind } },
      "crash-handlers",
      "client-abort",
    );
    return;
  }
  void reportFatalAndExit(err, kind);
}

export function installCrashHandlers(): void {
  process.on("uncaughtException", (err) =>
    classifyAbortOrFatal(err, "uncaughtException"),
  );
  process.on("unhandledRejection", (reason) =>
    classifyAbortOrFatal(reason, "unhandledRejection"),
  );
}

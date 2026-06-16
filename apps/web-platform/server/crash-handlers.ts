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

export function installCrashHandlers(): void {
  process.on("uncaughtException", (err) => {
    void reportFatalAndExit(err, "uncaughtException");
  });
  process.on("unhandledRejection", (reason) => {
    void reportFatalAndExit(reason, "unhandledRejection");
  });
}

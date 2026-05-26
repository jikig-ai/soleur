import pino from "pino";
import * as Sentry from "@sentry/nextjs";

import { REDACT_PATHS } from "./sensitive-keys";
import { renameUserIdToHash } from "./userid-pseudonymize";

const isDev = process.env.NODE_ENV !== "production";

// Sentry-mirror level: every pino call at this severity or higher emits a
// Sentry breadcrumb on the active scope (inheriting any
// `inngest.run_id` / `inngest.fn_id` tags wired by middleware). This lets
// an operator reading a Sentry issue see the structured log lines the
// handler emitted around the failure WITHOUT SSHing the container. Pino's
// numeric level order: trace=10, debug=20, info=30, warn=40, error=50,
// fatal=60. Default `warn` keeps the breadcrumb trail focused on signal.
// Tunable via `SENTRY_BREADCRUMB_LEVEL` (one of pino's level names).
const PINO_LEVEL_TO_SENTRY_LEVEL: Record<string, "info" | "warning" | "error" | "fatal"> = {
  trace: "info",
  debug: "info",
  info: "info",
  warn: "warning",
  error: "error",
  fatal: "fatal",
};
const SENTRY_BREADCRUMB_MIN_LEVEL = (
  process.env.SENTRY_BREADCRUMB_LEVEL ?? "warn"
).toLowerCase();
const SENTRY_BREADCRUMB_MIN_NUM = (() => {
  // pino exposes its level → number table on `pino.levels.values`; failing
  // open with a sane default keeps the logger usable even if the env
  // value is malformed.
  const v = pino.levels.values[SENTRY_BREADCRUMB_MIN_LEVEL];
  return typeof v === "number" ? v : 40; // 40 = warn
})();

// Best-effort breadcrumb emission. NEVER throws — observability must not
// kill the caller. Matches the defensive contract in `observability.ts`'s
// `reportSilentFallback`. Caller passes the SAME `obj` payload pino sees
// (already PII-renamed by formatters.log) plus the level name + message.
function mirrorToSentry(
  levelNum: number,
  levelName: string,
  args: unknown[],
): void {
  if (levelNum < SENTRY_BREADCRUMB_MIN_NUM) return;
  try {
    // pino accepts (obj, msg, ...) OR (msg, ...). Detect by first arg.
    let data: Record<string, unknown> | undefined;
    let message: string | undefined;
    if (typeof args[0] === "object" && args[0] !== null) {
      data = args[0] as Record<string, unknown>;
      message = typeof args[1] === "string" ? args[1] : undefined;
    } else if (typeof args[0] === "string") {
      message = args[0];
    }
    const level = PINO_LEVEL_TO_SENTRY_LEVEL[levelName] ?? "info";
    Sentry.addBreadcrumb({
      category: "pino",
      message: message ?? levelName,
      level: level === "fatal" ? "error" : level, // Sentry breadcrumb has no `fatal` level
      data,
      type: "default",
    });
    // At error/fatal, ALSO capture a Sentry message if the log carried an
    // Error instance. observability.reportSilentFallback already calls
    // captureException for known silent-fallback sites; this catches
    // logger.error({ err }, ...) emissions from anywhere else (e.g.,
    // ad-hoc catches that opted out of reportSilentFallback). De-duped at
    // Sentry's fingerprinting layer — same Error instance hashes the
    // same.
    if ((level === "error" || level === "fatal") && data) {
      const err = (data as { err?: unknown }).err;
      if (err instanceof Error) {
        Sentry.captureException(err, {
          tags: { feature: "pino-mirror" },
        });
      }
    }
  } catch {
    // breadcrumb / capture failures must NEVER propagate.
  }
}

// `REDACT_PATHS` is derived from a single sensitive-key list shared with
// the Sentry scrubber (`./sensitive-keys`). Pino's `fast-redact` has no
// recursive wildcard, so each canonical key is enumerated at top level
// + one-level-deep wildcard. Deeper structures should avoid logging
// credential-bearing objects; the BYOK lease (PR-B §1.4) is the
// canonical handling path.
export { REDACT_PATHS };

// One-time warn guard for the `formatters.log` fail-safe path. If the
// rename helper throws, we MUST NOT propagate — pino drops the entire log
// line if its formatter throws, which would swallow the original error
// context the caller was trying to record. The catch path uses
// `console.warn` (NOT `logger.warn`) to avoid re-entrancy: a logger.warn
// inside the formatter would re-invoke the formatter on the warn line.
// Module-scope flag ensures one warn per worker lifetime rather than
// spamming on a persistent failure mode. See ADR-029 invariants.
let formatterErrorReported = false;

const logger = pino({
  level: process.env.LOG_LEVEL || (isDev ? "debug" : "info"),
  ...(isDev
    ? {
        transport: {
          target: "pino-pretty",
          options: {
            colorize: true,
            translateTime: "SYS:HH:MM:ss.l",
            ignore: "pid,hostname",
          },
        },
      }
    : {}),
  // logMethod hook: intercepts EVERY logger call before pino formats /
  // emits. Mirrors WARN+ to Sentry as breadcrumbs (errors also as
  // captureException when `err` is present). Tags inherited from the
  // active scope — e.g. inngest-correlation middleware's `inngest.run_id`.
  // Must invoke the wrapped method WITH .apply so pino's level routing
  // and async-context bookkeeping continue to work.
  hooks: {
    logMethod(args, method, levelNum) {
      const levelName = pino.levels.labels[levelNum] ?? "info";
      mirrorToSentry(levelNum, levelName, args);
      // method is the level-bound pino fn (e.g., logger.warn); apply
      // forwards args verbatim. The Pino types expect a fixed-shape array;
      // we pass through the same args we received.
      // eslint-disable-next-line prefer-rest-params -- pino's hook
      // contract gives args as a tuple; .apply is the documented form.
      return (method as (...a: unknown[]) => void).apply(
        this,
        args as unknown as unknown[],
      );
    },
  },
  // Single source of truth for `userId` → `userIdHash` pseudonymisation at
  // the pino boundary (ADR-029). Renames before `redact` runs (verified at
  // `pino/lib/tools.js:161-200`). Top-level only — nested `extra.userId`
  // shapes are NOT rewritten by design; widening requires an explicit
  // ADR-029 amendment.
  formatters: {
    log: (obj) => {
      try {
        return renameUserIdToHash(obj);
      } catch (err) {
        if (!formatterErrorReported) {
          formatterErrorReported = true;
          // Serialise `err` to a primitive BEFORE handing it to `console.warn`.
          // util.inspect would otherwise walk getters / Proxy traps on a
          // caller-supplied Error, which can re-enter the logger and break
          // the re-entrancy invariant the comment above (line 19-22) claims.
          const errStr =
            err instanceof Error ? (err.stack ?? err.message) : String(err);
          // eslint-disable-next-line no-console -- intentional one-time fail-safe
          console.warn(
            "[logger] formatters.log threw; falling back to raw object",
            errStr,
          );
        }
        return obj;
      }
    },
  },
  redact: REDACT_PATHS as readonly string[] as string[],
});

export default logger;

export function createChildLogger(context: string) {
  return logger.child({ context });
}

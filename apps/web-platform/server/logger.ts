import pino from "pino";

import { REDACT_PATHS } from "./sensitive-keys";
import { renameUserIdToHash } from "./userid-pseudonymize";

const isDev = process.env.NODE_ENV !== "production";

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

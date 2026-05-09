import pino from "pino";

import { REDACT_PATHS } from "./sensitive-keys";

const isDev = process.env.NODE_ENV !== "production";

// `REDACT_PATHS` is derived from a single sensitive-key list shared with
// the Sentry scrubber (`./sensitive-keys`). Pino's `fast-redact` has no
// recursive wildcard, so each canonical key is enumerated at top level
// + one-level-deep wildcard. Deeper structures should avoid logging
// credential-bearing objects; the BYOK lease (PR-B §1.4) is the
// canonical handling path.
export { REDACT_PATHS };

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
  redact: REDACT_PATHS as readonly string[] as string[],
});

export default logger;

export function createChildLogger(context: string) {
  return logger.child({ context });
}

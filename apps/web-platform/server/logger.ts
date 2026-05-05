import pino from "pino";

const isDev = process.env.NODE_ENV !== "production";

// Pino's fast-redact does not support recursive wildcards, so each sensitive
// key is enumerated at top level (`apiKey`) and one level deep (`*.apiKey`).
// Deeper structures should avoid logging credential-bearing objects; the BYOK
// lease (PR-B) is the canonical handling path for those values.
export const REDACT_PATHS = [
  "req.headers['x-nonce']",
  "req.headers.cookie",
  "apiKey",
  "*.apiKey",
  "Authorization",
  "*.Authorization",
  "authorization",
  "*.authorization",
  "encryptedKey",
  "*.encryptedKey",
  "iv",
  "*.iv",
  "auth_tag",
  "*.auth_tag",
];

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
  redact: REDACT_PATHS,
});

export default logger;

export function createChildLogger(context: string) {
  return logger.child({ context });
}

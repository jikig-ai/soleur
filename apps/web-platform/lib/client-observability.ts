/**
 * Client-safe mirror of `server/observability.ts`.
 *
 * Pulling `@/server/observability` into a `"use client"` module transitively
 * imports `@/server/logger` → `pino` into the browser bundle. `@sentry/nextjs`
 * already has a first-party client build; pino does not. This shim exposes the
 * same `reportSilentFallback` contract without the pino dependency.
 *
 * Keep the public shape identical to the server version so call sites can
 * swap imports without any other change.
 *
 * PII strip: the browser bundle cannot hold the server's `SENTRY_USERID_PEPPER`
 * (a pepper in `NEXT_PUBLIC_*` is not a pepper — every reader recomputes hashes).
 * Instead of hashing, this module strips PII keys (`userId`, `user_id`, `email`)
 * from `extra` before forwarding to Sentry. The branded `ClientExtra` type
 * catches misuse at compile time; the runtime `stripPiiKeys` is the fail-closed
 * backstop. `sentry.client.config.ts` `beforeSend` adds a third layer that
 * covers direct `Sentry.captureException` calls that bypass this helper.
 */

import * as Sentry from "@sentry/nextjs";

// Anchored regex — matches `userId`, `user_id`, `email` case-insensitively.
// Does NOT match `customerId`, `tenantId`, `userIdentifier`, `userEmail` etc.
const PII_KEY_RE = /^user_?id$|^email$/i;

type PiiKey = "userId" | "user_id" | "email";

/**
 * Branded `extra` type that types known PII keys as `never` so a literal
 * `extra: { userId }` fails with TS2322 at the call site. Untyped spread
 * (`extra: { ...someShape }`) is unaffected — the runtime strip catches
 * those cases.
 */
export type ClientExtra = Record<string, unknown> & {
  [K in PiiKey]?: never;
};

export function stripPiiKeys(
  extra: Record<string, unknown> | undefined,
): Record<string, unknown> | undefined {
  if (!extra || typeof extra !== "object") return extra;
  const stripped: string[] = [];
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(extra)) {
    if (PII_KEY_RE.test(k)) {
      stripped.push(k);
      continue;
    }
    out[k] = v;
  }
  if (stripped.length === 0) return extra;
  if (process.env.NODE_ENV !== "production") {
    // eslint-disable-next-line no-console -- intentional dev signal
    console.warn(
      `[client-observability] stripped PII keys from Sentry extra: ${stripped.join(", ")}`,
    );
  }
  // `piiStripped` sentinel: preserves observable proof that a strip fired
  // without re-introducing the stripped values. Operators searching Sentry
  // for `piiStripped` find every event where a regression was caught.
  return { ...out, piiStripped: stripped };
}

export interface SilentFallbackOptions {
  feature: string;
  op?: string;
  extra?: ClientExtra;
  message?: string;
}

export function reportSilentFallback(
  err: unknown,
  options: SilentFallbackOptions,
): void {
  const { feature, op, extra, message } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;
  const cleanExtra = stripPiiKeys(extra);

  if (err instanceof Error) {
    Sentry.captureException(err, { tags, extra: cleanExtra });
  } else {
    Sentry.captureMessage(message ?? `${feature} silent fallback`, {
      level: "error",
      tags,
      extra: { err, ...(cleanExtra ?? {}) },
    });
  }
}

export function warnSilentFallback(
  err: unknown,
  options: SilentFallbackOptions,
): void {
  const { feature, op, extra, message } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;
  const cleanExtra = stripPiiKeys(extra);

  if (err instanceof Error) {
    Sentry.captureException(err, { level: "warning", tags, extra: cleanExtra });
  } else {
    Sentry.captureMessage(message ?? `${feature} silent fallback`, {
      level: "warning",
      tags,
      extra: { err, ...(cleanExtra ?? {}) },
    });
  }
}

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
 */

import * as Sentry from "@sentry/nextjs";

export interface SilentFallbackOptions {
  feature: string;
  op?: string;
  extra?: Record<string, unknown>;
  message?: string;
}

export function reportSilentFallback(
  err: unknown,
  options: SilentFallbackOptions,
): void {
  const { feature, op, extra, message } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;

  if (err instanceof Error) {
    Sentry.captureException(err, { tags, extra });
  } else {
    Sentry.captureMessage(message ?? `${feature} silent fallback`, {
      level: "error",
      tags,
      extra: { err, ...extra },
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

  if (err instanceof Error) {
    Sentry.captureException(err, { level: "warning", tags, extra });
  } else {
    Sentry.captureMessage(message ?? `${feature} silent fallback`, {
      level: "warning",
      tags,
      extra: { err, ...extra },
    });
  }
}

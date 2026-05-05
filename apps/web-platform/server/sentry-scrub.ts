// Sentry scrub helpers for `beforeSend` and `beforeBreadcrumb`.
//
// Sentry events nest sensitive data under request.headers, contexts, extra,
// tags, and breadcrumb.data. The recursive walk below replaces values whose
// key matches a case-insensitive sensitive set imported from
// `./sensitive-keys` (single source of truth shared with the pino redact
// paths in `./logger`).
//
// Cycle and shared-DAG correctness: a `Map<object, scrubbed>` memoizes the
// scrubbed copy on first visit and returns it on every subsequent visit.
// The prior WeakSet implementation returned the original (un-scrubbed)
// value on revisit, leaking credentials nested under shared sub-objects
// (e.g., a single `error.cause` chain referenced from multiple breadcrumbs).
// See PR #3240 review.

import { SENSITIVE_LOWER, SENSITIVE_KEY_NAMES } from "./sensitive-keys";

const REDACTED = "[Redacted]";

// Re-export under the legacy name so existing test surface keeps stable.
// `SENSITIVE_KEY_NAMES` is the canonical export from `./sensitive-keys`.
export const SENTRY_SENSITIVE_KEYS = SENSITIVE_KEY_NAMES;

function scrubRecursive(
  value: unknown,
  memo: Map<object, unknown>,
): unknown {
  if (value === null || typeof value !== "object") return value;
  const obj = value as object;

  const cached = memo.get(obj);
  if (cached !== undefined) return cached;

  if (Array.isArray(value)) {
    const out: unknown[] = [];
    memo.set(obj, out);
    for (const v of value) out.push(scrubRecursive(v, memo));
    return out;
  }

  const out: Record<string, unknown> = {};
  memo.set(obj, out);
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (SENSITIVE_LOWER.has(k.toLowerCase())) {
      out[k] = REDACTED;
    } else {
      out[k] = scrubRecursive(v, memo);
    }
  }
  return out;
}

export function scrubSentryEvent<T>(event: T): T {
  return scrubRecursive(event, new Map()) as T;
}

export function scrubSentryBreadcrumb<T>(breadcrumb: T): T {
  return scrubRecursive(breadcrumb, new Map()) as T;
}

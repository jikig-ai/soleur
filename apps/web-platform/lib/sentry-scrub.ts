// Sentry scrub helpers for `beforeSend` and `beforeBreadcrumb`.
//
// Sentry events nest sensitive data under request.headers, contexts, extra,
// tags, and breadcrumb.data — pino's path-based redact is not expressive
// enough for the recursive shape, so we walk the object once and replace
// values whose key matches a case-insensitive sensitive set.
//
// `apiKey`, `Authorization`, `encryptedKey`, `iv`, `auth_tag` cover the BYOK
// envelope (encrypted blob + AES-GCM IV + auth tag) and outbound auth headers.
// `x-nonce` and `cookie` were the prior beforeSend deletions, kept here so the
// scrubber is the single source of truth.

export const SENTRY_SENSITIVE_KEYS = [
  "apiKey",
  "Authorization",
  "encryptedKey",
  "iv",
  "auth_tag",
  "x-nonce",
  "cookie",
];

const SENSITIVE_LOWER = new Set(
  SENTRY_SENSITIVE_KEYS.map((k) => k.toLowerCase()),
);

const REDACTED = "[Redacted]";

function scrubRecursive(value: unknown, seen: WeakSet<object>): unknown {
  if (value === null || typeof value !== "object") return value;
  const obj = value as object;
  if (seen.has(obj)) return value;
  seen.add(obj);

  if (Array.isArray(value)) {
    return value.map((v) => scrubRecursive(v, seen));
  }

  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (SENSITIVE_LOWER.has(k.toLowerCase())) {
      out[k] = REDACTED;
    } else {
      out[k] = scrubRecursive(v, seen);
    }
  }
  return out;
}

export function scrubSentryEvent<T>(event: T): T {
  return scrubRecursive(event, new WeakSet()) as T;
}

export function scrubSentryBreadcrumb<T>(breadcrumb: T): T {
  return scrubRecursive(breadcrumb, new WeakSet()) as T;
}

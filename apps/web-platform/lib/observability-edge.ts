import * as Sentry from "@sentry/nextjs";

// Edge-runtime-safe variant of `server/observability.ts:reportSilentFallback`.
// Edge middleware cannot import `@/server/observability` — that file pulls
// `node:crypto` (via `hashUserId`) and `pino` (via `@/server/logger`),
// neither of which is edge-compatible. See `lib/auth/validate-origin.ts:3-7`
// for the documented constraint.
//
// Trade-offs vs the node-runtime variant:
//   - No pino mirror. The durable signal is `console.error` in structured-JSON
//     shape so log aggregators (Vercel runtime logs, Datadog, Better Stack
//     stdout shipper) still parse it. Sentry is the primary tag/aggregation
//     surface.
//   - No `node:crypto`-backed `hashExtraUserId`. `userId` is hashed via the
//     Web Crypto API's `crypto.subtle.digest` if available; otherwise we
//     fall back to a sha-256-prefix marker so the raw value never lands in
//     Sentry. Same `userIdHash` field name keeps log aggregator filters
//     working across runtimes.

interface EdgeFallbackOptions {
  feature: string;
  op?: string;
  message?: string;
  extra?: Record<string, unknown>;
}

async function hashUserIdEdge(value: string): Promise<string> {
  // Web Crypto API is available in Next.js edge runtime. The Recital 26
  // pseudonymisation contract only requires that the raw user_id not be
  // emitted; we do NOT need the server-side pepper here because the edge
  // hash is only used for log-aggregation grouping (not authentication or
  // cross-system correlation).
  if (
    typeof globalThis.crypto !== "undefined" &&
    typeof globalThis.crypto.subtle !== "undefined"
  ) {
    const bytes = new TextEncoder().encode(value);
    const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
    const hex = Array.from(new Uint8Array(digest))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    return hex.slice(0, 16);
  }
  // Edge runtime always exposes Web Crypto; this branch is defense-in-depth.
  return "edge-hash-unavailable";
}

async function transformExtra(
  extra: Record<string, unknown> | undefined,
): Promise<Record<string, unknown> | undefined> {
  if (!extra || !("userId" in extra)) return extra;
  const { userId, ...rest } = extra;
  const userIdHash =
    typeof userId === "string" && userId.length > 0
      ? await hashUserIdEdge(userId)
      : "";
  return { ...rest, userIdHash };
}

export async function reportEdgeSilentFallback(
  err: unknown,
  options: EdgeFallbackOptions,
): Promise<void> {
  const { feature, op, message, extra } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;

  const transformedExtra = await transformExtra(extra);

  // Durable signal: structured stderr line for runtime-log shipping.
  // Sentry edge SDK is best-effort; the console.error mirror is what
  // ensures operations see the event even if Sentry is shimmed.
  console.error(
    JSON.stringify({
      level: "error",
      feature,
      op,
      message: message ?? `${feature} silent fallback`,
      err: err instanceof Error ? { name: err.name, message: err.message } : err,
      ...transformedExtra,
    }),
  );

  try {
    if (err instanceof Error) {
      if (typeof Sentry.captureException === "function") {
        Sentry.captureException(err, { tags, extra: transformedExtra });
      }
    } else if (typeof Sentry.captureMessage === "function") {
      Sentry.captureMessage(message ?? `${feature} silent fallback`, {
        level: "error",
        tags,
        extra: { err, ...transformedExtra },
      });
    }
  } catch {
    // Same rationale as server/observability.ts — Sentry failures must
    // never convert a diagnostic mirror into a service-killing exception.
  }
}

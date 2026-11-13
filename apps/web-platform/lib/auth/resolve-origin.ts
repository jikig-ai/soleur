import { getAllowedOrigins } from "./validate-origin";

// This module is reached from edge middleware (`middleware.ts`) — do NOT
// import `@/server/logger`, which transitively pulls `node:crypto` via
// `server/observability.ts` (per ADR-029 §I10) and breaks the edge bundle.
// `console.warn` is supported in edge runtime; the `rejectedOrigin` field
// carries no user PII so the pino `userIdHash` rename hook is not needed.

// #7665 — the rejection warn is deduplicated per distinct origin per process.
//
// Measured on prod: the dedicated inngest host's --sdk-url sync poll
// (http://10.0.1.10:3000/api/inngest, ~120/hr) and the deploy canary's localhost
// probes are legitimately REJECTED — they are not admitted because
// `x-forwarded-host` is client-supplied, so whitelisting an internal literal
// would let any internet request claim a private-net origin. But each rejection
// is a non-JSON console line that escapes `app_container_warn_filter`'s
// `level >= 40` cut through the `parse_err != null` arm — ~5k rows/day of one
// repeated fact.
//
// The FIRST sighting of an origin still logs — that row is the diagnostic.
// Repeats are suppressed until process restart (per isolate; the deployment is
// single-process). The Set is insertion-ordered and capped: at capacity the
// OLDEST entry evicts so a novel origin is never permanently starved by scanner
// churn, and an evicted origin re-logs on its next rejection.
export const REJECTED_ORIGIN_LOG_CAP = 256;
const loggedRejectedOrigins = new Set<string>();

export function resolveOrigin(
  forwardedHost: string | null,
  forwardedProto: string | null,
  host: string | null,
): string {
  const allowed = getAllowedOrigins();
  const proto = forwardedProto ?? "https";
  const resolvedHost = forwardedHost ?? host ?? "app.soleur.ai";
  const computed = `${proto}://${resolvedHost}`.toLowerCase();
  if (!allowed.has(computed)) {
    if (!loggedRejectedOrigins.has(computed)) {
      if (loggedRejectedOrigins.size >= REJECTED_ORIGIN_LOG_CAP) {
        const oldest = loggedRejectedOrigins.values().next().value;
        if (oldest !== undefined) loggedRejectedOrigins.delete(oldest);
      }
      loggedRejectedOrigins.add(computed);
      // eslint-disable-next-line no-console -- edge-runtime boundary; see comment above
      console.warn(
        "[resolve-origin] Rejected origin:",
        computed.slice(0, 100).replace(/[\x00-\x1f]/g, ""),
        "(first occurrence — repeats suppressed until restart; #7665)",
      );
    }
    return "https://app.soleur.ai";
  }
  return computed;
}

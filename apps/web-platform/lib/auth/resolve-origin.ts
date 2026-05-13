import { getAllowedOrigins } from "./validate-origin";

// This module is reached from edge middleware (`middleware.ts`) — do NOT
// import `@/server/logger`, which transitively pulls `node:crypto` via
// `server/observability.ts` (per ADR-029 §I10) and breaks the edge bundle.
// `console.warn` is supported in edge runtime; the `rejectedOrigin` field
// carries no user PII so the pino `userIdHash` rename hook is not needed.

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
    // eslint-disable-next-line no-console -- edge-runtime boundary; see comment above
    console.warn(
      "[resolve-origin] Rejected origin:",
      computed.slice(0, 100).replace(/[\x00-\x1f]/g, ""),
    );
    return "https://app.soleur.ai";
  }
  return computed;
}

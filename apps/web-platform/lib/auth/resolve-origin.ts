const ALLOWED_ORIGINS = new Set([
  "https://app.soleur.ai",
  "http://localhost:3000",
]);

export function resolveOrigin(
  forwardedHost: string | null,
  forwardedProto: string | null,
  host: string | null,
): string {
  const proto = forwardedProto ?? "https";
  const resolvedHost = forwardedHost ?? host ?? "app.soleur.ai";
  const computed = `${proto}://${resolvedHost}`;
  if (!ALLOWED_ORIGINS.has(computed)) {
    console.warn(`[callback] Rejected origin: ${computed.slice(0, 100)}`);
    return "https://app.soleur.ai";
  }
  return computed;
}

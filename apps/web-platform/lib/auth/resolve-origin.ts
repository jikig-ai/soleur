const PRODUCTION_ORIGINS = new Set(["https://app.soleur.ai"]);
const DEV_ORIGINS = new Set(["https://app.soleur.ai", "http://localhost:3000"]);

export function resolveOrigin(
  forwardedHost: string | null,
  forwardedProto: string | null,
  host: string | null,
): string {
  const allowed = process.env.NODE_ENV === "development" ? DEV_ORIGINS : PRODUCTION_ORIGINS;
  const proto = forwardedProto ?? "https";
  const resolvedHost = forwardedHost ?? host ?? "app.soleur.ai";
  const computed = `${proto}://${resolvedHost}`.toLowerCase();
  if (!allowed.has(computed)) {
    console.warn(`[callback] Rejected origin: ${computed.slice(0, 100).replace(/[\x00-\x1f]/g, "")}`);
    return "https://app.soleur.ai";
  }
  return computed;
}

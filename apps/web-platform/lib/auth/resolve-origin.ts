import { getAllowedOrigins } from "./allowed-origins";

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
    console.warn(`[callback] Rejected origin: ${computed.slice(0, 100).replace(/[\x00-\x1f]/g, "")}`);
    return "https://app.soleur.ai";
  }
  return computed;
}

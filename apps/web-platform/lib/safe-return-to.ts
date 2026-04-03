const FALLBACK = "/dashboard";

/**
 * Validates a return_to param to prevent open redirect attacks.
 * Only allows relative paths starting with /dashboard.
 */
export function safeReturnTo(param: string | null): string {
  if (!param) return FALLBACK;
  if (!param.startsWith("/dashboard")) return FALLBACK;
  if (param.includes("//") || param.includes("\\") || param.includes("..")) return FALLBACK;
  return param;
}

// Shared Cache-Control fixture strings for KB binary-response tests. Keeping
// them here (a) centralizes the exact value so a policy tweak touches one
// place, and (b) prevents silent drift between test files that were each
// asserting the string verbatim.
export const PUBLIC_CACHE_CONTROL =
  "public, max-age=60, s-maxage=300, stale-while-revalidate=3600, must-revalidate";
export const PRIVATE_CACHE_CONTROL = "private, max-age=60";
export const NO_STORE = "no-store";

/** Recompute the weak fstat ETag the way buildETag does. */
export function deriveWeakETag(meta: {
  ino: number;
  size: number;
  mtimeMs: number;
}): string {
  return `W/"${meta.ino}-${meta.size}-${Math.floor(meta.mtimeMs)}"`;
}

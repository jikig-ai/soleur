/**
 * CSP applied to binary content responses from /api/kb/content/[...path].
 *
 * Lives in `lib/` (not in the route handler file) because Next.js App Router
 * rejects non-standard exports from `route.ts` -- only HTTP method handlers
 * and a small allow-list (`runtime`, `dynamic`, `revalidate`, etc.) are
 * permitted. Exporting this constant from route.ts breaks `next build`.
 */
export const KB_BINARY_RESPONSE_CSP =
  "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'";

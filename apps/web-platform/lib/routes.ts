// Shared route constants used by middleware and tests.
// Single source of truth — avoids drift between middleware.ts and middleware.test.ts.

/** No auth required — middleware returns early */
export const PUBLIC_PATHS = [
  "/login",
  "/signup",
  "/callback",
  "/api/webhooks",
  "/ws",
  "/manifest.webmanifest",
  "/shared",
  "/api/shared",
];

/** Auth required, but T&C check skipped (user must reach these to accept terms) */
export const TC_EXEMPT_PATHS = [
  "/accept-terms",
  "/api/accept-terms",
  "/api/auth/github-resolve/callback",
];

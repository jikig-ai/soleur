// Shared route constants used by middleware and tests.
// Single source of truth — avoids drift between middleware.ts and middleware.test.ts.

/** No auth required — middleware returns early */
export const PUBLIC_PATHS = [
  "/login",
  "/signup",
  "/callback",
  "/api/webhooks",
  // /api/inngest: SDK route served by `inngest/next.serve` with HMAC signature
  // verification on every POST (signingKey from INNGEST_SIGNING_KEY). Supabase
  // middleware would redirect to /login, breaking server↔SDK sync. ADR-030 I4
  // invariant: Inngest's own gate is load-bearing. Surfaced 2026-05-19 — PR-1
  // cron-daily-triage missed all scheduled fires post-merge (#4017) because
  // the Inngest server could not reach /api/inngest to register functions.
  "/api/inngest",
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

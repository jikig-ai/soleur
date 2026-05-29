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
  // /api/internal/kb-drift-ingest: HMAC-SHA256-gated POST (signing key
  // KB_DRIFT_INGEST_SIGNING_KEY) from the nightly KB-drift walker cron.
  // Carries no session cookie — Supabase middleware would 307→/login and the
  // route's own HMAC gate (route.ts:97) would never run, failing the workflow's
  // 2xx assertion. Same class as #4017 (/api/inngest). NARROW exact path — do
  // NOT broaden to /api/internal (would session-bypass future internal routes).
  "/api/internal/kb-drift-ingest",
  "/ws",
  "/manifest.webmanifest",
  // /robots.txt: Next.js robots.ts metadata route (Disallow: /). Public-by-design,
  // no auth/PII — must bypass Supabase middleware or crawlers get 307→/login and
  // never see the Disallow body. Same class as /manifest.webmanifest (#4587, #4573).
  "/robots.txt",
  "/shared",
  "/api/shared",
  "/invite",
];

/** Auth required, but T&C check skipped (user must reach these to accept terms) */
export const TC_EXEMPT_PATHS = [
  "/accept-terms",
  "/api/accept-terms",
  "/api/auth/github-resolve/callback",
];

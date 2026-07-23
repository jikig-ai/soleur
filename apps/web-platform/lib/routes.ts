// Shared route constants used by middleware and tests.
// Single source of truth — avoids drift between middleware.ts and middleware.test.ts.

/** No auth required — middleware returns early */
export const PUBLIC_PATHS = [
  "/login",
  "/signup",
  "/callback",
  "/api/webhooks",
  // /api/webhooks/resend-inbound: svix-signature-gated POST from Resend
  // Inbound (#5103). The route carries no session cookie — without
  // PUBLIC_PATHS membership Supabase middleware would 307→/login before
  // the route's own svix verification gate runs (learning 2026-05-29;
  // same class as #4017 /api/inngest). Covered today by the /api/webhooks
  // prefix above, but pinned as a NARROW exact path so the ingress
  // survives any future narrowing of that broad prefix.
  "/api/webhooks/resend-inbound",
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
  // /api/internal/trigger-cron: Bearer-shared-secret-gated POST
  // (INNGEST_MANUAL_TRIGGER_SECRET) from an operator/agent firing a cron
  // manual-trigger on demand (#4734). Carries no session cookie — Supabase
  // middleware would 307→/login and the route's own length-guarded
  // timingSafeEqual gate would never run (the post-merge AC4 curl would get a
  // redirect, not 202). Same class as #4017 (/api/inngest) and kb-drift-ingest
  // above. NARROW exact path — do NOT broaden to /api/internal.
  "/api/internal/trigger-cron",
  // /api/internal/schedule-reminder: Bearer-shared-secret-gated POST
  // (INNGEST_MANUAL_TRIGGER_SECRET) that arms the generic reminder primitive
  // (emits a future-ts `reminder.scheduled` event). Cookieless operator/agent
  // caller — Supabase middleware would 307→/login before the route's own
  // length-guarded timingSafeEqual gate runs. Same class as trigger-cron /
  // kb-drift-ingest. NARROW exact path — do NOT broaden to /api/internal.
  "/api/internal/schedule-reminder",
  "/ws",
  "/manifest.webmanifest",
  // /robots.txt: Next.js robots.ts metadata route (Disallow: /). Public-by-design,
  // no auth/PII — must bypass Supabase middleware or crawlers get 307→/login and
  // never see the Disallow body. Same class as /manifest.webmanifest (#4587, #4573).
  "/robots.txt",
  "/shared",
  "/api/shared",
  // /api/waitlist: public marketing-waitlist email capture from the anonymous
  // shared-document banner (proxies to Buttondown). Carries no session cookie —
  // Supabase middleware would 307→/login before the route's own validateOrigin +
  // honeypot + per-IP rate-limit gates run, making the form unreachable for the
  // anonymous visitor it exists to serve. Same class as #4017 (/api/inngest).
  // NARROW exact path — do NOT broaden to /api.
  "/api/waitlist",
  "/invite",
  // /offline.html: static, script-free PWA offline fallback (public/offline.html)
  // served by the service worker's navigate branch. The middleware matcher does
  // NOT exclude .html (only sw.js + image extensions), so without PUBLIC_PATHS
  // membership Supabase middleware 307→/login and the SW precache would capture
  // the redirect body instead of the real offline page. Same class as
  // /manifest.webmanifest (#4587). NARROW exact path.
  "/offline.html",
];

/** Auth required, but T&C check skipped (user must reach these to accept terms) */
export const TC_EXEMPT_PATHS = [
  "/accept-terms",
  "/api/accept-terms",
  "/api/auth/github-resolve/callback",
];

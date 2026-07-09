import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";
import { buildSecurityHeaders } from "./lib/security-headers";

const securityHeaders = buildSecurityHeaders();

// Dev server may fall back to an alternate port (e.g. 3001) when 3000 is
// taken by a concurrent worktree. Track the actual bound port so Server
// Actions accept the origin instead of returning 500.
const devPort = process.env.PORT || "3000";

const nextConfig: NextConfig = {
  // Custom server handles HTTP — disable standalone output
  output: undefined,
  // Bake BUILD_VERSION / BUILD_SHA into both client and server bundles so
  // Sentry's `release` field links every event (client OR server) to the
  // deployed image. Build-arg flow: Dockerfile ARG → ENV → next.config env
  // → webpack inline-substitution. Falls back to "dev" sentinel when
  // missing (matches Dockerfile ARG defaults) so local dev / vitest don't
  // collide events under a phantom release.
  env: {
    BUILD_VERSION: process.env.BUILD_VERSION ?? "dev",
    BUILD_SHA: process.env.BUILD_SHA ?? "dev",
  },
  // Allow WebSocket upgrade on the same port
  // NOTE: `pdfjs-dist` is intentionally NOT in this list, despite the
  // bundling-reorder bug it causes in the custom server (Sentry
  // e8225a569fcd4b07a460b5b1bb2a5ee7 — fixed via esbuild
  // `--external:pdfjs-dist` in `package.json:scripts.build:server`).
  // Adding it here breaks `components/kb/pdf-preview.tsx`'s client-side
  // `new URL("pdfjs-dist/build/pdf.worker.min.mjs", import.meta.url)`
  // worker reference at `next build` time. If a Sentry event surfaces
  // from the Next.js Route Handler path (`app/api/kb/share/route.ts` →
  // `kb-share.ts` → `readPdfMetadata`), revisit with a different
  // mechanism (`transpilePackages`, restructure the worker URL, etc.).
  //
  // `pino` + `pino-pretty` MUST stay external: `server/logger.ts` enables
  // pino-pretty transport whenever `NODE_ENV !== "production"` (i.e. dev,
  // test, and CI's e2e job). The transport spawns a worker_thread that
  // loads `pino/lib/worker.js` + the `pino-pretty` entry by resolving from
  // `node_modules`. If Next.js bundles them into `.next/server/vendor-
  // chunks/`, the runtime `new Worker(workerUrl)` call hits
  // `MODULE_NOT_FOUND: /.next/server/vendor-chunks/lib/worker.js` and the
  // worker thread exits, cascading uncaught exceptions through every
  // server route that calls `logger.error` (e.g. `app/(auth)/callback/
  // route.ts` → `reportSilentFallback`). All pino consumers are
  // server-only (`server/**`), so externalizing has no client-bundle
  // cost.
  serverExternalPackages: [
    "@anthropic-ai/claude-agent-sdk",
    "ws",
    "pino",
    "pino-pretty",
  ],
  experimental: {
    // SECURITY: restrict Server Action origins for defense-in-depth
    serverActions: {
      allowedOrigins:
        process.env.NODE_ENV === "development"
          ? [
              "app.soleur.ai",
              `localhost:${devPort}`,
              `127.0.0.1:${devPort}`,
            ]
          : ["app.soleur.ai"],
    },
    // Next.js clones the request body when middleware modifies headers.
    // Default limit is 10 MB — bodies exceeding it are silently truncated,
    // causing "Failed to parse body as FormData" for uploads >10 MB.
    // Set to 25 MB (route handler caps at 20 MB; headroom for multipart overhead).
    middlewareClientMaxBodySize: 25 * 1024 * 1024,
    // ADR-067 amendment (2026-07-09): the RSC-shell half of instant dashboard
    // tab-switching. Next.js 15 defaults `staleTimes.dynamic` to 0, so the
    // App Router client Router Cache discards a dynamic route's RSC payload the
    // instant you navigate away — returning to a tab always refetches from the
    // server and re-shows its `loading.tsx` skeleton. `dynamic: 30` restores
    // Next 14's reuse window: a returning tab renders instantly from the Router
    // Cache and revalidates in the background. This composes with the SWR data
    // cache (ADR-067 / PR #5639) — SWR caches `fetch` results, the Router Cache
    // caches the RSC shell.
    //
    // ISOLATION INVARIANT (brand_survival_threshold = single-user incident): a
    // Router-Cache HIT serves an RSC payload from client memory with NO server
    // round-trip, so `middleware.ts` (auth gate, #4307 revocation gate, T&C
    // consent, billing) does NOT run for cached segments. A warm cache must
    // therefore never survive a principal boundary. There is no API to
    // selectively evict the App Router Router Cache; the ONLY full wipe is a
    // HARD navigation (full document load). So every navigation that enters or
    // leaves an authenticated principal context hard-navigates
    // (`window.location.assign`) — see `components/auth/use-sign-out.ts` (GAP
    // C/D), `components/auth/login-form.tsx` + the onboarding funnel (GAP E),
    // `components/settings/delete-account-dialog.tsx` + the in-session 401/302
    // bounces (GAP F), `middleware.ts` `no-store` for bfcache (GAP G), and
    // `admin/analytics` mount-time re-validation (GAP H). `static` is left at
    // its Next 15 default (300 s) — irrelevant to the dynamic tab bug.
    staleTimes: {
      dynamic: 30,
    },
  },
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: securityHeaders,
      },
    ];
  },
};

export default withSentryConfig(nextConfig, {
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  authToken: process.env.SENTRY_AUTH_TOKEN,
  // sentry-cli base URL — falls back to org-subdomain for the new DE org.
  // `eu.sentry.io` is NOT correct (rewrites slugs ending in `-eu`, per learning
  // `2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`).
  sentryUrl: process.env.SENTRY_URL,
  // Upload source maps for all client chunks
  widenClientFileUpload: true,
  // Delete source maps after upload — don't ship to users
  sourcemaps: { deleteSourcemapsAfterUpload: true },
  // Suppress noisy logs outside CI
  silent: !process.env.CI,
  disableLogger: true,
});

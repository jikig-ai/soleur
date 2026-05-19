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

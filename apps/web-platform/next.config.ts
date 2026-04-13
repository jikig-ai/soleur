import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";
import { buildSecurityHeaders } from "./lib/security-headers";

const securityHeaders = buildSecurityHeaders();

const nextConfig: NextConfig = {
  // Custom server handles HTTP — disable standalone output
  output: undefined,
  // Allow WebSocket upgrade on the same port
  serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws"],
  experimental: {
    // SECURITY: restrict Server Action origins for defense-in-depth
    serverActions: {
      allowedOrigins:
        process.env.NODE_ENV === "development"
          ? ["app.soleur.ai", "localhost:3000"]
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
  // Upload source maps for all client chunks
  widenClientFileUpload: true,
  // Delete source maps after upload — don't ship to users
  sourcemaps: { deleteSourcemapsAfterUpload: true },
  // Suppress noisy logs outside CI
  silent: !process.env.CI,
  disableLogger: true,
});

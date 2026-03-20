import type { NextConfig } from "next";
import { buildSecurityHeaders } from "./lib/security-headers";

const securityHeaders = buildSecurityHeaders();

const nextConfig: NextConfig = {
  // Custom server handles HTTP — disable standalone output
  output: undefined,
  // Allow WebSocket upgrade on the same port
  serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws"],
  // SECURITY: restrict Server Action origins for defense-in-depth
  serverActions: {
    allowedOrigins:
      process.env.NODE_ENV === "development"
        ? ["app.soleur.ai", "localhost:3000"]
        : ["app.soleur.ai"],
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

export default nextConfig;

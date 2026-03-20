import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Custom server handles HTTP — disable standalone output
  output: undefined,
  // Allow WebSocket upgrade on the same port
  serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws"],
  // SECURITY: restrict Server Action origins for defense-in-depth
  serverActions: {
    allowedOrigins: ["app.soleur.ai"],
  },
};

export default nextConfig;

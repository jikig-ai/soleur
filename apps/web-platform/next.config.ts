import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Custom server handles HTTP — disable standalone output
  output: undefined,
  // Allow WebSocket upgrade on the same port
  serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws"],
};

export default nextConfig;

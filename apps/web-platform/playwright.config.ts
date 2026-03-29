import { defineConfig } from "@playwright/test";
import path from "path";

const PORT = 3099;

export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.e2e.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,

  outputDir: path.resolve(__dirname, "test-results"),

  use: {
    baseURL: `http://localhost:${PORT}`,
    trace: "on-first-retry",
    launchOptions: {
      args: ["--no-sandbox"],
    },
  },

  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],

  webServer: {
    command: `tsx server/index.ts`,
    port: PORT,
    timeout: 120_000,
    reuseExistingServer: !process.env.CI,
    env: {
      PORT: String(PORT),
      NEXT_PUBLIC_SUPABASE_URL: "https://test.supabase.co",
      NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon-key",
      SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key",
    },
  },
});

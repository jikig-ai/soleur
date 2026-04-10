import { defineConfig } from "@playwright/test";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PORT = 3099;
const MOCK_SUPABASE_PORT = 54399;
const MOCK_SUPABASE_URL = `http://localhost:${MOCK_SUPABASE_PORT}`;

export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.e2e.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,

  globalSetup: "./e2e/global-setup.ts",
  globalTeardown: "./e2e/global-teardown.ts",

  outputDir: path.resolve(__dirname, "test-results"),

  use: {
    baseURL: `http://localhost:${PORT}`,
    trace: "on-first-retry",
    launchOptions: {
      args: ["--no-sandbox"],
    },
  },

  projects: [
    // Public page tests (no auth needed)
    {
      name: "chromium",
      testIgnore: "**/start-fresh-*.e2e.ts",
      use: { browserName: "chromium" },
    },
    // Authenticated dashboard tests (use mock Supabase session)
    {
      name: "authenticated",
      testMatch: "**/start-fresh-*.e2e.ts",
      timeout: 60_000,
      use: {
        browserName: "chromium",
        storageState: "e2e/.auth/user.json",
        navigationTimeout: 45_000,
      },
    },
  ],

  webServer: {
    command: `tsx server/index.ts`,
    port: PORT,
    timeout: 120_000,
    reuseExistingServer: !process.env.CI,
    env: {
      PORT: String(PORT),
      NEXT_PUBLIC_SUPABASE_URL: MOCK_SUPABASE_URL,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon-key",
      SUPABASE_URL: MOCK_SUPABASE_URL,
      SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key",
    },
  },
});

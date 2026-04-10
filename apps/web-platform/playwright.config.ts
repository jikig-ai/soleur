import { defineConfig } from "@playwright/test";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PUBLIC_PORT = 3099;
const AUTH_PORT = 3100;
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
    trace: "on-first-retry",
    launchOptions: {
      args: ["--no-sandbox"],
    },
  },

  projects: [
    // Public page tests (no auth needed) — uses fake Supabase URL (unreachable)
    {
      name: "chromium",
      testIgnore: "**/start-fresh-*.e2e.ts",
      use: {
        browserName: "chromium",
        baseURL: `http://localhost:${PUBLIC_PORT}`,
      },
    },
    // Authenticated dashboard tests — uses mock Supabase for server-side auth
    {
      name: "authenticated",
      testMatch: "**/start-fresh-*.e2e.ts",
      timeout: 60_000,
      use: {
        browserName: "chromium",
        baseURL: `http://localhost:${AUTH_PORT}`,
        storageState: "e2e/.auth/user.json",
        navigationTimeout: 45_000,
      },
    },
  ],

  webServer: [
    // Server for public page tests (original config — fake unreachable Supabase URL)
    {
      command: `tsx server/index.ts`,
      port: PUBLIC_PORT,
      timeout: 120_000,
      reuseExistingServer: !process.env.CI,
      env: {
        PORT: String(PUBLIC_PORT),
        NEXT_PUBLIC_SUPABASE_URL: "https://test.supabase.co",
        NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon-key",
        SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key",
      },
    },
    // Server for authenticated tests (mock Supabase for middleware auth)
    {
      command: `tsx server/index.ts`,
      port: AUTH_PORT,
      timeout: 120_000,
      reuseExistingServer: !process.env.CI,
      env: {
        PORT: String(AUTH_PORT),
        NEXT_PUBLIC_SUPABASE_URL: MOCK_SUPABASE_URL,
        NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon-key",
        SUPABASE_URL: MOCK_SUPABASE_URL,
        SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key",
      },
    },
  ],
});

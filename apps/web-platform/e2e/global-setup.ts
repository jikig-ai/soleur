/**
 * Playwright global setup: starts the mock Supabase server and writes
 * authenticated storage state (auth cookies) for dashboard E2E tests.
 */
import fs from "node:fs";
import path from "node:path";
import type { FullConfig } from "@playwright/test";
import { startMockSupabase, MOCK_SESSION, AUTH_COOKIE_NAME } from "./mock-supabase";

export const MOCK_SUPABASE_PORT = 54399;
export const STORAGE_STATE_PATH = "e2e/.auth/user.json";

export default async function globalSetup(config: FullConfig) {
  // Start mock Supabase server
  const server = await startMockSupabase(MOCK_SUPABASE_PORT);
  (globalThis as Record<string, unknown>).__mockSupabaseServer = server;

  // Write Playwright storage state file directly (avoids needing to launch a
  // browser in globalSetup, which would require `npx playwright install`).
  const storageState = {
    cookies: [
      {
        name: AUTH_COOKIE_NAME,
        value: JSON.stringify(MOCK_SESSION),
        domain: "localhost",
        path: "/",
        expires: Math.floor(Date.now() / 1000) + 86400,
        httpOnly: false,
        secure: false,
        sameSite: "Lax" as const,
      },
    ],
    origins: [],
  };

  fs.mkdirSync(path.dirname(STORAGE_STATE_PATH), { recursive: true });
  fs.writeFileSync(STORAGE_STATE_PATH, JSON.stringify(storageState, null, 2));
}

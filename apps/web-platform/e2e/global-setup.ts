/**
 * Playwright global setup: starts the mock Supabase server and writes
 * authenticated storage state (auth cookies) for dashboard E2E tests.
 */
import fs from "node:fs";
import path from "node:path";
import type { FullConfig } from "@playwright/test";
import {
  startMockSupabase,
  MOCK_SESSION,
  MOCK_FOUNDER_SESSION,
  AUTH_COOKIE_NAME,
} from "./mock-supabase";

export const MOCK_SUPABASE_PORT = 54399;
export const STORAGE_STATE_PATH = "e2e/.auth/user.json";
/** The legal-acceptance founder's session (#12197): `MOCK_FOUNDER` in mock-supabase.ts. */
const FOUNDER_STORAGE_STATE_PATH = "e2e/.auth/founder.json";

/** Playwright storage state carrying one mock session in the Supabase SSR auth cookie. */
function storageStateFor(session: typeof MOCK_SESSION) {
  return {
    cookies: [
      {
        name: AUTH_COOKIE_NAME,
        value: JSON.stringify(session),
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
}

export default async function globalSetup(config: FullConfig) {
  // Start mock Supabase server
  const server = await startMockSupabase(MOCK_SUPABASE_PORT);
  (globalThis as Record<string, unknown>).__mockSupabaseServer = server;

  // Write Playwright storage state file directly (avoids needing to launch a
  // browser in globalSetup, which would require `npx playwright install`).
  // e2e/.auth/ is gitignored.
  fs.mkdirSync(path.dirname(STORAGE_STATE_PATH), { recursive: true });
  fs.writeFileSync(STORAGE_STATE_PATH, JSON.stringify(storageStateFor(MOCK_SESSION), null, 2));
  fs.writeFileSync(
    FOUNDER_STORAGE_STATE_PATH,
    JSON.stringify(storageStateFor(MOCK_FOUNDER_SESSION), null, 2),
  );
}

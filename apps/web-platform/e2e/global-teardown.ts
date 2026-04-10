/**
 * Playwright global teardown: stops the mock Supabase server.
 */
import type http from "node:http";

export default async function globalTeardown() {
  const server = (globalThis as Record<string, unknown>).__mockSupabaseServer as http.Server | undefined;
  if (server) {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}
